/* PlatformRaster (src/VM-Platform/PlatformRaster.st, its C in vm/gen/platform_raster.c) as CUDA kernels for sm_121:
 * the Renderer's uber-shader on a draw's vertices, fills, blits and copies, bit-exact with the C reference compiled
 * without floating-point contraction (as the UEFI VM is: -ffp-contract=off). Built with -fmad=false so that no
 * a * b + c becomes a fused multiply-add; the doubles and their operations are the reference's, in its order.
 *
 * A draw is two kernels (their parameters: raster_abi.h; docs/nv-kernels.md):
 *   raster_prims  one thread per primitive slot (3 vertices): parses quads and triangles as rasterize() walks them
 *                 (six equal vertices at an index divisible by six, without bit 31 of mode, are one quad and take two
 *                 slots), runs drawQuad's or drawTriangle's setup, picks the path drawQuad would (solid, pattern, 1:1
 *                 glyph or image rows, scaled, per-pixel shade) and writes a record and the pixel rectangle it covers;
 *                 its first thread writes the draw's clip to the scratch's header.
 *   raster_tiles  one block per 16 x 16 tile of the clip rectangle, a thread per pixel: the block lists, in order, the
 *                 primitives whose rectangle meets the tile, then each thread applies them to its pixel, held in a
 *                 register, in that order. A pixel sees the same sequence of operations as in the reference, so the
 *                 result is the same (every path's value for a pixel depends only on that pixel and the primitive).
 * raster_batch_prims and raster_batch_tiles do the same for a pass's draws into one target at once (RasterBatchParams):
 * the slots of all draws in order, each record with its draw, one tile pass over all of them, each primitive applied
 * with its own draw's state; a pixel still sees the same sequence of operations.
 * No globals, constants or device-side runtime calls: everything comes in the parameter struct, so a launcher needs
 * only the cubin, the entry names and the parameter layouts. */
#include "raster_abi.h"

typedef unsigned long long u64;
typedef long long i64;
typedef unsigned int u32;
typedef unsigned char u8;

#define PF_TEX_R8 1
#define PF_TEX_RGBA8 2
#define PF_TEX_BGRA8 3
#define PF_BLEND_NONE 0
#define PF_BLEND_ALPHA 1
#define PF_BLEND_PREMULTIPLIED 2
#define RS_STRIDE 40
#define RS_MAX_COORD 1048576

/* primitive kinds: the paths of drawQuad, and triangles */
enum { K_NONE, K_SOLID_STORE, K_SOLID_BLEND, K_SOLID_OVER, K_PATTERN, K_GLYPH, K_IMAGE, K_SCALED, K_SHADE, K_TRIANGLE };

struct QuadData { double u0, v0, du, dv; i64 tx, ty; };
struct TriData { i64 ea[3], eb[3], ex[3], ey[3], et[3]; double at[6], dx[6], dy[6]; double fx0, fy0; };
struct Prim {
	int kind; u32 color; u32 mode; int flat;
	int x0, y0, x1, y1;
	double orgX, orgY;
	union { QuadData q; TriData t; };
};
static_assert(sizeof(Prim) + 16 <= RASTER_PRIM_BYTES, "a primitive's record and rectangle fit its slot");
#define PRIM_RECORD_BYTES (RASTER_PRIM_BYTES - 16)

/* The raster state of a draw (prepare:). */
struct Ctx {
	u8 *pixels; i64 w, h; int fmt, blend;
	i64 cx0, cy0, cx1, cy1;
	double ox, oy, sx, sy, tx, ty;
	const u8 *tex; i64 texW, texH; int texFmt; bool linear, repeat;
};

/* floorOf: (truncate, minus one where that is above x: floor(x), as an integer within +-10^15, 0 for NaN), in fewer
 * double operations (GB10 runs them at 1/64 of the float rate): floor, then the clamp, which is exact on integers. */
__device__ __forceinline__ i64 floor_of(double x)
{
	if (!(x == x)) return 0;
	return (i64)fmin(fmax(floor(x), -1000000000000000.0), 1000000000000000.0);
}

__device__ __forceinline__ i64 snap(double x)
{
	double c = x;
	if (c < (double)(-RS_MAX_COORD)) c = (double)(-RS_MAX_COORD);
	if (c > (double)RS_MAX_COORD) c = (double)RS_MAX_COORD;
	return floor_of(c * 256.0 + 0.5);
}

__device__ __forceinline__ i64 unorm8(double x)
{
	if (!(x > 0.0)) return 0;
	if (x >= 1.0) return 255;
	return floor_of(x * 255.0 + 0.5);
}

/* a / b, without the division's long double-precision sequence where the quotient is 1 (b finite, not zero, equal
 * to a: the 1:1 scales of most draws), where IEEE's correctly rounded a / b is exactly 1. */
__device__ __forceinline__ double quotient(double a, double b)
{
	if (a == b && b != 0.0 && b - b == 0.0) return 1.0;
	return a / b;
}

__device__ __forceinline__ u32 swap_rb(u32 v)
{
	return (v & 0xFF00FF00u) | ((v >> 16) & 0xFFu) | ((v & 0xFFu) << 16);
}

/* over:color: (premultiplied source-over, two lanes at a time, rounded once, saturated) */
__device__ __forceinline__ u32 over(u32 d, u32 c)
{
	i64 ia = 255 - (i64)(c >> 24);
	i64 t = ((i64)d & 0xFF00FF) * ia + 0x800080;
	i64 rb = (((t + ((t >> 8) & 0xFF00FF)) >> 8) & 0xFF00FF) + ((i64)c & 0xFF00FF);
	t = (((i64)d >> 8) & 0xFF00FF) * ia + 0x800080;
	i64 ag = (((t + ((t >> 8) & 0xFF00FF)) >> 8) & 0xFF00FF) + (((i64)c >> 8) & 0xFF00FF);
	i64 ov = rb & 0x1000100;
	rb = (rb | (ov - (ov >> 8))) & 0xFF00FF;
	ov = ag & 0x1000100;
	ag = (ag | (ov - (ov >> 8))) & 0xFF00FF;
	return (u32)(rb | (ag << 8));
}

