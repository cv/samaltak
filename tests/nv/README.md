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
  - `replay replay <cubin> <record> [timing passes]`: replays a record of what a SoftwareGPU got and produced (textures,
    buffers, uploads, clears, draws, blits, each pass's target at its end, each presented frame) on the GPU and on both
    references; at each pass end and frame it compares the GPU, the references and the recorded pixels (then carries on
    from the recorded ones), and prints each command buffer's GPU time (the sum of its kernels, from CUDA events).
- `record.st`: the `--eval` that records the World's first frames at 1920x1080 (the Tools' default desktop) through a
  `SoftwareGPURecorder` (Tests-Graphics; its comment has the record format) into `$OUT/nv/world.nvrec` (about
  150 MB for 6 frames).

Fails if the GPU differs from the reference without contraction anywhere, or a recorded frame equals neither reference.
