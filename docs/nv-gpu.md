# NvComputeGPU: the World on the GB10 without a graphics driver

`NvComputeGPU` (package Graphics-NV, layer 1) is a GPU device for Graphics-GPU that renders on an NVIDIA GPU through
nothing but the image's own RM client (System-NV, docs/nv-rm.md) and the raster kernels (`NvRasterKernels`,
docs/nv-kernels.md): no CUDA, no Vulkan, no OpenGL. It is a `SoftwareGPU` (docs/uefi.md) with the memory and the pixel
work replaced, so the device protocol, handles, errors and the Renderer-only shader rule are the same, and the pixels are
too: the kernels are bit-exact with PlatformRaster.

    vm/build/samaltak build/samaltak.image --gpu nv          # or SAMALTAK_GPU=nv: the World on the GB10
    vm/build/samaltak build/samaltak.image --gpu software    # the same, on a SoftwareGPU (the CPU)
    make test-nv                                             # NvComputeGPUTest, replays, the World under Xvfb

## Choosing it

`GPUPlatform chooseBackends` (on first use after the image starts) reads `--gpu NAME`, else the environment's
`SAMALTAK_GPU`: `nv` is an NvComputeGPU, `software` a SoftwareGPU, nothing the default (SDL_GPU where the VM has
windows, a SoftwareGPU on the firmware's display on UEFI). The windows and events stay the platform's. Where the device
cannot be made (no Graphics-NV, no `/dev/nvidiactl`, `NvDevice open` fails) the default is used and stderr says
`Samaltak: --gpu: no NVIDIA GPU here: the default GPU instead`; an unknown name likewise.

## How

| | SoftwareGPU | NvComputeGPU |
| --- | --- | --- |
| textures, buffers, back buffers | `Machine allocate:` | `NvMemory` (system memory mapped for both; SoftwareGPU keeps its CPU address) |
| clear | `rasterFill` | `raster_fill` |
| draw | `rasterDraw` | `raster_prims` then `raster_tiles` (RasterDrawParams from the pass's state; one scratch for all draws) |
| blit | `rasterBlit` | `raster_blit` |
| uploads, downloads | CPU copies | the same CPU copies, after waiting for the launches that use that memory |
| fences | done when made | the channel's fence values |
| present | the display gets the back buffer's address | the same, once the GPU drew it |

SoftwareGPU's 'memory and pixels' methods are the seam (`allocate:`, `free:`, `touch:`, `fill:...`,
`draw:buffer:offset:first:count:`, `blit:...`, `present:`). Launches are queued in call order on one compute channel
and run while the CPU encodes on; every launch ends with a semaphore release with wait-for-idle, so they run one after
another (a draw's `raster_tiles` reads what its `raster_prims` wrote, and later draws see earlier ones). Each memory
remembers the fence of the last launch that used it; the CPU waits for it before writing (uploads), reading (downloads,
present) or freeing it, and nowhere else. `shaderLanguage` is `'raster'`: not software, so the Compositor composes
continuously as on SDL_GPU; FragmentShaders fail as on a SoftwareGPU.

**Presenting.** The device presents the BGRA8 back buffer from its CPU address on its display
(`presentWindow:pixels:width:height:`). Hosted that is a `HostFramePresenter` (Graphics-GPU): it copies the frame into a
ByteArray, uploads it into a BGRA8 texture of an SDL_GPU device of its own and blits that onto the window's swapchain. On
UEFI it would be `FirmwareDisplay` (FirmwareScreen draws the frame into the GOP framebuffer, as for a SoftwareGPU),
unchanged, once System-NV runs there (docs/nv.md, Phase B): nothing in NvComputeGPU is hosted-only but NvDevice.

**Launch path** (System-NV, `NvCompute>>launch:grid:block:parameters:`): the QMD and constant bank 0 templates of the
kernel are copied and patched at offsets found once (grid, block, bank 0's address, the parameter struct), and a
pushbuffer made once is submitted with the QMD's address and the fence value patched in (`NvChannel>>submitBytes:fenceAt:`):
about 1.2 µs of CPU and 3 µs of GPU a launch (the GPU's, with the wait-for-idle). The shader caches are invalidated when
a kernel's code is uploaded, not at each launch, and launches raise no interrupt (waits poll). `NvCubin` now gives a
kernel its own constant banks (`.nv.constant2.raster_tiles`: raster_tiles' jump table, bound as bank 2).

**Lost doorbells.** Now and then a doorbell reaches the GB10 before the GPPut written just before it: the work then waits
for the next doorbell (once 5 s, until the timeout). `Machine barrier` (`__sync_synchronize`, `dmb ish` on arm64)
orders the stores for the CPUs only; a `dsb st` would order them for the GPU, which needs a VM change. Meanwhile
`NvChannel>>wait:` rings the doorbell again after 20 µs without progress (`rerings` counts it), timed by the real clock
(`Time utcMicroseconds`: on the recording clock the image's clock stands still during a frame).

## Tests

`make test-nv` (tests/nv/run.sh), on the GB10:

- `NvComputeGPUTest`: every SoftwareGPUTest (coverage, blends, patterns, lines, blits, regions, swapchain, handles, the
  Renderer through GPUPlatform) on an NvComputeGPU.
- `tests/nv/replay.st`: the World's first frames recorded at 1920x1080 by a SoftwareGPURecorder replayed through the gpu
  protocol (`SoftwareGPUReplay`, Tests-Graphics) on an NvComputeGPU and on a SoftwareGPU: every pass's target and every
  frame equal to the record, byte for byte (19 passes and 3 frames in about 0.2 s).
- `tests/nv/world_test.sh`: the World hosted on a private Xvfb at 1920x1080 on the recording clock, `SAMALTAK_GPU=nv`
  then `software`: each on its device without a compositor error, and the screenshots equal outside the live
  statistics (the top bar's frame time, the Process Browser's CPU column), within 2 levels: the SoftwareGPU composes only
  when something changed, and a cross-fade may still be a level from its end there (unloaded, they were identical).

test-core needs no GPU: `GPUPlatformTest` (the choice, with a stand-in for the NVIDIA class), `NvCubinTest` (bank 2),
SoftwareGPUTest on the refactored SoftwareGPU.

## Numbers

On the GB10 (DGX Spark), the World of the Tools at 1920x1080 under Xvfb, hosted; SDL_GPU on NVIDIA's Vulkan driver
(`VK_DRIVER_FILES=.../nvidia_icd.json`). Composite: the Compositor's whole-screen composite (desk, the windows' layers
as images, top bar) into an offscreen 1920x1080 texture, then wait for idle; redraw: every window's layer rendered again
first. Wall and the compositor Process's CPU time per frame, mean of 20 after 3; live: the Compositor's own frames over
5 s (FrameRecord end - start, its CPU share).

| | composite | redraw | live frame | compositor CPU |
| --- | --- | --- | --- | --- |
| NvComputeGPU | 1.1 ms (CPU 1.1) | 8.3 ms (CPU 7.7) | 5.5 ms, 60 fps | 28 % (4.7 ms a frame) |
| SoftwareGPU | 3.8 ms (CPU 3.6) | 5.9 ms (CPU 5.7) | 10.6 ms, on change only | 6 % (rests) |
| SDL_GPU, Vulkan | 0.21 ms (CPU 0.10) | 0.44 ms (CPU 0.21) | 3.4 ms, 60 fps | 11 % (1.9 ms) |

The CPU time of NvComputeGPU includes its waits, which poll. A composite is GPU-bound (about 20 draws); the live frame
adds the present (GPU work, an 8 MB copy, SDL's upload and blit). A redraw is about 210 draws, 430 launches: each draw's
`raster_tiles` covers its whole scissor, mostly empty tiles, so a draw costs about 40 µs, nearly all of it the GPU's.
Batching a pass's draws into one launch pair (the kernels' work) would remove most of it; the present would shrink
without the ByteArray copy if `gpuUploadTexture` took an address.
