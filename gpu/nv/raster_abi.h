/* The parameters of the raster kernels (gpu/nv/raster.cu): PlatformRaster's work (src/VM-Platform/PlatformRaster.st)
 * as CUDA kernels for sm_121. Each kernel takes one of these structs by value as its only parameter; the layouts are
 * the ABI that tools/nv-kernels.py turns into NvRasterKernels (src/System-Devices) and docs/nv-kernels.md documents.
 * Rules for this file (the tool parses it): fields are uint64_t (device addresses), int64_t, double, int32_t or
 * uint32_t, optionally arrays [n]; no padding (8-byte fields first, 4-byte ones last, an even number of them).
 * Formats and blends are the gpu primitives' codes: formats 1 R8, 2 RGBA8, 3 BGRA8; blends 0 none, 1 alpha,
 * 2 premultiplied. Pixels are rows of R8 (1 byte) or RGBA8/BGRA8 (4 bytes, 4-aligned), tightly packed. */
#ifndef SAMALTAK_RASTER_ABI_H
#define SAMALTAK_RASTER_ABI_H
#include <stdint.h>

/* The scratch raster_prims writes and raster_tiles reads (RasterDrawParams.prims): a header (the clip), then per
 * primitive slot (one per 3 vertices) its pixel rectangle and its record: RASTER_SCRATCH_HEADER + RASTER_PRIM_BYTES *
 * (count / 3) bytes, 8-byte aligned. */
#define RASTER_SCRATCH_HEADER 64
#define RASTER_PRIM_BYTES 400
/* raster_tiles: threads per block (one per pixel of a 16 x 16 tile). */
#define RASTER_TILE 16
#define RASTER_TILE_THREADS 256

/* raster_fill: count pixels of bpp bytes at pixels set to value (bpp 1: its low byte). Any grid; block 256. */
typedef struct {
	uint64_t pixels;
	int64_t count;
	int32_t bpp;
	uint32_t value;
} RasterFillParams;

/* raster_copy: height rows of width pixels of bpp bytes (1 or 4) from src to dst (row strides in bytes); 4-byte
 * pixels with mode bit 1 swap red and blue, with bit 2 only those whose alpha is not 0 are copied (PlatformRaster>>copy).
 * Any grid: x over the pixels of a row, y over the rows; block (256, 1, 1). */
typedef struct {
	uint64_t dst;
	int64_t dstStride;
	uint64_t src;
	int64_t srcStride;
	int64_t width;
	int64_t height;
	int64_t bpp;
	int64_t mode;
} RasterCopyParams;

/* raster_blit: rects x y w h; each destination pixel of dstRect samples the source at its centre mapped into srcRect
 * (nearest, or linear), clamped to the source's edge, converted to the destination's format (PlatformRaster>>blitPixels).
 * Any grid: x over destination columns, y over rows; block (256, 1, 1). */
typedef struct {
	uint64_t src;
	int64_t srcWidth;
	int64_t srcHeight;
	uint64_t dst;
	int64_t dstWidth;
	int64_t dstHeight;
	int64_t srcRect[4];
	int64_t dstRect[4];
	int32_t srcFormat;
	int32_t dstFormat;
	int32_t linear;
	int32_t pad;
} RasterBlitParams;

/* raster_prims then raster_tiles, with the same parameters: one draw of the Renderer's pipeline, the vertices
 * first .. first + count - 1 (40 bytes each, the Renderer's layout) at vertices (vertex 0's address: the vertex buffer
 * plus the bound offset), into the target pixels (width x height, format 2 or 3), with RasterState's fields
 * (PlatformRaster): the blend, scissor and viewport (pixels), the vertex uniforms viewSize and translate, the texture
 * of slot 0 (0: none) and its sampler (linear, repeat: 0 or 1).
 * prims: scratch of RASTER_SCRATCH_HEADER + RASTER_PRIM_BYTES * (count / 3) bytes, written by raster_prims and read by
 * raster_tiles (so a draw's raster_tiles must follow its raster_prims, and the next draw's raster_prims that one, when
 * they share it).
 * raster_prims: any grid, x over the slots (count / 3), block 256. raster_tiles: block RASTER_TILE_THREADS, any grid:
 * x over the 16 x 16 tiles of the clip (the scissor within the target and the viewport): ceil(w / 16) * ceil(h / 16)
 * blocks for the scissor's w x h within the target cover it in one pass; fewer loop. */
typedef struct {
	uint64_t pixels;
	int64_t width;
	int64_t height;
	int64_t scissorX;
	int64_t scissorY;
	int64_t scissorW;
	int64_t scissorH;
	double viewportX;
	double viewportY;
	double viewportW;
	double viewportH;
	double viewSizeX;
	double viewSizeY;
	double translateX;
	double translateY;
	uint64_t texture;
	int64_t textureWidth;
	int64_t textureHeight;
	uint64_t vertices;
	int64_t first;
	int64_t count;
	uint64_t prims;
	int32_t format;
	int32_t blend;
	int32_t textureFormat;
	int32_t linear;
	int32_t repeat;
	int32_t pad;
} RasterDrawParams;

/* raster_batch_prims then raster_batch_tiles, with the same parameters: drawCount draws into one target, in order (a
 * pass's), drawn as each one's raster_prims and raster_tiles after the other would draw them.
 * draws: drawCount RasterDrawParams (prims unused; pixels, width, height and format the same in all).
 * slotStarts: drawCount + 1 int64, draw d's primitive slots (count / 3) being slotStarts[d] .. slotStarts[d + 1] - 1
 * of the batch's, slots = slotStarts[drawCount].
 * prims: scratch of RASTER_BATCH_SLOT_BYTES * slots bytes, written by raster_batch_prims, read by raster_batch_tiles.
 * clipX0 clipY0 clipX1 clipY1: a rectangle that holds every draw's clip (the union of their scissors within the target).
 * raster_batch_prims: any grid, x over the slots, block 256. raster_batch_tiles: block RASTER_TILE_THREADS, any grid: x
 * over the 16 x 16 tiles of the clip rectangle. */
#define RASTER_BATCH_SLOT_BYTES 408
typedef struct {
	uint64_t draws;
	uint64_t slotStarts;
	uint64_t prims;
	int64_t drawCount;
	int64_t slots;
	int64_t clipX0;
	int64_t clipY0;
	int64_t clipX1;
	int64_t clipY1;
} RasterBatchParams;

#endif
