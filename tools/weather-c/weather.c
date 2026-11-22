// The weather app of apps/Weather in plain C, as a memory baseline for Samaltak (docs/apps.md):
// SDL3 with its GPU renderer (SDL_GPU on Vulkan, as Samaltak draws), FreeType for the same
// Nerd Font, libcurl for Open-Meteo, the same layout as the Omarchy card, and the same
// refresh policy (every 15 minutes, a minute after a failure, the wall clock checked every 2 s).
//
//   make -C tools/weather-c && tools/weather-c/weather
#include <SDL3/SDL.h>
#include <ft2build.h>
#include FT_FREETYPE_H
#include <curl/curl.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

// ---- theme and fonts

typedef struct { float r, g, b, a; } Color;
static Color fg = {0.06f, 0.06f, 0.06f, 1}, bg = {1, 0.99f, 0.94f, 1};

static Color parse_hex(const char *s, Color fallback) {
	unsigned v;
	if (!s || sscanf(s, "#%6x", &v) != 1) return fallback;
	return (Color){((v >> 16) & 255) / 255.0f, ((v >> 8) & 255) / 255.0f, (v & 255) / 255.0f, 1};
}

static char *read_file(const char *path) {
	FILE *f = fopen(path, "rb");
	if (!f) return NULL;
	fseek(f, 0, SEEK_END);
	long n = ftell(f);
	fseek(f, 0, SEEK_SET);
	char *buf = malloc(n + 1);
	buf[fread(buf, 1, n, f)] = 0;
	fclose(f);
	return buf;
}

// "key = "#rrggbb"" in a TOML file
static Color toml_color(const char *text, const char *key, Color fallback) {
	char pat[64];
	snprintf(pat, sizeof pat, "\n%s", key);
	const char *p = text ? strstr(text, pat) : NULL;
	if (!p) return fallback;
	p = strchr(p, '#');
	return parse_hex(p, fallback);
}

static void load_theme(void) {
	char path[512];
	snprintf(path, sizeof path, "%s/.local/state/omarchy/current/theme/colors.toml", getenv("HOME"));
	char *t = read_file(path);
	fg = toml_color(t, "foreground", fg);
	bg = toml_color(t, "background", bg);
	free(t);
}

static FT_Library ft;
typedef struct { SDL_Texture *tex; int w, h, left, top; float advance; float overhang; } Glyph;
typedef struct { FT_Face face; int px; Glyph cache[0x10000]; float letter; } Font;
static SDL_Renderer *ren;
static float scale = 2;

static char *fc_match(const char *pattern) {
	char cmd[256];
	snprintf(cmd, sizeof cmd, "fc-match -f '%%{file}' '%s'", pattern);
	FILE *p = popen(cmd, "r");
	static char buf[2][512];
	static int which;
	char *out = buf[which++ & 1];
	out[0] = 0;
	if (p) { if (!fgets(out, 512, p)) out[0] = 0; pclose(p); }
	return out;
}

static Font *font_open(const char *path, int px, float letter) {
	Font *f = calloc(1, sizeof *f);
	FT_New_Face(ft, path, 0, &f->face);
	FT_Set_Pixel_Sizes(f->face, 0, (FT_UInt)(px * scale));
	f->px = px;
	f->letter = letter;
	return f;
}

static Glyph *glyph(Font *f, unsigned cp) {
	Glyph *g = &f->cache[cp & 0xFFFF];
	if (g->advance > 0 || g->tex) return g;
	FT_Load_Char(f->face, cp, FT_LOAD_RENDER | FT_LOAD_TARGET_LIGHT);
	FT_GlyphSlot s = f->face->glyph;
	g->advance = s->advance.x / 64.0f / scale + f->letter;
	g->left = s->bitmap_left;
	g->top = s->bitmap_top;
	g->w = s->bitmap.width;
	g->h = s->bitmap.rows;
	g->overhang = fmaxf(0, (s->bitmap_left + (int)s->bitmap.width) / scale - s->advance.x / 64.0f / scale);
	if (g->w && g->h) {
		SDL_Surface *surf = SDL_CreateSurface(g->w, g->h, SDL_PIXELFORMAT_RGBA32);
		for (int y = 0; y < g->h; y++)
			for (int x = 0; x < g->w; x++) {
				Uint8 *px = (Uint8 *)surf->pixels + y * surf->pitch + x * 4;
				px[0] = px[1] = px[2] = 255;
				px[3] = s->bitmap.buffer[y * s->bitmap.pitch + x];
			}
		g->tex = SDL_CreateTextureFromSurface(ren, surf);
		SDL_DestroySurface(surf);
	}
	return g;
}

