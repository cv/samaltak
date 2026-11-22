#!/usr/bin/env python3
"""Runs compute kernels on the NVIDIA GPU through the open kernel module's RM ioctls alone: the executable reference
for docs/nv.md (written for GB10, driver 580.178.04). No CUDA or Vulkan libraries: Python's stdlib and ctypes.

usage: tools/nv-probe.py [--uvm | --ats] [KERNELS.cubin]
  (default)  a VA space RM owns: memory is NV01_MEMORY_SYSTEM mapped with NV_ESC_RM_MAP_MEMORY_DMA; no /dev/nvidia-uvm
  --uvm      the VA space nvidia-uvm owns, as tinygrad and CUDA do (UVM_REGISTER_GPU_VASPACE, UVM_MAP_EXTERNAL_ALLOCATION)
  --ats      --uvm with ATS: kernels also read and write plain process memory (malloc) at its CPU address
  KERNELS    default build/nv-probe.cubin, built from tools/nv-probe.cu with nvcc -arch=sm_121 when missing
Launches add1 (1000 floats), blocksum (shared memory, barriers) and dims (blockDim, gridDim, dynamic shared memory);
exits 0 when the results are right. Needs a GPU: not part of any test target.
"""
import ctypes, os, struct, subprocess, sys, time

libc = ctypes.CDLL(None, use_errno=True)
libc.ioctl.argtypes = [ctypes.c_int, ctypes.c_ulong, ctypes.c_void_p]
libc.mmap.restype = ctypes.c_void_p
libc.mmap.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_long]
PROT_RW, MAP_SHARED, MAP_FIXED = 3, 1, 0x10
VERBOSE = os.environ.get("V")

class Buf:  # a C struct in memory we own
  def __init__(self, n): self.b = ctypes.create_string_buffer(n); self.addr = ctypes.addressof(self.b); self.n = n
  def __len__(self): return self.n
  def u32(self, off, v=None):
    if v is None: return struct.unpack_from("<I", self.b, off)[0]
    struct.pack_into("<I", self.b, off, v & 0xffffffff); return self
  def u64(self, off, v=None):
    if v is None: return struct.unpack_from("<Q", self.b, off)[0]
    struct.pack_into("<Q", self.b, off, v); return self

class Mem:  # raw memory at an address (mapped GPU memory, doorbell page)
  def __init__(self, addr, size): self.addr, self.size = addr, size
  def w32(self, off, v): ctypes.c_uint32.from_address(self.addr + off).value = v & 0xffffffff
  def w64(self, off, v): ctypes.c_uint64.from_address(self.addr + off).value = v
  def r32(self, off): return ctypes.c_uint32.from_address(self.addr + off).value
  def r64(self, off): return ctypes.c_uint64.from_address(self.addr + off).value
  def write(self, off, data): ctypes.memmove(self.addr + off, data, len(data))

def IOWR(nr, size): return (3 << 30) | (size << 16) | (ord('F') << 8) | nr
def ioctl(fd, req, buf):
  if libc.ioctl(fd, req, buf.addr) < 0: e = ctypes.get_errno(); raise OSError(e, f"ioctl {req:#x}: {os.strerror(e)}")

# NV_ESC_* (nv_escape.h, nv-ioctl-numbers.h)
ESC_RM_ALLOC_MEMORY, ESC_RM_FREE, ESC_RM_CONTROL, ESC_RM_ALLOC = 0x27, 0x29, 0x2a, 0x2b
ESC_RM_MAP_MEMORY, ESC_RM_MAP_MEMORY_DMA, ESC_CARD_INFO, ESC_REGISTER_FD = 0x4e, 0x57, 0xc8, 0xc9
# classes
ROOT_CLIENT, DEVICE, SUBDEVICE, MEMORY_SYSTEM, MEMORY_VIRTUAL = 0x41, 0x80, 0x2080, 0x3e, 0x70
VASPACE, CHANNEL_GROUP, CONTEXT_SHARE, USERMODE = 0x90f1, 0xa06c, 0x9067, 0xc661
GPFIFO, COMPUTE = 0xc96f, 0xcec0
O_FLAGS = os.O_RDWR | os.O_CLOEXEC

