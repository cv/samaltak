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
| textures, buffers, back buffers | `Machine allocate:` | `NvMemory` (system memory mapped for both; SoftwareGPU keeps its CPU address): textures in the GPU's L2, buffers and back buffers not |
| clear | `rasterFill` | `raster_fill` |
| draw | `rasterDraw` | batched: a target's consecutive draws as one `raster_batch_prims` and one `raster_batch_tiles` |
| blit | `rasterBlit` | `raster_blit` |
| uploads, downloads | CPU copies | the same CPU copies, after waiting for the launches that use that memory |
| fences | done when made | the channel's fence values; elapsed from the GPU's clock |
| present | the display gets the back buffer's address | the same, once the GPU drew it |

SoftwareGPU's 'memory and pixels' methods are the seam (`allocate:`, `free:`, `touch:`, `fill:...`,
`draw:buffer:offset:first:count:`, `blit:...`, `present:`). Launches are queued in call order on one compute channel
and run while the CPU encodes on; every launch ends with a semaphore release with wait-for-idle, so they run one after
another (`raster_batch_tiles` reads what `raster_batch_prims` wrote, later launches see earlier ones). Each memory
remembers the fence of the last launch that used it; the CPU waits for it before writing (uploads), reading (downloads,
present) or freeing it, and nowhere else.

**Batches.** A draw does not launch: its RasterDrawParams (the pass's state, the vertices' address) join the batch of
its target. The batch goes out when anything else comes (a draw into another target, a clear, a blit, a CPU access, a
submit): the params and each draw's first slot are written into an arena (GPU memory used as a ring, the GPU done with
its start before it is reused), then `raster_batch_prims` (a thread per slot of all the draws, each with its draw's
state, 64 threads a block) and `raster_batch_tiles` (16 x 16 tiles over the union of the draws' scissors within the
target; a tile skips each 256 slots none of whose chunks' bounding boxes meets it, lists the slots over it in order and
applies each with its own draw's blend, texture and sampler). A pixel sees the
draws in order, so the pixels are the same as draw by draw (docs/nv-kernels.md). A layer is two launches, not two a draw.

**Memory and the L2.** On the GB10 the GPU's L2 is not coherent with the CPU for system memory: memory allocated
`gpuCached` (`NvDevice allocate:gpuCached:`) is fast for kernels, but the CPU does not see their writes until the L2
writes its dirty lines back, nor do kernels see the CPU's writes while the L2 holds older lines (all memory cached, the
channel hangs: the GPU reads stale QMDs). NvComputeGPU caches what kernels use most and the CPU touches least: textures
(layer surfaces, glyph atlases, images) and the draws' scratch. Buffers (vertices, uniforms, a batch's params), written by
the CPU for nearly every draw, and back buffers, which the CPU reads every frame, stay uncached. It keeps them in step
as UVM does on an integrated GPU (uvm_blackwell_host.c): after a launch the L2 may hold dirty lines, so before the CPU
reads or writes cached memory (a download, an upload, freeing) the channel runs sysmembar, L2_FLUSH_DIRTY, sysmembar
(`NvChannel>>flushL2`) and the CPU waits for it; after the CPU wrote cached memory (an upload, a new allocation's
zeroes) the next launch is preceded by the flush and an L2_SYSMEM_NCOH_INVALIDATE (`flushAndInvalidateL2`).
`NvComputeGPUTest>>testTheL2AndTheCPUAgree` fails without either.