/* over:color:k: (exact: round((c k 255 + d (65025 - c.a k)) / 65025) per lane); every term fits 32 bits */
__device__ __forceinline__ u32 over_k(u32 d, u32 c, u32 k)
{
	u32 ia = 65025u - (c >> 24) * k;
	u32 r = 0;
	for (int s = 0; s <= 24; s += 8) {
		u32 ch = (((c >> s) & 255u) * k * 255u + ((d >> s) & 255u) * ia + 32512u) / 65025u;
		if (ch > 255u) ch = 255u;
		r |= ch << s;
	}
	return r;
}

/* blend:source:k: */
__device__ __forceinline__ u32 blend(int mode, u32 d, u32 c, i64 k)
{
	if (mode == PF_BLEND_PREMULTIPLIED) return over_k(d, c, (u32)k);
	i64 r = 0, ch;
	if (mode == PF_BLEND_NONE) {
		for (int s = 0; s <= 24; s += 8) {
			ch = ((i64)((c >> s) & 255) * k + 127) / 255;
			r |= ch << s;
		}
		return (u32)r;
	}
	i64 sa = (i64)(c >> 24) * k;
	for (int s = 0; s <= 16; s += 8) {
		ch = ((i64)((c >> s) & 255) * k * sa * 255 + (i64)((d >> s) & 255) * (65025 - sa) * 65025 + 2114125312LL) / 4228250625LL;
		if (ch > 255) ch = 255;
		r |= ch << s;
	}
	ch = (sa * 255 + (i64)(d >> 24) * (65025 - sa) + 32512) / 65025;
	if (ch > 255) ch = 255;
	return (u32)(r | (ch << 24));
}

/* bilinear:with:with:with:fx:fy: */
__device__ __forceinline__ u32 bilinear(u32 a, u32 b, u32 c, u32 d, i64 fx, i64 fy)
{
	u64 gx = (u64)(256 - fx), gy = (u64)(256 - fy), ux = (u64)fx, uy = (u64)fy;
#define SPREAD(v) (((u64)((v) & 0xFFu)) | (((u64)((v) & 0xFF0000u)) << 16))
	u64 rb = (SPREAD(a) * gx + SPREAD(b) * ux) * gy + (SPREAD(c) * gx + SPREAD(d) * ux) * uy + 0x800000008000ULL;
	u32 a2 = a >> 8, b2 = b >> 8, c2 = c >> 8, d2 = d >> 8;
	u64 ag = (SPREAD(a2) * gx + SPREAD(b2) * ux) * gy + (SPREAD(c2) * gx + SPREAD(d2) * ux) * uy + 0x800000008000ULL;
#undef SPREAD
	return ((u32)(((rb >> 16) & 0xFF) | ((rb >> 32) & 0xFF0000))) | ((u32)(((ag >> 8) & 0xFF00) | ((ag >> 24) & 0xFF000000ULL)));
}

/* A texture as sampleU:v: reads it, for a target of format fmt. */
struct Tex { const u8 *p; i64 w, h; int fmt; bool linear, repeat; };

__device__ __forceinline__ u32 texel_of(u32 r, int fmt)
{
	return fmt == PF_TEX_BGRA8 ? ((u32)((u64)r << 16) | 0xFF000000u) : (r | 0xFF000000u);
}

__device__ __forceinline__ u32 texel_xy(const Tex &t, int fmt, i64 x, i64 y)
{
	if (t.fmt == PF_TEX_R8) return texel_of((u32)t.p[y * t.w + x], fmt);
	u32 v = ((const u32 *)t.p)[y * t.w + x];
	return t.fmt == fmt ? v : swap_rb(v);
}

__device__ __forceinline__ i64 texel_index(i64 i, i64 n, bool repeat)
{
	if (repeat) {
		i64 m = i % n;
		return m < 0 ? m + n : m;
	}
	if (i < 0) return 0;
	return i >= n ? n - 1 : i;
}

/* sampleU:v: */
__device__ u32 sample(const Tex &t, int fmt, double u, double v)
{
	if (t.p == 0) return 0;
	if (!t.linear) return texel_xy(t, fmt, texel_index(floor_of(u), t.w, t.repeat), texel_index(floor_of(v), t.h, t.repeat));
	double uu = u - 0.5, vv = v - 0.5;
	i64 x = floor_of(uu), y = floor_of(vv);
	i64 fx = floor_of((uu - (double)x) * 256.0 + 0.5);
	i64 fy = floor_of((vv - (double)y) * 256.0 + 0.5);
	i64 x0 = texel_index(x, t.w, t.repeat), x1 = texel_index(x + 1, t.w, t.repeat);
	i64 y0 = texel_index(y, t.h, t.repeat), y1 = texel_index(y + 1, t.h, t.repeat);
	return bilinear(texel_xy(t, fmt, x0, y0), texel_xy(t, fmt, x1, y0), texel_xy(t, fmt, x0, y1), texel_xy(t, fmt, x1, y1), fx, fy);
}

__device__ __forceinline__ Tex tex_of(const Ctx &c)
{
	Tex t; t.p = c.tex; t.w = c.texW; t.h = c.texH; t.fmt = c.texFmt; t.linear = c.linear; t.repeat = c.repeat;
	return t;
}

/* shade:x:y:u:v: with the primitive's color, mode and origin: the new value of the pixel d. */
__device__ u32 shade(const Ctx &c, u32 d, i64 px, i64 py, double u, double v, u32 color, u32 mode, double orgX, double orgY)
{
	u32 m = mode & 255, src = color;
	i64 k = 255;
	if (m == 1) {
		u32 s = sample(tex_of(c), c.fmt, u, v);
		k = (i64)((c.fmt == PF_TEX_BGRA8 ? s >> 16 : s) & 255);
	} else if (m == 2) {
		src = sample(tex_of(c), c.fmt, u, v);
		k = (i64)(color >> 24);
	} else if (m == 5) {
		double au = u < 0.0 ? -u : u;
		double cover = v + 0.5 - au;
		k = unorm8(cover);
	} else if (m != 0) {
		i64 cell = (mode >> 8) & 255;
		if (cell == 0) cell = 1;
		u32 variant = (mode >> 16) & 255;
		i64 dx = floor_of((double)px + 0.5 - orgX);
		i64 dy = floor_of((double)py + 0.5 - orgY);
		i64 ix = (dx > 0 ? dx : 0) / cell;
		i64 iy = (dy > 0 ? dy : 0) / cell;
		bool on;
		if (m == 3) on = variant == 1 ? ((ix + iy) & 1) == 0 : ((ix & 1) == 1 && (iy & 1) == 1);
		else if (variant == 1) on = (ix & 1) == 0;
		else if (variant == 2) {
			i64 diagonal = dx + dy;
			if (diagonal < 0) diagonal = 0;
			on = ((diagonal / cell) & 1) == 0;
		} else on = (iy & 1) == 0;
		if (!on) k = 0;
	}
	if (k == 0 && c.blend != PF_BLEND_NONE) return d;
	return blend(c.blend, d, src, k);
}

