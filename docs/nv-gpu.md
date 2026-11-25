# NvComputeGPU: the World on the GB10 without a graphics driver

`NvComputeGPU` (package Graphics-NV, layer 1) is a GPU device for Graphics-GPU that renders on an NVIDIA GPU with the
raster kernels (`NvRasterKernels`, docs/nv-kernels.md), launched through NVIDIA's CUDA userspace (libcuda: `NvCudaDevice`
and `NvCudaCompute`, System-CUDA, docs/nv.md): no Vulkan, no OpenGL. It is a `SoftwareGPU` (docs/uefi.md) with the
memory and the pixel work replaced, so the device protocol, handles, errors and the Renderer-only shader rule are the
same, and the pixels are too: the kernels are bit-exact with PlatformRaster. Its memory is CUDA's pinned host memory and
its launches are on the CUDA runtime's context and default stream, the ones cuBLAS and `CudaArray` use. libcuda is its
only backend: an RM-ioctl one (System-NV's own RM client) was removed (docs/nv-rm.md, archived).

    vm/build/samaltak build/samaltak.image --gpu nv          # or SAMALTAK_GPU=nv: the World on the GB10
    vm/build/samaltak build/samaltak.image --gpu software    # the same, on a SoftwareGPU (the CPU)
    make test-nv                                             # NvComputeGPUTest, replays, the World under Xvfb

## Choosing it

`GPUPlatform chooseBackends` (on first use after the image starts) reads `--gpu NAME`, else the environment's
`SAMALTAK_GPU`: `nv` is an NvComputeGPU, `software` a SoftwareGPU, nothing the default (SDL_GPU where the VM has
windows, a SoftwareGPU on the firmware's display on UEFI or on the appliance's KMS screen). The windows and events stay
the platform's. Where the device cannot be made (no Graphics-NV; no CUDA userspace: libcuda, the CUDA runtime and a
device, `NvComputeGPU isAvailable`; `NvCudaDevice open` fails) the default is used, without an error, and stderr says
why and what instead: `Samaltak: --gpu: nv: no CUDA userspace (libcuda and the CUDA runtime, with a device): software
rendering instead` on the appliance's screen (the Spark without its CUDA root), `...: the default GPU instead` hosted;
an unknown name likewise.

## How

| | SoftwareGPU | NvComputeGPU |
| --- | --- | --- |
| textures, buffers, back buffers | `Machine allocate:` | `NvCudaMemory` (`cudaMallocHost`: one address for the CPU and the GPU; SoftwareGPU keeps it) |
| clear | `rasterFill` | `raster_fill` |
| draw | `rasterDraw` | batched: a target's consecutive draws as one `raster_batch_prims` and one `raster_batch_tiles` |
| blit | `rasterBlit` | `raster_blit` |
| uploads, downloads | CPU copies | buffers: CPU copies after the draws reading that range; textures up to 256 KB: into the arena, then `raster_copy` in launch order; downloads and larger uploads: CPU copies after the launches using that memory |
| fences | done when made | the stream's fence values; elapsed from the GPU's clock |
| present | the display gets the back buffer's address | the same, once the GPU drew it |

SoftwareGPU's 'memory and pixels' methods are the seam (`allocate:`, `free:`, `touch:`, `fill:...`,
`draw:buffer:offset:first:count:`, `blit:...`, `present:`). Launches are queued in call order on the default stream
(`cuLaunchKernel`, the cubin loaded once by `cuModuleLoadData`) and run while the CPU encodes on, one after another
(`raster_batch_tiles` reads what `raster_batch_prims` wrote, later launches see earlier ones). Each memory remembers
the fence of the last launch that used it, a buffer the fences of the ranges draws read; the CPU waits for them before
writing (a buffer's upload: only for the draws reading its range; small texture uploads go through the arena in launch
order instead), reading (downloads, present) or freeing it, and nowhere else (Small frames, below).

