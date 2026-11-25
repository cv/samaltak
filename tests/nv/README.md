# tests/nv: the raster kernels on the GPU

`make test-nv` (`tests/nv/run.sh`) checks the CUDA raster kernels (`gpu/nv/raster.cu`, checked in as
`NvRasterKernels`; docs/nv-kernels.md) on this machine's NVIDIA GPU against PlatformRaster's C
(`vm/gen/platform_raster.c`). It needs the GPU, its driver (libcuda) and `cuda.h`, not nvcc, and is not part of
`make test` or CI (which have no NVIDIA GPU); the checks that need no GPU are `NvRasterKernelsTest` and
`SoftwareGPURecorderTest` in test-core.

- `replay.cpp`: loads the cubin with the CUDA driver API (`cuModuleLoadData`, `cuLaunchKernel` with the parameter
  structs: what a launcher without the CUDA runtime does) and links the C reference twice, without floating-point
  contraction (`-ffp-contract=off`, as the UEFI VM) and with it (gcc's default, as the hosted VM).
  - `replay fuzz <cubin> <cases> [seed]`: random draws (every mode, cell and variant, R8/RGBA8/BGRA8 textures, both
    targets, the three blends, nearest/linear, clamp/repeat, quads at any position and scale and the 1:1 ones, triangles
    positioned explicitly or by quad corner, scissors, viewports, translations), blits, copies and fills; the GPU must
    equal the reference without contraction, byte for byte. It prints how many primitives took each path.
  - `replay fuzzbatch <cubin> <cases> [seed]`: the same draws, 1 to 40 a case into one target, launched as one batch
    (`raster_batch_prims`, `raster_batch_tiles`) against the reference applying them one after another.
  - `replay replay <cubin> <record> [timing passes]`: replays a record of what a SoftwareGPU got and produced (textures,
    buffers, uploads, clears, draws, blits, each pass's target at its end, each presented frame) on the GPU and on both
    references; at each pass end and frame it compares the GPU, the references and the recorded pixels (then carries on
    from the recorded ones), and prints each command buffer's GPU time (the sum of its kernels, from CUDA events).
- `record.st`: the `--eval` that records the World's first frames at 1920x1080 (the Tools' default desktop) through a
  `SoftwareGPURecorder` (Tests-Graphics; its comment has the record format) into `$OUT/nv/world.nvrec` (about
  150 MB for 6 frames).

- `replay.st`: the same record replayed by the image itself (`SoftwareGPUReplay`) on an `NvComputeGPU` (Graphics-NV:
  the kernels launched through libcuda, docs/nv-gpu.md) and on a `SoftwareGPU`: every pass end and frame must equal the
  record, byte for byte.
- `world_test.sh`: the World hosted on a private Xvfb at 1920x1080 on the recording clock with `SAMALTAK_GPU=nv` and then
  `software`; `world_compare.st` checks the devices, that the compositor had no error, and that the screenshots are equal
  outside the live statistics (top bar, the Process Browser's CPU column); then both again on the appliance's screen
  path (`SAMALTAK_SCREEN=memory:1920x1080`: KmsDisplay, no SDL window), compared with `NV_SUFFIX=-kms`.

- `frames.sh [OUT] [cuda software]` (not part of `make test-nv`): what rendering costs in the nine interactions of
  docs/graphics-damage.md (`RenderScenarios`, Tests-Tools-Agent: a hidden 1920x1080 World on a private Xvfb, the
  events injected) on each device; per scenario and presented frame the renderer's CPU (median, 90th percentile, mean
  and its stages), the compositor's CPU, kernel launches, waits and GPU span. `NV_FRAMES_NSYS=1` profiles the libcuda
  run with nsys, and `frames_nsys.py [OUT]` reads it: the kernels per frame, their GPU time and their launch calls'.
- `graph_bench.cpp` (built by hand: `c++ -O2 -I$CUDA/include tests/nv/graph_bench.cpp -o graph_bench -lcuda`): a frame's
  small launches as stream launches or as a CUDA graph replayed with new parameters, CPU and GPU per frame (docs/nv-gpu.md,
  Small frames: why NvComputeGPU does not use graphs).

`make test-nv` also runs `NvComputeGPUTest` (SoftwareGPUTest on an NvComputeGPU) with NvCudaComputeTest and the CUDA libraries' GPU tests. Fails if the GPU differs from the reference without contraction anywhere, or a recorded frame equals neither reference.