/* The target, blend and texture of the raster state (prepare:'s part without arithmetic). */
__device__ __forceinline__ void prepare_target(const RasterDrawParams &st, Ctx &c)
{
	c.pixels = (u8 *)st.pixels; c.w = st.width; c.h = st.height; c.fmt = st.format; c.blend = st.blend;
	c.tex = (const u8 *)st.texture; c.texW = st.textureWidth; c.texH = st.textureHeight; c.texFmt = st.textureFormat;
	c.linear = st.linear != 0; c.repeat = st.repeat != 0;
}

/* prepare:'s clip (false: nothing can be drawn) */
__device__ __forceinline__ bool prepare_clip(const RasterDrawParams &st, Ctx &c)
{
	if (st.format == PF_TEX_R8 || !(st.viewSizeX > 0.0 && st.viewSizeY > 0.0)) return false;
	c.w = st.width; c.h = st.height;
	i64 x0 = st.scissorX > 0 ? st.scissorX : 0;
	i64 y0 = st.scissorY > 0 ? st.scissorY : 0;
	i64 x1 = st.scissorX + st.scissorW;
	i64 y1 = st.scissorY + st.scissorH;
	if (x1 > c.w) x1 = c.w;
	if (y1 > c.h) y1 = c.h;
	i64 v = floor_of(st.viewportX + 0.5);
	if (v > x0) x0 = v;
	v = floor_of(st.viewportY + 0.5);
	if (v > y0) y0 = v;
	v = floor_of(st.viewportX + st.viewportW + 0.5);
	if (v < x1) x1 = v;
	v = floor_of(st.viewportY + st.viewportH + 0.5);
	if (v < y1) y1 = v;
	if (!(x0 < x1 && y0 < y1)) return false;
	c.cx0 = x0; c.cy0 = y0; c.cx1 = x1; c.cy1 = y1;
	return true;
}

/* prepare: (false: nothing can be drawn) */
__device__ __forceinline__ bool prepare(const RasterDrawParams &st, Ctx &c)
{
	if (!prepare_clip(st, c)) return false;
	prepare_target(st, c);
	c.ox = st.viewportX; c.oy = st.viewportY;
	c.sx = quotient(st.viewportW, st.viewSizeX); c.sy = quotient(st.viewportH, st.viewSizeY);
	c.tx = st.translateX; c.ty = st.translateY;
	return true;
}

__device__ __forceinline__ const u8 *vertex(const RasterDrawParams &st, i64 k) { return (const u8 *)st.vertices + k * RS_STRIDE; }

/* isQuad: (compared as 32-bit words: vertices need only be 4-byte aligned) */
__device__ __forceinline__ bool is_quad(const u8 *v)
{
	const u32 *w = (const u32 *)v;
	if ((w[7] >> 31) != 0) return false;
	for (int i = 0; i < 50; i++) if (w[i] != w[i + 10]) return false;
	return true;
}

__device__ __forceinline__ u32 target_color(const Ctx &c, u32 rgba) { return c.fmt == PF_TEX_BGRA8 ? swap_rb(rgba) : rgba; }

/* drawQuad:'s setup and choice of path. */
__device__ void setup_quad(const Ctx &c, const u8 *v, Prim &p)
{
	const float *f = (const float *)v;
	const u32 *u = (const u32 *)v;
	p.kind = K_NONE;
	double ox = (double)f[8] + c.tx, oy = (double)f[9] + c.ty;
	double x0 = (double)f[0] + ox, y0 = (double)f[1] + oy, x1 = (double)f[2] + ox, y1 = (double)f[3] + oy;
	u32 mode = u[7], color = target_color(c, u[6]);
	p.mode = mode; p.color = color; p.flat = 1; p.orgX = x0; p.orgY = y0;
	i64 xa = snap(c.ox + x0 * c.sx), xb = snap(c.ox + x1 * c.sx);
	i64 ya = snap(c.oy + y0 * c.sy), yb = snap(c.oy + y1 * c.sy);
	i64 px0, px1, py0, py1;
	if (xa <= xb) { px0 = (xa + 127) >> 8; px1 = (xb + 127) >> 8; } else { px0 = (xb + 127) >> 8; px1 = (xa + 127) >> 8; }
	if (ya <= yb) { py0 = (ya + 127) >> 8; py1 = (yb + 127) >> 8; } else { py0 = (yb + 127) >> 8; py1 = (ya + 127) >> 8; }
	if (px0 < c.cx0) px0 = c.cx0;
	if (py0 < c.cy0) py0 = c.cy0;
	if (px1 > c.cx1) px1 = c.cx1;
	if (py1 > c.cy1) py1 = c.cy1;
	if (!(px0 < px1 && py0 < py1)) return;
	p.x0 = (int)px0; p.y0 = (int)py0; p.x1 = (int)px1; p.y1 = (int)py1;
	i64 w = px1 - px0, h = py1 - py0;
	u32 m = mode & 255, ca = color >> 24;
	if (m == 0) {
		if (c.blend == PF_BLEND_NONE || ca == 255) p.kind = K_SOLID_STORE;
		else if (c.blend != PF_BLEND_PREMULTIPLIED) p.kind = K_SOLID_BLEND;
		else if (color != 0) p.kind = K_SOLID_OVER;
		return;
	}
	if (!(m == 1 || m == 2) && m != 5) {
		if (c.blend != PF_BLEND_PREMULTIPLIED) {
			p.kind = K_SHADE; p.q.u0 = 0.0; p.q.v0 = 0.0; p.q.du = 0.0; p.q.dv = 0.0;
		} else if (color != 0) {
			p.kind = K_PATTERN;
			p.q.tx = floor_of((double)px0 + 0.5 - x0);
		}
		return;
	}
	double ua = (double)(u[4] & 0xFFFF), va = (double)(u[4] >> 16);
	double ub = (double)(u[5] & 0xFFFF), vb = (double)(u[5] >> 16);
	double sx0 = (double)xa / 256.0, sy0 = (double)ya / 256.0;
	double du = quotient(ub - ua, (double)(xb - xa) / 256.0);
	double dv = quotient(vb - va, (double)(yb - ya) / 256.0);
	ua = ua + du * ((double)px0 + 0.5 - sx0);
	va = va + dv * ((double)py0 + 0.5 - sy0);
	p.q.u0 = ua; p.q.v0 = va; p.q.du = du; p.q.dv = dv;
	if (m != 5) {
		/* texturedX: 1:1 on texels inside the texture */
		if (!(c.tex == 0 || c.blend != PF_BLEND_PREMULTIPLIED || du != 1.0 || dv != 1.0)) {
			i64 tx, ty;
			bool ok = true;
			if (c.linear) {
				tx = floor_of(ua - 0.5);
				ty = floor_of(va - 0.5);
				ok = (double)tx == ua - 0.5 && (double)ty == va - 0.5;
			} else {
				tx = floor_of(ua);
				ty = floor_of(va);
			}
			if (ok && tx >= 0 && ty >= 0 && tx + w <= c.texW && ty + h <= c.texH) {
				p.q.tx = tx; p.q.ty = ty;
				p.kind = m == 1 ? K_GLYPH : (ca == 0 ? K_NONE : K_IMAGE);
				return;
			}
		}
		/* scaledX: any scale, clamped to the edge */
		if (!(c.tex == 0 || c.repeat || c.blend != PF_BLEND_PREMULTIPLIED)) {
			double ue = ua + du * (double)w, ve = va + dv * (double)h;
			if ((ua > -1.0e9 && ua < 1.0e9) && (ue > -1.0e9 && ue < 1.0e9) && (va > -1.0e9 && va < 1.0e9) && (ve > -1.0e9 && ve < 1.0e9)) {
				p.kind = (m == 2 && ca == 0) ? K_NONE : K_SCALED;
				return;
			}
		}
	}
	p.kind = K_SHADE;
}