class RM:
  def __init__(self, uvm=False):
    self.ctl = os.open("/dev/nvidiactl", O_FLAGS)
    self.root = self.alloc(0, ROOT_CLIENT)
    self.dev_fd = self.open_dev()
    if uvm:
      self.uvm_fd = os.open("/dev/nvidia-uvm", O_FLAGS)
      self.uvm(0x30000001, Buf(16), 8)                               # UVM_INITIALIZE
      self.uvm_fd2 = os.open("/dev/nvidia-uvm", O_FLAGS)
      p = Buf(8).u32(0, self.uvm_fd); libc.ioctl(self.uvm_fd2, 0x4b, p.addr)   # UVM_MM_INITIALIZE (may be NOTHING_TO_DO)
    self.device = self.alloc(self.root, DEVICE, Buf(56).u32(0, 0).u32(4, self.root))   # deviceId 0, hClientShare
    self.subdevice = self.alloc(self.device, SUBDEVICE, Buf(4))

  def open_dev(self):  # /dev/nvidia0 linked to our control fd (NV_ESC_REGISTER_FD)
    fd = os.open("/dev/nvidia0", O_FLAGS); ioctl(fd, IOWR(ESC_REGISTER_FD, 4), Buf(4).u32(0, self.ctl)); return fd

  def alloc(self, parent, cls, params=None):  # NV_ESC_RM_ALLOC, NVOS21_PARAMETERS
    p = Buf(32).u32(0, self.root if parent else 0).u32(4, parent).u32(12, cls)
    if params is not None: p.u64(16, params.addr).u32(24, len(params))
    ioctl(self.ctl, IOWR(ESC_RM_ALLOC, 32), p)
    if p.u32(28): raise RuntimeError(f"RM alloc class {cls:#x} under {parent:#x}: status {p.u32(28):#x}")
    if VERBOSE: print(f"  alloc {cls:#06x} -> {p.u32(8):#x}")
    return p.u32(8)

  def control(self, obj, cmd, params):  # NV_ESC_RM_CONTROL, NVOS54_PARAMETERS
    p = Buf(32).u32(0, self.root).u32(4, obj).u32(8, cmd).u64(16, params.addr).u32(24, len(params))
    ioctl(self.ctl, IOWR(ESC_RM_CONTROL, 32), p)
    if p.u32(28): raise RuntimeError(f"RM control {cmd:#x} on {obj:#x}: status {p.u32(28):#x}")
    return params

  def uvm(self, cmd, params, status_off=None):
    if libc.ioctl(self.uvm_fd, cmd, params.addr) < 0: raise OSError(ctypes.get_errno(), f"uvm {cmd:#x}")
    st = params.u32(len(params) - 4 if status_off is None else status_off)
    if st: raise RuntimeError(f"uvm {cmd:#x}: status {st:#x}")

  def sysmem(self, size, contiguous=False):  # NV01_MEMORY_SYSTEM: NV_MEMORY_ALLOCATION_PARAMS
    size = (size + 0xfff) & ~0xfff
    attr = (1 << 25) | ((2 if contiguous else 1) << 27) | (1 << 23)   # LOCATION_PCI, PHYSICALITY, PAGE_SIZE_4KB
    attr2 = (2 << 2) | 1                                               # GPU_CACHEABLE_NO, ZBC_PREFER_NO_ZBC
    p = Buf(128).u32(0, self.root).u32(4, 13).u32(8, 0xc101).u32(24, attr).u32(28, attr2).u32(32, 6)
    p.u64(64, size).u64(72, 0x1000).u64(88, size - 1)
    return self.alloc(self.device, MEMORY_SYSTEM, p), size

  def map_cpu(self, hmem, size, fd_path="/dev/nvidiactl", target=None):  # NV_ESC_RM_MAP_MEMORY + mmap on a fresh fd
    fd = os.open(fd_path, O_FLAGS)
    if fd_path != "/dev/nvidiactl": ioctl(fd, IOWR(ESC_REGISTER_FD, 4), Buf(4).u32(0, self.ctl))
    p = Buf(56).u32(0, self.root).u32(4, self.device).u32(8, hmem).u64(24, size).u32(48, fd)
    ioctl(self.ctl, IOWR(ESC_RM_MAP_MEMORY, 56), p)
    if p.u32(40): raise RuntimeError(f"map memory: status {p.u32(40):#x}")
    a = libc.mmap(target, size, PROT_RW, MAP_SHARED | (MAP_FIXED if target else 0), fd, 0)
    if a in (None, ctypes.c_void_p(-1).value): raise OSError(ctypes.get_errno(), "mmap")
    os.close(fd)
    return Mem(a, size)

  def map_gpu(self, hdma, hmem, size, fixed=None):  # NV_ESC_RM_MAP_MEMORY_DMA, NVOS46_PARAMETERS -> GPU VA
    flags = (1 << 8) | (1 << 4) | ((1 << 15) if fixed is not None else 0)   # PAGE_SIZE_4KB, CACHE_SNOOP_ENABLE, DMA_OFFSET_FIXED
    p = Buf(64).u32(0, self.root).u32(4, self.device).u32(8, hdma).u32(12, hmem).u64(24, size).u32(32, flags).u64(48, fixed or 0)
    ioctl(self.ctl, IOWR(ESC_RM_MAP_MEMORY_DMA, 64), p)
    if p.u32(56): raise RuntimeError(f"map dma: status {p.u32(56):#x}")
    return p.u64(48)

