// The raster primitives' C (vm/gen/platform_raster.c) on a record of what a SoftwareGPU got and produced
// (SoftwareGPURecorder, tests/nv/record.st): replays it on the CPU, compares every pass end and presented frame with
// the recorded pixels (then carries on from those) and times the raster work of each 1920x1080 command buffer.
//   replay <record> [passes]    prints the differences and, per pass, the mean time of a 1920x1080 command buffer
// Built by tests/raster/run.sh with the compiler and flags given; no GPU needed.
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "samaltak.h"

typedef struct { int64_t handle; int64_t w, h; int fmt; size_t bytes; uint8_t *p; int refs; } Obj;
static Obj *objs; static int nobjs, capobjs;
typedef struct { int64_t window; Obj *o; } Win;
static Win wins[16]; static int nwins;

static int bppOf(int fmt) { return fmt == 1 ? 1 : 4; }
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec * 1e3 + t.tv_nsec / 1e6; }

// handles map to heap objects; a swapchain handle shares its window's buffer
typedef struct { int64_t h; Obj *o; } Handle;
static Handle *hs; static int nhs, caphs;
static Obj *get(int64_t h) { for (int i = nhs - 1; i >= 0; i--) if (hs[i].h == h) return hs[i].o; fprintf(stderr, "unknown handle %lld\n", (long long)h); exit(2); }
static void put(int64_t h, Obj *o)
{
	for (int i = 0; i < nhs; i++) if (hs[i].h == h) { hs[i].o = o; return; }
	if (nhs == caphs) { caphs = caphs ? 2 * caphs : 256; hs = realloc(hs, caphs * sizeof *hs); }
	hs[nhs].h = h; hs[nhs].o = o; nhs++;
}
static void drop(int64_t h) { for (int i = 0; i < nhs; i++) if (hs[i].h == h) { hs[i] = hs[--nhs]; return; } }
static Obj *newObj(int64_t w, int64_t h, int fmt, size_t bytes)
{
	Obj *o = calloc(1, sizeof *o);
	o->w = w; o->h = h; o->fmt = fmt; o->bytes = bytes; o->p = calloc(bytes ? bytes : 1, 1);
	return o;
}

static int64_t checks, diffs, diffPixels;
static double allMs;  // the raster work of every command buffer in a pass
static void check(Obj *o, const uint8_t *recorded)
{
	int bpp = bppOf(o->fmt);
	int64_t n = o->w * o->h, bad = 0;
	if (memcmp(o->p, recorded, o->bytes)) {
		for (int64_t i = 0; i < n; i++) if (memcmp(o->p + i * bpp, recorded + i * bpp, bpp)) bad++;
	}
	checks++;
	if (bad) { diffs++; diffPixels += bad; }
	memcpy(o->p, recorded, o->bytes);
}