/* drawTriangle:index:'s setup: positions, edges, the attribute planes of vertex 0. */
__device__ void setup_triangle(const Ctx &c, const RasterDrawParams &st, i64 k, Prim &p)
{
	i64 xs[3], ys[3];
	double at[18];
	p.kind = K_NONE;
	for (int j = 0; j <= 2; j++) {
		const u8 *vp = vertex(st, k + j);
		const float *f = (const float *)vp;
		const u32 *u = (const u32 *)vp;
		double px, py, uu, vv;
		if ((u[7] >> 31) != 0) {
			px = (double)f[0]; py = (double)f[1]; uu = (double)f[4]; vv = (double)f[5];
		} else {
			i64 corner = (k + j) % 6;
			double kx = (corner == 1 || corner == 3 || corner == 4) ? 1.0 : 0.0;
			double ky = (corner == 2 || corner == 4 || corner == 5) ? 1.0 : 0.0;
			px = (double)f[0] + ((double)f[2] - (double)f[0]) * kx;
			py = (double)f[1] + ((double)f[3] - (double)f[1]) * ky;
			uu = (double)(u[4] & 0xFFFF);
			uu = uu + ((double)(u[5] & 0xFFFF) - uu) * kx;
			vv = (double)(u[4] >> 16);
			vv = vv + ((double)(u[5] >> 16) - vv) * ky;
		}
		px = px + ((double)f[8] + c.tx);
		py = py + ((double)f[9] + c.ty);
		xs[j] = snap(c.ox + px * c.sx);
		ys[j] = snap(c.oy + py * c.sy);
		u32 col = target_color(c, u[6]);
		at[j * 6] = uu;
		at[j * 6 + 1] = vv;
		for (int l = 0; l <= 3; l++) at[j * 6 + 2 + l] = (double)((col >> (l * 8)) & 255);
		if (j == 0) {
			p.mode = u[7];
			p.color = col;
			p.orgX = (double)f[0] + ((double)f[8] + c.tx);
			p.orgY = (double)f[1] + ((double)f[9] + c.ty);
		}
	}
	const u32 *u0 = (const u32 *)vertex(st, k), *u1 = (const u32 *)vertex(st, k + 1), *u2 = (const u32 *)vertex(st, k + 2);
	p.flat = (u1[6] == u0[6]) && (u2[6] == u0[6]);
	i64 area = (xs[1] - xs[0]) * (ys[2] - ys[0]) - (ys[1] - ys[0]) * (xs[2] - xs[0]);
	if (area == 0) return;
	for (int e = 0; e <= 2; e++) {
		int ia, ib;
		if (area > 0) { ia = e; ib = (e + 1) % 3; } else { ia = (e + 1) % 3; ib = e; }
		i64 ea = -(ys[ib] - ys[ia]), eb = xs[ib] - xs[ia];
		p.t.ea[e] = ea; p.t.eb[e] = eb;
		p.t.ex[e] = xs[ia]; p.t.ey[e] = ys[ia];
		p.t.et[e] = (ea > 0) || ((ea == 0) && (eb > 0)) ? 0 : 1;
	}
	i64 minX = xs[0] < xs[1] ? xs[0] : xs[1], maxX = xs[0] > xs[1] ? xs[0] : xs[1];
	minX = minX < xs[2] ? minX : xs[2]; maxX = maxX > xs[2] ? maxX : xs[2];
	i64 minY = ys[0] < ys[1] ? ys[0] : ys[1], maxY = ys[0] > ys[1] ? ys[0] : ys[1];
	minY = minY < ys[2] ? minY : ys[2]; maxY = maxY > ys[2] ? maxY : ys[2];
	i64 x0 = (minX + 127) >> 8, x1 = ((maxX + 127) >> 8) + 1;
	i64 y0 = (minY + 127) >> 8, y1 = ((maxY + 127) >> 8) + 1;
	if (x0 < c.cx0) x0 = c.cx0;
	if (y0 < c.cy0) y0 = c.cy0;
	if (x1 > c.cx1) x1 = c.cx1;
	if (y1 > c.cy1) y1 = c.cy1;
	if (!(x0 < x1 && y0 < y1)) return;
	double fx0 = (double)xs[0] / 256.0, fy0 = (double)ys[0] / 256.0;
	double ax = (double)(xs[1] - xs[0]) / 256.0, ay = (double)(ys[1] - ys[0]) / 256.0;
	double bx = (double)(xs[2] - xs[0]) / 256.0, by = (double)(ys[2] - ys[0]) / 256.0;
	double det = ax * by - bx * ay;
	for (int l = 0; l <= 5; l++) {
		p.t.at[l] = at[l];
		p.t.dx[l] = ((at[6 + l] - at[l]) * by - (at[12 + l] - at[l]) * ay) / det;
		p.t.dy[l] = ((at[12 + l] - at[l]) * ax - (at[6 + l] - at[l]) * bx) / det;
	}
	p.t.fx0 = fx0; p.t.fy0 = fy0;
	p.x0 = (int)x0; p.y0 = (int)y0; p.x1 = (int)x1; p.y1 = (int)y1;
	p.kind = K_TRIANGLE;
}