**Batches.** A draw does not launch: its RasterDrawParams (the pass's state, the vertices' address) join the batch of
its target. The batch goes out when anything else comes (a draw into another target, a clear, a blit, a CPU access to
memory it uses, a submit): the params and each draw's first slot are written into an arena (GPU memory used as a ring, the GPU done with
its start before it is reused), then `raster_batch_prims` (a thread per slot of all the draws, each with its draw's
state, 64 threads a block) and `raster_batch_tiles` (16 x 16 tiles over the union of the draws' scissors within the
target, or only those the scissors meet when they are scattered; a tile skips each 256 slots none of whose chunks' bounding boxes meets it, lists the slots over it in order and
applies each with its own draw's blend, texture and sampler). A pixel sees the
draws in order, so the pixels are the same as draw by draw (docs/nv-kernels.md). A layer is two launches, not two a draw.

**Memory.** CUDA keeps pinned host memory coherent between the CPU and the GPU on the GB10: what a kernel wrote is
there once its fence is reached, what the CPU wrote before a launch the kernel sees. NvComputeGPU still marks textures
and the draws' scratch as memory the GPU may cache (`allocate:gpuCached:`, a hint CUDA does not need) and still calls
the compute's L2 flushes around CPU access to them (`flushL2`, `flushAndInvalidateL2`: nothing on libcuda, but
`writeBackL2` waits for the stream once); what the RM backend needed for its non-coherent L2, left to simplify.
`NvComputeGPUTest>>testTheL2AndTheCPUAgree` checks uploads over pixels a kernel read and downloads of what kernels wrote.