static double pass(const uint8_t *b, size_t size, int *frames, double *drawMs, double *blitMs, double *fillMs)
{
	double total = 0, cmd = 0, cmdMax = 0;
	allMs = 0;
	int64_t i = 8;
	*frames = 0;
	nhs = 0; nwins = 0;
	while (i + 16 <= (int64_t)size) {
		uint32_t op, n, nb;
		memcpy(&op, b + i, 4); memcpy(&n, b + i + 4, 4); memcpy(&nb, b + i + 8, 4);
		const uint8_t *wp = b + i + 16;
		#define I(k) ({ int64_t v_; memcpy(&v_, wp + 8 * (k), 8); v_; })
		#define D(k) ({ double v_; memcpy(&v_, wp + 8 * (k), 8); v_; })
		const uint8_t *data = wp + 8 * n;
		i += 16 + 8 * (int64_t)n + nb + ((8 - nb % 8) % 8);
		switch (op) {
		case 1: put(I(0), newObj(I(1), I(2), (int)I(3), (size_t)(I(1) * I(2) * bppOf((int)I(3))))); break;
		case 2: put(I(0), newObj(0, 0, 0, (size_t)I(1))); break;
		case 3: drop(I(0)); break;
		case 4: {
			Obj *o = get(I(0));
			int bpp = bppOf(o->fmt);
			int64_t x = I(1), y = I(2), w = I(3), h = I(4);
			for (int64_t j = 0; j < h; j++) memcpy(o->p + ((y + j) * o->w + x) * bpp, data + j * w * bpp, w * bpp);
			break;
		}
		case 5: memcpy(get(I(0))->p + I(1), data, (size_t)I(2)); break;
		case 6: {
			Win *wn = 0;
			for (int k = 0; k < nwins; k++) if (wins[k].window == I(1)) wn = &wins[k];
			if (!wn) { wn = &wins[nwins++]; wn->window = I(1); wn->o = 0; }
			if (!wn->o || wn->o->w != I(2) || wn->o->h != I(3)) wn->o = newObj(I(2), I(3), 3, (size_t)(I(2) * I(3) * 4));
			put(I(0), wn->o);
			break;
		}
		case 7: {
			Obj *o = get(I(0));
			double t0 = now();
			platform_raster_fill(o->p, o->w * o->h, bppOf(o->fmt), (uint32_t)I(1));
			double t = now() - t0; cmd += t; *fillMs += t;
			break;
		}
		case 8: {
			Obj *tg = get(I(0)), *vb = get(I(17)), *tx = I(14) ? get(I(14)) : 0;
			raster_state s; memset(&s, 0, sizeof s);
			s.pixels = tg->p; s.width = tg->w; s.height = tg->h; s.format = tg->fmt; s.blend = (int)I(1);
			s.scissor_x = I(2); s.scissor_y = I(3); s.scissor_w = I(4); s.scissor_h = I(5);
			s.viewport_x = D(6); s.viewport_y = D(7); s.viewport_w = D(8); s.viewport_h = D(9);
			s.view_size_x = D(10); s.view_size_y = D(11); s.translate_x = D(12); s.translate_y = D(13);
			if (tx) { s.texture = tx->p; s.texture_width = tx->w; s.texture_height = tx->h; s.texture_format = tx->fmt; }
			s.linear = I(15) != 0; s.wrap = I(16) != 0;
			if (tg->w * tg->h > cmdMax) cmdMax = (double)(tg->w * tg->h);
			double t0 = now();
			rasterize(&s, vb->p + I(18), I(19), I(20));
			double t = now() - t0; cmd += t; *drawMs += t;
			break;
		}
		case 9: {
			Obj *s = get(I(0)), *d = get(I(5));
			int64_t sr[4], dr[4];
			for (int k = 0; k < 4; k++) { sr[k] = I(1 + k); dr[k] = I(6 + k); }
			double t0 = now();
			blit_pixels(s->p, s->w, s->h, s->fmt, sr, d->p, d->w, d->h, d->fmt, dr, I(10) != 0);
			double t = now() - t0; cmd += t; *blitMs += t;
			break;
		}
		case 10: check(get(I(0)), data); break;
		case 11: { Obj *o = 0; for (int k = 0; k < nwins; k++) if (wins[k].window == I(0)) o = wins[k].o; if (o) check(o, data); break; }
		case 12:
			if (cmdMax >= 1920.0 * 1080.0) { total += cmd; (*frames)++; }
			allMs += cmd;
			cmd = 0; cmdMax = 0;
			break;
		default: fprintf(stderr, "unknown op %u\n", op); exit(2);
		}
	}
	return total;  // objects leak until exit: a pass is short-lived
}

static int cmpd(const void *a, const void *b) { double x = *(const double *)a, y = *(const double *)b; return x < y ? -1 : x > y; }

int main(int argc, char **argv)
{
	if (argc < 2) { fprintf(stderr, "usage: %s record [passes]\n", argv[0]); return 2; }
	int passes = argc > 2 ? atoi(argv[2]) : 5;
	FILE *f = fopen(argv[1], "rb");
	if (!f) { perror(argv[1]); return 2; }
	fseek(f, 0, SEEK_END); size_t size = (size_t)ftell(f); fseek(f, 0, SEEK_SET);
	uint8_t *b = malloc(size);
	if (fread(b, 1, size, f) != size) { perror("read"); return 2; }
	fclose(f);
	if (size < 8 || memcmp(b, "SAMNVRC1", 8)) { fprintf(stderr, "%s: not a SoftwareGPURecorder record\n", argv[1]); return 2; }
	double *per = calloc(passes, sizeof *per);
	double draw = 0, blit = 0, fill = 0;
	int frames = 0;
	for (int p = 0; p < passes; p++) {
		checks = diffs = diffPixels = 0;
		double t = pass(b, size, &frames, &draw, &blit, &fill);
		per[p] = frames ? t / frames : 0;
	}
	qsort(per, passes, sizeof *per, cmpd);
	printf("%lld checks, %lld differ from the recorded pixels (%lld pixels)\n", (long long)checks, (long long)diffs, (long long)diffPixels);
	printf("1920x1080 command buffers: %d; ms each: median %.3f, min %.3f, max %.3f over %d passes; all command buffers %.3f ms; draws %.1f%%, blits %.1f%%, fills %.1f%%\n",
		frames, per[passes / 2], per[0], per[passes - 1], passes, allMs,
		100 * draw / (draw + blit + fill), 100 * blit / (draw + blit + fill), 100 * fill / (draw + blit + fill));
	return diffs ? 1 : 0;
}