/* The scratch: the clip (x0 y0 x1 y1; empty: nothing to draw), each slot's rectangle, each slot's record. */
__device__ __forceinline__ i64 *scratch_clip(const RasterDrawParams &st) { return (i64 *)st.prims; }
__device__ __forceinline__ int4 *slot_boxes(const RasterDrawParams &st) { return (int4 *)((u8 *)st.prims + RASTER_SCRATCH_HEADER); }
__device__ __forceinline__ Prim *slot_prim(const RasterDrawParams &st, i64 nslots, i64 n)
{
	return (Prim *)((u8 *)st.prims + RASTER_SCRATCH_HEADER + nslots * 16 + n * PRIM_RECORD_BYTES);
}

/* Slot n of a draw (prepared into c): its record in p and the rectangle it covers (all 0: nothing). */
__device__ __forceinline__ int4 prim_slot(const RasterDrawParams &st, const Ctx &c, i64 n, Prim &p)
{
	i64 k = st.first + 3 * n, last = st.first + st.count;
	p.kind = K_NONE;
	if (k % 6 == 0 && k + 6 <= last && is_quad(vertex(st, k)))
		setup_quad(c, vertex(st, k), p);
	else if (!(k % 6 == 3 && k - 3 >= st.first && k + 3 <= last && is_quad(vertex(st, k - 3))))
		setup_triangle(c, st, k, p);
	return p.kind != K_NONE ? make_int4(p.x0, p.y0, p.x1, p.y1) : make_int4(0, 0, 0, 0);
}

extern "C" __global__ void __launch_bounds__(256) raster_prims(const RasterDrawParams st)
{
	Ctx c;
	if (st.count < 3) return;
	bool ok = prepare(st, c);
	if (blockIdx.x == 0 && threadIdx.x == 0) {
		i64 *clip = scratch_clip(st);
		clip[0] = ok ? c.cx0 : 0; clip[1] = ok ? c.cy0 : 0; clip[2] = ok ? c.cx1 : 0; clip[3] = ok ? c.cy1 : 0;
	}
	if (!ok) return;
	i64 nslots = st.count / 3;
	for (i64 n = (i64)blockIdx.x * blockDim.x + threadIdx.x; n < nslots; n += (i64)gridDim.x * blockDim.x) {
		Prim p;
		slot_boxes(st)[n] = prim_slot(st, c, n, p);
		*slot_prim(st, nslots, n) = p;
	}
}

/* A batch's scratch: each slot's rectangle, each slot's draw, each slot's record. */
__device__ __forceinline__ int4 *batch_boxes(const RasterBatchParams &b) { return (int4 *)b.prims; }
__device__ __forceinline__ int *batch_draws(const RasterBatchParams &b) { return (int *)((u8 *)b.prims + b.slots * 16); }
__device__ __forceinline__ Prim *batch_prim(const RasterBatchParams &b, i64 n)
{
	return (Prim *)((u8 *)b.prims + b.slots * 16 + ((b.slots * 4 + 15) & ~15LL) + n * PRIM_RECORD_BYTES);
}
/* each chunk of RASTER_BATCH_CHUNK slots' bounding box (all 0: nothing), after the records */
__device__ __forceinline__ int4 *batch_chunks(const RasterBatchParams &b)
{
	return (int4 *)((u8 *)b.prims + b.slots * 16 + ((b.slots * 4 + 15) & ~15LL) + b.slots * PRIM_RECORD_BYTES);
}

/* The draw slot n belongs to: the last d with slotStarts[d] <= n (draws without slots start where the next does). */
__device__ __forceinline__ i64 draw_of_slot(const i64 *starts, i64 drawCount, i64 n)
{
	i64 lo = 0, hi = drawCount - 1;
	while (lo < hi) {
		i64 mid = (lo + hi + 1) >> 1;
		if (starts[mid] <= n) lo = mid; else hi = mid - 1;
	}
	return lo;
}

/* A block of RASTER_BATCH_CHUNK threads a chunk (small blocks: a slot's setup is long, in doubles, and the chunks
 * spread over every SM). */
extern "C" __global__ void __launch_bounds__(RASTER_BATCH_CHUNK) raster_batch_prims(const RasterBatchParams b)
{
	__shared__ int bx0, by0, bx1, by1;
	const RasterDrawParams *draws = (const RasterDrawParams *)b.draws;
	const i64 *starts = (const i64 *)b.slotStarts;
	i64 chunks = (b.slots + RASTER_BATCH_CHUNK - 1) / RASTER_BATCH_CHUNK;
	for (i64 chunk = blockIdx.x; chunk < chunks; chunk += gridDim.x) {
		if (threadIdx.x == 0) { bx0 = by0 = 0x7FFFFFFF; bx1 = by1 = -0x7FFFFFFF; }
		__syncthreads();
		i64 n = chunk * RASTER_BATCH_CHUNK + threadIdx.x;
		if (n < b.slots) {
			i64 d = draw_of_slot(starts, b.drawCount, n);
			const RasterDrawParams st = draws[d];
			Ctx c;
			Prim p;
			p.kind = K_NONE;
			int4 box = make_int4(0, 0, 0, 0);
			if (prepare(st, c)) box = prim_slot(st, c, n - starts[d], p);
			batch_boxes(b)[n] = box;
			batch_draws(b)[n] = (int)d;
			*batch_prim(b, n) = p;
			if (box.x < box.z) {
				atomicMin(&bx0, box.x); atomicMin(&by0, box.y); atomicMax(&bx1, box.z); atomicMax(&by1, box.w);
			}
		}
		__syncthreads();
		if (threadIdx.x == 0) batch_chunks(b)[chunk] = bx0 < bx1 ? make_int4(bx0, by0, bx1, by1) : make_int4(0, 0, 0, 0);
		__syncthreads();
	}
}

