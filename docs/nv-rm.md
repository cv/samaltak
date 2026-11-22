# System-NV: an NVIDIA GPU driven from Smalltalk

System-NV runs compute kernels on an NVIDIA GPU (the GB10: Blackwell, integrated, sm_121) from the image, through the
open kernel module's resource manager (RM) API: ioctls on `/dev/nvidiactl` and `/dev/nvidia0` made with PosixDevice
(docs/platform.md), parameter blocks built in Smalltalk. No CUDA, Vulkan or UVM user space. docs/nv.md describes the
GPU side (objects, struct layouts, memory, channels, QMD, constant bank 0, cubins) and `tools/nv-probe.py` does it in
Python; this is the Smalltalk client that follows it with an RM-owned VA space. Hosted Linux only for now (Phase A);
on UEFI PosixDevice fails and `NvDevice isAvailable` is false.

```smalltalk
NvDevice during: [:gpu | | compute vadd a b c |
	compute := gpu newCompute.
	vadd := NvTestKernels cubin kernelNamed: 'vadd'.
	a := gpu allocate: 4096. b := gpu allocate: 4096. c := gpu allocate: 4096.
	"... write floats into a and b with bytesAt:put: ..."
	compute run: vadd grid: 4 block: 256 arguments: {a gpuAddress. b gpuAddress. c gpuAddress. 1024}.
	c bytesAt: 0 count: 4096]
```

## Classes

| Class | What |
| --- | --- |
| `NvDevice` | `open`/`during:`/`close`: the RM object tree, `alloc:parent:params:`, `control:object:params:`, `free:parent:`, `allocate:` (NvMemory), `newChannel`, `newCompute`; GR info (`smVersion`, `smCount`), `classes` |
| `NvMemory` | system memory mapped for both: `gpuAddress`, `cpuAddress`, `uint32At:(put:)`, `uint64At:(put:)`, `bytesAt:count:`, `bytesAt:put:`, `free` |
| `NvChannel` | channel group + GPFIFO channel + compute object; `submit:` (an NvPushBuffer), `submitWithFence:`, `fence`, `wait:`, `sync`, `close` |
| `NvCompute` | compute class setup; `launch:grid:block:arguments:` (answers a fence), `run:...` (waits), `close` |
| `NvCubin`, `NvKernel`, `NvElfSection` | the cubin ELF: kernels, code, registers, shared memory, parameters, constant banks |
| `NvPushBuffer` | method headers and data words; host semaphore methods; GPFIFO entries |
| `NvQmd` | QMD version 5 bit fields by NVIDIA's names |
| `NvRm` | ioctl numbers, escapes, classes, commands, flags, status names, every parameter block |
| `NvStruct`, `NvError` | C structs as bytes (0-based offsets); an RM status other than NV_OK |

## Objects

`NvDevice open`: root client (`NV01_ROOT_CLIENT` 16r41, allocated with hRoot 0) → `NV_ESC_CARD_INFO` (gpu_id, minor)
→ `/dev/nvidiaN` tied to the control file (`NV_ESC_REGISTER_FD`) → `NV0000_CTRL_CMD_GPU_GET_ID_INFO_V2` (device
instance) → device (16r80) → subdevice (16r2080) → class list, GR info → VA space (`FERMI_VASPACE_A` 16r90F1, flags 0:
RM owns it and writes the page tables, no UVM) → `NV01_MEMORY_VIRTUAL` (16r70) in it, the `hDma` of every GPU mapping
→ usermode (`HOPPER_USERMODE_A` 16rC661 on the GB10) mapped for the CPU: its page holds the doorbell (16r90).

Memory (`allocate:`): `NV01_MEMORY_SYSTEM` (16r3E; the GB10 has no video memory), noncontiguous, PCI location, GPU
uncacheable, 4 KB pages; mapped for the CPU (`NV_ESC_RM_MAP_MEMORY` on a fresh `/dev/nvidiactl` file, then mmap of
that file at offset 0) and for the GPU (`NV_ESC_RM_MAP_MEMORY_DMA`; RM picks the address).

Channel (`newChannel`): ring memory (12 KB: 1024 GPFIFO entries, USERD at 16r2000), an error notifier, a 64 KB
pushbuffer, a 4 KB semaphore; channel group (`KEPLER_CHANNEL_GROUP_A`, engine graphics) → context share (async
subcontext, the VA space) → GPFIFO channel (`BLACKWELL_CHANNEL_GPFIFO_B` 16rCA6F on the GB10) → compute object
(`BLACKWELL_COMPUTE_B` 16rCEC0); work submit token (`NVC36F_CTRL_CMD_GPFIFO_GET_WORK_SUBMIT_TOKEN`); schedule the group
(`NVA06C_CTRL_CMD_GPFIFO_SCHEDULE`).

Closing frees newest first: channels (after waiting for their last fence), memory (munmap, unmap DMA, free), the
doorbell mapping, the root client (RM frees what is under it), the files. `NvDevice during:` closes on errors too;
NvGpuTest closes in tearDown. The kernel frees everything when the process exits anyway.

