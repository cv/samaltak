# NVIDIA GPU (GB10)

How to run compute kernels on the NVIDIA GB10 (DGX Spark: Blackwell, integrated, PCI `10de:2e12`, compute capability 12.1) without NVIDIA's user-space libraries: the open kernel module's resource manager (RM) API, ioctls on `/dev/nvidiactl` and `/dev/nvidia0` (and `/dev/nvidia-uvm` where wanted), with driver 580.178.04. Phase A of Samaltak's NVIDIA driver works through these ioctls on hosted Linux; Phase B (below) will speak the same RM API to the GPU's own firmware (GSP) from UEFI.

`tools/nv-probe.py` is the executable form of this document: Python's standard library and ctypes, no CUDA, no tinygrad. It opens the GPU, builds the objects below, and launches three kernels compiled by nvcc 13.0 for sm_121 (`tools/nv-probe.cu`: `add1`, `blocksum` with shared memory and barriers, `dims` reading blockDim, gridDim and dynamic shared memory) and checks their results. It needs a GPU and is no part of any test target.

    tools/nv-probe.py          # VA space owned by RM: no nvidia-uvm at all
    tools/nv-probe.py --uvm    # VA space owned by nvidia-uvm, as tinygrad and CUDA do
    tools/nv-probe.py --ats    # --uvm with ATS: kernels read and write malloc'd process memory at its CPU address

All three pass on GB10 (driver 580.178.04): channel setup round trip about 0.15–0.35 ms, a launch of `add1` (8 CTAs) to its semaphore 10–30 µs.

Sources cited: the open-gpu-kernel-modules tree at tag 580.178.04 (`~/src/github.com/NVIDIA/open-gpu-kernel-modules`; SDK headers under `src/common/sdk/nvidia/inc`, below `inc/`), tinygrad's NV backend `tinygrad/runtime/ops_nv.py` at commit f0b80032 (838 lines), and the QMD header `clcec0qmd.h` that tinygrad carries in `extra/nv_gpu_driver/` (NVIDIA, MIT; not in the kernel tree). Struct offsets were checked with `offsetof` against the 580.178.04 headers (aarch64, LP64; x86-64 is the same).

## The path, in short