/* The new value of pixel d at (px, py), inside primitive p's rectangle. */
__device__ __forceinline__ u32 apply(const Ctx &c, const Prim *__restrict__ pp, i64 px, i64 py, u32 d)
{
	int kind = pp->kind;
	u32 color = pp->color;
	i64 i = px - pp->x0, j = py - pp->y0;
	switch (kind) {
	case K_SOLID_STORE: return color;
	case K_SOLID_BLEND: return blend(c.blend, d, color, 255);
	case K_SOLID_OVER: return over(d, color);
	case K_PATTERN: {
		u32 mode = pp->mode, m = mode & 255;
		i64 cell = (mode >> 8) & 255;
		if (cell == 0) cell = 1;
		u32 variant = (mode >> 16) & 255;
		i64 dy = floor_of((double)py + 0.5 - pp->orgY);
		i64 iy = (dy > 0 ? dy : 0) / cell;
		int pkind = 0;
		i64 want = 0;
		bool rowOn = false;
		if (m == 3) {
			if (variant == 1) { pkind = 1; want = iy & 1; }
			else if ((iy & 1) == 1) { pkind = 1; want = 1; }
		} else {
			if (variant == 1) pkind = 1;
			else if (variant == 2) pkind = 2;
			else rowOn = (iy & 1) == 0;
		}
		if (pkind == 0) return rowOn ? ((color >> 24) == 255 ? color : over(d, color)) : d;
		i64 t = (pkind == 1 ? pp->q.tx : pp->q.tx + dy) + i;
		if (t < 0) t = 0;
		return ((t / cell) & 1) == want ? over(d, color) : d;
	}
	case K_GLYPH: {
		int bpp = c.texFmt == PF_TEX_R8 ? 1 : 4;
		u32 k = c.tex[(((pp->q.ty + j) * c.texW + pp->q.tx) * bpp + (c.texFmt == PF_TEX_BGRA8 ? 2 : 0)) + i * bpp];
		if (k == 0) return d;
		if ((color >> 24) == 255 && k == 255) return color;
		return over_k(d, color, k);
	}
	case K_IMAGE: {
		u32 ca = color >> 24;
		if (c.texFmt == PF_TEX_R8)
			return over_k(d, texel_of((u32)c.tex[(pp->q.ty + j) * c.texW + pp->q.tx + i], c.fmt), ca);
		u32 t = ((const u32 *)c.tex)[(pp->q.ty + j) * c.texW + pp->q.tx + i];
		bool swap = c.texFmt != c.fmt;
		if (ca == 255) {
			if ((t >> 24) == 255) return swap ? swap_rb(t) : t;
			return t != 0 ? over(d, swap ? swap_rb(t) : t) : d;
		}
		if (swap) t = swap_rb(t);
		return t != 0 ? over_k(d, t, ca) : d;
	}
	case K_SCALED: {
		u32 m = pp->mode & 255, ca = color >> 24;
		int bpp = c.texFmt == PF_TEX_R8 ? 1 : 4;
		int conv = c.texFmt == PF_TEX_R8 ? (c.fmt == PF_TEX_BGRA8 ? 3 : 2) : (c.texFmt == c.fmt ? 0 : 1);
		i64 maxX = c.texW - 1, maxY = c.texH - 1, t, tx0, tx1, ty0, ty1, fx, fy;
		double v = pp->q.v0 + pp->q.dv * (double)j;
		if (c.linear) {
			double vv = v - 0.5;
			t = floor_of(vv);
			fy = floor_of((vv - (double)t) * 256.0 + 0.5);
			ty0 = t < 0 ? 0 : (t > maxY ? maxY : t);
			t = t + 1;
			ty1 = t < 0 ? 0 : (t > maxY ? maxY : t);
		} else {
			t = floor_of(v);
			ty0 = t < 0 ? 0 : (t > maxY ? maxY : t);
			ty1 = ty0;
			fy = 0;
		}
		double u = pp->q.u0 + pp->q.du * (double)i;
		if (c.linear) {
			double uu = u - 0.5;
			t = floor_of(uu);
			fx = floor_of((uu - (double)t) * 256.0 + 0.5);
			tx0 = t < 0 ? 0 : (t > maxX ? maxX : t);
			t = t + 1;
			tx1 = t < 0 ? 0 : (t > maxX ? maxX : t);
		} else {
			t = floor_of(u);
			tx0 = t < 0 ? 0 : (t > maxX ? maxX : t);
			tx1 = tx0;
			fx = 0;
		}
		const u8 *r0 = c.tex + ty0 * c.texW * bpp, *r1 = c.tex + ty1 * c.texW * bpp;
#define FETCH(r, x) (conv == 0 ? ((const u32 *)(r))[x] : conv == 1 ? swap_rb(((const u32 *)(r))[x]) : conv == 2 ? ((u32)(r)[x] | 0xFF000000u) : (((u32)(r)[x] << 16) | 0xFF000000u))
		u32 s = (fx == 0 && fy == 0) ? FETCH(r0, tx0) : bilinear(FETCH(r0, tx0), FETCH(r0, tx1), FETCH(r1, tx0), FETCH(r1, tx1), fx, fy);
#undef FETCH
		if (m == 1) {
			u32 k = (s >> (c.fmt == PF_TEX_BGRA8 ? 16 : 0)) & 255;
			return k != 0 ? over_k(d, color, k) : d;
		}
		if (s == 0) return d;
		return ca == 255 ? over(d, s) : over_k(d, s, ca);
	}
	case K_SHADE:
		return shade(c, d, px, py, pp->q.u0 + pp->q.du * (double)i, pp->q.v0 + pp->q.dv * (double)j, color, pp->mode, pp->orgX, pp->orgY);
	case K_TRIANGLE: {
		const TriData &t = pp->t;
		i64 cx = px * 256 + 128, cy = py * 256 + 128;
		for (int e = 0; e < 3; e++)
			if (t.ea[e] * (cx - t.ex[e]) + t.eb[e] * (cy - t.ey[e]) < t.et[e]) return d;
		double ey = (double)py + 0.5 - t.fy0;
		double ex = (double)px + 0.5 - t.fx0;
		if (!pp->flat) {
			u32 cc = 0;
			for (int l = 0; l <= 3; l++) {
				i64 ch = floor_of(t.at[2 + l] + t.dx[2 + l] * ex + t.dy[2 + l] * ey + 0.5);
				if (ch < 0) ch = 0;
				if (ch > 255) ch = 255;
				cc |= (u32)ch << (l * 8);
			}
			color = cc;
		}
		return shade(c, d, px, py, t.at[0] + t.dx[0] * ex + t.dy[0] * ey, t.at[1] + t.dx[1] * ex + t.dy[1] * ey, color, pp->mode, pp->orgX, pp->orgY);
	}
	}
	return d;
}