static unsigned next_cp(const char **s) {
	const unsigned char *p = (const unsigned char *)*s;
	unsigned c = *p++;
	if (c >= 0xF0) { c = (c & 7) << 18 | (p[0] & 63) << 12 | (p[1] & 63) << 6 | (p[2] & 63); p += 3; }
	else if (c >= 0xE0) { c = (c & 15) << 12 | (p[0] & 63) << 6 | (p[1] & 63); p += 2; }
	else if (c >= 0xC0) { c = (c & 31) << 6 | (p[0] & 63); p += 1; }
	*s = (const char *)p;
	return c;
}

// As a Qt Text measures it: advances, plus the last glyph's ink past its advance, rounded up.
static float text_width(Font *f, const char *s) {
	float w = 0, over = 0;
	while (*s) { Glyph *g = glyph(f, next_cp(&s)); w += g->advance; over = g->overhang; }
	return ceilf(w + over);
}

static float line_height(Font *f) { return f->face->size->metrics.height / 64.0f / scale; }

static void draw_text(Font *f, const char *s, float x, float y, Color c) {
	float base = y + f->face->size->metrics.ascender / 64.0f / scale;
	while (*s) {
		Glyph *g = glyph(f, next_cp(&s));
		if (g->tex) {
			SDL_SetTextureColorModFloat(g->tex, c.r, c.g, c.b);
			SDL_SetTextureAlphaModFloat(g->tex, c.a);
			SDL_FRect dst = {x + g->left / scale, base - g->top / scale, g->w / scale, g->h / scale};
			SDL_RenderTexture(ren, g->tex, NULL, &dst);
		}
		x += g->advance;
	}
}

// ---- weather

typedef struct { char date[11]; double hi, lo; int code; } Day;
static struct {
	int ok;
	double temp, feels, humid, wind;
	int code, is_day;
	Day days[3];
	int ndays;
	char place[128];
	double lat, lon;
} W;

typedef struct { char *data; size_t len; } Buf;
static size_t on_data(char *p, size_t s, size_t n, void *u) {
	Buf *b = u;
	b->data = realloc(b->data, b->len + s * n + 1);
	memcpy(b->data + b->len, p, s * n);
	b->len += s * n;
	b->data[b->len] = 0;
	return s * n;
}

static char *http_get(const char *url) {
	CURL *c = curl_easy_init();
	Buf b = {0};
	curl_easy_setopt(c, CURLOPT_URL, url);
	curl_easy_setopt(c, CURLOPT_USERAGENT, "samaltak-weather");
	curl_easy_setopt(c, CURLOPT_TIMEOUT, 10L);
	curl_easy_setopt(c, CURLOPT_WRITEFUNCTION, on_data);
	curl_easy_setopt(c, CURLOPT_WRITEDATA, &b);
	long status = 0;
	int ok = curl_easy_perform(c) == CURLE_OK;
	curl_easy_getinfo(c, CURLINFO_RESPONSE_CODE, &status);
	curl_easy_cleanup(c);
	if (!ok || status != 200) { free(b.data); return NULL; }
	return b.data;
}

// The number after "key": in the object starting at from.
static double json_num(const char *from, const char *key, double fallback) {
	char pat[64];
	snprintf(pat, sizeof pat, "\"%s\":", key);
	const char *p = from ? strstr(from, pat) : NULL;
	return p ? strtod(p + strlen(pat), NULL) : fallback;
}

static int json_array(const char *from, const char *key, double *out, int max) {
	char pat[64];
	snprintf(pat, sizeof pat, "\"%s\":[", key);
	const char *p = from ? strstr(from, pat) : NULL;
	if (!p) return 0;
	p += strlen(pat);
	int n = 0;
	while (n < max && *p && *p != ']') {
		char *end;
		out[n++] = strtod(p, &end);
		p = end;
		while (*p == ',' || *p == ' ') p++;
	}
	return n;
}

