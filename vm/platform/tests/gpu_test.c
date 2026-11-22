/* Standalone platform test (no VM): files, processes, sockets, events,
 * offscreen GPU rendering + readback, and presenting to a visible window. */
#include "samaltak.h"

#include <SDL3/SDL.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static int failures, checks;

/* PlatformGPU>>createShader:source:entry:stage:samplers:uniformBuffers:storageBuffers:storageTextures: (the source in the
   device's language, GLSL compiled by the host); its C name is long since createShader:spirv:size:... sits beside it. */
static int32_t create_shader(int32_t dev, const char *source, char *entry, int32_t stage, int32_t samplers,
    int32_t uniform_buffers, int32_t storage_buffers, int32_t storage_textures)
{
    return platform_gpu_create_shader_source_entry_stage_samplers_uniform_buffers_storage_buffers_storage_textures(
        dev, (void *)source, entry, stage, samplers, uniform_buffers, storage_buffers, storage_textures);
}
#define CHECK(c, ...)                                                        \
    do {                                                                     \
        checks++;                                                            \
        if (!(c)) {                                                          \
            failures++;                                                      \
            printf("FAIL %s:%d: %s -- ", __FILE__, __LINE__, #c);            \
            printf(__VA_ARGS__);                                             \
            printf(" [%s]\n", last_error_string());                              \
        }                                                                    \
    } while (0)

/* VM services */
static int signals[256], nsignals;
void signal_external_semaphore(int index) { signals[nsignals++ & 255] = index; }
void request_interrupt_check(void) {}
void request_periodic_poll(int64_t interval_us) {}
static bool signaled(int index)
{
    for (int i = 0; i < nsignals && i < 256; i++)
        if (signals[i] == index) return true;
    return false;
}

/* poll until semaphore index is signaled, at most 2 s (socket readiness is not immediate) */
static bool poll_until_signaled(int index)
{
    for (int i = 0; i < 2000 && !signaled(index); i++) {
        platform_interface_poll();
        if (!signaled(index)) usleep(1000);
    }
    return signaled(index);
}

/* recv, retrying while it would block, at most 2 s */
static int64_t recv_within(int s, void *buf, size_t n)
{
    int64_t r = -1;
    for (int i = 0; i < 2000 && (r = platform_sockets_recv(s, buf, n)) == -1; i++) usleep(1000);
    return r;
}

static double wall_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1e3 + ts.tv_nsec / 1e6;
}

/* ---- files and processes ---------------------------------------------- */