extern "C" __global__ void __launch_bounds__(RASTER_TILE_THREADS) raster_tiles(const RasterDrawParams st)
{
	__shared__ int list[RASTER_TILE_THREADS];
	__shared__ int4 boxes[RASTER_TILE_THREADS];
	__shared__ int counts[RASTER_TILE_THREADS / 32];
	if (st.count < 3) return;
	/* the clip raster_prims computed (its double arithmetic in every block would cost more than drawing) */
	const i64 *clip = scratch_clip(st);
	Ctx c;
	c.cx0 = clip[0]; c.cy0 = clip[1]; c.cx1 = clip[2]; c.cy1 = clip[3];
	if (!(c.cx0 < c.cx1 && c.cy0 < c.cy1)) return;
	prepare_target(st, c);
	i64 nslots = st.count / 3;
	int tid = threadIdx.x, lane = tid & 31, warp = tid >> 5;
	i64 tilesX = (c.cx1 - c.cx0 + RASTER_TILE - 1) / RASTER_TILE, tilesY = (c.cy1 - c.cy0 + RASTER_TILE - 1) / RASTER_TILE;
	const int4 *slotBoxes = slot_boxes(st);
	for (i64 tile = blockIdx.x; tile < tilesX * tilesY; tile += gridDim.x) {
		int tx0 = (int)(c.cx0 + (tile % tilesX) * RASTER_TILE), ty0 = (int)(c.cy0 + (tile / tilesX) * RASTER_TILE);
		int tx1 = min(tx0 + RASTER_TILE, (int)c.cx1), ty1 = min(ty0 + RASTER_TILE, (int)c.cy1);
		int px = tx0 + (tid % RASTER_TILE), py = ty0 + (tid / RASTER_TILE);
		bool inside = px < tx1 && py < ty1;
		u32 *dp = (u32 *)(c.pixels + ((i64)py * c.w + px) * 4);
		u32 d = 0;
		bool touched = false;  /* the pixel is read at the first primitive over it and written if there was one */
		for (i64 base = 0; base < nslots; base += RASTER_TILE_THREADS) {
			i64 s = base + tid;
			int4 b = make_int4(0, 0, 0, 0);
			bool hit = false;
			if (s < nslots) {
				b = slotBoxes[s];
				hit = b.x < tx1 && b.z > tx0 && b.y < ty1 && b.w > ty0;
			}
			unsigned ballot = __ballot_sync(0xFFFFFFFFu, hit);
			if (lane == 0) counts[warp] = __popc(ballot);
			__syncthreads();
			int off = 0, total = 0;
			for (int w = 0; w < RASTER_TILE_THREADS / 32; w++) {
				if (w < warp) off += counts[w];
				total += counts[w];
			}
			if (hit) {
				int at = off + __popc(ballot & ((1u << lane) - 1u));
				list[at] = (int)s;
				boxes[at] = b;
			}
			__syncthreads();
			if (inside)
				for (int q = 0; q < total; q++) {
					int4 bb = boxes[q];
					if (px >= bb.x && px < bb.z && py >= bb.y && py < bb.w) {
						if (!touched) { d = *dp; touched = true; }
						d = apply(c, slot_prim(st, nslots, list[q]), px, py, d);
					}
				}
			__syncthreads();
		}
		if (touched) *dp = d;
	}
}

extern "C" __global__ void __maxnreg__(128) raster_batch_tiles(const RasterBatchParams b)
{
	__shared__ int list[RASTER_TILE_THREADS];
	__shared__ int listDraws[RASTER_TILE_THREADS];
	__shared__ int4 boxes[RASTER_TILE_THREADS];
	__shared__ int counts[RASTER_TILE_THREADS / 32];
	if (b.slots <= 0 || !(b.clipX0 < b.clipX1 && b.clipY0 < b.clipY1)) return;
	const RasterDrawParams *draws = (const RasterDrawParams *)b.draws;
	u8 *pixels = (u8 *)draws[0].pixels;
	i64 width = draws[0].width;
	i64 nslots = b.slots;
	int tid = threadIdx.x, lane = tid & 31, warp = tid >> 5;
	i64 tilesX = (b.clipX1 - b.clipX0 + RASTER_TILE - 1) / RASTER_TILE, tilesY = (b.clipY1 - b.clipY0 + RASTER_TILE - 1) / RASTER_TILE;
	const int4 *slotBoxes = batch_boxes(b);
	const int *slotDraws = batch_draws(b);
	const int4 *chunkBoxes = batch_chunks(b);
	for (i64 tile = blockIdx.x; tile < tilesX * tilesY; tile += gridDim.x) {
		int tx0 = (int)(b.clipX0 + (tile % tilesX) * RASTER_TILE), ty0 = (int)(b.clipY0 + (tile / tilesX) * RASTER_TILE);
		int tx1 = min(tx0 + RASTER_TILE, (int)b.clipX1), ty1 = min(ty0 + RASTER_TILE, (int)b.clipY1);
		int px = tx0 + (tid % RASTER_TILE), py = ty0 + (tid / RASTER_TILE);
		bool inside = px < tx1 && py < ty1;
		u32 *dp = (u32 *)(pixels + ((i64)py * width + px) * 4);
		u32 d = 0;
		bool touched = false;
		for (i64 base = 0; base < nslots; base += RASTER_TILE_THREADS) {
			/* skip the slots if no chunk of them meets the tile (the same for the whole block) */
			bool near = false;
			for (i64 q = base / RASTER_BATCH_CHUNK; q < (base + RASTER_TILE_THREADS) / RASTER_BATCH_CHUNK && q * RASTER_BATCH_CHUNK < nslots; q++) {
				int4 cb = chunkBoxes[q];
				near = near || (cb.x < tx1 && cb.z > tx0 && cb.y < ty1 && cb.w > ty0);
			}
			if (!near) continue;
			i64 s = base + tid;
			int4 bx = make_int4(0, 0, 0, 0);
			bool hit = false;
			if (s < nslots) {
				bx = slotBoxes[s];
				hit = bx.x < tx1 && bx.z > tx0 && bx.y < ty1 && bx.w > ty0;
			}
			unsigned ballot = __ballot_sync(0xFFFFFFFFu, hit);
			if (lane == 0) counts[warp] = __popc(ballot);
			__syncthreads();
			int off = 0, total = 0;
			for (int w = 0; w < RASTER_TILE_THREADS / 32; w++) {
				if (w < warp) off += counts[w];
				total += counts[w];
			}
			if (hit) {
				int at = off + __popc(ballot & ((1u << lane) - 1u));
				list[at] = (int)s;
				listDraws[at] = slotDraws[s];
				boxes[at] = bx;
			}
			__syncthreads();
			if (inside)
				for (int q = 0; q < total; q++) {
					int4 bb = boxes[q];
					if (px >= bb.x && px < bb.z && py >= bb.y && py < bb.w) {
						if (!touched) { d = *dp; touched = true; }
						Ctx c;
						prepare_target(draws[listDraws[q]], c);
						d = apply(c, batch_prim(b, list[q]), px, py, d);
					}
				}
			__syncthreads();
		}
		if (touched) *dp = d;
	}
}