def parse_cubin(data, name):
  shoff, shentsize, shnum, shstrndx = struct.unpack_from("<QxxxxHHH", data, 0x28)[0], *struct.unpack_from("<HHH", data, 0x3a)
  secs = [struct.unpack_from("<IIQQQQIIQQ", data, shoff + i * shentsize) for i in range(shnum)]
  strtab = secs[shstrndx]
  def nm(off): s = strtab[4] + off; return data[s:data.index(b"\0", s)].decode()
  S = {nm(s[0]): s for s in secs}
  body = lambda s: data[s[4]:s[4] + s[5]] if s[1] != 8 else b""
  def attrs(sec):
    b, i = body(sec), 0
    while i < len(b):
      fmt, attr, size = struct.unpack_from("<BBH", b, i)
      if fmt == 4: yield attr, b[i + 4:i + 4 + size]; i += 4 + size
      else: yield attr, size; i += 4
  symtab = S[".symtab"]; symstr = secs[symtab[6]]
  syms = [struct.unpack_from("<IBBHQQ", data, symtab[4] + i * 24) for i in range(symtab[5] // 24)]
  symname = lambda s: data[symstr[4] + s[0]:data.index(b"\0", symstr[4] + s[0])].decode()
  sym = next(i for i, s in enumerate(syms) if symname(s) == name)
  # .nv.shared.<kernel> already holds the 1 KB every CTA reserves (sm_90 on); kernels without one still need it
  k = {"text": body(S[".text." + name]), "regs": 0, "barriers": 0, "shared": max(S.get(".nv.shared." + name, (0,) * 10)[5], 0x400),
       "cbank0_size": S[".nv.constant0." + name][5], "param_off": 0x380, "param_size": 0}
  for a, v in attrs(S[".nv.info"]):
    if a == 0x2f and struct.unpack_from("<I", v)[0] == sym: k["regs"] = struct.unpack_from("<II", v)[1]   # EIATTR_REGCOUNT
  for a, v in attrs(S[".nv.info." + name]):
    if a == 0x0a: _, off, size = struct.unpack_from("<IHH", v); k["param_off"], k["param_size"] = off, size   # EIATTR_PARAM_CBANK
    if a == 0x4c: k["barriers"] = v                                                                         # EIATTR_NUM_BARRIERS
  return k

def qmd_set(q, hi, lo, v):  # write a field MW(hi:lo) of the QMD bytearray
  n = int.from_bytes(q[lo // 8:hi // 8 + 1], "little")
  mask = ((1 << (hi - lo + 1)) - 1) << (lo % 8)
  assert v >> (hi - lo + 1) == 0, (hi, lo, v)
  q[lo // 8:hi // 8 + 1] = ((n & ~mask) | (v << (lo % 8))).to_bytes(hi // 8 - lo // 8 + 1, "little")

def method(subc, mthd, *args): return [(1 << 29) | (len(args) << 16) | (subc << 13) | (mthd >> 2), *args]   # SEC_OP_INC_METHOD

def main():
  use_ats = "--ats" in sys.argv
  use_uvm = "--uvm" in sys.argv or use_ats
  here = os.path.dirname(os.path.abspath(__file__))
  cubin = next((a for a in sys.argv[1:] if a.endswith(".cubin")), os.path.join(here, "..", "build", "nv-probe.cubin"))
  if not os.path.exists(cubin):
    os.makedirs(os.path.dirname(cubin), exist_ok=True)
    nvcc = os.environ.get("NVCC", "/usr/local/cuda/bin/nvcc")
    subprocess.run([nvcc, "-arch=sm_121", "-cubin", "-o", cubin, os.path.join(here, "nv-probe.cu")], check=True)
  rm = RM(uvm=use_uvm)
  info = Buf(5 * 8)
  for i, idx in enumerate((0x0c, 0x14, 0x17, 0x20, 0x0d)): info.u32(i * 8, idx)
  rm.control(rm.subdevice, 0x20801201, Buf(32).u32(0, 5).u64(8, info.addr))         # NV2080_CTRL_CMD_GR_GET_INFO
  sm_version, gpcs, tpcs, sms, warps = (info.u32(i * 8 + 4) for i in range(5))
  print(f"GR: sm_version {sm_version:#x} gpcs {gpcs} tpc/gpc {tpcs} sm/tpc {sms} warps/sm {warps}")

  # VA space. Default: owned by RM (no UVM). --uvm: owned by UVM, like tinygrad/CUDA.
  vflags = ((1 << 3) | (1 << 6) | ((1 << 4) if use_ats else 0)) if use_uvm else 0                                    # IS_EXTERNALLY_OWNED | ENABLE_PAGE_FAULTING
  vaspace = rm.alloc(rm.device, VASPACE, Buf(56).u32(4, vflags).u64(8, 0x1fffffb000000 if use_uvm else 0).u64(40, 0x1000 if use_uvm else 0))
  virt = rm.alloc(rm.device, MEMORY_VIRTUAL, Buf(24).u64(8, 0x1ffffffffffff if use_uvm else 0).u32(16, 0 if use_uvm else vaspace))
  if use_uvm:
    gid = rm.control(rm.subdevice, 0x2080014a, Buf(268).u32(4, 2).u32(8, 16))     # NV2080_CTRL_CMD_GPU_GET_GID_INFO, binary
    uuid = bytes(gid.b[12:28])
    p = Buf(40); ctypes.memmove(p.addr, uuid, 16); p.u32(24, 0xffffffff); rm.uvm(0x25, p, 36)                      # UVM_REGISTER_GPU
    p = Buf(32); ctypes.memmove(p.addr, uuid, 16); p.u32(16, rm.ctl).u32(20, rm.root).u32(24, vaspace); rm.uvm(0x19, p, 28)  # UVM_REGISTER_GPU_VASPACE
  next_va = [0x1000000000]
  def buffer(size, contiguous=False):  # system memory, CPU-mapped, GPU-mapped; returns (handle, Mem, gpu va)
    h, size = rm.sysmem(size, contiguous)
    if use_uvm:
      va = next_va[0]; next_va[0] += (size + 0x1fffff) & ~0x1fffff
      m = rm.map_cpu(h, size, target=va)
      rm.uvm(0x49, Buf(24).u64(0, va).u64(8, size), 16)                             # UVM_CREATE_EXTERNAL_RANGE
      rm.map_gpu(virt, h, size, fixed=va)
      p = Buf(9264).u64(0, va).u64(8, size); ctypes.memmove(p.addr + 24, uuid, 16); p.u32(24 + 16, 1)   # gpuMappingType 1
      p.u32(9240, 1).u32(9248, rm.ctl).u32(9252, rm.root).u32(9256, h); rm.uvm(0x21, p, 9260)              # UVM_MAP_EXTERNAL_ALLOCATION
      return h, m, va
    return h, rm.map_cpu(h, size), rm.map_gpu(virt, h, size)

  ENTRIES, USERD_OFF = 1024, 0x2000
  fifo_h, fifo, fifo_va = buffer(0x3000, contiguous=True)
  err_h, _, _ = buffer(0x1000)
  group = rm.alloc(rm.device, CHANNEL_GROUP, Buf(20).u32(12, 1))                    # engineType NV2080_ENGINE_TYPE_GRAPHICS
  ctxshare = rm.alloc(group, CONTEXT_SHARE, Buf(12).u32(0, vaspace).u32(4, 1))       # SUBCONTEXT_ASYNC
  cp = Buf(368).u32(0, err_h).u32(4, fifo_h).u64(8, fifo_va).u32(16, ENTRIES).u32(24, ctxshare).u32(32, fifo_h).u64(64, USERD_OFF)
  channel = rm.alloc(group, GPFIFO, cp)
  rm.alloc(channel, COMPUTE)
  token = rm.control(channel, 0xc36f0108, Buf(4).u32(0, 0xffffffff)).u32(0)          # NVC36F_CTRL_CMD_GPFIFO_GET_WORK_SUBMIT_TOKEN
  if use_uvm:
    p = Buf(56); ctypes.memmove(p.addr, uuid, 16); p.u32(16, rm.ctl).u32(20, rm.root).u32(24, channel)
    p.u64(32, next_va[0]).u64(40, 0x4000000); next_va[0] += 0x4000000; rm.uvm(0x1b, p, 48)                     # UVM_REGISTER_CHANNEL
  sched = Buf(3); sched.b[0] = 1
  rm.control(group, 0xa06c0101, sched)                                              # NVA06C_CTRL_CMD_GPFIFO_SCHEDULE, 3 bytes: bEnable, bSkipSubmit, bSkipEnable
  usermode = rm.alloc(rm.subdevice, USERMODE)
  doorbell = rm.map_cpu(usermode, 0x10000, fd_path="/dev/nvidia0")
  print(f"channel {channel:#x} token {token:#x} fifo va {fifo_va:#x} usermode mapped at {doorbell.addr:#x}")

  pb_h, pb, pb_va = buffer(0x10000)
  sem_h, sem, sem_va = buffer(0x1000)
  state = {"put": 0, "pb": 0}
  def submit(words):
    off = state["pb"]; data = struct.pack(f"<{len(words)}I", *words); pb.write(off, data)
    state["pb"] = (off + len(data) + 0xff) & ~0xff
    fifo.w64((state["put"] % ENTRIES) * 8, (pb_va + off) | (len(words) << 42) | (1 << 41))
    state["put"] += 1
    fifo.w32(USERD_OFF + 0x8c, state["put"] % ENTRIES)                                # USERD GPPut
    doorbell.w32(0x90, token)                                                         # NOTIFY_CHANNEL_PENDING
  def release(value):  # host semaphore release with WFI, 64-bit payload
    return method(0, 0x5c, sem_va & 0xffffffff, sem_va >> 32, value & 0xffffffff, value >> 32, 1 | (1 << 20) | (1 << 24))
  def wait(value, what):
    t = time.time()
    while sem.r64(0) != value:
      if time.time() - t > 3: raise RuntimeError(f"{what}: timeout, semaphore {sem.r64(0):#x}, GPGet {fifo.r32(USERD_OFF + 0x88)}")
    return time.time() - t

  submit(method(1, 0x0, COMPUTE) + release(1))
  print(f"SET_OBJECT + semaphore release: done in {wait(1, 'setup') * 1e6:.0f} us")

  # local memory (shader stack), windows
  SHARED_WIN, LOCAL_WIN, slm = 0x729400000000, 0x729300000000, 0x240
  per_tpc = ((((slm * 32) + 0x1ff) & ~0x1ff) * warps * sms + 0x7fff) & ~0x7fff
  lm_size = (per_tpc * tpcs * gpcs + 0x1ffff) & ~0x1ffff
  _, _, lm_va = buffer(lm_size)
  submit(method(1, 0x7b0, LOCAL_WIN >> 32, LOCAL_WIN & 0xffffffff) + method(1, 0x2a0, SHARED_WIN >> 32, SHARED_WIN & 0xffffffff)
         + method(1, 0x790, lm_va >> 32, lm_va & 0xffffffff) + method(1, 0x2e4, per_tpc >> 32, per_tpc & 0xffffffff, 0xff) + release(2))
  wait(2, "local memory")

  progs = {}
  def launch(cubin, name, grid, block, params, dyn_smem=0):
    if (cubin, name) not in progs:
      k = parse_cubin(open(cubin, "rb").read(), name)
      _, code, code_va = buffer(len(k["text"]) + 0x1000); code.write(0, k["text"])
      progs[(cubin, name)] = (k, code_va)
    k, code_va = progs[(cubin, name)]
    grid, block = (tuple(grid) + (1, 1))[:3], (tuple(block) + (1, 1))[:3]
    cbuf = bytearray(max(k["cbank0_size"], k["param_off"] + k["param_size"]))
    shmem = (k["shared"] + dyn_smem + 127) & ~127
    struct.pack_into("<I", cbuf, 0x16c, shmem)                                   # total shared memory size
    struct.pack_into("<4I", cbuf, 0x2f0, SHARED_WIN & 0xffffffff, SHARED_WIN >> 32, LOCAL_WIN & 0xffffffff, LOCAL_WIN >> 32)
    struct.pack_into("<3I", cbuf, 0x360, *block)                                 # blockDim
    struct.pack_into("<3I", cbuf, 0x370, *grid)                                  # gridDim
    struct.pack_into("<I", cbuf, 0x37c, 0xfffdc0)                                # initial stack pointer
    struct.pack_into("<I", cbuf, 0x2ac, dyn_smem)                                # dynamic shared memory size (CGA size 0)
    cbuf[k["param_off"]:k["param_off"] + len(params)] = params
    smem_cfg = min(c * 1024 for c in (32, 64, 100) if c * 1024 >= shmem) // 4096 + 1
    _, qm, q_va = buffer(0x1000)                                                 # QMD at 0, constant bank 0 at 0x200
    cb_va = q_va + 0x200
    qm.write(0x200, bytes(cbuf))
    q = bytearray(0x180)
    for (hi, lo), v in {(149, 144): 0x3f, (153, 151): 2, (455, 448): ((sm_version >> 4) & 0xf0) | (sm_version & 0xf), (456, 456): 1, (457, 457): 1,
        (471, 468): 5, (472, 472): 1, (473, 473): 1, (474, 474): 1, (475, 475): 1, (625, 624): 1,
        (1055, 1024): (code_va >> 4) & 0xffffffff, (1076, 1056): code_va >> 36, (1085, 1077): min(len(k["text"]) >> 8, 0x1ff),
        (1103, 1088): block[0], (1119, 1104): block[1], (1127, 1120): block[2], (1136, 1128): k["regs"], (1141, 1137): k["barriers"],
        (1162, 1152): shmem >> 7, (1168, 1163): smem_cfg, (1174, 1169): 0x1a, (1180, 1175): smem_cfg, (1215, 1200): slm >> 4,
        (1279, 1248): grid[0], (1295, 1280): grid[1], (1327, 1312): grid[2],
        (1375, 1344): (cb_va >> 6) & 0xffffffff, (1394, 1376): cb_va >> 38, (1407, 1395): (len(cbuf) + 15) >> 4, (1856, 1856): 1, (1859, 1859): 1,
        (1919, 1888): (code_va >> 8) & 0xffffffff, (1936, 1920): code_va >> 40}.items(): qmd_set(q, hi, lo, v)
    qm.write(0, bytes(q))
    state["sem"] = state.get("sem", 2) + 1
    submit(method(1, 0x1698, 0x1011) + method(1, 0x2b4, q_va >> 8) + method(1, 0x2c0, 9) + release(state["sem"]))
    return wait(state["sem"], name)

  N = 1000
  _, a, a_va = buffer(N * 4); _, b, b_va = buffer(N * 4)
  a.write(0, struct.pack(f"<{N}f", *[float(i) for i in range(N)]))
  dt = launch(cubin, "add1", ((N + 127) // 128,), (128,), struct.pack("<QQi", a_va, b_va, N))
  out = struct.unpack(f"<{N}f", ctypes.string_at(b.addr, N * 4))
  bad = [i for i in range(N) if out[i] != i + 1.0]
  print(f"add1 b[i] = a[i] + 1, n {N}: {'OK' if not bad else f'{len(bad)} wrong, first {bad[:5]} -> {[out[i] for i in bad[:5]]}'} ({dt * 1e6:.0f} us)")
  ok = not bad

  M = 64
  _, s, s_va = buffer(M * 256 * 4); _, o, o_va = buffer(M * 4)
  s.write(0, struct.pack(f"<{M * 256}f", *[float(i % 7) for i in range(M * 256)]))
  dt = launch(cubin, "blocksum", (M,), (256,), struct.pack("<QQ", s_va, o_va))
  got = struct.unpack(f"<{M}f", ctypes.string_at(o.addr, M * 4))
  want = [float(sum(i % 7 for i in range(j * 256, j * 256 + 256))) for j in range(M)]
  print(f"blocksum (shared memory, barriers), {M} blocks: {'OK' if list(got) == want else f'wrong {got[:4]} want {want[:4]}'} ({dt * 1e6:.0f} us)")
  ok = ok and list(got) == want

  if use_ats:  # plain process memory (Python's malloc), never registered with RM or UVM
    n = 4096
    ha = ctypes.create_string_buffer(struct.pack(f"<{n}f", *[float(i) for i in range(n)])); hb = ctypes.create_string_buffer(n * 4)
    dt = launch(cubin, "add1", (n // 128,), (128,), struct.pack("<QQi", ctypes.addressof(ha), ctypes.addressof(hb), n))
    got = struct.unpack(f"<{n}f", hb.raw)
    good = all(got[i] == i + 1.0 for i in range(n))
    print(f"ATS: add1 on malloc'd memory at {ctypes.addressof(ha):#x}: {'OK' if good else 'WRONG ' + str(got[:4])} ({dt * 1e6:.0f} us)")
    ok = ok and good

  if True:
    _, d, d_va = buffer(0x1000)
    launch(cubin, "dims", (3, 2, 1), (4, 5, 6), struct.pack("<Q", d_va), dyn_smem=256)
    print("dims kernel (blockDim xyz, gridDim xyz, dynamic smem, total smem, dyn ptr):", [hex(x) for x in struct.unpack("<9I", ctypes.string_at(d.addr, 36))])
  return 0 if ok else 1

if __name__ == "__main__": sys.exit(main())