static void test_files(void)
{
    char dir[] = "/tmp/samaltak-pf-XXXXXX";
    CHECK(mkdtemp(dir) != NULL, "mkdtemp");
    char a[256], b[256], fifo[256], out[256];
    snprintf(a, sizeof a, "%s/a.txt", dir);
    snprintf(b, sizeof b, "%s/b.txt", dir);
    snprintf(fifo, sizeof fifo, "%s/fifo", dir);
    snprintf(out, sizeof out, "%s/out", dir);

    int f = platform_files_open(a, PF_FILE_CREATE_TRUNCATE);
    CHECK(f > 0, "open");
    CHECK(platform_files_write(f, "hello world", 11) == 11, "write");
    CHECK(platform_files_size(f) == 11, "size");
    CHECK(seek(f, 6), "seek");
    char buf[64] = {0};
    CHECK(platform_files_read(f, buf, 5) == 5 && !memcmp(buf, "world", 5), "read '%s'", buf);
    CHECK(position(f) == 11, "position");
    CHECK(platform_files_read(f, buf, 5) == 0, "eof");
    CHECK(platform_files_flush(f), "flush");
    CHECK(platform_files_close(f), "close");
    CHECK(!platform_files_close(f), "double close fails");

    f = platform_files_open(a, PF_FILE_APPEND);
    CHECK(platform_files_write(f, "!", 1) == 1, "append");
    platform_files_close(f);
    pf_stat st;
    CHECK(platform_files_stat(a, &st) && st.exists && !st.is_dir && st.file_size == 12 && st.mtime_us > 0, "stat file");
    CHECK(platform_files_stat(dir, &st) && st.exists && st.is_dir, "stat dir");
    CHECK(platform_files_stat(b, &st) && !st.exists, "stat missing");
    CHECK(platform_files_open(b, PF_FILE_READ) == 0, "open missing fails");
    CHECK(platform_files_rename(a, b), "rename");
    char sub[256];
    snprintf(sub, sizeof sub, "%s/sub", dir);
    CHECK(dir_create(sub), "mkdir");
    int n = 0;
    char **names = dir_entries(dir, &n);
    bool has_b = false, has_sub = false;
    for (int i = 0; i < n; i++) {
        has_b |= !strcmp(names[i], "b.txt");
        has_sub |= !strcmp(names[i], "sub");
        free(names[i]);
    }
    free(names);
    CHECK(n == 2 && has_b && has_sub, "dirEntries n=%d", n);
    char *cwd = platform_files_cwd();
    CHECK(cwd && cwd[0] == '/', "cwd");
    free(cwd);

    /* spawn + wait */
    char *sh3[] = {"sh", "-c", "exit 3", NULL};
    int64_t pid = platform_files_spawn(sh3);
    int status = -1;
    bool done = false;
    CHECK(pid > 0 && process_wait(pid, true, &status, &done) && done && status == 3, "spawn exit %d", status);
    char *sleeper[] = {"sleep", "0.2", NULL};
    pid = platform_files_spawn(sleeper);
    CHECK(process_wait(pid, false, &status, &done) && !done, "nohang wait");
    process_wait(pid, true, &status, &done);

    /* FIFO to a child process, the video-recording path */
    CHECK(platform_files_mkfifo(fifo), "mkfifo");
    char cmd[600];
    snprintf(cmd, sizeof cmd, "cat '%s' > '%s'", fifo, out);
    char *catter[] = {"sh", "-c", cmd, NULL};
    pid = platform_files_spawn(catter);
    f = platform_files_open(fifo, PF_FILE_APPEND); /* blocks until the reader opens */
    CHECK(f > 0, "open fifo");
    static uint8_t frame[1 << 20];
    for (size_t i = 0; i < sizeof frame; i++) frame[i] = (uint8_t)(i * 7);
    CHECK(platform_files_write(f, frame, sizeof frame) == (int64_t)sizeof frame, "fifo write");
    platform_files_close(f);
    process_wait(pid, true, &status, &done);
    CHECK(platform_files_stat(out, &st) && st.file_size == (int64_t)sizeof frame, "fifo output size %lld", (long long)st.file_size);

    CHECK(delete(b) && delete(fifo) && delete(out) && delete(sub) && delete(dir),
          "cleanup");
}

/* ---- sockets ------------------------------------------------------------ */

static int late_client;
static double late_sent_ms;
static void *late_send(void *arg)
{
    usleep(50000);
    late_sent_ms = wall_ms();
    platform_sockets_send(late_client, "late", 4);
    return arg;
}

static void test_wake(const char *mode, int server_side, int client)
{
    char buf[16];
    nsignals = 0;
    while (platform_sockets_recv(server_side, buf, sizeof buf) > 0) {}
    late_client = client;
    pthread_t t;
    pthread_create(&t, NULL, late_send, NULL);
    double t0 = wall_ms();
    for (int i = 0; i < 40 && !signaled(7); i++) platform_interface_wait(2000000);
    double woke = wall_ms();
    pthread_join(t, NULL);
    /* from the send: on a loaded machine the sender's wakeup can be late too */
    double dt = woke - late_sent_ms;
    CHECK(signaled(7) && dt < 1000, "%s idle wait woke %.1f ms after the socket data was sent", mode, dt);
    printf("  %s: platform_interface_wait woke on socket data %.1f ms after it was sent (at %.1f ms)\n", mode, dt, late_sent_ms - t0);
    CHECK(platform_sockets_recv(server_side, buf, sizeof buf) == 4, "recv late");
}