static void read_location(void) {
	char path[512];
	snprintf(path, sizeof path, "%s/.local/state/omarchy/settings/weather.json", getenv("HOME"));
	char *t = read_file(path);
	if (!t) t = http_get("https://geo.omarchy.org/");
	if (!t) return;
	W.lat = json_num(t, "latitude", NAN);
	W.lon = json_num(t, "longitude", NAN);
	const char *n = strstr(t, "\"name\"");
	if (n && (n = strchr(n + 6, '"'))) {
		const char *e = strchr(n + 1, '"');
		snprintf(W.place, sizeof W.place, "%.*s", (int)(e - n - 1), n + 1);
		for (char *c = W.place; *c; c++) if (*c >= 'a' && *c <= 'z') *c -= 32;
	}
	free(t);
}

static int fetch(void) {
	if (isnan(W.lat)) read_location();
	if (isnan(W.lat)) return 0;
	char url[512];
	snprintf(url, sizeof url, "https://api.open-meteo.com/v1/forecast?latitude=%g&longitude=%g"
		"&daily=weather_code,temperature_2m_max,temperature_2m_min"
		"&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day"
		"&forecast_days=4&timezone=auto", W.lat, W.lon);
	char *t = http_get(url);
	if (!t) return 0;
	const char *cur = strstr(t, "\"current\":{");
	const char *daily = strstr(t, "\"daily\":{");
	if (!cur || !daily) { free(t); return 0; }
	W.temp = json_num(cur, "temperature_2m", 0);
	W.feels = json_num(cur, "apparent_temperature", 0);
	W.humid = json_num(cur, "relative_humidity_2m", 0);
	W.wind = json_num(cur, "wind_speed_10m", 0);
	W.code = (int)json_num(cur, "weather_code", 3);
	W.is_day = (int)json_num(cur, "is_day", 1);
	char today[11] = "";
	const char *tm = strstr(cur, "\"time\":\"");
	if (tm) snprintf(today, sizeof today, "%.10s", tm + 8);
	double hi[8], lo[8], code[8];
	int n = json_array(daily, "temperature_2m_max", hi, 8);
	json_array(daily, "temperature_2m_min", lo, 8);
	json_array(daily, "weather_code", code, 8);
	const char *dates = strstr(daily, "\"time\":[");
	W.ndays = 0;
	if (dates) dates += 8;
	for (int i = 0; i < n && dates && W.ndays < 3; i++) {
		dates = strchr(dates, '"'); // the date's opening quote
		if (!dates) break;
		char d[11];
		snprintf(d, sizeof d, "%.10s", dates + 1);
		dates = strchr(dates + 1, '"');
		if (!dates) break;
		dates++;
		if (strcmp(d, today) <= 0) continue;
		Day *day = &W.days[W.ndays++];
		memcpy(day->date, d, 11);
		day->hi = hi[i]; day->lo = lo[i]; day->code = (int)code[i];
	}
	free(t);
	W.ok = 1;
	return 1;
}

static const char *icon(int code, int night) {
	if (code == 0) return night ? "" : "";
	if (code == 1 || code == 2) return night ? "" : "";
	if (code == 45 || code == 48) return night ? "" : "";
	if ((code >= 51 && code <= 57) || code == 61) return "";
	if ((code >= 63 && code <= 67) || (code >= 80 && code <= 82)) return "";
	if ((code >= 71 && code <= 77) || code == 85 || code == 86) return "";
	if (code >= 95) return "";
	return "";
}

static int imperial;
static long js_round(double v) { return (long)floor(v + 0.5); }
static double temp_of(double c) { return imperial ? c * 9 / 5 + 32 : c; }

static const char *day_name(const char *date) {
	static const char *names[] = {"SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY"};
	struct tm tm = {0};
	sscanf(date, "%d-%d-%d", &tm.tm_year, &tm.tm_mon, &tm.tm_mday);
	tm.tm_year -= 1900; tm.tm_mon -= 1; tm.tm_hour = 12;
	timegm(&tm);
	return names[tm.tm_wday];
}