## Submitting

A submit copies the pushbuffer's words into the pushbuffer memory, writes the GPFIFO entry (address | words << 42 |
1 << 41) at put mod 1024, a barrier, USERD GPPut (16r8C) := put mod 1024, a barrier, the token to the doorbell. A
method header is `type << 28 | count << 16 | subchannel << 13 | method >> 2` (type 2: incrementing); subchannel 0 is
the channel class, 1 compute. Fences: host semaphore release (`SEM_ADDR_LO` 16r5C .. `SEM_EXECUTE`: release, WFI,
64-bit payload) then `NON_STALL_INTERRUPT`; waiting polls the 64-bit semaphore (5 s timeout, an error naming
GPGet/GPPut and the error notifier; by the real clock). `timestamp:payload:` releases with RELEASE_TIMESTAMP: the payload,
then the GPU's clock in ns. USERD GPGet (16r88) is not kept up to date on the GB10, so the channel drains (waits for a fence) before
the ring could overflow, and before the pushbuffer wraps (`makeRoomFor:`), before a submission takes its fence value: the
semaphore never goes back.

## Launching

Setup on the compute subchannel: `SET_OBJECT` (the compute class), local and shared memory windows (16r7B0, 16r2A0:
16r729300000000, 16r729400000000), local memory (16r790 address, 16r2E4 size per TPC: 16r240 bytes per thread for
every warp of a TPC's SMs).

Per kernel, on first launch: its code (plus 4 KB of slack: the GPU prefetches past the end) and its constant banks
other than 0 (`__constant__` data: bank 3) are uploaded, and a QMD template and a constant bank 0 template made.

Per launch (one of 64 slots of 4 KB, reused after their fence): QMD at the slot, constant bank 0 at slot + 16r200;
pushbuffer `SEND_PCAS_A` (16r2B4, QMD address >> 8), `SEND_SIGNALING_PCAS2_B` (16r2C0, 9: prefetch and schedule),
then a fence without the interrupt. The templates are copied and patched at offsets found once and the pushbuffer is
made once (`launch:grid:block:parameters:`, `NvChannel>>submitBytes:fenceAt:`): about 1.2 µs of CPU and 3 µs of GPU a
launch. `INVALIDATE_SHADER_CACHES_NO_WFI` (16r1698) goes out once, when a kernel's code is uploaded; the QMD invalidates
constant bank 0.

Constant bank 0 (sm_120/121; what the CUDA driver fills and nvcc's code reads): 16r16C shared memory size, 16r2F0
shared window, 16r2F8 local window, 16r358 a 64-bit memory descriptor (0 works), 16r360/364/368 blockDim,
16r370/374/378 gridDim, 16r37C initial stack pointer (16rFFFDC0), 16r380 the parameters (EIATTR_PARAM_CBANK), each at
its EIATTR_KPARAM_INFO offset: pointers 8 bytes, `unsigned`/`float` 4.

QMD v5 (384 bytes): group 16r3F, type grid CTA (2), major version 5, SASS version (16rA4 from SM version 16rA04),
register count, barrier count 1, shared memory size (16r400 reserved + the kernel's, in 128-byte units), SM shared
memory configs, local memory size, program address >> 4 and prefetch address >> 8 and size, grid, block, constant
buffers (address >> 6, size, valid), cache invalidations.

## Cubins

`NvCubin on: bytes` reads the ELF (docs/nv.md, Cubins for sm_121) into NvKernels: code, registers, frame and stack
sizes, static shared memory, parameters (KPARAM_INFO), the parameter area in bank 0 (PARAM_CBANK), MAX_THREADS, exit
offsets, bank 0, the kernel's own other banks (`.nv.constantN.<kernel>`) and the cubin's, relocations (read; NvCompute refuses kernels that have any).
Test kernels: `tests/nv/test-kernels.cu` → `tools/nv-test-kernels.sh` (nvcc 13.0, `-cubin -arch=sm_121`) →
`src/Tests-NV/NvTestKernels.st` (Base64), so building the image never needs nvcc. NvRm's parameter blocks follow
docs/nv.md's Struct layouts; NvEncodingTest checks their offsets.

## Tests and numbers

`make test-core` runs NvCubinTest and NvEncodingTest (no GPU). `make test-nv` runs NvGpuTest on the GPU: it is not
part of `make test` (`NvGpuTest class>>runsByDefault` is false, so `--test` without names leaves it out) and fails,
saying so, where there is no NVIDIA driver. `NvGpuMeasure report` (evaluate it) measures, on the GB10 (48 SMs),
best of a few runs:

| | |
| --- | --- |
| fence round trip (submit a semaphore release, poll) | 6 µs |
| launch one block and wait | 10 µs |
| queued launches (1000, then one wait) | 2.8 µs each, about 355,000 per second |
| copy16, 64 MB (read + write) | 547 µs, 245 GB/s |

Not done yet: relocations, dynamic shared memory, per-launch local memory sizing beyond 16r240 bytes per thread,
interrupts (waits poll), error notifier decoding, the copy engine.
