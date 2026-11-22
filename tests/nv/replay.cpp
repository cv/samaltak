// The raster kernels (gpu/nv/raster.cu, as the cubin checked in as NvRasterKernels) against PlatformRaster, through
// the CUDA driver API only (cuModuleLoadData + cuLaunchKernel with the parameter structs, as a launcher without the
// CUDA runtime does). tests/nv/README.md; built and run by make test-nv.
//
//   replay <cubin> <record>     replay a SoftwareGPURecorder record (Tests-Graphics): every texture, buffer, upload,
//                                clear, draw, blit on the GPU and on the C reference (vm/gen/platform_raster.c, linked
//                                twice: -ffp-contract=off, as the UEFI VM, and =fast, gcc's default, as the hosted VM);
//                                at each pass end and presented frame compare the GPU's pixels, the references' and the
//                                recorded ones; report the GPU time of each command buffer.
//   fuzz <cubin> <cases> [seed]  random draws (every mode, format, blend, sampler, quads and triangles, scissors,
//                                viewports), blits, copies and fills against the reference without contraction.
// Exit status 1 if the GPU differs from the reference without contraction anywhere, or a recorded frame matches
// neither reference (the replay would not be faithful).
#include <cuda.h>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <chrono>
#include <map>
#include <memory>
#include <string>
#include <vector>
#include "../../gpu/nv/raster_abi.h"

extern "C" {
struct raster_state {
	uint8_t *pixels; int64_t width, height; int32_t format, blend;
	int64_t scissor_x, scissor_y, scissor_w, scissor_h;
	double viewport_x, viewport_y, viewport_w, viewport_h, view_size_x, view_size_y, translate_x, translate_y;
	uint8_t *texture; int64_t texture_width, texture_height; int32_t texture_format; bool linear, wrap;
};
void ref_off_rasterize(raster_state *, uint8_t *, int64_t, int64_t);
void ref_fma_rasterize(raster_state *, uint8_t *, int64_t, int64_t);
void ref_off_blit_pixels(uint8_t *, int64_t, int64_t, int32_t, int64_t *, uint8_t *, int64_t, int64_t, int32_t, int64_t *, bool);
void ref_fma_blit_pixels(uint8_t *, int64_t, int64_t, int32_t, int64_t *, uint8_t *, int64_t, int64_t, int32_t, int64_t *, bool);
void ref_off_copy(uint8_t *, int64_t, uint8_t *, int64_t, int64_t, int64_t, int64_t, int64_t);
void ref_off_fill(uint8_t *, int64_t, int, uint32_t);
}
static_assert(sizeof(raster_state) == 160, "RasterState as the VM lays it out");