// ---- drawing: the card's layout (apps/Weather/WeatherCard.st)

static Font *fIcon, *fTemp, *fUnit, *fPlace, *fMarker, *fLabel, *fValue, *fDayIcon, *fDayName, *fDayTemp, *fStatus;
static const float PAD = 16, WIDTH = 490 - 4;

static Color darker(Color c, float f) { return (Color){c.r / f, c.g / f, c.b / f, c.a}; }

static float hero_height(void) {
	float l = fmaxf(line_height(fIcon), line_height(fTemp));
	float r = line_height(fPlace) + 12 + line_height(fLabel) + 5 + line_height(fValue);
	return fmaxf(l, r);
}
static float forecast_height(void) {
	return fmaxf(line_height(fDayIcon), line_height(fDayName) + 2 + line_height(fDayTemp));
}

static void draw(void) {
	Color dim = darker(fg, 1.4f), dimmer = darker(fg, 1.5f);
	SDL_SetRenderDrawColorFloat(ren, bg.r, bg.g, bg.b, 1);
	SDL_RenderClear(ren);
	if (!W.ok) {
		draw_text(fStatus, "Fetching weather…", PAD, PAD, dimmer);
		SDL_RenderPresent(ren);
		return;
	}
	char buf[64];
	float h = hero_height(), x = PAD + 16, y;
	const char *ic = icon(W.code, !W.is_day);
	draw_text(fIcon, ic, x, PAD + (h - line_height(fIcon)) / 2 + 5, fg);
	x += text_width(fIcon, ic) + 16;
	snprintf(buf, sizeof buf, "%ld", js_round(temp_of(W.temp)));
	float ty = PAD + (h - line_height(fTemp)) / 2;
	draw_text(fTemp, buf, x, ty, fg);
	x += text_width(fTemp, buf) + 2;
	draw_text(fUnit, imperial ? "°F" : "°C", x, ty + 10, fg);
	char stats[3][2][32];
	snprintf(stats[0][0], 32, "FEELS"); snprintf(stats[0][1], 32, "%ld°%s", js_round(temp_of(W.feels)), imperial ? "F" : "C");
	snprintf(stats[1][0], 32, "WIND");
	if (imperial) snprintf(stats[1][1], 32, "%ld mph", js_round(W.wind * 0.621371));
	else snprintf(stats[1][1], 32, "%ld km/h", js_round(W.wind));
	snprintf(stats[2][0], 32, "HUMID"); snprintf(stats[2][1], 32, "%ld%%", js_round(W.humid));
	float widths[3], total = 0;
	for (int i = 0; i < 3; i++) { widths[i] = fmaxf(text_width(fLabel, stats[i][0]), text_width(fValue, stats[i][1])); total += widths[i]; }
	total += 2 * 36;
	float rx = WIDTH - PAD - 20 - total;
	y = PAD + (h - (line_height(fPlace) + 12 + line_height(fLabel) + 5 + line_height(fValue))) / 2;
	draw_text(fMarker, "", rx, y, dim);
	draw_text(fPlace, W.place, rx + text_width(fMarker, "") + 6, y, dim);
	y += line_height(fPlace) + 12;
	for (int i = 0; i < 3; i++) {
		draw_text(fLabel, stats[i][0], rx, y, dimmer);
		draw_text(fValue, stats[i][1], rx, y + line_height(fLabel) + 5, fg);
		rx += widths[i] + 36;
	}
	y = PAD + h + 14;
	SDL_SetRenderDrawBlendMode(ren, SDL_BLENDMODE_BLEND);
	SDL_SetRenderDrawColorFloat(ren, fg.r, fg.g, fg.b, 0.12f);
	SDL_FRect rule = {PAD, y, WIDTH - 2 * PAD, 1};
	SDL_RenderFillRect(ren, &rule);
	y += 15;
	float fh = forecast_height(), cells[3], sum = 0;
	char hi[3][16], lo[3][16];
	for (int i = 0; i < W.ndays; i++) {
		snprintf(hi[i], 16, "%ld°", js_round(temp_of(W.days[i].hi)));
		snprintf(lo[i], 16, "%ld°", js_round(temp_of(W.days[i].lo)));
		float temps = text_width(fDayTemp, hi[i]) + 6 + text_width(fDayTemp, lo[i]);
		cells[i] = text_width(fDayIcon, icon(W.days[i].code, 0)) + 10 + fmaxf(text_width(fDayName, day_name(W.days[i].date)), temps);
		sum += cells[i];
	}
	x = PAD + (WIDTH - 2 * PAD - (sum + (W.ndays - 1) * 44)) / 2;
	for (int i = 0; i < W.ndays; i++) {
		const char *di = icon(W.days[i].code, 0);
		draw_text(fDayIcon, di, x, y + (fh - line_height(fDayIcon)) / 2, fg);
		float nx = x + text_width(fDayIcon, di) + 10;
		float ny = y + (fh - (line_height(fDayName) + 2 + line_height(fDayTemp))) / 2;
		draw_text(fDayName, day_name(W.days[i].date), nx, ny, dim);
		ny += line_height(fDayName) + 2;
		draw_text(fDayTemp, hi[i], nx, ny, fg);
		draw_text(fDayTemp, lo[i], nx + text_width(fDayTemp, hi[i]) + 6, ny, dimmer);
		x += cells[i] + 44;
	}
	SDL_RenderPresent(ren);
}