static int srv, conn, cli;

static void test_sockets(void)
{
    srv = platform_sockets_listen("127.0.0.1", 0, 8);
    CHECK(srv > 0, "listen");
    int port = local_port(srv);
    CHECK(port > 0, "port");
    bool wb;
    CHECK(platform_sockets_accept(srv, &wb) == 0 && wb, "accept would block");
    platform_sockets_semaphores_read_write(srv, 3, 0);
    cli = platform_sockets_connect("127.0.0.1", port);
    CHECK(cli > 0, "connect");
    nsignals = 0;
    CHECK(poll_until_signaled(3), "listen semaphore signaled");
    conn = platform_sockets_accept(srv, &wb);
    CHECK(conn > 0, "accept");
    char buf[64];
    CHECK(platform_sockets_recv(conn, buf, sizeof buf) == -1, "recv would block");
    platform_sockets_semaphores_read_write(conn, 7, 8);
    nsignals = 0;
    platform_interface_poll();
    CHECK(!signaled(7), "no data, no signal");
    CHECK(platform_sockets_send(cli, "ping", 4) == 4, "send");
    CHECK(poll_until_signaled(7), "read semaphore signaled");
    nsignals = 0;
    platform_interface_poll();
    CHECK(!signaled(7), "signaled once until re-armed");
    CHECK(platform_sockets_recv(conn, buf, sizeof buf) == 4 && !memcmp(buf, "ping", 4), "recv");
    CHECK(platform_sockets_send(conn, "pong!", 5) == 5, "send back");
    CHECK(recv_within(cli, buf, sizeof buf) == 5 && !memcmp(buf, "pong!", 5), "recv back");
    test_wake("headless", conn, cli);
}

static void test_sockets_close(void)
{
    char buf[8];
    platform_sockets_close(cli);
    CHECK(recv_within(conn, buf, sizeof buf) == 0, "EOF after peer close");
    CHECK(platform_sockets_close(conn) && platform_sockets_close(srv), "close");
}

/* ---- events -------------------------------------------------------------- */

static void test_events(int win)
{
    pf_event e = {0}, got;
    while (platform_events_next(&got)) free(got.text);
    set_semaphore(5);
    nsignals = 0;
    e = (pf_event){.type = PF_EV_MOUSE_DOWN, .time_ms = 42, .x = 10.5, .y = 20.25, .key = 1, .mods = PF_MOD_SHIFT,
                   .xkind = PF_X_INT, .ival = 2, .window = win};
    platform_events_push(&e);
    e = (pf_event){.type = PF_EV_TEXT_INPUT, .xkind = PF_X_TEXT, .text = "héllo", .window = win};
    platform_events_push(&e);
    platform_interface_poll();
    CHECK(signaled(5), "input semaphore signaled");
    while (platform_events_next(&got) && got.type != PF_EV_MOUSE_DOWN) free(got.text); /* skip OS window events */
    CHECK(got.type == PF_EV_MOUSE_DOWN && got.x == 10.5 && got.y == 20.25 && got.key == 1 &&
              got.mods == PF_MOD_SHIFT && got.ival == 2 && got.window == win && got.time_ms == 42,
          "mouse round trip");
    CHECK(platform_events_next(&got) && got.type == PF_EV_TEXT_INPUT && !strcmp(got.text, "héllo"), "text round trip");
    free(got.text);
    bool extra = false;
    while (platform_events_next(&got)) extra |= got.type == PF_EV_MOUSE_DOWN || got.type == PF_EV_TEXT_INPUT, free(got.text);
    CHECK(!extra, "no duplicates");

    /* OS events take the same path: push raw SDL events and let the poll translate them */
    SDL_Event se = {0};
    se.type = SDL_EVENT_KEY_DOWN;
    se.key.windowID = SDL_GetWindowID(sdl_window(win));
    se.key.key = SDLK_LEFT;
    se.key.mod = SDL_KMOD_LGUI | SDL_KMOD_LALT;
    se.key.down = true;
    SDL_PushEvent(&se);
    memset(&se, 0, sizeof se);
    se.type = SDL_EVENT_MOUSE_WHEEL;
    se.wheel.windowID = SDL_GetWindowID(sdl_window(win));
    se.wheel.y = -3;
    se.wheel.mouse_x = 5;
    se.wheel.mouse_y = 6;
    SDL_PushEvent(&se);
    nsignals = 0;
    platform_interface_wait(100000);
    CHECK(signaled(5), "semaphore signaled for SDL events");
    bool key = false, wheel = false;
    while (platform_events_next(&got)) {
        if (got.type == PF_EV_KEY_DOWN)
            key = got.key == SDLK_LEFT && got.mods == (PF_MOD_CMD | PF_MOD_ALT) && got.window == win;
        if (got.type == PF_EV_WHEEL) wheel = got.dy == -3 && got.x == 5 && got.y == 6 && got.xkind == PF_X_POINT;
        free(got.text);
    }
    CHECK(key, "SDL key event translated");
    CHECK(wheel, "SDL wheel event translated");
    set_semaphore(0);
}

