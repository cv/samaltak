# The Renderer as CUDA kernels (gpu/nv)

The pixel work of the software GPU (`PlatformRaster`, the raster primitives behind `SoftwareGPU`; docs/uefi.md) as CUDA
kernels for the NVIDIA GB10 (Blackwell, sm_121): the Renderer's uber-shader on a draw's vertices (every mode: solid,
glyphs, images, halftone, stripes, lines; quads and triangles; the three blends), fills, blits and copies. They produce
the same bytes as the C reference (`vm/gen/platform_raster.c`) compiled without floating-point contraction, as the UEFI VM
is. A launcher needs only the cubin and this ABI: no CUDA libraries (Phase A: the image's RM client, System-NV).

    gpu/nv/raster.cu        the kernels                gpu/nv/raster_abi.h      their parameter structs (the ABI)
    tools/nv-kernels.py     build (nvcc), check, extract, abi
    src/System-Devices/NvRasterKernels.st             generated: the cubin in Base64, the ABI as Smalltalk
    tests/nv/               make test-nv: the kernels on the GPU against the reference (README.md there)

`make nv-kernels` (`tools/nv-kernels.py build`) compiles with nvcc 13.0 (`/usr/local/cuda/bin/nvcc -cubin -arch=sm_121
-O3 -fmad=false`) and regenerates `NvRasterKernels`, so image builds never need nvcc (CI has none); `check` fails if the
checked-in class is not what the sources give (nvcc's output is deterministic), `extract` writes the checked-in cubin,
`abi` prints the ABI. Change the kernels, run `make nv-kernels` and `make test-nv`, commit all three.

## Exactness

PlatformRaster mixes integers (blending, coverage, sampling weights, edge functions, all exact) and doubles (the vertex
transform, uv interpolation, triangle planes). The kernels do the same operations on the same types in the same order:
doubles stay doubles, and `-fmad=false` keeps every `a * b + c` two roundings, as `-ffp-contract=off` does in C. So the
result is the reference's, bit for bit, in every mode; nothing is approximated. The hosted VM on Linux is compiled with
gcc's default, `-ffp-contract=fast`, which may fuse multiply-adds (on arm64) and could round a scaled image's or a
triangle's uv differently in a rare pixel: the World's frames recorded on this machine were identical with and without
contraction.

## Kernels

Each takes one struct by value (`raster_abi.h`); in the cubin the parameters are in constant bank 0 at 0x380 (the ABI's
`paramOffset`), `paramBytes` long. No kernel uses local memory (frame and stack sizes 0), globals or device-side calls;
`raster_tiles` has 40 bytes of constants the compiler placed in constant bank 2 (`.nv.constant2.raster_tiles`, the
ABI's `constantBank2`: bind them as bank 2 when launching it). Every kernel loops over its work with grid strides, so any
grid is correct and the one below covers the work in one pass. Blocks are 256 threads (x).

| kernel | parameters (bytes) | grid | does |
| --- | --- | --- | --- |
| `raster_prims` | RasterDrawParams (200) | ceil(slots / 256), slots = count / 3 | parse and set up a draw's primitives, write its clip |
| `raster_tiles` | RasterDrawParams (200) | ceil(w / 16) x ceil(h / 16) blocks in x, w x h the scissor within the target | shade the draw's pixels, 16 x 16 a block |
| `raster_fill` | RasterFillParams (24) | ceil(count / 256) (any) | count pixels of 1 or 4 bytes := value |
| `raster_copy` | RasterCopyParams (64) | (ceil(width / 256), height) | rows of pixels; swap red and blue, copy only alpha ≠ 0 (mode bits 1, 2) |
| `raster_blit` | RasterBlitParams (128) | (ceil(dstWidth / 256), dstHeight) | SDL_BlitGPUTexture's sampling of a source rect into a destination rect, converting formats |

Registers (sm_121): raster_prims 155, raster_tiles 48, fill 24, copy 40, blit 56. Shared memory per block: raster_tiles
6176 bytes (its `.nv.shared.raster_tiles`, the 1 KB every block reserves on sm_90 and later included), the others that
1 KB (docs/nv.md, Cubins for sm_121). `NvRasterKernels kernel: 'raster_tiles'` answers all of this from the cubin.

A **draw** is `raster_prims` then `raster_tiles` with the same parameters, in order on one queue (the second reads what the
first wrote; a later draw may reuse the scratch only after). `raster_prims` has a thread per primitive slot (three
vertices): six equal vertices without bit 31 of mode at an index divisible by six are one quad (two slots, the second
empty), as `rasterize` walks them; it runs `drawQuad`'s or `drawTriangle`'s setup, chooses the path drawQuad would (solid,
pattern, 1:1 glyph or image rows, scaled image, per-pixel shading, triangle) and writes the primitive's record and pixel
rectangle; its first thread writes the draw's clip (scissor, viewport, target). `raster_tiles` has a block per 16 x 16
tile of the clip: the block lists, in order, the primitives whose rectangle meets the tile (256 at a time, by warp
ballots), then each thread applies them to its pixel, which it reads at the first one and writes after the last. Every
path's value at a pixel depends only on that pixel and the primitive, so each pixel goes through the reference's
sequence of operations.

## Parameters

Formats and blends are the gpu primitives' codes: formats 1 R8, 2 RGBA8, 3 BGRA8; blends 0 none, 1 alpha, 2
premultiplied. Addresses are GPU virtual addresses; pixels are rows of 1 or 4 bytes, tightly packed, 4-byte ones 4-byte
aligned; vertices 4-byte aligned. Integers are little-endian, doubles IEEE. `NvRasterKernels params: #RasterDrawParams
with: {#pixels -> va. ...}` builds the bytes (fields left out are zero).

**RasterDrawParams** (200): uint64 pixels@0, int64 width@8, height@16, scissorX@24, scissorY@32, scissorW@40,
scissorH@48, double viewportX@56, viewportY@64, viewportW@72, viewportH@80, viewSizeX@88, viewSizeY@96, translateX@104,
translateY@112, uint64 texture@120 (0: none), int64 textureWidth@128, textureHeight@136, uint64 vertices@144 (vertex 0:
the vertex buffer plus the bound offset), int64 first@152, count@160, uint64 prims@168 (scratch), int32 format@176
(2 or 3), blend@180, textureFormat@184, linear@188, repeat@192 (0 or 1), pad@196. The fields are RasterState's
(SoftwarePass's state): the target, the pipeline's blend, the pass's scissor and viewport, the command buffer's vertex
uniforms (viewSize, translate), slot 0's texture and sampler. The scratch holds `RASTER_SCRATCH_HEADER` (64) +
`RASTER_PRIM_BYTES` (400) x (count / 3) bytes (`NvRasterKernels drawScratchBytes: count`), 8-byte aligned.

**RasterFillParams** (24): uint64 pixels@0, int64 count@8, int32 bpp@16 (1 or 4), uint32 value@20 (the pixel as
stored; for bpp 1 its low byte).

**RasterCopyParams** (64): uint64 dst@0, int64 dstStride@8, uint64 src@16, int64 srcStride@24 (bytes), width@32,
height@40 (pixels, rows), bpp@48 (1 or 4), mode@56 (bit 1 swap red and blue, bit 2 only pixels whose alpha is not 0).

**RasterBlitParams** (128): uint64 src@0, int64 srcWidth@8, srcHeight@16, uint64 dst@24, int64 dstWidth@32,
dstHeight@40, srcRect@48 [4], dstRect@80 [4] (x y w h, pixels), int32 srcFormat@112, dstFormat@116, linear@120, pad@124.

## Validation and speed

`make test-nv` (tests/nv) fuzzes 20000 random draws, blits, copies and fills against the reference, records the World's
first frames at 1920x1080 through a `SoftwareGPURecorder` (the Tools' default desktop: text, the halftone desk, images,
the Mandelbrot, lines) and replays them on the GPU: no byte differs, in any pass or frame. On the GB10 a frame of the
composited 1920x1080 screen (clear, the desk, the windows' layers as images, the top bar, the blit to the BGRA8
swapchain) takes about 0.55 ms of GPU time, against 3.2 ms for the C reference on one of its CPU cores; rendering a
window's layer costs about 20 µs a draw, mostly the two launches' fixed cost (a pass of 180 small draws: 4 ms), which
batching a pass's draws into one launch pair would remove.

`NvComputeGPU` (docs/nv-gpu.md) launches them from the image through System-NV, as Graphics-GPU's device (`--gpu nv`).

The checks that need no GPU run in test-core: `NvRasterKernelsTest` (the cubin decodes to what was checked in, the ABI
is consistent, params:with: lays out a struct) and `SoftwareGPURecorderTest`.