1. Open `/dev/nvidiactl`; allocate a root client (`NV01_ROOT_CLIENT`).
2. Open `/dev/nvidia0`, link it to the control fd (`NV_ESC_REGISTER_FD`).
3. Allocate device `NV01_DEVICE_0` and subdevice `NV20_SUBDEVICE_0`; query GR info (SM version, GPC/TPC/SM counts).
4. Allocate a VA space `FERMI_VASPACE_A` and a virtual memory object `NV01_MEMORY_VIRTUAL` over it.
5. Memory is system memory (`NV01_MEMORY_SYSTEM`): GB10 has no video memory. Map each allocation for the CPU (`NV_ESC_RM_MAP_MEMORY` with a fresh fd, then `mmap` of that fd at offset 0) and for the GPU (`NV_ESC_RM_MAP_MEMORY_DMA` → GPU VA).
6. Channel group `KEPLER_CHANNEL_GROUP_A` (engine GR), context share `FERMI_CONTEXT_SHARE_A`, GPFIFO channel `BLACKWELL_CHANNEL_GPFIFO_A` (ring and USERD in a system memory allocation), compute object `BLACKWELL_COMPUTE_B` on it; get the work submit token; schedule the group.
7. Allocate `HOPPER_USERMODE_A` on the subdevice and map it through `/dev/nvidia0`: the doorbell is at offset 0x90.
8. Write a pushbuffer (methods), put a GPFIFO entry pointing to it in the ring, bump GPPut in USERD, write the token to the doorbell; wait for a semaphore the pushbuffer releases.
9. A kernel launch is a QMD (queue meta data, 384 bytes) and its constant bank 0 (driver parameters, then the kernel's parameters at 0x380) in GPU memory, sent with two compute methods.

## Device files and ioctls

`/dev/nvidiactl` (char 195:255) carries the RM API; `/dev/nvidia0` (195:0) is the GPU: BAR mappings (the usermode doorbell page) and `NV_ESC_RM_ALLOC_MEMORY`; `/dev/nvidia-uvm` (its own major) only for the UVM and ATS paths. All are mode 0666 on the Spark. An ioctl request is `_IOWR('F', nr, size)` = `0xC0000000 | size << 16 | 0x46 << 8 | nr`; the kernel takes the argument's size from the request (`_IOC_SIZE`, 14 bits on arm64 and x86-64) and copies that much in and out (`kernel-open/nvidia/nv.c` 2380–2460, `nvidia_ioctl`). Every RM call answers in its `status` field (an `NV_STATUS`, `inc/nvstatus.h`); the ioctl itself fails only for bad sizes or copies.

| nr | name | fd | argument | source |
|---|---|---|---|---|
| 0x27 | `NV_ESC_RM_ALLOC_MEMORY` | nvidia0 | `nv_ioctl_nvos02_parameters_with_fd` (56) | escape.c 320 |
| 0x29 | `NV_ESC_RM_FREE` | ctl | `NVOS00_PARAMETERS` (16) | escape.c 438 |
| 0x2a | `NV_ESC_RM_CONTROL` | ctl | `NVOS54_PARAMETERS` (32) | escape.c 722 |
| 0x2b | `NV_ESC_RM_ALLOC` | ctl | `NVOS21_PARAMETERS` (32) or `NVOS64_PARAMETERS` (48, with access rights) | escape.c 387 |
| 0x4e | `NV_ESC_RM_MAP_MEMORY` | ctl | `nv_ioctl_nvos33_parameters_with_fd` (56) | escape.c 513 |
| 0x57 | `NV_ESC_RM_MAP_MEMORY_DMA` | ctl | `NVOS46_PARAMETERS` (64) | escape.c 630 |
| 0xc8 | `NV_ESC_CARD_INFO` | ctl | array of `nv_ioctl_card_info_t` (72 each) | nv.c 2527 |
| 0xc9 | `NV_ESC_REGISTER_FD` | nvidia0 | `nv_ioctl_register_fd_t` (4): the ctl fd | escape.c 850 |
| 0xd3 | `NV_ESC_IOCTL_XFER_CMD` | any | `nv_ioctl_xfer_t` (16) | nv.c 2411–2437 |

Numbers: `src/nvidia/arch/nvalloc/unix/include/nv_escape.h` 27–53 (RM escapes), `kernel-open/common/inc/nv-ioctl-numbers.h` 29–42 (`NV_IOCTL_BASE` 200 and up); escape.c is `src/nvidia/arch/nvalloc/unix/src/escape.c` (`RmIoctl`, from 299). Requests seen on GB10: alloc `0xC020462B`, control `0xC020462A`, map `0xC038464E`, map DMA `0xC0404657`, alloc memory `0xC0384627`, register fd `0xC00446C9`, card info for 64 GPUs `0xD20046C8`.

**Large parameters.** `nv_ioctl_xfer_t` {cmd@0, size@4, ptr@8 (u64)} (`kernel-open/common/inc/nv-ioctl.h` 40–52) passes an escape whose argument does not fit the request's size field: the kernel copies `size` bytes from `ptr`, up to `NV_ABSOLUTE_MAX_IOCTL_SIZE` = 16384 (`kernel-open/common/inc/nv.h` 70). With 14 size bits that only matters on architectures with 13 (tinygrad masks sizes to 13 bits, `nv_iowr`, ops_nv.py 41–43). The large RM structures are not passed in the ioctl anyway: `NV_ESC_RM_ALLOC` and `NV_ESC_RM_CONTROL` carry a pointer and size (`pAllocParms`/`params`, `paramsSize`) and RM copies the class or control parameters itself.

**Mmap contexts.** `NV_ESC_RM_MAP_MEMORY` validates a mapping and records it in the file passed in its `fd` field; the next `mmap` of that fd (offset 0, the same length) makes it (`kernel-open/nvidia/nv-mmap.c` 506–640, `nvidia_mmap_helper`: no valid context → EINVAL, `vm_pgoff != 0` → EINVAL, a size other than the context's → ENXIO). A file holds one context, so every mapping gets a fresh fd: `/dev/nvidiactl` for system memory (the control node maps system memory), `/dev/nvidia0` linked by `NV_ESC_REGISTER_FD` for BAR space such as the usermode page. The fd may be closed after `mmap`. The kernel overrides the caching type the caller asks for (`NVOS33_FLAGS_CACHING_TYPE_DEFAULT`, escape.c 527–528).

## Struct layouts

Fields are NvU32 unless sized otherwise (`(8)` = NvU64 or a pointer, NvP64 aligned to 8); `@` is the byte offset; the total size in parentheses. All `status` fields are out.

ioctl wrappers (`src/nvidia/arch/nvalloc/unix/include/nv-unix-nvos-params-wrappers.h` 33–46, `kernel-open/common/inc/nv-ioctl.h`):
- `nv_ioctl_nvos02_parameters_with_fd` (56): params `NVOS02_PARAMETERS`@0, fd@48 (int; -1 when not mapping).
- `nv_ioctl_nvos33_parameters_with_fd` (56): params `NVOS33_PARAMETERS`@0, fd@48 (the fd to `mmap`).
- `nv_ioctl_register_fd_t` (4): ctl_fd@0 (nv-ioctl.h 124–127).
- `nv_ioctl_card_info_t` (72): valid@0 (NvBool), pci_info@4 {domain@4, bus@8, slot@9, function@10, vendor_id@12 (u16), device_id@14 (u16)}, gpu_id@16, interrupt_line@20 (u16), reg_address@24 (8), reg_size@32 (8), fb_address@40 (8), fb_size@48 (8), minor_number@56, dev_name@60 (10 bytes) (nv-ioctl.h 54–66). On the Spark one valid entry: gpu_id 0xF0100 (domain 0xF, bus 1), minor 0.

RM API (`inc/nvos.h`):
- `NVOS21_PARAMETERS` (32), alloc (462–471): hRoot@0 (the client), hObjectParent@4, hObjectNew@8 (in: 0 lets RM choose; out: the handle), hClass@12, pAllocParms@16 (8), paramsSize@24, status@28. The root client is allocated with hRoot = hObjectParent = 0 and its handle comes back in hObjectNew (RM forces the class to `NV01_ROOT_CLIENT`, escape.c 403–409). RM-chosen handles look like 0xC1D07AD8 (client) and 0xCAF000nn (objects).
- `NVOS54_PARAMETERS` (32), control (2229–2238): hClient@0, hObject@4, cmd@8, flags@12, params@16 (8), paramsSize@24, status@28. `paramsSize` must be the control's exact size: `NVA06C_CTRL_CMD_GPFIFO_SCHEDULE` with 4 instead of 3 fails with 0x1F (`NV_ERR_INVALID_ARGUMENT`, `inc/nvstatuscodes.h` 60).
- `NVOS00_PARAMETERS` (16), free (160–166): hRoot@0, hObjectParent@4, hObjectOld@8, status@12.
- `NVOS02_PARAMETERS` (48), alloc memory (283–293): hRoot@0, hObjectParent@4, hObjectNew@8, hClass@12, flags@16, pMemory@24 (8), limit@32 (8; size − 1), status@40. Used for `NV01_MEMORY_SYSTEM_OS_DESCRIPTOR` (0x71): wraps existing process memory (pMemory) as an RM memory object; flags (190–278) PHYSICALITY 7:4, LOCATION 11:8, COHERENCY 15:12, MAPPING 31:30 — tinygrad uses 0x40001010 (noncontiguous, cached, no map).
- `NVOS33_PARAMETERS` (48), map for the CPU (1844–1854): hClient@0, hDevice@4, hMemory@8, offset@16 (8), length@24 (8), pLinearAddress@32 (8, out: a cookie, not the address), status@40, flags@44 (1732–1829: ACCESS 1:0, MAPPING 16:15, CACHING_TYPE 25:23, which the kernel resets).
- `NVOS46_PARAMETERS` (64), map for the GPU (2167–2183): hClient@0, hDevice@4, hDma@8 (the `NV01_MEMORY_VIRTUAL` object), hMemory@12, offset@16 (8), length@24 (8), flags@32, flags2@36, kindOverride@40, dmaOffset@48 (8; in with DMA_OFFSET_FIXED, out: the GPU VA), status@56. Flags (1974–2040): ACCESS 1:0, CACHE_SNOOP 4:4, SHADER_ACCESS 7:6, PAGE_SIZE 11:8 (1 = 4 KB), DMA_OFFSET_FIXED 15:15. The probe uses 0x110 (4 KB pages, snooped); tinygrad 0x8110 (fixed).

Allocation parameters (`pAllocParms`):
- `NV0080_ALLOC_PARAMETERS` (56) for `NV01_DEVICE_0` (`inc/class/cl0080.h` 54–64): deviceId@0 (0), hClientShare@4 (the client), hTargetClient@8, hTargetDevice@12, flags@16, vaSpaceSize@24 (8), vaStartInternal@32 (8), vaLimitInternal@40 (8), vaMode@48 (0 = `NV_DEVICE_ALLOCATION_VAMODE_OPTIONAL_MULTIPLE_VASPACES`, nvos.h 2853).
- `NV2080_ALLOC_PARAMETERS` (4) for `NV20_SUBDEVICE_0`: subDeviceId@0 (0).
- `NV_VASPACE_ALLOCATION_PARAMETERS` (56) for `FERMI_VASPACE_A` (nvos.h 3154–3164): index@0 (0 = new), flags@4, vaSize@8 (8; 0 = default), vaStartInternal@16 (8), vaLimitInternal@24 (8), bigPageSize@32, vaBase@40 (8), pasid@48. Flags (3166–3182): IS_EXTERNALLY_OWNED bit 3 (UVM owns the page tables), ENABLE_NVLINK_ATS bit 4, ENABLE_PAGE_FAULTING bit 6.
- `NV_MEMORY_VIRTUAL_ALLOCATION_PARAMS` (24) for `NV01_MEMORY_VIRTUAL` (`inc/class/cl0070.h`): offset@0 (8), limit@8 (8; 0 = the whole VA space), hVASpace@16 (0 = the device's default VA space).
- `NV_MEMORY_ALLOCATION_PARAMS` (128) for `NV01_MEMORY_SYSTEM` (nvos.h 1608–1642): owner@0 (the client), type@4, flags@8, width@12, height@16, pitch@20, attr@24, attr2@28, format@32, comprCovg@36, zcullCovg@40, rangeLo@48 (8), rangeHi@56 (8), size@64 (8), alignment@72 (8), offset@80 (8), limit@88 (8), address@96 (8), ctagOffset@104, hVASpace@108, internalflags@112, tag@116, numaNode@120. Values that work on GB10: type 13 (`NVOS32_TYPE_NOTIFIER`; 0 `IMAGE` is the usual one), flags 0xC101 (`IGNORE_BANK_PLACEMENT | ALIGNMENT_FORCE | MEMORY_HANDLE_PROVIDED | MAP_NOT_REQUIRED`, 1444–1464), attr = LOCATION_PCI (1 at 26:25) | PHYSICALITY (1 noncontiguous / 2 contiguous at 28:27) | PAGE_SIZE 4KB (1 at 24:23) (917–1090), attr2 = GPU_CACHEABLE_NO (2 at 3:2) | ZBC_PREFER_NO_ZBC (1) (1106–1273), format 6, size, alignment 0x1000, limit size − 1. RM writes back the attributes it chose.
- `NV_CHANNEL_GROUP_ALLOCATION_PARAMETERS` (20) for `KEPLER_CHANNEL_GROUP_A` (nvos.h 2904–2911): hObjectError@0, hObjectEccError@4, hVASpace@8, engineType@12 (1 = `NV2080_ENGINE_TYPE_GRAPHICS`, `inc/class/cl2080_notification.h` 282), bIsCallingContextVgpuPlugin@16 (u8).
- `NV_CTXSHARE_ALLOCATION_PARAMETERS` (12) for `FERMI_CONTEXT_SHARE_A` (nvos.h, ends 3237): hVASpace@0, flags@4 (SUBCONTEXT 1:0, 1 = ASYNC, 3239–3243), subctxId@8 (out).
- `NV_CHANNEL_ALLOC_PARAMS` (368) for `BLACKWELL_CHANNEL_GPFIFO_A` (`inc/alloc/alloc_channel.h` 296–342): hObjectError@0 (a memory object for the error notifier), hObjectBuffer@4 (the memory holding the ring), gpFifoOffset@8 (8; the ring's GPU VA), gpFifoEntries@16, flags@20, hContextShare@24, hVASpace@28 (0: the context share's), hUserdMemory@32 (8 × u32; [0] = memory holding USERD), userdOffset@64 (8 × u64; [0] = USERD's offset in it), engineType@128 (0), cid@132, subDeviceId@136, hObjectEccError@140, then RM-internal descriptors (instanceMem@144, userdMem@168, ramfcMem@192, mthdbufMem@216, `NV_MEMORY_DESC_PARAMS` {base (8), size (8), addressSpace, cacheAttrib}), hPhysChannelGroup@240, internalFlags@244, errorNotifierMem@248, eccErrorNotifierMem@272, ProcessID@296, SubProcessID@300, encryptIv@304, decryptIv@316, hmacNonce@328, tpcConfigID@360: zero.

Controls (cmd = class interface << 8 | message id; `NVOS54.params`):
- `NV0000_CTRL_CMD_SYSTEM_GET_BUILD_VERSION_V2` 0x13E on the client (1032 bytes: driverVersionBuffer@0 char[256] = "580.178.04", …) (`inc/ctrl/ctrl0000/ctrl0000system.h` 2395).
- `NV0000_CTRL_CMD_GPU_GET_ID_INFO_V2` 0x205 on the client (32): gpuId@0 in (from card info), gpuFlags@4, deviceInstance@8, subDeviceInstance@12, sliStatus@16, boardId@20, gpuInstance@24, numaId@28 (`ctrl0000gpu.h` 172).
- `NV0080_CTRL_CMD_GPU_GET_CLASSLIST` 0x800201 on the device (16): numClasses@0, classList@8 (8; pointer to u32s; call with 0 first to get the count) (`ctrl0080gpu.h` 70).
- `NV2080_CTRL_CMD_GR_GET_INFO` 0x20801201 on the subdevice (32): grInfoListSize@0, grInfoList@8 (8; pointer to {index, data} pairs), grRouteInfo@16 (16, zero) (`ctrl2080gr.h` 395–403). Indexes (`ctrl0080gr.h` 114–134): SM_VERSION 0x0C, MAX_WARPS_PER_SM 0x0D, LITTER_NUM_GPCS 0x14, LITTER_NUM_TPC_PER_GPC 0x17, LITTER_NUM_SM_PER_TPC 0x20.
- `NV2080_CTRL_CMD_GPU_GET_GID_INFO` 0x2080014A (268): index@0, flags@4 (2 = binary), length@8 (16), data@12 (256): the GPU UUID UVM wants (`ctrl2080gpu.h` 1775–1790).
- `NVC36F_CTRL_CMD_GPFIFO_GET_WORK_SUBMIT_TOKEN` 0xC36F0108 on the channel (4): workSubmitToken@0 (out) (`inc/ctrl/ctrlc36f.h` 60–79).
- `NVA06C_CTRL_CMD_GPFIFO_SCHEDULE` 0xA06C0101 on the channel group (3): bEnable@0, bSkipSubmit@1, bSkipEnable@2 (u8 each) (`inc/ctrl/ctrla06c.h` 82–99).

## Objects and classes on GB10

| object | class | parent | parameters |
|---|---|---|---|
| client | `NV01_ROOT_CLIENT` 0x41 (nvos.h 184) | — | none |
| device | `NV01_DEVICE_0` 0x80 (cl0080.h 36) | client | deviceId 0, hClientShare client |
| subdevice | `NV20_SUBDEVICE_0` 0x2080 (cl2080.h 36) | device | subDeviceId 0 |
| VA space | `FERMI_VASPACE_A` 0x90F1 (cl90f1.h 33) | device | flags 0 (RM-owned) or 0x48 / 0x58 (UVM, + ATS) |
| virtual memory | `NV01_MEMORY_VIRTUAL` 0x70 (cl0070.h 32) | device | hVASpace = the VA space |
| memory | `NV01_MEMORY_SYSTEM` 0x3E (cl003e.h 33) | device | see above |
| OS memory | `NV01_MEMORY_SYSTEM_OS_DESCRIPTOR` 0x71 (cl0071.h 32) | device | via `NV_ESC_RM_ALLOC_MEMORY` |
| channel group | `KEPLER_CHANNEL_GROUP_A` 0xA06C (cla06c.h 33) | device | engineType 1 |
| context share | `FERMI_CONTEXT_SHARE_A` 0x9067 (cl9067.h 33) | channel group | hVASpace, flags 1 |
| channel | `BLACKWELL_CHANNEL_GPFIFO_A` 0xC96F (clc96f.h 27) | channel group | `NV_CHANNEL_ALLOC_PARAMS` |
| compute | `BLACKWELL_COMPUTE_B` 0xCEC0 (clcec0.h 27) | channel | none |
| usermode | `HOPPER_USERMODE_A` 0xC661 (clc661.h 26) | subdevice | none |

The device's class list on GB10 also has `BLACKWELL_CHANNEL_GPFIFO_B` 0xCA6F, `BLACKWELL_USERMODE_A` 0xC761, `BLACKWELL_DMA_COPY_B` 0xCAB5 (copy engine), `BLACKWELL_DMA_COPY_A` 0xC9B5, `BLACKWELL_INLINE_TO_MEMORY_A` 0xCD40 and the 3D class `BLACKWELL_B` 0xCE97, but not `BLACKWELL_COMPUTE_A` 0xCDC0 (GB100's): as far as its classes go, GB10 is a GB20x-family part. GR info: SM_VERSION 0xA04 (`NV2080_CTRL_GR_INFO_SM_VERSION_10_04`, `ctrl2080gr.h` 316–332; CUDA calls it 12.1, `SM_VERSION_12_01` = 0xC01 is not what RM reports), 4 GPCs × 6 TPCs × 2 SMs = 48 SMs, 48 warps per SM.

Freeing: `NV_ESC_RM_FREE` of the client frees everything under it; closing `/dev/nvidiactl` (process exit) does too. The GPU stays up for other clients (the Spark's display and services use it).

## Memory on GB10

GB10 has no video memory: one 64 MB BAR, every GPU page is system memory reached over C2C, coherent with the CPU (addressing mode ATS). So:
- `NV01_MEMORY_LOCAL_USER` (0x40, video memory) fails with `NV_ERR_NOT_SUPPORTED` (0x56). This is why tinygrad's NV backend (f0b80032) fails on GB10 out of the box: its GPFIFO buffer asks for device memory (`fifos`, ops_nv.py 615–616, `force_devmem=True`) — every allocation as `NV01_MEMORY_SYSTEM` (its `uncached=True` path) makes it run (512×512 matmul, reductions, elementwise all correct; see Notes).
- Allocate `NV01_MEMORY_SYSTEM` (LOCATION_PCI); RM pins and maps it. CPU mapping through `/dev/nvidiactl` (the control node maps system memory), GPU mapping through `NV_ESC_RM_MAP_MEMORY_DMA`.
- The page size of the Spark's kernel is 4 KB.

Three ways to give a kernel memory, all working:

**RM-owned VA space (default; no UVM).** `FERMI_VASPACE_A` flags 0, an `NV01_MEMORY_VIRTUAL` with hVASpace = that VA space, `NV_ESC_RM_MAP_MEMORY_DMA` without a fixed offset: RM picks the GPU VA (0x120000000 and up seen) and writes it to dmaOffset. The GPU VA differs from the CPU address of the mapping. RM refuses page faulting on a VA space it owns (`src/nvidia/src/kernel/gpu/mem_mgr/vaspace_api.c` 677–690: a fault-capable VA space must be externally owned), so every page a kernel touches must be mapped up front.

**UVM-owned VA space (tinygrad's and CUDA's way).** `FERMI_VASPACE_A` with flags IS_EXTERNALLY_OWNED | ENABLE_PAGE_FAULTING (0x48), vaBase 0x1000, vaSize 0x1FFFFFB000000; the `NV01_MEMORY_VIRTUAL` is the device's default (limit 0x1FFFFFFFFFFFF, hVASpace 0). Then `/dev/nvidia-uvm` (ioctl request = the bare number, no `_IOC` encoding: `UVM_IOCTL_BASE(i)` = i, `kernel-open/nvidia-uvm/uvm_ioctl.h` 38–40):
- `UVM_INITIALIZE` 0x30000001 (16): flags@0 (8), rmStatus@8 (`uvm_linux_ioctl.h` 32–38).
- `UVM_MM_INITIALIZE` 75 on a second `/dev/nvidia-uvm` fd (8): uvmFd@0 (the first), rmStatus@4 (uvm_ioctl.h 1069–1092; may answer an error that changes nothing).
- `UVM_REGISTER_GPU` 37 (40): gpu_uuid@0 (16), numaEnabled@16 (u8), numaNodeId@20, rmCtrlFd@24 (-1), hClient@28, hSmcPartRef@32, rmStatus@36 (532).
- `UVM_REGISTER_GPU_VASPACE` 25 (32): gpuUuid@0, rmCtrlFd@16, hClient@20, hVaSpace@24, rmStatus@28 (400).
- per channel, after allocating it: `UVM_REGISTER_CHANNEL` 27 (56): gpuUuid@0, rmCtrlFd@16, hClient@20, hChannel@24, base@32 (8), length@40 (8; a VA range UVM may use for the channel's buffers, tinygrad 64 MB), rmStatus@48 (425).
- per buffer: choose the GPU VA (= the CPU address: `mmap` the CPU mapping there with MAP_FIXED), `UVM_CREATE_EXTERNAL_RANGE` 73 (24): base@0, length@8, rmStatus@16 (1042); `NV_ESC_RM_MAP_MEMORY_DMA` with DMA_OFFSET_FIXED at that VA; `UVM_MAP_EXTERNAL_ALLOCATION` 33 (9264): base@0, length@8, offset@16, perGpuAttributes@24 (256 × `UvmGpuMappingAttributes` (36): gpuUuid@0, gpuMappingType@16 (1 = read-write-atomic), gpuCachingType@20, gpuFormatType@24, gpuElementBits@28, gpuCompressionType@32), gpuAttributesCount@9240 (8), rmCtrlFd@9248, hClient@9252, hMemory@9256, rmStatus@9260 (491). Freeing: `UVM_FREE` 34 (24): base, length, rmStatus (509).

**ATS: process memory directly.** With ENABLE_NVLINK_ATS added (flags 0x58) the UVM-owned VA space is ATS-enabled: RM accepts ATS only on an externally owned VA space, the PASID coming from UVM (vaspace_api.c 651–690); UVM binds the process's address space through the SMMU (SVA) at `UVM_REGISTER_GPU_VASPACE` and refuses the VA space if ATS is off (`kernel-open/nvidia-uvm/uvm_va_space.c` 1528–1557, `uvm_ats.c` 30–45; `uvm_ats_mode` is 1 on the Spark). The GPU then translates any address of the process like the CPU does: `--ats` runs `add1` on two buffers from Python's malloc, never registered with RM or UVM, at their CPU addresses. For Samaltak this means a kernel can read and write objects on the heap and memory from `Machine allocate:` in place — as long as they do not move while the GPU uses them (the GC must not compact them away: allocate GPU-visible data outside the object heap, or pin it). The ring, USERD and error notifier stay RM memory objects (RM names them by handle). Pushbuffers, QMDs, code and constant banks were RM memory in the probe; through ATS they could be plain memory too (untested).

Which for Samaltak: the RM-owned VA space is the smallest (no UVM, nine fewer ioctls, no fixed VAs); ATS is the most convenient (no per-buffer RM objects at all). nv-rm can start with the first and add the second; both need the same channel code.

## Channel: GPFIFO, USERD, doorbell

One system memory allocation (contiguous in the probe, 4 KB aligned) holds the ring of `gpFifoEntries` 8-byte entries and USERD (the probe: 1024 entries at offset 0, USERD at 0x2000; tinygrad: 0x10000 entries, USERD after them). USERD (`Nvc56fControl`, `kernel-open/nvidia-uvm/clc56f.h` 48–64; `inc/class/clc96f.h` 29–32): GPGet@0x88 (read only, the GPU's position), GPPut@0x8C (the next entry the CPU will write, modulo the ring size).

GPFIFO entry (`clc96f.h` 91–111), as one little-endian u64: bits 1:0 = 0 (FETCH unconditional), 39:2 the pushbuffer's GPU VA (4-byte aligned; entry0 GET 31:2 and entry1 GET_HI 7:0: the pushbuffer must lie below 2^40), bit 41 LEVEL (0 main, 1 subroutine; tinygrad sets 1, so does the probe), 62:42 LENGTH in 32-bit words, bit 63 SYNC (wait for the previous segment). So `entry = va | words << 42 | 1 << 41` (tinygrad `nv_submit`, ops_nv.py 98–104).

Submitting: write the pushbuffer, write `ring[put % n]`, write USERD GPPut = (put + 1) % n, then write the work submit token (from `NVC36F_CTRL_CMD_GPFIFO_GET_WORK_SUBMIT_TOKEN`, e.g. 0x40000002) as a u32 to the doorbell, `NOTIFY_CHANNEL_PENDING` at offset 0x90 of the usermode page (`inc/class/clc361.h` 30–33; the page is 64 KB, `NVC361_NV_USERMODE__SIZE`; TIME_0/TIME_1 at 0x80/0x84 is a GPU timer). The usermode page is `HOPPER_USERMODE_A` mapped through `/dev/nvidia0` (`NV_ESC_RM_MAP_MEMORY` with length 0x10000 and an nvidia0 fd that `NV_ESC_REGISTER_FD` linked to the ctl fd; flags come back 0x3000000). On arm64 the stores to cacheable memory must be visible before the doorbell store to device memory: a `dmb`/`dsb` between them (`Machine barrier`, the `machineBarrier` primitive). Python and tinygrad get away without one; Samaltak should not.

## Pushbuffer methods

A method header (`kernel-open/nvidia-uvm/clc56f.h` 287–337): bits 31:29 SEC_OP (1 = incrementing method, 3 = non-incrementing, 4 = immediate data, 5 = increment once), 28:16 COUNT of data words that follow (or the immediate data), 15:13 SUBCHANNEL, 11:0 method address / 4. So `(1 << 29) | count << 16 | subch << 13 | method >> 2`, then the words (tinygrad `nvm`, ops_nv.py 45–46, writes `2 << 28`, the same). Subchannel 0 carries host methods (the channel class), 1 compute (bind it with `SET_OBJECT` 0x0000 = 0xCEC0 on subchannel 1 first), 4 the copy engine in tinygrad.

Host (channel) methods, `clc96f.h` 35–88 and the fuller `kernel-open/nvidia-uvm/clc56f.h`:
- `SEM_ADDR_LO` 0x5C, `SEM_ADDR_HI` 0x60 (24:0), `SEM_PAYLOAD_LO` 0x64, `SEM_PAYLOAD_HI` 0x68, `SEM_EXECUTE` 0x6C — one incrementing method of 5 words. SEM_EXECUTE: OPERATION 2:0 (0 acquire, 1 release, 2 acq_strict_geq, 3 acq_circ_geq, 4 acq_and, 5 acq_nor; clc56f.h 216–221), RELEASE_WFI 20:20 (wait for idle before releasing), PAYLOAD_SIZE 24:24 (1 = 64 bits). Release with WFI, 64-bit: 0x01100001; acquire (circular ≥), 64-bit: 0x01000003.
- `NON_STALL_INTERRUPT` 0x20 (an interrupt for waiters on an event; tinygrad sends it after each release; polling needs none).
- `MEM_OP_A..D` 0x28–0x34 (TLB invalidate, L2 flush).

Compute methods (`BLACKWELL_COMPUTE_B` uses the Ampere compute method numbers, `inc/class/clc6c0.h`):
- `SET_SHADER_SHARED_MEMORY_WINDOW_A/B` 0x2A0/0x2A4 (hi, lo) and `SET_SHADER_LOCAL_MEMORY_WINDOW_A/B` 0x7B0/0x7B4 (hi, lo): where shared and local memory appear in the generic address space (tinygrad: 0x729400000000 and 0x729300000000; the same values go into constant bank 0, below).
- `SET_SHADER_LOCAL_MEMORY_A/B` 0x790/0x794 (hi, lo): the local memory (stack) buffer; `SET_SHADER_LOCAL_MEMORY_NON_THROTTLED_A/B/C` 0x2E4/0x2E8/0x2EC: bytes per TPC (hi, lo) and 0xFF. Size per TPC = round_up(round_up(bytes per thread × 32, 0x200) × warps per SM × SMs per TPC, 0x8000); the buffer = that × TPCs, rounded to 0x20000 (tinygrad `_ensure_has_local_memory`, ops_nv.py 686–694). With 0x240 bytes per thread (tinygrad's minimum) that is 0x1B0000 per TPC, 40.5 MB on GB10.
- `INVALIDATE_SHADER_CACHES_NO_WFI` 0x1698: INSTRUCTION 0:0, GLOBAL_DATA 4:4, CONSTANT 12:12 (0x1011 = all three), before a launch whose code or constants changed (clc6c0.h 555–564).
- `SEND_PCAS_A` 0x2B4: the QMD's GPU VA >> 8 (so QMDs are 256-byte aligned); `SEND_SIGNALING_PCAS2_B` 0x2C0: PCAS_ACTION 3:0, 9 = PREFETCH_SCHEDULE (clc6c0.h 357–383). These two launch.

A launch, as the probe sends it: `INVALIDATE_SHADER_CACHES_NO_WFI` 0x1011, `SEND_PCAS_A` qmd >> 8, `SEND_SIGNALING_PCAS2_B` 9, then a host semaphore release with WFI of a 64-bit counter; the CPU polls the counter. Channel setup, once: `SET_OBJECT` 0xCEC0, the two windows, the local memory buffer.

## QMD V05 (BLACKWELL_COMPUTE_B)

384 bytes (0x180; bits 0–3071), fields `NVCEC0_QMDV05_00_*` as MW(high:low) bit ranges (clcec0qmd.h 42–304; tinygrad class `QMD`, ops_nv.py 48–95, fills them by name). A launch sets:

| field | bits | value |
|---|---|---|
| QMD_GROUP_ID | 149:144 | 0x3F |
| QMD_TYPE | 153:151 | 2 GRID_CTA |
| SASS_VERSION | 455:448 | 0xA4 (SM_VERSION 0xA04: (v >> 4 & 0xF0) \| (v & 0xF)) |
| API_VISIBLE_CALL_LIMIT | 456 | 1 (no check) |
| SAMPLER_INDEX | 457 | 1 (via header index) |
| QMD_MAJOR_VERSION | 471:468 | 5 |
| INVALIDATE_TEXTURE_HEADER/SAMPLER/DATA_CACHE, INVALIDATE_SHADER_DATA_CACHE | 472, 473, 474, 475 | 1 |
| CWD_MEMBAR_TYPE | 625:624 | 1 L1_SYSMEMBAR |
| PROGRAM_ADDRESS_LOWER/UPPER_SHIFTED4 | 1055:1024, 1076:1056 | code VA >> 4 (split at bit 32) |
| PROGRAM_PREFETCH_SIZE | 1085:1077 | min(code size >> 8, 0x1FF) |
| CTA_THREAD_DIMENSION0/1/2 | 1103:1088, 1119:1104, 1127:1120 | blockDim x, y, z |
| REGISTER_COUNT | 1136:1128 | EIATTR_REGCOUNT |
| BARRIER_COUNT | 1141:1137 | EIATTR_NUM_BARRIERS (tinygrad: 1) |
| SHARED_MEMORY_SIZE_SHIFTED7 | 1162:1152 | round_up(static + dynamic shared, 128) >> 7 |
| MIN/MAX/TARGET_SM_CONFIG_SHARED_MEM_SIZE | 1168:1163, 1174:1169, 1180:1175 | min, 0x1A, min: the smallest of 32/64/100 KB holding the shared memory, / 4 KB + 1 |
| SHADER_LOCAL_MEMORY_HIGH_SIZE_SHIFTED4 | 1215:1200 | local memory bytes per thread >> 4 (0x24) |
| GRID_WIDTH/HEIGHT/DEPTH | 1279:1248, 1295:1280, 1327:1312 | gridDim x, y, z |
| CONSTANT_BUFFER_ADDR_LOWER/UPPER_SHIFTED6(i) | (1375+64i):(1344+64i), (1394+64i):(1376+64i) | bank i VA >> 6 (64-byte aligned) |
| CONSTANT_BUFFER_SIZE_SHIFTED4(i) | (1407+64i):(1395+64i) | bank size >> 4 (tinygrad writes the byte size, which over-declares harmlessly) |
| CONSTANT_BUFFER_VALID(i), _INVALIDATE(i) | 1856+4i, 1859+4i | 1 |
| PROGRAM_PREFETCH_ADDR_LOWER/UPPER_SHIFTED | 1919:1888, 1936:1920 | code VA >> 8 |

Completion can also come from the QMD itself: RELEASE_SEMAPHORE0_ADDR_LOWER/UPPER 511:480 / 536:512, PAYLOAD_LOWER/UPPER 575:544 / 607:576, RELEASE_STRUCTURE_SIZE(0) 290:289 (0 four words with timestamp, 1 one word, 2 two words), RELEASE0_ENABLE; and launches chain through DEPENDENT_QMD0_POINTER 415:384 (VA >> 8), _ACTION 339:337 (1 schedule), _PREFETCH 340, _ENABLE — tinygrad chains consecutive kernels that way (ops_nv.py 179–186). The probe uses the host semaphore after WFI instead.

## Constant bank 0

Bank 0 holds the driver's parameters, then the kernel's. Its size is the cubin's `.nv.constant0.<kernel>` (0x380 + parameter bytes); the probe puts it in the QMD's allocation at QMD + 0x200, as tinygrad does. Read off the SASS nvcc 13.0 emits for sm_121 (`cuobjdump -sass`), all byte offsets:

| offset | contents |
|---|---|
| 0x16C | read for `%total_smem_size` (the probe's value did not show up in the result: unresolved; nothing of ours uses it) |
| 0x2AC + 4 × CGA size | `%dynamic_smem_size` (CGA size 0: 0x2AC) |
| 0x2F0, 0x2F4 | shared memory window, low and high word (ops_nv.py 284: words 188–189) |
| 0x2F8, 0x2FC | local memory window, low and high (words 190–191) |
| 0x358 | 64-bit global memory descriptor (`desc[UR4]` of every load and store); zero works |
| 0x360, 0x364, 0x368 | blockDim x, y, z (`%ntid`): must be set — `add1` computes `blockIdx.x * blockDim.x + threadIdx.x` from 0x360, and with zero there only the first CTA's results land |
| 0x370, 0x374, 0x378 | gridDim x, y, z (`%nctaid`) |
| 0x37C | initial stack pointer: 0xFFFDC0 (word 223) |
| 0x380 | the kernel's parameters, in order, each at its natural alignment (EIATTR_PARAM_CBANK, EIATTR_KPARAM_INFO) |

tinygrad fills only the windows and the stack pointer (its kernels take their sizes as constants); `dims` reads back blockDim, gridDim and the dynamic shared memory size exactly as written.

## Cubins for sm_121

`nvcc -arch=sm_121 -cubin` (CUDA 13.0) writes an ELF64 little-endian executable: EI_OSABI 0x41 (CUDA), ABI version 8, e_type 2 (EXEC), e_machine 190 (EM_CUDA), e_flags 0x06007902 (0x79 = 121 in bits 15:8; `EF_CUDA_SM121 EF_CUDA_VIRTUAL_SM(SM121)`). Everything is position-independent code at address 0; the loader copies sections, it does not link. Per kernel `k` (`extern "C"` keeps the names plain):
- `.text.k` (PROGBITS, flags AX, align 128): the SASS. Copy it to a 256-byte aligned GPU address with 4 KB of padding after it (instruction prefetch reads past the end; tinygrad pads too, ops_nv.py 276). Its symbol `k` (FUNC, GLOBAL) has the size.
- `.nv.constant0.k` (PROGBITS, flags 0x42): bank 0's size and initial contents (zeros: driver area plus parameters). Other banks (`.nv.constant3`, … for `__constant__` data) become QMD constant buffers i (ops_nv.py 246–254, 174–175).
- `.nv.shared.k` (NOBITS): static shared memory, including the 1 KB every CTA reserves on sm_90 and later (`.nv.shared.reserved.0`, `.nv.reservedSmem.cap` 0x400): `add1` (no `__shared__`) has 0x400, `blocksum` (1 KB array) 0x800, and dynamic shared memory starts at 0x400 after it. A kernel without the section still needs 0x400.
- `.nv.info` (type 0x70000000 SHT_CUDA_INFO, for all kernels) and `.nv.info.k` (sh_info = the section index of `.text.k`): attributes, each a u8 format, a u8 attribute, a u16 size, then (format 4, EIFMT_SVAL) size bytes of payload — formats 1 NVAL (no value), 2 BVAL and 3 HVAL carry the value in the size field (ops_nv.py 306–310). Seen:
  - in `.nv.info`, keyed by the kernel's symbol table index: 0x2F EIATTR_REGCOUNT (sym, registers: add1 10, blocksum 12), 0x11 EIATTR_FRAME_SIZE (sym, bytes), 0x12 EIATTR_MIN_STACK_SIZE (sym, bytes);
  - in `.nv.info.k`: 0x37 CUDA_API_VERSION (0x82), 0x17 KPARAM_INFO (12 bytes per parameter: u32 index, u16 ordinal, u16 offset, u32 with log alignment 7:0, space 11:8, cbank 16:12 (0x1F), size in bytes 31:18), 0x50 SPARSE_MMA_MASK, 0x1B MAXREG_COUNT (0xFF), 0x4C NUM_BARRIERS (BVAL; blocksum 1, absent when 0), 0x5F MERCURY_ISA_VERSION (0x101), 0x4A VRC_CTA_INIT_COUNT, 0x1C EXIT_INSTR_OFFSETS (u32 offsets of EXITs), 0x19 CBANK_PARAM_SIZE (HVAL: parameter bytes), 0x0A PARAM_CBANK (u32 symbol of `.nv.constant0.k`, u16 offset 0x380, u16 size), 0x36 SW_WAR.
- `.rela.text.k`: relocations, for kernels that take the address of their own data (device globals, `__constant__`): R_CUDA_64 (type 2, a 64-bit address), 0x38 and 0x39 (low and high 32 bits into an instruction's immediate at offset + 4) — ops_nv.py 259–265. The kernels in the probe have none; Samaltak's kernels should avoid globals and keep it so.
- `.nv.capmerc.text.k` and `.nv.merc.*` ("Mercury": a capability-preserving form the driver can recompile for other Blackwell parts) are ignored; `.text.k` runs as is.

sm_120 cubins (what tinygrad's NVRTC compiles for this GPU) run on GB10 too.

## Completion and errors

A 64-bit semaphore released with WFI after the launch is the simplest fence: poll it (the probe), or wait in the kernel for an event (`NON_STALL_INTERRUPT` and an `NV01_EVENT_OS_EVENT`; not needed yet). A channel that faults (a bad address, a bad QMD) is torn down by RM's recovery and stops advancing GPGet; RM writes the error notifier (the hObjectError memory) and the kernel log has an Xid line. Other clients and the GPU go on. tinygrad reads SM and MMU fault state through a `GT200_DEBUGGER` (0x83DE) object on the channel's compute object (`on_device_hang`, ops_nv.py 727–746). Timeouts are the caller's: the probe gives up after 3 s and prints the semaphore and GPGet.

## GB10 specifics

- No video memory; all memory is system memory, coherent with the CPU over C2C; the GPU walks the CPU's page tables when ATS is on (above).
- RM reports SM version 0xA04 where CUDA says 12.1; the QMD's SASS version follows RM (0xA4).
- The display controller (`NVKMS`, `/dev/nvidia-modeset`) and the Spark's own services share the GPU: open, allocate and free like any client; never reset or reconfigure it.

## Notes from tinygrad on GB10

tinygrad f0b80032 (`DEV=NV`; `NV=1` is refused now) fails on GB10 with `rm_alloc returned 86: NV_ERR_NOT_SUPPORTED` at its first channel buffer (above). With every non-host allocation made `NV01_MEMORY_SYSTEM` (a five-line monkeypatch of `NVKIface.alloc`), it runs: `(Tensor([1,2,3])+1)` gives `[2 3 4]`, a 512×512 matmul agrees with numpy to 2e-4 (2.3 TFLOPS), a 1M-element sum and `exp` are right. It picks `BLACKWELL_COMPUTE_B`, `BLACKWELL_CHANNEL_GPFIFO_A`, `BLACKWELL_DMA_COPY_B`, `HOPPER_USERMODE_A`, and compiles for "sm_120" (it maps SM version 0xA04 to sm_120). Its sequence: client, build version, `UVM_INITIALIZE`, `UVM_MM_INITIALIZE`, card info, nvidia0 + `REGISTER_FD`, GPU id info, device, subdevice, virtual memory, class list, usermode (mapped), `NV2080_CTRL_CMD_PERF_BOOST` (ops_nv.py 582; not needed), VA space (UVM-owned), GID info, `UVM_REGISTER_GPU`, `UVM_REGISTER_GPU_VASPACE`, channel group, context share, GR info; per buffer `NV01_MEMORY_SYSTEM` + map + `UVM_CREATE_EXTERNAL_RANGE` + `NV_ESC_RM_MAP_MEMORY_DMA` (fixed) + `UVM_MAP_EXTERNAL_ALLOCATION`, host buffers as `NV01_MEMORY_SYSTEM_OS_DESCRIPTOR`; per channel the GPFIFO channel, its engine object, (compute: a `GT200_DEBUGGER`), work submit token, `UVM_REGISTER_CHANNEL`; then `GPFIFO_SCHEDULE` on the group (ops_nv.py 335–560 `NVKIface`, 565–700 `NVDevice`). The probe drops UVM, the boost, the debugger and the copy engine.

## Open questions (Phase A)

- Constant bank offset 0x16C (`%total_smem_size`) did not read back what the probe wrote; 0x358 (the memory descriptor) works as zero, but what CUDA puts there (caching policy?) is unknown.
- LEVEL_SUBROUTINE in GPFIFO entries is tinygrad's choice; main level should work as well (untested).
- `GPU_CACHEABLE_NO` system memory (as tinygrad's) is what was tested; whether `GPU_CACHEABLE_YES` is coherent enough for CPU-written inputs and CPU-read outputs on GB10 without explicit flushes, and what it gains, is to be measured.
- Whether the pushbuffer, QMDs and code may themselves be plain process memory under ATS (only kernel data was tried).