int main(void) {
	const char *lang = getenv("LC_ALL");
	if (!lang || !*lang) lang = getenv("LC_MEASUREMENT");
	if (!lang || !*lang) lang = getenv("LANG");
	imperial = lang && (!strncmp(lang, "en_US", 5) || !strncmp(lang, "en_LR", 5) || !strncmp(lang, "my", 2));
	W.lat = W.lon = NAN;
	load_theme();
	SDL_SetHint(SDL_HINT_APP_ID, "org.samaltak.weather-c");
	if (!SDL_Init(SDL_INIT_VIDEO)) { fprintf(stderr, "%s\n", SDL_GetError()); return 1; }
	FT_Init_FreeType(&ft);
	curl_global_init(CURL_GLOBAL_DEFAULT);
	char regular[512], bold[512];
	snprintf(regular, sizeof regular, "%s", fc_match("monospace"));
	snprintf(bold, sizeof bold, "%s", fc_match("monospace:bold"));
	SDL_Window *win = SDL_CreateWindow("Weather (C)", 100, 100, SDL_WINDOW_HIGH_PIXEL_DENSITY | SDL_WINDOW_HIDDEN);
	ren = SDL_CreateRenderer(win, "gpu");
	if (!ren) { fprintf(stderr, "%s\n", SDL_GetError()); return 1; }
	scale = SDL_GetWindowDisplayScale(win);
	fIcon = font_open(regular, 64, 0); fTemp = font_open(bold, 56, 0); fUnit = font_open(regular, 24, 0);
	fPlace = font_open(regular, 12, 1); fMarker = font_open(regular, 12, 0); fLabel = font_open(regular, 11, 1);
	fValue = font_open(regular, 14, 0); fDayIcon = font_open(regular, 24, 0); fDayName = font_open(regular, 10, 1);
	fDayTemp = font_open(regular, 12, 0); fStatus = font_open(regular, 11, 0);
	float height = 2 * PAD + hero_height() + 14 + 1 + 14 + forecast_height();
	SDL_SetWindowSize(win, (int)WIDTH, (int)ceilf(height));
	SDL_SetRenderScale(ren, scale, scale);
	SDL_ShowWindow(win);
	time_t next = 0;
	int dirty = 1;
	for (;;) {
		SDL_Event e;
		if (SDL_WaitEventTimeout(&e, 2000)) {
			do {
				if (e.type == SDL_EVENT_QUIT || e.type == SDL_EVENT_WINDOW_CLOSE_REQUESTED) return 0;
				if (e.type == SDL_EVENT_WINDOW_EXPOSED) dirty = 1;
				if (e.type == SDL_EVENT_MOUSE_BUTTON_DOWN && e.button.button == SDL_BUTTON_MIDDLE) next = 0;
			} while (SDL_PollEvent(&e));
		}
		if (time(NULL) >= next) {
			next = time(NULL) + (fetch() ? 15 * 60 : 60);
			dirty = 1;
		}
		if (dirty) { draw(); dirty = 0; }
	}
}