#define CK(x) do { CUresult r_ = (x); if (r_ != CUDA_SUCCESS) { const char *s_ = ""; cuGetErrorString(r_, &s_); \
	fprintf(stderr, "%s:%d: %s: %s\n", __FILE__, __LINE__, #x, s_); exit(2); } } while (0)

static CUfunction fPrims, fTiles, fFill, fCopy, fBlit;
static CUstream stream;
static CUdeviceptr scratch;
static size_t scratchBytes;
static std::vector<std::pair<CUevent, CUevent>> spans;  // around each launch since the last flush
static size_t spanCount;
static double kernelMs;       // GPU time of the kernels since the last reset (flushTiming)
static double wallMs;         // from the first launch's start to the last one's end
static bool timing = true;
static bool quiet = false;     // timing passes: no per-check lines

static int bppOf(int fmt) { return fmt == 1 ? 1 : 4; }

static void launch(CUfunction f, unsigned gx, unsigned gy, unsigned bx, void *params)
{
	void *args[] = {params};
	if (timing) {
		if (spanCount == spans.size()) {
			CUevent a, b;
			CK(cuEventCreate(&a, CU_EVENT_DEFAULT));
			CK(cuEventCreate(&b, CU_EVENT_DEFAULT));
			spans.push_back({a, b});
		}
		CK(cuEventRecord(spans[spanCount].first, stream));
	}
	CK(cuLaunchKernel(f, gx ? gx : 1, gy ? gy : 1, 1, bx, 1, 1, 0, stream, args, nullptr));
	if (timing) CK(cuEventRecord(spans[spanCount++].second, stream));
}

// Add the launches' GPU time since the last flush to kernelMs, the span from the first start to the last end to wallMs.
static void flushTiming()
{
	if (!spanCount) return;
	CK(cuEventSynchronize(spans[spanCount - 1].second));
	for (size_t k = 0; k < spanCount; k++) {
		float ms;
		CK(cuEventElapsedTime(&ms, spans[k].first, spans[k].second));
		kernelMs += ms;
	}
	float ms;
	CK(cuEventElapsedTime(&ms, spans[0].first, spans[spanCount - 1].second));
	wallMs += ms;
	spanCount = 0;
}

static void ensureScratch(size_t n)
{
	if (n <= scratchBytes) return;
	if (scratch) CK(cuMemFree(scratch));
	scratchBytes = n * 2;
	CK(cuMemAlloc(&scratch, scratchBytes));
}

static std::vector<uint8_t> download(CUdeviceptr p, size_t n);
static int64_t kinds[10];  // fuzz: primitives by path (raster.cu's K_*: the first int of a slot's record)
static bool countKinds = false;

static void gpuDraw(RasterDrawParams p)
{
	int64_t slots = p.count / 3;
	size_t scratchNeeded = RASTER_SCRATCH_HEADER + (size_t)(slots > 0 ? slots : 0) * RASTER_PRIM_BYTES;
	ensureScratch(scratchNeeded);
	p.prims = scratch;
	if (countKinds) CK(cuMemsetD8(scratch, 0, scratchNeeded));  // a draw that draws nothing writes no records
	launch(fPrims, (unsigned)((slots + 255) / 256), 1, 256, &p);
	// enough blocks for the tiles of the scissor within the target (the clip is inside it)
	int64_t cw = std::min(p.scissorX + p.scissorW, p.width) - std::max<int64_t>(p.scissorX, 0);
	int64_t ch = std::min(p.scissorY + p.scissorH, p.height) - std::max<int64_t>(p.scissorY, 0);
	if (cw > 0 && ch > 0) launch(fTiles, (unsigned)(((cw + 15) / 16) * ((ch + 15) / 16)), 1, RASTER_TILE_THREADS, &p);
	if (countKinds && slots > 0) {
		std::vector<uint8_t> s = download(scratch, scratchNeeded);
		for (int64_t n = 0; n < slots; n++) {
			int k;
			memcpy(&k, &s[RASTER_SCRATCH_HEADER + slots * 16 + n * (RASTER_PRIM_BYTES - 16)], 4);
			if (k >= 0 && k < 10) kinds[k]++;
		}
	}
}

static void gpuFill(CUdeviceptr px, int64_t n, int bpp, uint32_t v)
{
	RasterFillParams p{px, n, bpp, v};
	launch(fFill, (unsigned)std::min<int64_t>((n + 255) / 256, 4096), 1, 256, &p);
}

static void gpuBlit(RasterBlitParams p)
{
	launch(fBlit, (unsigned)((p.dstWidth + 255) / 256), (unsigned)std::min<int64_t>(p.dstHeight, 65535), 256, &p);
}

struct Diff { int64_t pixels = 0; int maxDelta = 0; int64_t first = -1; };

static Diff compare(const uint8_t *a, const uint8_t *b, int64_t n, int bpp)
{
	Diff d;
	for (int64_t i = 0; i < n; i++) {
		if (memcmp(a + i * bpp, b + i * bpp, bpp) == 0) continue;
		if (d.first < 0) d.first = i;
		d.pixels++;
		for (int c = 0; c < bpp; c++) d.maxDelta = std::max(d.maxDelta, abs((int)a[i * bpp + c] - (int)b[i * bpp + c]));
	}
	return d;
}

static std::vector<uint8_t> download(CUdeviceptr p, size_t n)
{
	std::vector<uint8_t> v(n);
	CK(cuStreamSynchronize(stream));
	CK(cuMemcpyDtoH(v.data(), p, n));
	return v;
}

static void loadModule(const char *path)
{
	FILE *f = fopen(path, "rb");
	if (!f) { perror(path); exit(2); }
	std::vector<char> b;
	char buf[65536];
	size_t n;
	while ((n = fread(buf, 1, sizeof buf, f)) > 0) b.insert(b.end(), buf, buf + n);
	fclose(f);
	CK(cuInit(0));
	CUdevice dev;
	CK(cuDeviceGet(&dev, 0));
	CUcontext ctx;
	CK(cuDevicePrimaryCtxRetain(&ctx, dev));
	CK(cuCtxSetCurrent(ctx));
	char name[256];
	CK(cuDeviceGetName(name, sizeof name, dev));
	int major, minor;
	CK(cuDeviceGetAttribute(&major, CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MAJOR, dev));
	CK(cuDeviceGetAttribute(&minor, CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MINOR, dev));
	printf("device: %s (sm_%d%d), cubin %s (%zu bytes)\n", name, major, minor, path, b.size());
	CUmodule m;
	CK(cuModuleLoadData(&m, b.data()));
	CK(cuModuleGetFunction(&fPrims, m, "raster_prims"));
	CK(cuModuleGetFunction(&fTiles, m, "raster_tiles"));
	CK(cuModuleGetFunction(&fFill, m, "raster_fill"));
	CK(cuModuleGetFunction(&fCopy, m, "raster_copy"));
	CK(cuModuleGetFunction(&fBlit, m, "raster_blit"));
	CK(cuStreamCreate(&stream, CU_STREAM_DEFAULT));  // ordered after the (legacy-stream) copies
}

// ---- replay ----

struct Obj {
	int kind = 0;  // 1 texture or swapchain buffer, 2 vertex buffer
	int64_t w = 0, h = 0; int fmt = 0; size_t bytes = 0;
	CUdeviceptr dev = 0;
	std::vector<uint8_t> off, fma;  // the references' copies
	~Obj() { if (dev) cuMemFree(dev); }
};
typedef std::shared_ptr<Obj> ObjP;

static ObjP newObj(int kind, int64_t w, int64_t h, int fmt, size_t bytes)
{
	auto o = std::make_shared<Obj>();
	o->kind = kind; o->w = w; o->h = h; o->fmt = fmt; o->bytes = bytes;
	CK(cuMemAlloc(&o->dev, bytes ? bytes : 1));
	CK(cuMemsetD8(o->dev, 0, bytes ? bytes : 1));
	o->off.assign(bytes, 0);
	o->fma.assign(bytes, 0);
	return o;
}

struct Totals { int64_t checks = 0, gpuOffDiffs = 0, gpuRecordedDiffs = 0, unfaithful = 0, recordedFma = 0, recordedOff = 0; int maxDelta = 0; };

static void check(const char *what, int64_t handle, Obj &o, const uint8_t *recorded, Totals &t, bool refs)
{
	flushTiming();
	CK(cuStreamSynchronize(stream));
	std::vector<uint8_t> g = download(o.dev, o.bytes);
	int bpp = bppOf(o.fmt);
	int64_t n = o.w * o.h;
	Diff gr = compare(g.data(), recorded, n, bpp);
	t.checks++;
	t.maxDelta = std::max(t.maxDelta, gr.maxDelta);
	if (gr.pixels) t.gpuRecordedDiffs++;
	if (refs) {
		Diff go = compare(g.data(), o.off.data(), n, bpp);
		Diff ro = compare(recorded, o.off.data(), n, bpp);
		Diff rf = compare(recorded, o.fma.data(), n, bpp);
		if (go.pixels) t.gpuOffDiffs++;
		if (!rf.pixels) t.recordedFma++;
		if (!ro.pixels) t.recordedOff++;
		if (rf.pixels && ro.pixels) t.unfaithful++;
		printf("  %-8s %3lld %5lldx%-5lld gpu/ref %lld px%s, gpu/recorded %lld px (max %d), recorded/ref-fma %lld, recorded/ref %lld\n",
			what, (long long)handle, (long long)o.w, (long long)o.h, (long long)go.pixels,
			go.pixels ? " <-- DIFFERS" : "", (long long)gr.pixels, gr.maxDelta, (long long)rf.pixels, (long long)ro.pixels);
		if (go.pixels) printf("           first at (%lld, %lld): gpu %08x ref %08x\n", (long long)(go.first % o.w), (long long)(go.first / o.w),
			bpp == 4 ? ((uint32_t *)g.data())[go.first] : g[go.first], bpp == 4 ? ((uint32_t *)o.off.data())[go.first] : o.off[go.first]);
	} else if (!quiet) {
		printf("  %-8s %3lld %5lldx%-5lld gpu/recorded %lld px (max %d)\n", what, (long long)handle, (long long)o.w, (long long)o.h, (long long)gr.pixels, gr.maxDelta);
	}
	// carry on from the recorded pixels, so that a difference is reported where it starts
	CK(cuMemcpyHtoD(o.dev, recorded, o.bytes));
	if (refs) { memcpy(o.off.data(), recorded, o.bytes); memcpy(o.fma.data(), recorded, o.bytes); }
}

static int replay(const char *path, bool refs)
{
	FILE *f = fopen(path, "rb");
	if (!f) { perror(path); return 2; }
	std::vector<uint8_t> b;
	{ std::vector<uint8_t> buf(1 << 20); size_t n; while ((n = fread(buf.data(), 1, buf.size(), f)) > 0) b.insert(b.end(), buf.begin(), buf.begin() + n); }
	fclose(f);
	if (b.size() < 8 || memcmp(b.data(), "SAMNVRC1", 8)) { fprintf(stderr, "%s: not a SoftwareGPURecorder record\n", path); return 2; }
	std::map<int64_t, ObjP> handles, windows;
	Totals t;
	int64_t draws = 0, slots = 0, cmdDraws = 0, cmdSlots = 0;
	double cpuOffMs = 0, cmdMaxPixels = 0;
	int frame = 0;
	std::vector<std::pair<double, double>> frameTimes;  // GPU ms, reference ms
	kernelMs = wallMs = 0;
	size_t i = 8;
	auto get = [&](int64_t h) -> ObjP { auto it = handles.find(h); if (it == handles.end()) { fprintf(stderr, "unknown handle %lld\n", (long long)h); exit(2); } return it->second; };
	while (i + 16 <= b.size()) {
		uint32_t op, n, nb;
		memcpy(&op, &b[i], 4); memcpy(&n, &b[i + 4], 4); memcpy(&nb, &b[i + 8], 4);
		const uint8_t *wp = &b[i + 16];
		auto I = [&](int k) { int64_t v; memcpy(&v, wp + 8 * k, 8); return v; };
		auto D = [&](int k) { double v; memcpy(&v, wp + 8 * k, 8); return v; };
		const uint8_t *data = wp + 8 * n;
		i += 16 + 8 * (size_t)n + nb + ((8 - nb % 8) % 8);
		switch (op) {
		case 1: handles[I(0)] = newObj(1, I(1), I(2), (int)I(3), (size_t)(I(1) * I(2) * bppOf((int)I(3)))); break;
		case 2: handles[I(0)] = newObj(2, 0, 0, 0, (size_t)I(1)); break;
		case 3: handles.erase(I(0)); break;
		case 4: {
			ObjP o = get(I(0));
			int bpp = bppOf(o->fmt);
			int64_t x = I(1), y = I(2), w = I(3), h = I(4);
			for (int64_t j = 0; j < h; j++) {
				size_t at = (size_t)(((y + j) * o->w + x) * bpp);
				CK(cuMemcpyHtoD(o->dev + at, data + j * w * bpp, w * bpp));
				if (refs) { memcpy(&o->off[at], data + j * w * bpp, w * bpp); memcpy(&o->fma[at], data + j * w * bpp, w * bpp); }
			}
			break;
		}
		case 5: {
			ObjP o = get(I(0));
			CK(cuMemcpyHtoD(o->dev + I(1), data, (size_t)I(2)));
			if (refs) { memcpy(&o->off[I(1)], data, I(2)); memcpy(&o->fma[I(1)], data, I(2)); }
			break;
		}
		case 6: {
			ObjP &wb = windows[I(1)];
			if (!wb || wb->w != I(2) || wb->h != I(3)) wb = newObj(1, I(2), I(3), 3, (size_t)(I(2) * I(3) * 4));
			handles[I(0)] = wb;
			break;
		}
		case 7: {
			ObjP o = get(I(0));
			gpuFill(o->dev, o->w * o->h, bppOf(o->fmt), (uint32_t)I(1));
			if (refs) { ref_off_fill(o->off.data(), o->w * o->h, bppOf(o->fmt), (uint32_t)I(1)); ref_off_fill(o->fma.data(), o->w * o->h, bppOf(o->fmt), (uint32_t)I(1)); }
			break;
		}
		case 8: {
			ObjP tg = get(I(0)), vb = get(I(17));
			ObjP tx = I(14) ? get(I(14)) : nullptr;
			RasterDrawParams p{};
			p.pixels = tg->dev; p.width = tg->w; p.height = tg->h; p.format = tg->fmt; p.blend = (int)I(1);
			p.scissorX = I(2); p.scissorY = I(3); p.scissorW = I(4); p.scissorH = I(5);
			p.viewportX = D(6); p.viewportY = D(7); p.viewportW = D(8); p.viewportH = D(9);
			p.viewSizeX = D(10); p.viewSizeY = D(11); p.translateX = D(12); p.translateY = D(13);
			if (tx) { p.texture = tx->dev; p.textureWidth = tx->w; p.textureHeight = tx->h; p.textureFormat = tx->fmt; }
			p.linear = (int)I(15); p.repeat = (int)I(16);
			p.vertices = vb->dev + I(18); p.first = I(19); p.count = I(20);
			gpuDraw(p);
			draws++; cmdDraws++; slots += p.count / 3; cmdSlots += p.count / 3;
			cmdMaxPixels = std::max(cmdMaxPixels, (double)(tg->w * tg->h));
			if (refs) {
				for (int k = 0; k < 2; k++) {
					raster_state s{};
					s.pixels = (k ? tg->fma : tg->off).data(); s.width = tg->w; s.height = tg->h; s.format = tg->fmt; s.blend = (int)I(1);
					s.scissor_x = I(2); s.scissor_y = I(3); s.scissor_w = I(4); s.scissor_h = I(5);
					s.viewport_x = D(6); s.viewport_y = D(7); s.viewport_w = D(8); s.viewport_h = D(9);
					s.view_size_x = D(10); s.view_size_y = D(11); s.translate_x = D(12); s.translate_y = D(13);
					if (tx) { s.texture = (k ? tx->fma : tx->off).data(); s.texture_width = tx->w; s.texture_height = tx->h; s.texture_format = tx->fmt; }
					s.linear = I(15) != 0; s.wrap = I(16) != 0;
					uint8_t *base = (k ? vb->fma : vb->off).data() + I(18);
					auto t0 = std::chrono::steady_clock::now();
					(k ? ref_fma_rasterize : ref_off_rasterize)(&s, base, I(19), I(20));
					if (!k) cpuOffMs += std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
				}
			}
			break;
		}
		case 9: {
			ObjP s = get(I(0)), d = get(I(5));
			RasterBlitParams p{};
			p.src = s->dev; p.srcWidth = s->w; p.srcHeight = s->h; p.dst = d->dev; p.dstWidth = d->w; p.dstHeight = d->h;
			for (int k = 0; k < 4; k++) { p.srcRect[k] = I(1 + k); p.dstRect[k] = I(6 + k); }
			p.srcFormat = s->fmt; p.dstFormat = d->fmt; p.linear = (int)I(10);
			gpuBlit(p);
			if (refs) {
				int64_t sr[4], dr[4];
				for (int k = 0; k < 4; k++) { sr[k] = I(1 + k); dr[k] = I(6 + k); }
				auto t0 = std::chrono::steady_clock::now();
				ref_off_blit_pixels(s->off.data(), s->w, s->h, s->fmt, sr, d->off.data(), d->w, d->h, d->fmt, dr, I(10) != 0);
				cpuOffMs += std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
				ref_fma_blit_pixels(s->fma.data(), s->w, s->h, s->fmt, sr, d->fma.data(), d->w, d->h, d->fmt, dr, I(10) != 0);
			}
			break;
		}
		case 10: check("pass-end", I(0), *get(I(0)), data, t, refs); break;
		case 11: check("present", I(0), *windows[I(0)], data, t, refs); break;
		case 12:
			flushTiming();
			CK(cuStreamSynchronize(stream));
			if (!quiet) printf("submit %d: %lld draws, %lld primitive slots, largest target %.0f px: GPU kernels %.3f ms (%.3f ms first start to last end)",
				frame, (long long)cmdDraws, (long long)cmdSlots, cmdMaxPixels, kernelMs, wallMs);
			if (!quiet) printf("%s\n", refs ? (", reference " + std::to_string(cpuOffMs) + " ms").c_str() : "");
			if (cmdMaxPixels >= 1920.0 * 1080.0) frameTimes.push_back({kernelMs, cpuOffMs});
			frame++; cmdDraws = cmdSlots = 0; cmdMaxPixels = 0; kernelMs = wallMs = 0; cpuOffMs = 0;
			break;
		default: fprintf(stderr, "unknown op %u\n", op); return 2;
		}
	}
	CK(cuStreamSynchronize(stream));
	double gsum = 0, rsum = 0;
	for (auto &x : frameTimes) { gsum += x.first; rsum += x.second; }
	printf("replayed %lld draws (%lld primitive slots); %lld checks: GPU != reference (no contraction) in %lld, GPU != recorded in %lld (max channel delta %d)\n",
		(long long)draws, (long long)slots, (long long)t.checks, (long long)t.gpuOffDiffs, (long long)t.gpuRecordedDiffs, t.maxDelta);
	if (refs) printf("recorded pixels equal the reference with contraction in %lld checks, without in %lld, neither in %lld\n",
		(long long)t.recordedFma, (long long)t.recordedOff, (long long)t.unfaithful);
	if (!frameTimes.empty())
		printf("1920x1080 command buffers: %zu, GPU kernels %.3f ms each on average%s\n", frameTimes.size(), gsum / frameTimes.size(),
			refs ? (" (C reference: " + std::to_string(rsum / frameTimes.size()) + " ms)").c_str() : "");
	return (t.gpuOffDiffs || t.unfaithful) ? 1 : 0;
}

// ---- fuzz ----

static uint64_t rng = 88172645463325252ULL;
static uint32_t rnd() { rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17; return (uint32_t)(rng >> 16); }
static int rint_(int a, int b) { return a + (int)(rnd() % (uint32_t)(b - a + 1)); }
static float rf(float a, float b) { return a + (b - a) * (rnd() % 1000001) / 1000000.0f; }
static float rcoord(float a, float b) { float v = rf(a, b); int k = rint_(0, 3); return k == 0 ? (float)(int)v : k == 1 ? (int)v + 0.5f : v; }

struct Vtx { float r[4]; uint32_t uv0, uv1, color, mode; float org[2]; };
static_assert(sizeof(Vtx) == 40, "the Renderer's vertex");

static void randomBytes(std::vector<uint8_t> &v) { for (auto &x : v) x = (uint8_t)rnd(); }

static int fuzz(int cases)
{
	int64_t bad = 0, pixels = 0, drawn = 0;
	timing = false;
	countKinds = true;
	for (int c = 0; c < cases; c++) {
		int W = rint_(1, 200), H = rint_(1, 160), fmt = rint_(2, 3);
		std::vector<uint8_t> tgt((size_t)W * H * 4), ref;
		randomBytes(tgt);
		ref = tgt;
		CUdeviceptr dTgt, dTex = 0, dVtx;
		CK(cuMemAlloc(&dTgt, tgt.size()));
		CK(cuMemcpyHtoD(dTgt, tgt.data(), tgt.size()));
		int kind = rint_(0, 9);
		const char *what;
		if (kind <= 6) {
			what = "draw";
			int tfmt = rint_(1, 3), TW = rint_(1, 48), TH = rint_(1, 48);
			bool hasTex = rint_(0, 9) != 0;
			std::vector<uint8_t> tex((size_t)TW * TH * bppOf(tfmt));
			randomBytes(tex);
			if (rint_(0, 2) == 0) for (size_t k = 0; k < tex.size(); k += 7) tex[k] = rint_(0, 1) ? 0 : 255;
			if (hasTex) { CK(cuMemAlloc(&dTex, tex.size())); CK(cuMemcpyHtoD(dTex, tex.data(), tex.size())); }
			bool exact = rint_(0, 2) == 0;  // the 1:1 paths: default viewport, integer translation and origins
			int first = rint_(0, 11), count = rint_(0, 120);
			std::vector<Vtx> v(first + count + 6);
			for (auto &x : v) { x.r[0] = rf(-20, 220); x.r[1] = rf(-20, 180); x.r[2] = rf(-20, 220); x.r[3] = rf(-20, 180); x.uv0 = rnd(); x.uv1 = rnd(); x.color = rnd(); x.mode = rnd(); x.org[0] = rf(-5, 5); x.org[1] = rf(-5, 5); }
			int k = first;
			while (k < first + count) {
				int m = rint_(0, 7);
				if (m == 6) m = 2;
				uint32_t mode = (uint32_t)m | ((uint32_t)rint_(0, 4) << 8) | ((uint32_t)rint_(0, 3) << 16);
				uint32_t color = rnd();
				if (rint_(0, 3) == 0) color |= 0xFF000000u;
				if (rint_(0, 5) == 0) color = 0;
				if (k % 6 == 0 && rint_(0, 3) != 0) {  // a quad
					Vtx q;
					q.r[0] = rcoord(-10, W + 10); q.r[1] = rcoord(-10, H + 10);
					int w = (exact ? rint_(0, 3) != 0 : rint_(0, 3) == 0) ? rint_(1, TW) : 0, h = rint_(1, TH);
					if (w) { q.r[0] = (float)(int)q.r[0]; q.r[1] = (float)(int)q.r[1]; q.r[2] = q.r[0] + w; q.r[3] = q.r[1] + h; }
					else { q.r[2] = rcoord(-10, W + 10); q.r[3] = rcoord(-10, H + 10); }
					uint32_t u0 = rint_(0, exact ? TW - w : TW + 4), v0 = rint_(0, exact ? TH - h : TH + 4);
					q.uv0 = u0 | (v0 << 16);
					q.uv1 = w ? ((u0 + w) | ((v0 + h) << 16)) : ((uint32_t)rint_(0, TW * 2) | ((uint32_t)rint_(0, TH * 2) << 16));
					if (m == 5) q.uv0 = rnd(), q.uv1 = rnd();
					q.color = color; q.mode = mode;
					q.org[0] = rint_(0, 1) ? 0.0f : exact ? (float)rint_(-3, 3) : rf(-3, 3); q.org[1] = rint_(0, 1) ? 0.0f : exact ? (float)rint_(-3, 3) : rf(-3, 3);
					for (int j = 0; j < 6 && k + j < (int)v.size(); j++) v[k + j] = q;
					k += 6;
				} else {
					for (int j = 0; j < 3 && k + j < (int)v.size(); j++) {
						Vtx &x = v[k + j];
						bool explicitly = rint_(0, 3) != 0;
						x.mode = mode | (explicitly ? 0x80000000u : 0);
						x.color = rint_(0, 1) ? color : rnd();
						if (explicitly) { float a = rf(-4, TW + 4), b2 = rf(-4, TH + 4); memcpy(&x.uv0, &a, 4); memcpy(&x.uv1, &b2, 4); }
					}
					k += 3;
				}
			}
			CK(cuMemAlloc(&dVtx, v.size() * sizeof(Vtx)));
			CK(cuMemcpyHtoD(dVtx, v.data(), v.size() * sizeof(Vtx)));
			RasterDrawParams p{};
			p.pixels = dTgt; p.width = W; p.height = H; p.format = fmt; p.blend = rint_(0, 4) == 0 ? rint_(0, 1) : 2;
			p.scissorX = rint_(0, 3) ? 0 : rint_(-10, W); p.scissorY = rint_(0, 3) ? 0 : rint_(-10, H);
			p.scissorW = rint_(0, 3) ? W : rint_(0, W + 10); p.scissorH = rint_(0, 3) ? H : rint_(0, H + 10);
			bool vp = !exact && rint_(0, 3) == 0;
			p.viewportX = vp ? rf(-5, 20) : 0; p.viewportY = vp ? rf(-5, 20) : 0;
			p.viewportW = vp ? rf(1, W * 1.5f) : W; p.viewportH = vp ? rf(1, H * 1.5f) : H;
			p.viewSizeX = exact || rint_(0, 3) ? W : rf(1, W * 2.0f); p.viewSizeY = exact || rint_(0, 3) ? H : rf(1, H * 2.0f);
			p.translateX = rint_(0, 1) ? 0 : exact ? rint_(-8, 8) : (double)rcoord(-8, 8); p.translateY = rint_(0, 1) ? 0 : exact ? rint_(-8, 8) : (double)rcoord(-8, 8);
			if (exact && hasTex) p.blend = 2;
			if (hasTex) { p.texture = dTex; p.textureWidth = TW; p.textureHeight = TH; p.textureFormat = tfmt; }
			p.linear = rint_(0, 1); p.repeat = rint_(0, 3) == 0;
			p.vertices = dVtx; p.first = first; p.count = count;
			gpuDraw(p);
			raster_state s{};
			s.pixels = ref.data(); s.width = W; s.height = H; s.format = fmt; s.blend = p.blend;
			s.scissor_x = p.scissorX; s.scissor_y = p.scissorY; s.scissor_w = p.scissorW; s.scissor_h = p.scissorH;
			s.viewport_x = p.viewportX; s.viewport_y = p.viewportY; s.viewport_w = p.viewportW; s.viewport_h = p.viewportH;
			s.view_size_x = p.viewSizeX; s.view_size_y = p.viewSizeY; s.translate_x = p.translateX; s.translate_y = p.translateY;
			if (hasTex) { s.texture = tex.data(); s.texture_width = TW; s.texture_height = TH; s.texture_format = tfmt; }
			s.linear = p.linear; s.wrap = p.repeat;
			ref_off_rasterize(&s, (uint8_t *)v.data(), first, count);
			CK(cuMemFree(dVtx));
			drawn++;
		} else if (kind <= 8) {
			what = "blit";
			int sfmt = rint_(1, 3), SW = rint_(1, 64), SH = rint_(1, 64), dfmt = rint_(1, 3);
			std::vector<uint8_t> src((size_t)SW * SH * bppOf(sfmt));
			randomBytes(src);
			CK(cuMemAlloc(&dTex, src.size()));
			CK(cuMemcpyHtoD(dTex, src.data(), src.size()));
			// the destination: tgt's bytes as dfmt pixels of W x H (R8 uses the first quarter)
			int64_t sr[4] = {rint_(-4, SW), rint_(-4, SH), rint_(-2, SW + 4), rint_(-2, SH + 4)};
			int64_t dr[4] = {rint_(-8, W), rint_(-8, H), rint_(0, 1) ? sr[2] : rint_(-2, W + 8), rint_(0, 1) ? sr[3] : rint_(-2, H + 8)};
			// (the reference copies a negative count where the destination rect lies left of or above the target)
			if (dr[0] + dr[2] < 1) dr[2] = 1 - dr[0];
			if (dr[1] + dr[3] < 1) dr[3] = 1 - dr[1];
			RasterBlitParams p{};
			p.src = dTex; p.srcWidth = SW; p.srcHeight = SH; p.dst = dTgt; p.dstWidth = W; p.dstHeight = H;
			for (int q = 0; q < 4; q++) { p.srcRect[q] = sr[q]; p.dstRect[q] = dr[q]; }
			p.srcFormat = sfmt; p.dstFormat = dfmt; p.linear = rint_(0, 1);
			gpuBlit(p);
			ref_off_blit_pixels(src.data(), SW, SH, sfmt, sr, ref.data(), W, H, dfmt, dr, p.linear != 0);
		} else {
			what = "copy/fill";
			if (rint_(0, 1)) {
				int bpp = rint_(0, 1) ? 1 : 4;
				int64_t n = rint_(0, W * H);
				uint32_t val = rnd();
				gpuFill(dTgt, n, bpp, val);
				ref_off_fill(ref.data(), n, bpp, val);
			} else {
				int bpp = rint_(0, 1) ? 1 : 4, w = rint_(1, W / 2 + 1), h = rint_(1, H), mode = rint_(0, 3);
				std::vector<uint8_t> src((size_t)w * h * 4);
				randomBytes(src);
				for (size_t q = 3; q < src.size(); q += 8) src[q] = 0;
				CK(cuMemAlloc(&dTex, src.size()));
				CK(cuMemcpyHtoD(dTex, src.data(), src.size()));
				RasterCopyParams p{dTgt, (int64_t)W * 4, dTex, (int64_t)w * bpp, w, h, bpp, mode};
				launch(fCopy, (unsigned)((w + 255) / 256), (unsigned)h, 256, &p);
				ref_off_copy(ref.data(), (int64_t)W * 4, src.data(), (int64_t)w * bpp, w, h, bpp, mode);
			}
		}
		std::vector<uint8_t> g = download(dTgt, tgt.size());
		Diff d = compare(g.data(), ref.data(), (int64_t)W * H, 4);
		if (d.pixels) {
			bad++;
			pixels += d.pixels;
			if (bad <= 10) printf("case %d (%s, %dx%d format %d): %lld pixels differ (max %d), first at (%lld, %lld): gpu %08x ref %08x\n", c, what, W, H, fmt,
				(long long)d.pixels, d.maxDelta, (long long)(d.first % W), (long long)(d.first / W), ((uint32_t *)g.data())[d.first], ((uint32_t *)ref.data())[d.first]);
		}
		CK(cuMemFree(dTgt));
		if (dTex) CK(cuMemFree(dTex));
	}
	printf("fuzz: %d cases (%lld draws): %lld differ (%lld pixels)\n", cases, (long long)drawn, (long long)bad, (long long)pixels);
	printf("primitives by path: none %lld, solid %lld/%lld/%lld (store/alpha/over), pattern %lld, 1:1 glyph %lld, 1:1 image %lld, scaled %lld, shaded %lld, triangle %lld\n",
		(long long)kinds[0], (long long)kinds[1], (long long)kinds[2], (long long)kinds[3], (long long)kinds[4], (long long)kinds[5], (long long)kinds[6], (long long)kinds[7], (long long)kinds[8], (long long)kinds[9]);
	return bad ? 1 : 0;
}

int main(int argc, char **argv)
{
	if (argc >= 4 && !strcmp(argv[1], "replay")) {
		loadModule(argv[2]);
		int status = replay(argv[3], true);
		for (int r = argc >= 5 ? atoi(argv[4]) : 0; r > 0; r--) {  // timing passes without the references
			quiet = r > 1;
			if (!quiet) printf("\ntiming pass without the references:\n");
			replay(argv[3], false);
		}
		return status;
	}
	if (argc >= 4 && !strcmp(argv[1], "fuzz")) {
		loadModule(argv[2]);
		if (argc >= 5) rng = strtoull(argv[4], nullptr, 10) * 2654435761ULL + 1;
		return fuzz(atoi(argv[3]));
	}
	fprintf(stderr, "usage: replay replay <cubin> <record> [repeat] | replay fuzz <cubin> <cases> [seed]\n");
	return 2;
}
