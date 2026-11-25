# NVIDIA GPU (GB10)

Samaltak runs compute kernels on the NVIDIA GB10 (DGX Spark: Blackwell, integrated, PCI `10de:2e12`, compute
capability 12.1, 48 SMs) through NVIDIA's CUDA userspace: libcuda (the driver API) and the CUDA runtime, which every
place Samaltak runs on the GB10 has (hosted on DGX OS; the Linux appliance with its CUDA root, docs/cuda.md and
docs/linux-appliance.md). libcuda is the only GPU backend. An earlier one drove `nvidia.ko` through RM ioctls with no
userspace; it was removed (cv/samaltak#20) and is archived in docs/nv-rm.md and at the tag `archive/nv-rm`.

```smalltalk
NvCudaDevice during: [:gpu | | compute fill a |
	compute := gpu newCompute.
	fill := NvTestKernels cubin kernelNamed: 'fill'.
	a := gpu allocate: 4096.
	compute run: fill grid: 4 block: 256 arguments: {a gpuAddress. 7. 1024}.
	a uint32At: 4092]                                          "7"
```

## Layers

| what | classes | docs |
| --- | --- | --- |
| kernels: cubins, NVRTC | `NvCubin`, `NvKernel`, `NvElfSection`, `NvRtc` (System-NV) | below; docs/nv-shaders.md |
| device, memory, launches | `NvCudaDevice`, `NvCudaMemory`, `NvCudaCompute` (System-CUDA) | below; docs/cuda.md |
| the World's GPU | `NvComputeGPU` (Graphics-NV) on the raster kernels (`NvRasterKernels`, `gpu/nv`) | docs/nv-gpu.md, docs/nv-kernels.md |
| fragment shaders | `NvShaderCompiler`, `NvPrecompiledShaders` (Graphics-NV) | docs/nv-shaders.md |
| the CUDA libraries | `Cuda`, `CudaArray`, cuBLAS, cuRAND, cuSOLVER, cuFFT, cuOpt (System-CUDA); `GpuMonitor` and the demos (Tools-CUDA) | docs/cuda.md |

## The compute protocol

What launches kernels is small, and everything above uses only it (NvComputeGPU, `Cuda compute`, the shaders,
GpuMonitor's view of the allocations, the tests):

- **device** (`NvCudaDevice`): `open`, `during:`, `close` (frees what it made), `isAvailable` (libcuda and the runtime
  load and see a device), `allocate:` and `allocate:gpuCached:` (memory both reach; the flag is a hint CUDA may ignore),
  `newCompute`, `computeCapability` (121), `arch` (`sm_121`, NVRTC's `-arch`), `smCount`. It is the runtime's
  primary context on device 0, the one `Cuda`, `CudaArray`, cuBLAS and cuRAND use.
- **memory** (`NvCudaMemory`): `cudaMallocHost`'s pinned memory, zeroed, at one address for the CPU and the GPU
  (`gpuAddress` = `cpuAddress`), a CUDA allocation the VM knows (so cuBLAS takes its address); `uint32At:(put:)`,
  `uint64At:(put:)`, `bytesAt:count:`, `bytesAt:put:`, `fill:bytes:from:` (0-based offsets, checked), `free`,
  `isFreed` (also after a snapshot is restored: never a stale address).
- **compute** (`NvCudaCompute`): `launch:grid:block:arguments:` (asynchronous; answers a fence value; arguments as
  `NvKernel>>parameterBytes:` takes them, CudaArrays and memory as their addresses), `launch:grid:block:parameters:`
  (the parameter area as bytes), `run:grid:block:arguments:` (launch and wait), `fence`, `wait:`, `sync`,
  `completedValue`, `timestamp:payload:` (the GPU's clock, `%globaltimer`, written once the work before is done),
  `forget:` (unload a kernel's module once none of it is left), `close`. A kernel's cubin is loaded once
  (`cuModuleLoadData`), its function looked up once; a launch is one `cuLaunchKernel` on the default stream; a fence
  is a word the stream writes (`cuStreamWriteValue64`) when one is first waited for or asked about. `channel`
  answers the compute itself (fences and timestamps are asked of it), and its L2 flushes do nothing: CUDA keeps the
  CPU coherent.

Where libcuda is not (no CUDA userspace, no device: the appliance without its CUDA root, a machine without an NVIDIA
GPU), `NvCudaDevice isAvailable` and `NvComputeGPU isAvailable` are false, and `--gpu nv` falls back without an
error: GPUPlatform says why on stderr (`Samaltak: --gpu: nv: no CUDA userspace (...): software rendering instead`) and
renders in software on the appliance's screen (the default GPU, SDL_GPU, hosted).

## Cubins for sm_121

`nvcc -arch=sm_121 -cubin` (CUDA 13.0) writes an ELF64 little-endian executable: EI_OSABI 0x41 (CUDA), ABI version 8, e_type 2 (EXEC), e_machine 190 (EM_CUDA), e_flags 0x06007902 (0x79 = 121 in bits 15:8; `EF_CUDA_SM121 EF_CUDA_VIRTUAL_SM(SM121)`). Everything is position-independent code at address 0; the CUDA driver (`cuModuleLoadData`) places the sections and applies the relocations. Per kernel `k` (`extern "C"` keeps the names plain):
- `.text.k` (PROGBITS, flags AX, align 128): the SASS. Its symbol `k` (FUNC, GLOBAL) has the size.
- `.nv.constant0.k` (PROGBITS, flags 0x42): bank 0's size and initial contents (zeros: driver area plus parameters). Other banks (`.nv.constant3`, … for `__constant__` data) are the kernel's constant buffers.
- `.nv.shared.k` (NOBITS): static shared memory, including the 1 KB every CTA reserves on sm_90 and later (`.nv.shared.reserved.0`, `.nv.reservedSmem.cap` 0x400): `add1` (no `__shared__`) has 0x400, `blocksum` (1 KB array) 0x800, and dynamic shared memory starts at 0x400 after it. A kernel without the section still needs 0x400.
- `.nv.info` (type 0x70000000 SHT_CUDA_INFO, for all kernels) and `.nv.info.k` (sh_info = the section index of `.text.k`): attributes, each a u8 format, a u8 attribute, a u16 size, then (format 4, EIFMT_SVAL) size bytes of payload — formats 1 NVAL (no value), 2 BVAL and 3 HVAL carry the value in the size field. Seen:
  - in `.nv.info`, keyed by the kernel's symbol table index: 0x2F EIATTR_REGCOUNT (sym, registers: add1 10, blocksum 12), 0x11 EIATTR_FRAME_SIZE (sym, bytes), 0x12 EIATTR_MIN_STACK_SIZE (sym, bytes);
  - in `.nv.info.k`: 0x37 CUDA_API_VERSION (0x82), 0x17 KPARAM_INFO (12 bytes per parameter: u32 index, u16 ordinal, u16 offset, u32 with log alignment 7:0, space 11:8, cbank 16:12 (0x1F), size in bytes 31:18), 0x50 SPARSE_MMA_MASK, 0x1B MAXREG_COUNT (0xFF), 0x4C NUM_BARRIERS (BVAL; blocksum 1, absent when 0), 0x5F MERCURY_ISA_VERSION (0x101), 0x4A VRC_CTA_INIT_COUNT, 0x1C EXIT_INSTR_OFFSETS (u32 offsets of EXITs), 0x19 CBANK_PARAM_SIZE (HVAL: parameter bytes), 0x0A PARAM_CBANK (u32 symbol of `.nv.constant0.k`, u16 offset 0x380, u16 size), 0x36 SW_WAR.
- `.rela.text.k`: relocations, for kernels that take the address of their own data (device globals, `__constant__`): R_CUDA_64 (type 2, a 64-bit address), 0x38 and 0x39 (low and high 32 bits into an instruction's immediate at offset + 4). The driver applies them; NvCubin reads them (`NvKernel>>relocations`, `bankRelocations`). NVRTC's kernels that call `sinf` and the like (docs/nv-shaders.md) have `.rela.nv.constant4` instead: R_CUDA_64 at bank 4's offset 0, the address of libdevice's `__cudart_i2opi_f` in `.nv.global.init`.
- `.nv.capmerc.text.k` and `.nv.merc.*` ("Mercury": a capability-preserving form the driver can recompile for other Blackwell parts) are ignored; `.text.k` runs as is.

sm_120 cubins (what tinygrad's NVRTC compiles for this GPU) run on GB10 too.

NvCubin (`NvCubin on: bytes`) reads all of this into NvKernels: code, registers, frame and stack sizes, static shared
memory, parameters (KPARAM_INFO), the parameter area in bank 0 (PARAM_CBANK), MAX_THREADS, exit offsets, the banks
and their relocations, the cubin's data; `NvKernel>>cubin` keeps the bytes libcuda loads. NvCubinTest checks it
without a GPU. Test kernels: `tests/nv/test-kernels.cu` → `tools/nv-test-kernels.sh` (nvcc 13.0, `-cubin
-arch=sm_121`) → `src/Tests-NV/NvTestKernels.st` (Base64), so building the image never needs nvcc.

## Tests and numbers

`make test-core` runs NvCubinTest and the other tests that need no GPU (NvRasterKernelsTest, GlslShaderTest,
GPUPlatformTest). `make test-nv` (a GPU machine, not CI) runs NvCudaComputeTest (the test kernels on libcuda:
memory, fences, local and shared memory, constant banks, launch dimensions and limits, NVRTC then cuBLAS on one
stream, timestamps), NvComputeGPUTest, NvFragmentShaderTest and the CUDA libraries' GPU tests, then the raster
kernels against PlatformRaster (tests/nv). `NvGpuMeasure report` (evaluate it) measures on the GB10, best of a few
runs: fence round trip 4 µs, launch one block and wait 7 µs, queued launches 2.1 µs each, copy16 of 64 MB 249 GB/s
(docs/cuda.md has the comparison with the RM path it replaced).

## GB10 specifics

- No video memory; all memory is system memory, coherent with the CPU over C2C: pinned host memory is the GPU's own,
  which it reads at full speed.
- CUDA says compute capability 12.1 (sm_121); sm_120 cubins run too.
- The display controller and the Spark's own services share the GPU: open, allocate and free like any client; never
  reset it or reload its modules.

## History

Phase A drove the GB10 through `nvidia.ko`'s RM ioctls from Smalltalk, without NVIDIA's userspace (docs/nv-rm.md,
archived: the objects, struct layouts, channels, QMDs and constant bank 0 it needed; tag `archive/nv-rm`). Phase B was
to speak the same RM API to the GPU's own firmware (GSP) from the bare UEFI app; it was dropped (cv/samaltak#20) for
the Linux appliance, its research archived in docs/nv-gsp.md, its code at the tag `archive/uefi-bare-metal`.