**Fences** keep the stream's value of the last launch when submitted (a word the stream writes, `cuStreamWriteValue64`,
when a fence is first waited for or asked about; waits poll by the real clock, asking the stream now and then whether a
kernel faulted). `fenceElapsed:` is the GPU's time for the command buffer: before its first clear, draw or blit and
after its last, a one-thread kernel writes the GPU's clock (`%globaltimer`, ns) into a ring of 256 slots
(`timestamp:payload:`); the fence is done once its end stamp is there. `shaderLanguage` is `'raster'`: not software,
so the Compositor composes continuously as on SDL_GPU. FragmentShaders (ShaderViews, Claude's Robot) run as CUDA
kernels made from their GLSL, precompiled or compiled in the image by NVRTC (docs/nv-shaders.md).

**Presenting.** The device presents the BGRA8 back buffer from its CPU address on its display
(`presentWindow:pixels:width:height:`). Hosted that is a `HostFramePresenter` (Graphics-GPU): it uploads the frame from
that address (`gpuUploadTexture` takes an Integer address too) into a BGRA8 texture of an SDL_GPU device of its own and
blits that onto the window's swapchain: 0.33 ms for the upload, about 3 ms for SDL's acquire, blit and present to the X
server (what SDL_GPU's own frames pay too). On the appliance it is a `KmsDisplay` (the image's KMS screen: the frame
copied into a dumb buffer, docs/linux-appliance.md).

**History.** The RM backend's launch path (QMDs and constant bank 0 patched per launch, a pushbuffer made once), its
fixes (fences across pushbuffer wraps, local memory sized per kernel's stack frame) and its L2 handling are in
docs/nv-rm.md and at the tag `archive/nv-rm`. On libcuda the driver sizes a kernel's local memory and places its
constant banks; `NvCudaComputeTest>>testLocalMemory` and `testConstantBank` check it.

## Small frames

An ordinary interactive frame (docs/graphics-damage.md's nine interactions, damage-limited: a typed character, a hovered
item, a dragged window) renders a few hundred to a few thousand pixels in one or two layers and the composite. On the
libcuda backend it had cost more than on the CPU: not the launches (5 to 14 a frame, batched already), but the CPU
waiting for the GPU inside the frame and the GPU drawing far more than the damage.

- **Waits.** Each list the Renderer uploads into its vertex ring waited for every launch that had used the ring, and a
  glyph or Form uploaded mid-frame for every launch that had used its texture: 4 to 7 GPU round trips a frame, each
  also ending the batch (so 4 to 5 batches a frame, not 2), each a GPU scheduling latency (0.5 to 2.5 ms when other
  processes keep the GPU busy, as on this shared machine). Now a buffer upload waits only for the draws that read its
  range (NvComputeGPU keeps the ranges a batch's draws read, with their fence), and a texture upload of up to 256 KB goes
  through the arena and `raster_copy` in launch order, as SDL_GPU's copy pass does: one wait a frame, its present.
- **Pixels.** A batch's tiles covered the bounds of its draws' clips: a typed character and the top bar's readout made
  the composite's `raster_batch_tiles` run 8160 blocks (the whole screen), the damage fills drew under a full-target
  scissor, and `raster_blit` ran a grid over the whole destination for each damage rectangle. Now a batch whose clips are
  scattered passes the list of the tiles they meet (`tilesOf:within:`, RasterBatchParams' `tiles`, docs/nv-kernels.md),
  the fills are scissored to their rectangles (`Renderer>>fill:color:into:commandBuffer:`) and a blit's grid covers its
  rectangle.

Measured with `tests/nv/frames.sh` (RenderScenarios: the nine interactions in a hidden 1920x1080 World under Xvfb, events
injected) and nsys (`NV_FRAMES_NSYS=1`, `tests/nv/frames_nsys.py`), on the GB10 shared with other GPU work (load 10-36).
Per presented frame, before (origin/main with the counters) → after. GPU: the kernels' own time (nsys), not waiting for
the GPU; render: the renderer's CPU from the frame's lists to a frame ready to present (layer and composite encoding,
the blit and the present's wait; the median of the frames, best of three runs: the other processes' load on the GPU
moves a run's latencies by milliseconds); SoftwareGPU's render is its rasterizing on the CPU (the same stages).

| scenario | kernels | waits | GPU µs | NV render µs | SoftwareGPU render µs |
| --- | --- | --- | --- | --- | --- |
| idle-caret | 16.5 → 13.2 | 7.0 → 1.2 | 295 → 171 | 1418 → 523 | 771 → 558 |
| typing | 17.9 → 13.5 | 6.1 → 1.0 | 343 → 170 | 626 → 346 | 251 → 190 |
| idle-after | 19.0 → 11.0 | 5.3 → 1.0 | 369 → 146 | 467 → 338 | 238 → 143 |
| scroll-list | 15.3 → 8.5 | 5.1 → 1.0 | 294 → 102 | 765 → 581 | 346 → 270 |
| hover | 14.2 → 8.0 | 4.3 → 1.0 | 287 → 96 | 448 → 345 | 183 → 169 |
| drag-window | 7.9 → 6.6 | 3.1 → 1.0 | 432 → 195 | 506 → 274 | 672 → 552 |
| agent-open | 16.3 → 10.8 | 6.3 → 1.1 | 522 → 267 | 771 → 479 | 2765 → 3035 |
| agent-stream | 15.1 → 10.6 | 6.2 → 1.0 | 337 → 179 | 480 → 230 | 197 → 148 |
| idle-end | 16.8 → 11.5 | 6.0 → 1.0 | 392 → 166 | 727 → 463 | 323 → 232 |

(kernels include the 3 to 4 timestamp kernels a frame; under load a run's medians were up to 3x these.) The NV frame
now costs the CPU 35-60 % less and the GPU 45-65 % less. It is faster than the CPU where a frame draws much (dragging a
window 274 against 552 µs, a window opening 479 against 3035, the caret's frames), not yet where it draws a few hundred
pixels: there SoftwareGPU rasterizes in 20-80 µs, while NV's fixed cost is its present's wait for the GPU (about 60 µs
idle, a GPU timeslice or more when other processes load it), about 13 launches and timestamps at 2 µs, and building a
draw's 200-byte RasterDrawParams in Smalltalk.

**CUDA Graphs** were measured and not taken. `tests/nv/graph_bench.cpp` issues a frame of 6 or 12 small kernels 2 ms
apart as stream launches, as a graph with each node's parameters set (cuGraphExecKernelNodeSetParams), and as the graph
captured: CPU 33 / 22 / 20 µs and GPU 23 / 17 / 13 µs for 6 kernels, 49 / 22 / 19 and 38 / 22 / 16 for 12 (medians, C,
two events and a fence included). A frame's shape changes with its damage (batches, blits, copies), so the graph would be
updated each frame, and from Smalltalk each node's update is an FFI call like a launch (2 µs in the image, the driver's
cost): it would save the GPU 1.5 µs a kernel, 10-20 µs a frame, against the 100-250 µs the tile lists and the waits
saved. The single tiled pass is what a batch is (one `raster_batch_prims` and one `raster_batch_tiles` a target),
now over the damaged tiles only; one launch for the whole frame cannot be had, the composite sampling the layers drawn
before it.

## Tests

`make test-nv` (tests/nv/run.sh), on the GB10:

- `NvComputeGPUTest`: every SoftwareGPUTest (coverage, blends, patterns, lines, blits, regions, swapchain, handles, the
  Renderer through GPUPlatform) on an NvComputeGPU.
- `NvCudaComputeTest` (the launches, fences and memory below NvComputeGPU), `NvComputeGPUTest>>testFenceElapsedIsTheGPUsTime`.
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

Measured on the RM backend this device had then (docs/nv-rm.md, archived); on libcuda a frame of about 30 launches is
5-10 % slower, all of it GPU time (docs/cuda.md has those numbers).

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