/* Events of a window that closed before they were pumped are dropped: as events of no window they would reach the
 * next World, a display scale change with the closed window's scale -1. */
static void test_closed_window_events(void)
{
    pf_event got;
    while (platform_events_next(&got)) free(got.text);
    int win = platform_windows_open(400, 300, "closed", PF_WIN_HIDDEN | PF_WIN_HIGH_DENSITY);
    CHECK(win > 0, "window");
    CHECK(platform_windows_close(win), "close window");
    pump();
    int orphans = 0;
    while (platform_events_next(&got)) orphans += got.window == 0 && got.type == PF_EV_DISPLAY_SCALE_CHANGED, free(got.text);
    CHECK(orphans == 0, "%d display scale events of a closed window", orphans);
}

/* ---- GPU ----------------------------------------------------------------- */

static const char *msl =
    "#include <metal_stdlib>\n"
    "using namespace metal;\n"
    "struct VIn { float2 pos [[attribute(0)]]; float2 uv [[attribute(1)]]; float4 color [[attribute(2)]]; };\n"
    "struct VOut { float4 pos [[position]]; float2 uv; float4 color; };\n"
    "struct U { float2 viewport; };\n"
    "vertex VOut vmain(VIn in [[stage_in]], constant U &u [[buffer(0)]]) {\n"
    "  VOut o; float2 p = in.pos / u.viewport * 2.0 - 1.0;\n"
    "  o.pos = float4(p.x, -p.y, 0.0, 1.0); o.uv = in.uv; o.color = in.color; return o; }\n"
    "fragment float4 fmain(VOut in [[stage_in]], texture2d<float> atlas [[texture(0)]], sampler s [[sampler(0)]]) {\n"
    "  return in.color * atlas.sample(s, in.uv).r; }\n";

/* The same in GLSL (Vulkan): one source, the stage chosen by SAMALTAK_VERTEX / SAMALTAK_FRAGMENT, the entry main. */
static const char *glsl =
    "#version 450\n"
    "#ifdef SAMALTAK_VERTEX\n"
    "layout(location = 0) in vec2 pos; layout(location = 1) in vec2 uv; layout(location = 2) in vec4 color;\n"
    "layout(location = 0) out vec2 vUv; layout(location = 1) out vec4 vColor;\n"
    "layout(set = 1, binding = 0) uniform U { vec2 viewport; } u;\n"
    "void main() { vec2 p = pos / u.viewport * 2.0 - 1.0;\n"
    "  gl_Position = vec4(p.x, -p.y, 0.0, 1.0); vUv = uv; vColor = color; }\n"
    "#else\n"
    "layout(location = 0) in vec2 vUv; layout(location = 1) in vec4 vColor;\n"
    "layout(location = 0) out vec4 fragColor;\n"
    "layout(set = 2, binding = 0) uniform sampler2D atlas;\n"
    "void main() { fragColor = vColor * texture(atlas, vUv).r; }\n"
    "#endif\n";