extern "C" __global__ void __launch_bounds__(256) raster_fill(const RasterFillParams p)
{
	for (i64 n = (i64)blockIdx.x * blockDim.x + threadIdx.x; n < p.count; n += (i64)gridDim.x * blockDim.x) {
		if (p.bpp == 1) ((u8 *)p.pixels)[n] = (u8)(p.value & 255);
		else ((u32 *)p.pixels)[n] = p.value;
	}
}

extern "C" __global__ void __launch_bounds__(256) raster_copy(const RasterCopyParams p)
{
	bool swap = (p.mode & 1) != 0, keyed = (p.mode & 2) != 0;
	for (i64 y = blockIdx.y; y < p.height; y += gridDim.y) {
		u8 *dr = (u8 *)p.dst + y * p.dstStride;
		const u8 *sr = (const u8 *)p.src + y * p.srcStride;
		for (i64 x = (i64)blockIdx.x * blockDim.x + threadIdx.x; x < p.width; x += (i64)gridDim.x * blockDim.x) {
			if (p.bpp == 1) { dr[x] = sr[x]; continue; }
			u32 v = ((const u32 *)sr)[x];
			if (p.mode == 0) { ((u32 *)dr)[x] = v; continue; }
			if (!keyed || (v >> 24) != 0) ((u32 *)dr)[x] = swap ? swap_rb(v) : v;
		}
	}
}

extern "C" __global__ void __launch_bounds__(256) raster_blit(const RasterBlitParams p)
{
	i64 sx = p.srcRect[0], sy = p.srcRect[1], sw = p.srcRect[2], sh = p.srcRect[3];
	i64 dx = p.dstRect[0], dy = p.dstRect[1], dw = p.dstRect[2], dh = p.dstRect[3];
	if (sw <= 0 || sh <= 0 || dw <= 0 || dh <= 0) return;
	i64 x0 = dx > 0 ? dx : 0, y0 = dy > 0 ? dy : 0;
	i64 x1 = dx + dw, y1 = dy + dh;
	if (x1 > p.dstWidth) x1 = p.dstWidth;
	if (y1 > p.dstHeight) y1 = p.dstHeight;
	int sbpp = p.srcFormat == PF_TEX_R8 ? 1 : 4, tbpp = p.dstFormat == PF_TEX_R8 ? 1 : 4;
	Tex t;
	t.p = (const u8 *)p.src; t.w = p.srcWidth; t.h = p.srcHeight; t.fmt = p.srcFormat; t.linear = p.linear != 0; t.repeat = false;
	bool same = sw == dw && sh == dh && sx >= 0 && sy >= 0 && sx + sw <= t.w && sy + sh <= t.h;
	i64 xStart = x0 + (i64)blockIdx.x * blockDim.x + threadIdx.x, xStep = (i64)gridDim.x * blockDim.x;
	if (same) {
		/* 1:1: convert: (two loops: a select between the paths would compute the scaled one's divisions too) */
		for (i64 py = y0 + blockIdx.y; py < y1; py += gridDim.y)
			for (i64 px = xStart; px < x1; px += xStep) {
				u8 *d = (u8 *)p.dst + (py * p.dstWidth + px) * tbpp;
				const u8 *s = t.p + ((py - dy + sy) * t.w + (px - dx + sx)) * sbpp;
				if (p.srcFormat == p.dstFormat) {
					if (sbpp == 1) *d = *s; else *(u32 *)d = *(const u32 *)s;
				} else if (p.srcFormat == PF_TEX_R8) {
					*(u32 *)d = p.dstFormat == PF_TEX_BGRA8 ? (((u32)*s << 16) | 0xFF000000u) : ((u32)*s | 0xFF000000u);
				} else if (p.dstFormat == PF_TEX_R8) {
					*d = p.srcFormat == PF_TEX_BGRA8 ? s[2] : s[0];
				} else {
					*(u32 *)d = swap_rb(*(const u32 *)s);
				}
			}
		return;
	}
	for (i64 py = y0 + blockIdx.y; py < y1; py += gridDim.y) {
		double v = (double)sy + ((double)py + 0.5 - (double)dy) * (double)sh / (double)dh;
		for (i64 px = xStart; px < x1; px += xStep) {
			u8 *d = (u8 *)p.dst + (py * p.dstWidth + px) * tbpp;
			double u = (double)sx + ((double)px + 0.5 - (double)dx) * (double)sw / (double)dw;
			u32 q = sample(t, PF_TEX_RGBA8, u, v);
			if (p.dstFormat == PF_TEX_R8) *d = (u8)(q & 255);
			else *(u32 *)d = p.dstFormat == PF_TEX_BGRA8 ? swap_rb(q) : q;
		}
	}
}