**Fences** keep the channel's value of the last launch when submitted; `fenceElapsed:` is the GPU's time for the command
buffer: before its first clear, draw or blit and after its last, a semaphore release with RELEASE_TIMESTAMP writes the
GPU's clock (ns) into a ring of 256 slots (`NvChannel>>timestamp:payload:`); the fence is done once its end stamp is
there. `shaderLanguage` is `'raster'`: not software, so the Compositor composes
continuously as on SDL_GPU. FragmentShaders (ShaderViews, Claude's Robot) run as CUDA kernels made from their GLSL,
precompiled or compiled in the image by NVRTC (docs/nv-shaders.md).

**Presenting.** The device presents the BGRA8 back buffer from its CPU address on its display
(`presentWindow:pixels:width:height:`). Hosted that is a `HostFramePresenter` (Graphics-GPU): it uploads the frame from
that address (`gpuUploadTexture` takes an Integer address too) into a BGRA8 texture of an SDL_GPU device of its own and
blits that onto the window's swapchain: 0.33 ms for the upload, about 3 ms for SDL's acquire, blit and present to the X
server (what SDL_GPU's own frames pay too). On
UEFI it would be `FirmwareDisplay` (FirmwareScreen draws the frame into the GOP framebuffer, as for a SoftwareGPU),
unchanged, if System-NV ever ran there (it does not: docs/nv.md, Phase B): nothing in NvComputeGPU is hosted-only but NvDevice.

**Launch path** (System-NV, `NvCompute>>launch:grid:block:parameters:`): the QMD and constant bank 0 templates of the
kernel are copied and patched at offsets found once (grid, block, bank 0's address, the parameter struct), and a
pushbuffer made once is submitted with the QMD's address and the fence value patched in (`NvChannel>>submitBytes:fenceAt:`):
about 1.2 µs of CPU and 3 µs of GPU a launch (the GPU's, with the wait-for-idle). The shader caches are invalidated when
a kernel's code is uploaded, not at each launch, and launches raise no interrupt (waits poll). `NvCubin` now gives a
kernel its own constant banks (`.nv.constant2.raster_tiles`: raster_tiles' jump table, bound as bank 2).

**Fences and wraps.** A fence value used to be taken before the pushbuffer was started over (or the ring drained),
whose own fence then came first: the semaphore went back (drain N + 1, then launch N), and a wait for N returned while
launch N had not run; the memory it used could be freed under it. About one World start in three stalled for the 5 s
timeout near fence 1430 (the 64 KB pushbuffer wraps every 1500 or so launches). `NvChannel>>makeRoomFor:` now wraps
and drains first (`testFencesAcrossWrapsAndDrains`); no stall in 25 starts since. Waits poll by the real clock
(`Time utcMicroseconds`: on the recording clock the image's clock stands still during a frame); a timeout says the
error notifier's status. `Machine barrier` is `dmb osh` on arm64 (Linux's dma_mb: the devices' domain), no longer
`__sync_synchronize`'s `dmb ish`.

**Stack frames.** A kernel's stack starts 16r240 bytes below the top of a thread's local window and grows down into its
frame, so a thread's local memory must be 16r240 plus the frame. NvCompute gave every kernel 16r240: a kernel with a
frame wrote past it (`raster_batch_tiles` with 24 bytes of spills hung; `local1k`, 1 KB, got 3000 wrong sums of 3000).
NvCompute now sizes the QMD's local memory per kernel and grows the channel's when a kernel needs more
(`localMemoryPerThread:`, `NvGpuTest>>testLocalMemory`). `raster_batch_tiles` stays at `__maxnreg__(128)`: no spills
is faster.

## Tests

`make test-nv` (tests/nv/run.sh), on the GB10:

- `NvComputeGPUTest`: every SoftwareGPUTest (coverage, blends, patterns, lines, blits, regions, swapchain, handles, the
  Renderer through GPUPlatform) on an NvComputeGPU.
- `NvGpuTest>>testFencesAcrossWrapsAndDrains`, `NvComputeGPUTest>>testFenceElapsedIsTheGPUsTime`.
- `replay fuzzbatch`: 20000 cases of 1 to 40 random draws (every path, blend, format, sampler, texture, scissor and
  viewport of the fuzz) into one target as one batch, against the C reference applying them one after another.
- `tests/nv/replay.st`: the World's first frames recorded at 1920x1080 by a SoftwareGPURecorder replayed through the gpu
  protocol (`SoftwareGPUReplay`, Tests-Graphics) on an NvComputeGPU and on a SoftwareGPU: every pass's target and every
  frame equal to the record, byte for byte (30 passes and 6 frames in about 0.35 s).
- `tests/nv/world_test.sh`: the World hosted on a private Xvfb at 1920x1080 on the recording clock, `SAMALTAK_GPU=nv`
  then `software`: each on its device without a compositor error, and the screenshots equal outside the live
  statistics (the top bar's frame time, the Process Browser's CPU column), within 2 levels: the SoftwareGPU composes only
  when something changed, and a cross-fade may still be a level from its end there (unloaded, they were identical).
  Then both again on the appliance's screen path, `SAMALTAK_SCREEN=memory:1920x1080` (a `KmsDisplay` on a
  `KmsScreen` in memory, no SDL window: what the Spark's KMS screen gets but for the device, docs/linux-appliance.md),
  compared the same way.

test-core needs no GPU: `GPUPlatformTest` (the choice, with a stand-in for the NVIDIA class), `NvCubinTest` (bank 2),
SoftwareGPUTest on the refactored SoftwareGPU.

## Numbers

On the GB10 (DGX Spark), the World of the Tools at 1920x1080 under Xvfb, hosted; SDL_GPU on NVIDIA's Vulkan driver
(`VK_DRIVER_FILES=.../nvidia_icd.json`). Composite: the Compositor's whole-screen composite (desk, the windows' layers
as images, top bar) into an offscreen 1920x1080 texture, then wait for idle; redraw: every window's layer rendered again
first. Wall and the compositor Process's CPU time per frame, mean of 20 or 30 after 3 (two runs: their range); live:
the Compositor's own frames over 5 s (FrameRecord end - start, its CPU share).

| | composite | redraw | live frame | compositor CPU |
| --- | --- | --- | --- | --- |
| NvComputeGPU | 0.39 ms (CPU 0.37) | 2.5-2.7 ms (CPU 1.4) | 4.6-4.9 ms, 60 fps | 20-25 % |
| NvComputeGPU, textures uncached | 0.43-0.47 ms (CPU 0.43-0.46) | 2.8 ms (CPU 1.75) | 4.9-5.3 ms, 60 fps | 21-23 % |
| NvComputeGPU, a draw at a time | 1.1 ms (CPU 1.1) | 8.3 ms (CPU 7.7) | 5.5 ms, 60 fps | 28 % (4.7 ms) |
| SoftwareGPU (main's NEON raster) | 1.7 ms (CPU 1.5) | 3.2 ms (CPU 2.9) | 7.4 ms, on change only | 5 % (rests) |
| SoftwareGPU before it | 3.9 ms (CPU 3.7) | 5.7-5.9 ms (CPU 5.5) | 11 ms, on change only | 6 % (rests) |
| SDL_GPU, Vulkan | 0.21-0.25 ms (CPU 0.10-0.16) | 0.44-0.57 ms (CPU 0.21-0.31) | 3.3 ms, 60 fps | 10 % (1.7 ms) |

The CPU time of NvComputeGPU includes its waits, which poll. A redraw is about 210 draws: batched, 2 launches a window's
layer instead of 2 a draw. Its GPU time (timestamp releases around each launch, 13 batches): `raster_batch_tiles` 0.74
ms (1.08 with textures uncached), `raster_batch_prims` 0.43-0.59 ms (0.73 with the scratch uncached too), the clears
0.09 ms; what is left waits on the vertices and params, uncached. The live frame is mostly SDL's present to the X
server (3 ms, as for SDL_GPU's own frames): within its noise either way. Back buffers cached made it worse (5.1 ms: 8 MB
written back every frame), buffers cached too (an invalidate after each upload) the redraw (3.0 ms).

World interaction (samaltak-ctl under Xvfb: eight drags of the System Browser, then typing 38 characters into the Workspace,
about 3.8 s of frames; two runs each): textures cached, frames 4.8-4.9 ms on average, 95th percentile 8.0-8.2 ms, the
longest 35 ms, compositor 21-22 %; uncached, 5.1-5.2 ms, 8.1-8.4 ms, 36-39 ms, 21-24 %.