typedef struct {
    float x, y, u, v;
    uint8_t r, g, b, a;
} vtx;

static int quad(vtx *v, float x0, float y0, float x1, float y1, float u, float vv, uint8_t r, uint8_t g, uint8_t b,
                uint8_t a)
{
    vtx c[4] = {{x0, y0, u, vv, r, g, b, a}, {x1, y0, u, vv, r, g, b, a}, {x0, y1, u, vv, r, g, b, a}, {x1, y1, u, vv, r, g, b, a}};
    v[0] = c[0], v[1] = c[1], v[2] = c[2], v[3] = c[1], v[4] = c[3], v[5] = c[2];
    return 6;
}

static pf_vattr layout[] = {{PF_VA_FLOAT2, 0}, {PF_VA_FLOAT2, 8}, {PF_VA_UBYTE4_NORM, 16}};

static bool near(const uint8_t *p, int r, int g, int b, int a)
{
    return abs(p[0] - r) <= 2 && abs(p[1] - g) <= 2 && abs(p[2] - b) <= 2 && abs(p[3] - a) <= 2;
}

static void check_px(const uint8_t *img, int w, int x, int y, int r, int g, int b, int a, const char *what)
{
    const uint8_t *p = img + ((size_t)y * w + x) * 4;
    CHECK(near(p, r, g, b, a), "%s at (%d,%d): got %d,%d,%d,%d want %d,%d,%d,%d", what, x, y, p[0], p[1], p[2], p[3], r,
          g, b, a);
}

static int dev, vs, fs, pipe_rgba, atlas, nearest, vbuf;

static int scene(vtx *v)
{
    int n = 0;
    n += quad(v + n, 100, 100, 500, 400, 0.25f, 0.5f, 255, 0, 0, 255);    /* red */
    n += quad(v + n, 600, 100, 1000, 400, 0.25f, 0.5f, 0, 255, 0, 255);   /* green */
    n += quad(v + n, 400, 300, 700, 600, 0.25f, 0.5f, 0, 0, 128, 128);    /* premultiplied half blue */
    n += quad(v + n, 1200, 100, 1600, 400, 0.75f, 0.5f, 255, 255, 255, 255); /* atlas value 128 */
    n += quad(v + n, 2001, 1000, 2880, 1800, 0.25f, 0.5f, 255, 255, 0, 255); /* yellow corner */
    return n;
}

static void render(int target, int tw, int th, int nverts)
{
    int cmd = acquire_command_buffer(dev);
    float clear[4] = {0, 0, 0, 1};
    int pass = begin_pass(cmd, target, clear);
    CHECK(pass > 0, "begin pass");
    bind_pipeline(pass, pipe_rgba);
    bind_vertex_buffer(pass, 0, vbuf, 0);
    bind_texture(pass, 0, atlas, nearest);
    float u[4] = {(float)tw, (float)th, 0, 0};
    push_uniforms(pass, PF_STAGE_VERTEX, 0, u, sizeof u);
    draw(pass, nverts, 0);
    CHECK(end_pass(pass), "end pass");
    bool ok;
    int fence = submit(cmd, true, &ok);
    CHECK(ok && fence > 0, "submit");
    CHECK(wait_fence(fence), "wait fence");
    CHECK(fence_done(fence) == 1, "fence done");
    release_handle(fence);
}

static void test_gpu(void)
{
    int win = platform_windows_open(1440, 900, "hidden", PF_WIN_HIDDEN | PF_WIN_HIGH_DENSITY);
    CHECK(win > 0, "hidden window");
    int w, h, pw, ph;
    CHECK(platform_windows_size(win, &w, &h) && w == 1440 && h == 900, "size %dx%d", w, h);
    CHECK(pixel_size(win, &pw, &ph), "pixel size");
    double scale = display_scale(win);
    printf("  hidden window: %dx%d points, %dx%d pixels, display scale %.2f, refresh %.0f Hz\n", w, h, pw, ph, scale,
           refresh_rate(win));
    test_events(win);

    dev = create_device(true);
    CHECK(dev > 0, "device");
    CHECK(claim_window(dev, win), "claim hidden");
    int cmd = acquire_command_buffer(dev);
    int sw, sh;
    CHECK(acquire_swapchain(cmd, win, &sw, &sh) == 0 && !*last_error_string(), "hidden window: no swapchain");
    bool ok;
    submit(cmd, false, &ok);

    const char *language = shader_language(dev);
    CHECK(language && (strcmp(language, "msl") == 0 || strcmp(language, "glsl") == 0), "shader language");
    bool metal = language && strcmp(language, "msl") == 0;
    printf("  shader language: %s\n", language ? language : "?");
    vs = create_shader(dev, metal ? msl : glsl, metal ? "vmain" : "main", PF_STAGE_VERTEX, 0, 1, 0, 0);
    fs = create_shader(dev, metal ? msl : glsl, metal ? "fmain" : "main", PF_STAGE_FRAGMENT, 1, 0, 0, 0);
    CHECK(vs > 0 && fs > 0, "shaders");
    CHECK(create_shader(dev, "garbage", "main0", PF_STAGE_VERTEX, 0, 0, 0, 0) == 0 &&
              strstr(last_error_string(), metal ? "unknown type name" : "syntax error"),
          "bad shader reports compile error");
    pipe_rgba = create_pipeline(dev, vs, fs, sizeof(vtx), layout, 3, PF_PRIM_TRIANGLES, PF_BLEND_PREMULTIPLIED,
                                       PF_TEX_RGBA8);
    CHECK(pipe_rgba > 0, "pipeline");

    /* R8 atlas: left half 255, right half 128 */
    atlas = create_texture(dev, 256, 256, PF_TEX_R8, PF_TEXUSE_SAMPLER);
    static uint8_t at[256 * 256];
    for (int y = 0; y < 256; y++)
        for (int x = 0; x < 256; x++) at[y * 256 + x] = x < 128 ? 255 : 128;
    CHECK(upload_texture(atlas, at, sizeof at, 0, 0, 256, 256, 256), "atlas upload");
    nearest = create_sampler(dev, false, false);
    vbuf = create_buffer(dev, PF_BUFUSE_VERTEX, 64 * sizeof(vtx));
    vtx v[64];
    int nv = scene(v);
    CHECK(upload_buffer(vbuf, v, nv * sizeof(vtx), 0), "vertex upload");

    const int FW = 2880, FH = 1800;
    int target = create_texture(dev, FW, FH, PF_TEX_RGBA8, PF_TEXUSE_COLOR_TARGET | PF_TEXUSE_SAMPLER);
    int half = create_texture(dev, FW / 2, FH / 2, PF_TEX_RGBA8, PF_TEXUSE_COLOR_TARGET | PF_TEXUSE_SAMPLER);
    CHECK(target > 0 && half > 0, "targets");
    int tw, th, tf;
    CHECK(texture_size(target, &tw, &th, &tf) && tw == FW && th == FH && tf == PF_TEX_RGBA8, "texture size");

    size_t bytes = (size_t)FW * FH * 4;
    uint8_t *img = malloc(bytes), *img2 = malloc(bytes);
    double t_render = 1e9, t_down = 1e9, t_up = 1e9;
    for (int iter = 0; iter < 5; iter++) {
        double t0 = wall_ms();
        upload_buffer(vbuf, v, nv * sizeof(vtx), 0);
        render(target, FW, FH, nv);
        double t1 = wall_ms();
        CHECK(download(target, 0, 0, FW, FH, img, bytes), "download");
        double t2 = wall_ms();
        if (t1 - t0 < t_render) t_render = t1 - t0;
        if (t2 - t1 < t_down) t_down = t2 - t1;
    }
    check_px(img, FW, 10, 10, 0, 0, 0, 255, "clear");
    check_px(img, FW, 200, 200, 255, 0, 0, 255, "red");
    check_px(img, FW, 800, 200, 0, 255, 0, 255, "green");
    check_px(img, FW, 450, 350, 127, 0, 128, 255, "blue over red");
    check_px(img, FW, 600, 500, 0, 0, 128, 255, "blue over black");
    check_px(img, FW, 1400, 200, 128, 128, 128, 255, "atlas 128");
    check_px(img, FW, FW - 1, FH - 1, 255, 255, 0, 255, "yellow corner");
    check_px(img, FW, 2000, 1000, 0, 0, 0, 255, "edge outside");
    check_px(img, FW, 2001, 1000, 255, 255, 0, 255, "edge inside");

    /* downsample */
    cmd = acquire_command_buffer(dev);
    int sr[4] = {0, 0, FW, FH}, dr[4] = {0, 0, FW / 2, FH / 2};
    CHECK(blit(cmd, target, sr, half, dr, true), "blit");
    submit(cmd, false, &ok);
    CHECK(download(half, 0, 0, FW / 2, FH / 2, img2, bytes), "download half");
    check_px(img2, FW / 2, 100, 100, 255, 0, 0, 255, "half red");
    check_px(img2, FW / 2, 400, 100, 0, 255, 0, 255, "half green");
    check_px(img2, FW / 2, 1300, 800, 255, 255, 0, 255, "half yellow");
    /* half pixel 1000 covers full pixels 2000 (black) and 2001 (yellow) */
    const uint8_t *e = img2 + ((size_t)600 * (FW / 2) + 1000) * 4;
    CHECK(e[0] < 250 && e[0] > 5, "linear edge %d", e[0]);
    CHECK(download(target, 100, 100, 8, 4, img2, bytes) && near(img2, 255, 0, 0, 255), "sub-region download");

    /* full-frame upload round trip */
    int up = create_texture(dev, FW, FH, PF_TEX_RGBA8, PF_TEXUSE_SAMPLER);
    for (size_t i = 0; i < bytes; i++) img[i] = (uint8_t)(i * 31 + (i >> 12));
    for (int iter = 0; iter < 5; iter++) {
        double t0 = wall_ms();
        upload_texture(up, img, bytes, 0, 0, FW, FH, FW * 4);
        wait_idle(dev);
        double dt = wall_ms() - t0;
        if (dt < t_up) t_up = dt;
    }
    memset(img2, 0, bytes);
    CHECK(download(up, 0, 0, FW, FH, img2, bytes) && !memcmp(img, img2, bytes), "upload/download round trip");
    /* partial upload with stride */
    CHECK(upload_texture(up, img, bytes, 10, 20, 3, 2, FW * 4), "partial upload");
    CHECK(download(up, 10, 20, 3, 2, img2, bytes) && !memcmp(img2, img, 12) && !memcmp(img2 + 12, img + FW * 4, 12),
          "partial upload content");

    /* BGRA target downloads as RGBA */
    int bg = create_texture(dev, 64, 64, PF_TEX_BGRA8, PF_TEXUSE_COLOR_TARGET | PF_TEXUSE_SAMPLER);
    cmd = acquire_command_buffer(dev);
    float c2[4] = {1, 0.5f, 0, 1};
    int p2 = begin_pass(cmd, bg, c2);
    end_pass(p2);
    submit(cmd, false, &ok);
    CHECK(download(bg, 0, 0, 64, 64, img2, bytes) && near(img2, 255, 128, 0, 255), "bgra download %d,%d,%d",
          img2[0], img2[1], img2[2]);

    printf("  2880x1800 RGBA8: upload %.2f ms, render %.2f ms, download %.2f ms (best of 5)\n", t_up, t_render, t_down);
    free(img);
    free(img2);
    release_handle(up);
    release_handle(bg);
    release_handle(half);
    release_handle(target);
    CHECK(platform_windows_close(win), "close hidden window");
}

static void test_present(void)
{
    int win = platform_windows_open(800, 500, "Samaltak platform test", PF_WIN_HIGH_DENSITY | PF_WIN_RESIZABLE);
    CHECK(win > 0, "visible window");
    CHECK(claim_window(dev, win), "claim");
    int fmt = swapchain_format(dev, win);
    CHECK(fmt == PF_TEX_BGRA8 || fmt == PF_TEX_RGBA8, "swapchain format %d", fmt);
    int pipe = create_pipeline(dev, vs, fs, sizeof(vtx), layout, 3, PF_PRIM_TRIANGLES, PF_BLEND_PREMULTIPLIED, fmt);
    CHECK(pipe > 0, "swapchain pipeline");
    CHECK(semaphore(9), "vsync semaphore");
    double hz = refresh_rate(win);
    int divisor = getenv("PF_VSYNC_DIV") ? atoi(getenv("PF_VSYNC_DIV")) : hz > 90 ? 2 : 1;
    int presented = 0, skipped = 0, slow_acq = 0;
    double worst = 0, worst_acq = 0, t_start = wall_ms();
    while (wall_ms() - t_start < 1500) {
        double t0 = wall_ms();
        platform_interface_poll();
        pf_event e;
        while (platform_events_next(&e)) free(e.text);
        int cmd = acquire_command_buffer(dev);
        int w, h;
        double ta = wall_ms();
        int sc = acquire_swapchain(cmd, win, &w, &h);
        ta = wall_ms() - ta;
        if (ta > worst_acq && presented > 3) worst_acq = ta;
        if (ta > 1) slow_acq++;
        CHECK(sc || !*last_error_string(), "acquire swapchain");
        if (sc) {
            float t = (float)(wall_ms() - t_start) / 1500.0f;
            float clear[4] = {t, 0.2f, 1 - t, 1};
            int pass = begin_pass(cmd, sc, clear);
            vtx v[6];
            float x = 100 + t * (w - 400);
            quad(v, x, 200, x + 200, 600, 0.25f, 0.5f, 255, 255, 255, 255);
            upload_buffer(vbuf, v, sizeof v, 0);
            bind_pipeline(pass, pipe);
            bind_vertex_buffer(pass, 0, vbuf, 0);
            bind_texture(pass, 0, atlas, nearest);
            float u[4] = {(float)w, (float)h, 0, 0};
            push_uniforms(pass, PF_STAGE_VERTEX, 0, u, sizeof u);
            draw(pass, 6, 0);
            end_pass(pass);
            presented++;
        } else skipped++;
        bool ok;
        submit(cmd, false, &ok);
        CHECK(ok, "submit present");
        double dt = wall_ms() - t0;
        if (dt > worst && presented > 3) worst = dt;
        /* pace by the vsync semaphore, as the compositor will */
        for (int k = 0; k < divisor; k++) {
            nsignals = 0;
            for (int i = 0; i < 50 && !signaled(9); i++) platform_interface_wait(100000);
        }
    }
    semaphore(0);
    printf("  visible window, every %d. vsync of %.0f Hz: %d frames in 1.5 s, %d acquires answered nil, %d acquires > 1 ms, worst "
           "frame %.2f ms (acquire %.2f ms)\n",
           divisor, hz, presented, skipped, slow_acq, worst, worst_acq);
    CHECK(presented > 50, "presented %d", presented);
    CHECK(release_handle(pipe), "release pipeline");
    test_wake("with SDL video", conn, cli);
    CHECK(platform_windows_close(win), "close window");
}

int main(int argc, char **argv)
{
    platform_interface_init();
    printf("files\n");
    test_files();
    printf("sockets\n");
    test_sockets();
    printf("gpu (offscreen) and events\n");
    test_gpu();
    test_closed_window_events();
    printf("present\n");
    test_present();
    test_sockets_close();
    release_handle(dev);
    platform_interface_shutdown();
    printf("%d/%d checks passed\n", checks - failures, checks);
    return failures ? 1 : 0;
}
