/* Platform primitives: argument checking and oop conversion around platform.h.
 *
 * Conventions: the receiver is ignored; arguments are positional. Handles are
 * SmallIntegers. Byte buffers are ByteArray/ByteString (or Bitmap where noted);
 * `start` is 1-based. Booleans are true/false. A primitive fails on bad
 * arguments or platform errors; `platformLastError` answers the reason.
 *
 * Events: nextEvent:/injectEvent: use 8-slot Arrays
 *   [type, timeMs, x, y, buttonOrKey, modifiers, textOrDelta, windowId]
 * x, y: Floats in points (mouse position; for windowResized the new size;
 * for displayScaleChanged x = new scale). modifiers: shift 1, ctrl 2, alt 4, cmd 8.
 *   type                    buttonOrKey            textOrDelta
 *   1  mouseMove            buttons held (1 L 2 M 4 R)   nil
 *   2  mouseDown            button (1 L, 2 M, 3 R)  click count
 *   3  mouseUp              button                  click count
 *   4  wheel                0                       Point dx@dy (Floats; +y = away from user)
 *   5  keyDown              keycode                 repeat (Boolean)
 *   6  keyUp                keycode                 repeat (Boolean)
 *   7  textInput            0                       String (UTF-8 decoded)
 *   8  windowResized        0                       nil
 *   9  windowCloseRequest   10 quit   11 focusGained   12 focusLost
 *   13 displayScaleChanged  14 mouseLeave   15 windowExposed
 * timeMs: platform monotonic ms (nil when injecting = now). windowId: window handle or nil.
 *
 * Keycodes (SDL): printable keys are their lowercase character code
 * ('a' = 97 ... 'z' = 122, '0' = 48, space = 32), return 13, escape 27,
 * backspace 8, tab 9, delete 127,
 * right 16r4000004F, left 16r40000050, down 16r40000051, up 16r40000052,
 * home 16r4000004A, end 16r4000004D, pageUp 16r4000004B, pageDown 16r4000004E,
 * insert 16r40000049, F1 16r4000003A ... F12 16r40000045, keypad enter 16r40000058,
 * lshift 16r400000E1, lctrl 16r400000E0, lalt 16r400000E2, lcmd 16r400000E3. */
#include "../src/vm.h"
#include "platform.h"

#include <stdlib.h>
#include <string.h>

static bool bad;

#define ARGS(n)                     \
    bad = false;                    \
    if (prim_argc() != (n)) {       \
        prim_fail();                \
        return;                     \
    }
#define CHECK()           \
    if (bad) {            \
        prim_fail();      \
        return;           \
    }

static int64_t I(int i)
{
    int64_t v;
    if (int64_of(prim_arg(i), &v)) return v;
    bad = true;
    return 0;
}

static double F(int i)
{
    oop o = prim_arg(i);
    if (is_int(o)) return (double)int_val(o);
    if (is_float(o)) return float_val(o);
    bad = true;
    return 0;
}

static bool B(int i)
{
    oop o = prim_arg(i);
    if (o == true_oop) return true;
    if (o != false_oop) bad = true;
    return false;
}

static bool is_text(oop o)
{
    if (!is_ptr(o)) return false;
    int f = format_of(o);
    return f >= 16 || f == 10 || f == 11;
}

/* malloc'd UTF-8 of a String argument (NULL + bad otherwise) */
static char *S(int i)
{
    oop o = prim_arg(i);
    char *s = is_text(o) ? utf8_of(o) : NULL;
    if (!s) bad = true;
    return s;
}

/* raw bytes of a byte object (formats 16-23) or Bitmap (10-11) */
static uint8_t *bytes_view(oop o, size_t *n, bool writable)
{
    if (!is_ptr(o)) return NULL;
    if (writable && (vm_hdr(o) & H_IMMUTABLE)) return NULL;
    int f = format_of(o);
    if (f >= 16) {
        *n = byte_size(o);
        return bytes_of(o);
    }
    if (f == 10 || f == 11) {
        *n = word32_size(o) * 4;
        return (uint8_t *)words32_of(o);
    }
    return NULL;
}

static void ret_self(void) { prim_return(prim_receiver()); }
static void ret_bool(bool b) { b ? ret_self() : prim_fail(); }
static void ret_handle(int h) { h > 0 ? prim_return(int_oop(h)) : prim_fail(); }
static void ret_string(char *s)
{
    if (!s) {
        prim_fail();
        return;
    }
    oop r = string_from_utf8(s, strlen(s));
    free(s);
    prim_return(r);
}

static oop array_of_ints(int n, const int64_t *v)
{
    oop a = alloc_slots(special(SO_ARRAY), n);
    for (int i = 0; i < n; i++) store_ref(a, i, int_oop(v[i]));
    return a;
}

static void ret_pair(bool ok, int a, int b)
{
    if (!ok) {
        prim_fail();
        return;
    }
    int64_t v[2] = {a, b};
    prim_return(array_of_ints(2, v));
}

static void ret_float(double d) { d < 0 ? prim_fail() : prim_return(float_oop(d)); }

/* ---- window & input ------------------------------------------------------ */

void prim_windowOpen(void)
{
    ARGS(4);
    int64_t w = I(0), h = I(1), flags = I(3);
    char *t = S(2);
    if (bad) {
        free(t);
        prim_fail();
        return;
    }
    int r = pf_window_open((int)w, (int)h, t, (int)flags);
    free(t);
    ret_handle(r);
}

void prim_windowClose(void) { ARGS(1); int64_t w = I(0); CHECK(); ret_bool(pf_window_close((int)w)); }

void prim_windowSize(void)
{
    ARGS(1);
    int64_t win = I(0);
    CHECK();
    int w = 0, h = 0;
    bool ok = pf_window_size((int)win, &w, &h);
    ret_pair(ok, w, h);
}

void prim_windowPixelSize(void)
{
    ARGS(1);
    int64_t win = I(0);
    CHECK();
    int w = 0, h = 0;
    bool ok = pf_window_pixel_size((int)win, &w, &h);
    ret_pair(ok, w, h);
}

void prim_windowDisplayScale(void) { ARGS(1); int64_t w = I(0); CHECK(); ret_float(pf_window_display_scale((int)w)); }
void prim_windowRefreshRate(void) { ARGS(1); int64_t w = I(0); CHECK(); ret_float(pf_window_refresh_rate((int)w)); }

void prim_windowSetTitle(void)
{
    ARGS(2);
    int64_t w = I(0);
    char *t = S(1);
    bool ok = !bad && pf_window_set_title((int)w, t);
    free(t);
    ret_bool(ok);
}

void prim_windowShow(void) { ARGS(1); int64_t w = I(0); CHECK(); ret_bool(pf_window_show((int)w, true)); }
void prim_windowHide(void) { ARGS(1); int64_t w = I(0); CHECK(); ret_bool(pf_window_show((int)w, false)); }
void prim_setCursor(void) { ARGS(1); int64_t k = I(0); CHECK(); ret_bool(pf_set_cursor((int)k)); }
void prim_clipboardGet(void) { ARGS(0); ret_string(pf_clipboard_get()); }

void prim_clipboardSet(void)
{
    ARGS(1);
    char *s = S(0);
    bool ok = !bad && pf_clipboard_set(s);
    free(s);
    ret_bool(ok);
}

static bool is_event_array(oop a)
{
    return is_ptr(a) && format_of(a) == F_VAR && num_slots(a) >= 8 && !(vm_hdr(a) & H_IMMUTABLE);
}

void prim_nextEvent(void)
{
    ARGS(1);
    oop a = prim_arg(0);
    if (!is_event_array(a)) {
        prim_fail();
        return;
    }
    pf_event e;
    if (!pf_event_next(&e)) {
        prim_return(nil_oop);
        return;
    }
    push_root(&a);
    store_ref(a, 0, int_oop(e.type));
    store_ref(a, 1, int_oop(e.time_ms));
    oop v = float_oop(e.x);
    store_ref(a, 2, v);
    v = float_oop(e.y);
    store_ref(a, 3, v);
    store_ref(a, 4, int_oop(e.key));
    store_ref(a, 5, int_oop(e.mods));
    switch (e.xkind) {
    case PF_X_INT: v = int_oop(e.ival); break;
    case PF_X_BOOL: v = e.ival ? true_oop : false_oop; break;
    case PF_X_TEXT: v = string_from_utf8(e.text, strlen(e.text)); break;
    case PF_X_POINT: {
        oop p = alloc_slots(special(SO_POINT), 0);
        push_root(&p);
        v = float_oop(e.dx);
        store_ref(p, 0, v);
        v = float_oop(e.dy);
        store_ref(p, 1, v);
        pop_root();
        v = p;
        break;
    }
    default: v = nil_oop;
    }
    store_ref(a, 6, v);
    store_ref(a, 7, e.window ? int_oop(e.window) : nil_oop);
    pop_root();
    free(e.text);
    prim_return(a);
}

static bool num_of(oop o, double *d)
{
    if (is_int(o)) *d = (double)int_val(o);
    else if (is_float(o)) *d = float_val(o);
    else return false;
    return true;
}

void prim_injectEvent(void)
{
    ARGS(1);
    oop a = prim_arg(0);
    if (!is_ptr(a) || format_of(a) != 2 || num_slots(a) < 8) {
        prim_fail();
        return;
    }
    pf_event e = {0};
    oop o;
    bool ok = is_int(o = load_ref(a, 0)) && (e.type = (int)int_val(o)) > 0;
    o = load_ref(a, 1);
    e.time_ms = is_int(o) ? int_val(o) : pf_now_ms();
    ok = ok && num_of(load_ref(a, 2), &e.x) && num_of(load_ref(a, 3), &e.y);
    o = load_ref(a, 4);
    e.key = is_int(o) ? int_val(o) : 0;
    o = load_ref(a, 5);
    e.mods = is_int(o) ? (int)int_val(o) : 0;
    o = load_ref(a, 7);
    e.window = is_int(o) ? (int)int_val(o) : 0;
    o = load_ref(a, 6);
    if (o == nil_oop) e.xkind = PF_X_NIL;
    else if (is_int(o)) e.xkind = PF_X_INT, e.ival = int_val(o);
    else if (o == true_oop || o == false_oop) e.xkind = PF_X_BOOL, e.ival = o == true_oop;
    else if (is_ptr(o) && class_of(o) == special(SO_POINT) && num_slots(o) >= 2)
        e.xkind = PF_X_POINT, ok = ok && num_of(load_ref(o, 0), &e.dx) && num_of(load_ref(o, 1), &e.dy);
    else if (is_ptr(o) && format_of(o) == 2 && num_slots(o) == 2)
        e.xkind = PF_X_POINT, ok = ok && num_of(load_ref(o, 0), &e.dx) && num_of(load_ref(o, 1), &e.dy);
    else if (is_text(o)) e.xkind = PF_X_TEXT, ok = ok && (e.text = utf8_of(o));
    else ok = false;
    if (ok) pf_event_push(&e);
    free(e.text);
    if (!ok) {
        prim_fail();
        return;
    }
    request_interrupt_check();
    ret_self();
}

void prim_inputSemaphore(void)
{
    ARGS(1);
    int64_t i = I(0);
    CHECK();
    pf_event_set_semaphore((int)i);
    ret_self();
}

void prim_droppedEvents(void) { ARGS(0); prim_return(int64_oop(pf_event_dropped())); }

void prim_vsyncSemaphore(void) { ARGS(1); int64_t i = I(0); CHECK(); ret_bool(pf_vsync_semaphore((int)i)); }

void prim_platformLastError(void)
{
    ARGS(0);
    const char *e = pf_last_error();
    prim_return(string_from_utf8(e, strlen(e)));
}

/* ---- GPU ------------------------------------------------------------------ */

void prim_gpuCreateDevice(void) { ARGS(1); bool d = B(0); CHECK(); ret_handle(pf_gpu_create_device(d)); }

void prim_gpuClaimWindow(void)
{
    ARGS(2);
    int64_t d = I(0), w = I(1);
    CHECK();
    ret_bool(pf_gpu_claim_window((int)d, (int)w));
}

void prim_gpuSwapchainFormat(void)
{
    ARGS(2);
    int64_t d = I(0), w = I(1);
    CHECK();
    ret_handle(pf_gpu_swapchain_format((int)d, (int)w));
}

void prim_gpuCreateShader(void)
{
    ARGS(8);
    int64_t d = I(0), stage = I(3), ns = I(4), nu = I(5), nsb = I(6), nst = I(7);
    char *src = S(1), *entry = S(2);
    int h = bad ? 0 : pf_gpu_create_shader((int)d, src, entry, (int)stage, (int)ns, (int)nu, (int)nsb, (int)nst);
    free(src);
    free(entry);
    if (bad) prim_fail();
    else ret_handle(h);
}

void prim_gpuCreatePipeline(void)
{
    ARGS(8);
    int64_t d = I(0), vs = I(1), fs = I(2), stride = I(3), prim = I(5), blend = I(6), fmt = I(7);
    oop attrs = prim_arg(4);
    CHECK();
    if (!is_ptr(attrs) || format_of(attrs) != 2 || num_slots(attrs) % 2 || num_slots(attrs) > 32) {
        prim_fail();
        return;
    }
    pf_vattr va[16];
    int n = (int)num_slots(attrs) / 2;
    for (int i = 0; i < n; i++) {
        oop f = load_ref(attrs, 2 * i), off = load_ref(attrs, 2 * i + 1);
        if (!is_int(f) || !is_int(off)) {
            prim_fail();
            return;
        }
        va[i] = (pf_vattr){(int)int_val(f), (int)int_val(off)};
    }
    ret_handle(pf_gpu_create_pipeline((int)d, (int)vs, (int)fs, (int)stride, va, n, (int)prim, (int)blend, (int)fmt));
}

void prim_gpuCreateTexture(void)
{
    ARGS(5);
    int64_t d = I(0), w = I(1), h = I(2), f = I(3), u = I(4);
    CHECK();
    ret_handle(pf_gpu_create_texture((int)d, (int)w, (int)h, (int)f, (int)u));
}

void prim_gpuCreateSampler(void)
{
    ARGS(3);
    int64_t d = I(0);
    bool lin = B(1), rep = B(2);
    CHECK();
    ret_handle(pf_gpu_create_sampler((int)d, lin, rep));
}

void prim_gpuCreateBuffer(void)
{
    ARGS(3);
    int64_t d = I(0), u = I(1), n = I(2);
    CHECK();
    if (n <= 0 || n > UINT32_MAX) {
        prim_fail();
        return;
    }
    ret_handle(pf_gpu_create_buffer((int)d, (int)u, (uint32_t)n));
}

void prim_gpuRelease(void) { ARGS(1); int64_t h = I(0); CHECK(); ret_bool(pf_gpu_release((int)h)); }

void prim_gpuUploadBuffer(void)
{
    ARGS(4);
    int64_t b = I(0), n = I(2), off = I(3);
    CHECK();
    size_t len;
    uint8_t *p = bytes_view(prim_arg(1), &len, false);
    if (!p || n < 0 || (size_t)n > len || off < 0 || off > UINT32_MAX) {
        prim_fail();
        return;
    }
    ret_bool(pf_gpu_upload_buffer((int)b, p, (uint32_t)n, (uint32_t)off));
}

void prim_gpuUploadTexture(void)
{
    ARGS(7);
    int64_t t = I(0), x = I(2), y = I(3), w = I(4), h = I(5), bpr = I(6);
    CHECK();
    size_t len;
    uint8_t *p = bytes_view(prim_arg(1), &len, false);
    if (!p) {
        prim_fail();
        return;
    }
    ret_bool(pf_gpu_upload_texture((int)t, p, len, (int)x, (int)y, (int)w, (int)h, (int)bpr));
}

void prim_gpuAcquireCommandBuffer(void) { ARGS(1); int64_t d = I(0); CHECK(); ret_handle(pf_gpu_acquire_cmd((int)d)); }

void prim_gpuAcquireSwapchain(void)
{
    ARGS(2);
    int64_t c = I(0), win = I(1);
    CHECK();
    int w = 0, h = 0;
    int t = pf_gpu_acquire_swapchain((int)c, (int)win, &w, &h);
    if (!t) {
        if (*pf_last_error()) prim_fail();
        else prim_return(nil_oop);
        return;
    }
    int64_t v[3] = {t, w, h};
    prim_return(array_of_ints(3, v));
}

void prim_gpuBeginPass(void)
{
    ARGS(3);
    int64_t c = I(0), t = I(1);
    oop cl = prim_arg(2);
    CHECK();
    float rgba[4];
    double d;
    if (cl != nil_oop) {
        if (!is_ptr(cl) || format_of(cl) != 2 || num_slots(cl) != 4) {
            prim_fail();
            return;
        }
        for (int i = 0; i < 4; i++) {
            if (!num_of(load_ref(cl, i), &d)) {
                prim_fail();
                return;
            }
            rgba[i] = (float)d;
        }
    }
    ret_handle(pf_gpu_begin_pass((int)c, (int)t, cl == nil_oop ? NULL : rgba));
}

void prim_gpuSetViewport(void)
{
    ARGS(5);
    int64_t p = I(0);
    double x = F(1), y = F(2), w = F(3), h = F(4);
    CHECK();
    ret_bool(pf_gpu_set_viewport((int)p, (float)x, (float)y, (float)w, (float)h));
}

void prim_gpuSetScissor(void)
{
    ARGS(5);
    int64_t p = I(0), x = I(1), y = I(2), w = I(3), h = I(4);
    CHECK();
    ret_bool(pf_gpu_set_scissor((int)p, (int)x, (int)y, (int)w, (int)h));
}

void prim_gpuBindPipeline(void)
{
    ARGS(2);
    int64_t p = I(0), q = I(1);
    CHECK();
    ret_bool(pf_gpu_bind_pipeline((int)p, (int)q));
}

void prim_gpuBindVertexBuffer(void)
{
    ARGS(4);
    int64_t p = I(0), s = I(1), b = I(2), off = I(3);
    CHECK();
    ret_bool(pf_gpu_bind_vertex_buffer((int)p, (int)s, (int)b, (uint32_t)off));
}

void prim_gpuBindTexture(void)
{
    ARGS(4);
    int64_t p = I(0), s = I(1), t = I(2), sm = I(3);
    CHECK();
    ret_bool(pf_gpu_bind_texture((int)p, (int)s, (int)t, (int)sm));
}

void prim_gpuPushUniforms(void)
{
    ARGS(4);
    int64_t c = I(0), st = I(1), sl = I(2);
    CHECK();
    size_t len;
    uint8_t *p = bytes_view(prim_arg(3), &len, false);
    if (!p) {
        prim_fail();
        return;
    }
    ret_bool(pf_gpu_push_uniforms((int)c, (int)st, (int)sl, p, (uint32_t)len));
}

void prim_gpuDraw(void)
{
    ARGS(3);
    int64_t p = I(0), n = I(1), f = I(2);
    CHECK();
    ret_bool(pf_gpu_draw((int)p, (int)n, (int)f));
}

void prim_gpuEndPass(void) { ARGS(1); int64_t p = I(0); CHECK(); ret_bool(pf_gpu_end_pass((int)p)); }

static bool rect_of(oop r, int out[4])
{
    if (!is_ptr(r) || format_of(r) != 2 || num_slots(r) != 4) return false;
    for (int i = 0; i < 4; i++) {
        oop v = load_ref(r, i);
        if (!is_int(v)) return false;
        out[i] = (int)int_val(v);
    }
    return true;
}

void prim_gpuBlit(void)
{
    ARGS(6);
    int64_t c = I(0), s = I(1), d = I(3);
    bool lin = B(5);
    int sr[4], dr[4];
    if (bad || !rect_of(prim_arg(2), sr) || !rect_of(prim_arg(4), dr)) {
        prim_fail();
        return;
    }
    ret_bool(pf_gpu_blit((int)c, (int)s, sr, (int)d, dr, lin));
}

void prim_gpuSubmit(void)
{
    ARGS(2);
    int64_t c = I(0);
    bool want = B(1);
    CHECK();
    bool ok;
    int f = pf_gpu_submit((int)c, want, &ok);
    if (!ok) prim_fail();
    else prim_return(f ? int_oop(f) : nil_oop);
}

void prim_gpuWaitFence(void) { ARGS(1); int64_t f = I(0); CHECK(); ret_bool(pf_gpu_wait_fence((int)f)); }

void prim_gpuFenceElapsed(void)
{
    ARGS(1);
    int64_t f = I(0);
    CHECK();
    int64_t r = pf_gpu_fence_elapsed((int)f);
    if (r == -2) prim_fail();
    else prim_return(r < 0 ? nil_oop : int_oop(r));
}

void prim_gpuFenceDone(void)
{
    ARGS(1);
    int64_t f = I(0);
    CHECK();
    int r = pf_gpu_fence_done((int)f);
    if (r < 0) prim_fail();
    else prim_return(r ? true_oop : false_oop);
}

void prim_gpuDownload(void)
{
    ARGS(6);
    int64_t t = I(0), x = I(1), y = I(2), w = I(3), h = I(4);
    CHECK();
    oop buf = prim_arg(5);
    size_t len;
    uint8_t *p = bytes_view(buf, &len, true);
    if (!p || !pf_gpu_download((int)t, (int)x, (int)y, (int)w, (int)h, p, len)) {
        prim_fail();
        return;
    }
    prim_return(buf);
}

void prim_gpuTextureSize(void)
{
    ARGS(1);
    int64_t t = I(0);
    CHECK();
    int w, h, f;
    if (!pf_gpu_texture_size((int)t, &w, &h, &f)) {
        prim_fail();
        return;
    }
    int64_t v[3] = {w, h, f};
    prim_return(array_of_ints(3, v));
}

void prim_gpuWaitIdle(void) { ARGS(1); int64_t d = I(0); CHECK(); ret_bool(pf_gpu_wait_idle((int)d)); }

/* ---- files & processes ------------------------------------------------------ */

static void path_op(bool (*fn)(const char *))
{
    ARGS(1);
    char *p = S(0);
    bool ok = !bad && fn(p);
    free(p);
    ret_bool(ok);
}

void prim_fileOpen(void)
{
    ARGS(2);
    char *p = S(0);
    int64_t m = I(1);
    int h = bad ? 0 : pf_file_open(p, (int)m);
    free(p);
    ret_handle(h);
}

void prim_fileClose(void) { ARGS(1); int64_t f = I(0); CHECK(); ret_bool(pf_file_close((int)f)); }

/* (handle, buffer, start, count) with 1-based start; answers the byte range */
static uint8_t *range_args(bool writable, int64_t *h, int64_t *count)
{
    if (prim_argc() != 4) return NULL;
    bad = false;
    *h = I(0);
    int64_t start = I(2);
    *count = I(3);
    size_t len;
    uint8_t *p = bytes_view(prim_arg(1), &len, writable);
    if (bad || !p || start < 1 || *count < 0 || (uint64_t)(start - 1 + *count) > len) return NULL;
    return p + start - 1;
}

void prim_fileRead(void)
{
    int64_t h, n;
    uint8_t *p = range_args(true, &h, &n);
    int64_t r = p ? pf_file_read((int)h, p, (size_t)n) : -1;
    r < 0 ? prim_fail() : prim_return(int_oop(r));
}

void prim_fileWrite(void)
{
    int64_t h, n;
    uint8_t *p = range_args(false, &h, &n);
    int64_t r = p ? pf_file_write((int)h, p, (size_t)n) : -1;
    r < 0 ? prim_fail() : prim_return(int_oop(r));
}

void prim_fileWriteBehind(void)
{
    int64_t h, n;
    uint8_t *p = range_args(false, &h, &n);
    int64_t r = p ? pf_file_write_behind((int)h, p, (size_t)n) : -1;
    r < 0 ? prim_fail() : prim_return(int_oop(r));
}

void prim_fileSize(void)
{
    ARGS(1);
    int64_t f = I(0);
    CHECK();
    int64_t r = pf_file_size((int)f);
    r < 0 ? prim_fail() : prim_return(int64_oop(r));
}

void prim_filePosition(void)
{
    ARGS(1);
    int64_t f = I(0);
    CHECK();
    int64_t r = pf_file_position((int)f);
    r < 0 ? prim_fail() : prim_return(int64_oop(r));
}

void prim_fileSeek(void)
{
    ARGS(2);
    int64_t f = I(0), pos = I(1);
    CHECK();
    ret_bool(pos >= 0 && pf_file_seek((int)f, pos));
}

void prim_fileFlush(void) { ARGS(1); int64_t f = I(0); CHECK(); ret_bool(pf_file_flush((int)f)); }
void prim_fileDelete(void) { path_op(pf_file_delete); }
void prim_dirCreate(void) { path_op(pf_dir_create); }
void prim_mkfifo(void) { path_op(pf_mkfifo); }

void prim_fileRename(void)
{
    ARGS(2);
    char *a = S(0), *b = S(1);
    bool ok = !bad && pf_file_rename(a, b);
    free(a);
    free(b);
    ret_bool(ok);
}

void prim_fileStat(void)
{
    ARGS(1);
    char *p = S(0);
    pf_stat st;
    bool ok = !bad && pf_file_stat(p, &st);
    free(p);
    if (!ok) {
        prim_fail();
        return;
    }
    oop a = alloc_slots(special(SO_ARRAY), 4);
    push_root(&a);
    store_ref(a, 0, st.exists ? true_oop : false_oop);
    store_ref(a, 1, st.is_dir ? true_oop : false_oop);
    oop v = int64_oop(st.size);
    store_ref(a, 2, v);
    v = int64_oop(st.mtime_us);
    store_ref(a, 3, v);
    pop_root();
    prim_return(a);
}

void prim_dirEntries(void)
{
    ARGS(1);
    char *p = S(0);
    int n = 0;
    char **v = bad ? NULL : pf_dir_entries(p, &n);
    free(p);
    if (!v) {
        prim_fail();
        return;
    }
    oop a = alloc_slots(special(SO_ARRAY), n);
    push_root(&a);
    for (int i = 0; i < n; i++) {
        oop s = string_from_utf8(v[i], strlen(v[i]));
        store_ref(a, i, s);
        free(v[i]);
    }
    pop_root();
    free(v);
    prim_return(a);
}

void prim_cwd(void) { ARGS(0); ret_string(pf_cwd()); }

/* malloc'd NULL-terminated C strings of an Array of Strings (NULL: not one, or empty when nonEmpty) */
static char **string_vector(oop a, bool nonEmpty)
{
    if (!is_ptr(a) || format_of(a) != 2 || (nonEmpty && num_slots(a) == 0)) return NULL;
    uint32_t n = num_slots(a);
    char **v = calloc(n + 1, sizeof *v);
    if (!v) return NULL;
    for (uint32_t i = 0; i < n; i++) {
        oop s = load_ref(a, i);
        if (!is_text(s) || !(v[i] = utf8_of(s))) {
            for (uint32_t k = 0; k < i; k++) free(v[k]);
            free(v);
            return NULL;
        }
    }
    return v;
}

static void free_vector(char **v)
{
    for (char **p = v; v && *p; p++) free(*p);
    free(v);
}

void prim_spawnProcess(void)
{
    ARGS(1);
    char **argv = string_vector(prim_arg(0), true);
    if (!argv) {
        prim_fail();
        return;
    }
    int64_t pid = pf_spawn(argv);
    free_vector(argv);
    pid < 0 ? prim_fail() : prim_return(int_oop(pid));
}

void prim_processWait(void)
{
    ARGS(2);
    int64_t pid = I(0);
    bool block = B(1);
    CHECK();
    int st = 0;
    bool done = false;
    if (!pf_process_wait(pid, block, &st, &done)) prim_fail();
    else prim_return(done ? int_oop(st) : nil_oop);
}

/* ---- sockets ---------------------------------------------------------------- */

void prim_socketListen(void)
{
    ARGS(3);
    char *host = S(0);
    int64_t port = I(1), backlog = I(2);
    int h = bad ? 0 : pf_socket_listen(host, (int)port, (int)backlog);
    free(host);
    ret_handle(h);
}

void prim_socketConnect(void)
{
    ARGS(2);
    char *host = S(0);
    int64_t port = I(1);
    int h = bad ? 0 : pf_socket_connect(host, (int)port);
    free(host);
    ret_handle(h);
}

void prim_socketAccept(void)
{
    ARGS(1);
    int64_t s = I(0);
    CHECK();
    bool wb;
    int h = pf_socket_accept((int)s, &wb);
    if (h) prim_return(int_oop(h));
    else if (wb) prim_return(nil_oop);
    else prim_fail();
}

void prim_socketRecv(void)
{
    int64_t h, n;
    uint8_t *p = range_args(true, &h, &n);
    int64_t r = p ? pf_socket_recv((int)h, p, (size_t)n) : -2;
    if (r == -1) prim_return(nil_oop);
    else r < 0 ? prim_fail() : prim_return(int_oop(r));
}

void prim_socketSend(void)
{
    int64_t h, n;
    uint8_t *p = range_args(false, &h, &n);
    int64_t r = p ? pf_socket_send((int)h, p, (size_t)n) : -2;
    if (r == -1) prim_return(nil_oop);
    else r < 0 ? prim_fail() : prim_return(int_oop(r));
}

void prim_socketClose(void) { ARGS(1); int64_t s = I(0); CHECK(); ret_bool(pf_socket_close((int)s)); }

void prim_socketSemaphore(void)
{
    bad = false;
    int argc = prim_argc();
    if (argc != 2 && argc != 3) {
        prim_fail();
        return;
    }
    int64_t s = I(0), r = I(1), w = argc == 3 ? I(2) : 0;
    CHECK();
    ret_bool(pf_socket_semaphores((int)s, (int)r, (int)w));
}

void prim_socketLocalPort(void) { ARGS(1); int64_t s = I(0); CHECK(); ret_handle(pf_socket_local_port((int)s)); }

/* ---- pseudo-terminals ------------------------------------------------------- */

void prim_ptySpawn(void)
{
    ARGS(5);
    char **argv = string_vector(prim_arg(0), true);
    char **envp = prim_arg(1) == nil_oop ? NULL : string_vector(prim_arg(1), false);
    char *cwd = prim_arg(2) == nil_oop ? NULL : S(2);
    int64_t rows = I(3), cols = I(4), pid = 0;
    int h = 0;
    if (!bad && argv && (envp || prim_arg(1) == nil_oop) && rows > 0 && cols > 0 && rows < 65536 && cols < 65536)
        h = pf_pty_spawn(argv, envp, cwd, (int)rows, (int)cols, &pid);
    free_vector(argv);
    free_vector(envp);
    free(cwd);
    int64_t v[2] = {h, pid};
    h > 0 ? prim_return(array_of_ints(2, v)) : prim_fail();
}

void prim_ptyRead(void)
{
    int64_t h, n;
    uint8_t *p = range_args(true, &h, &n);
    int64_t r = p ? pf_pty_read((int)h, p, (size_t)n) : -2;
    if (r == -1) prim_return(nil_oop);
    else r < 0 ? prim_fail() : prim_return(int_oop(r));
}

void prim_ptyWrite(void)
{
    int64_t h, n;
    uint8_t *p = range_args(false, &h, &n);
    int64_t r = p ? pf_pty_write((int)h, p, (size_t)n) : -2;
    if (r == -1) prim_return(nil_oop);
    else r < 0 ? prim_fail() : prim_return(int_oop(r));
}

void prim_ptyResize(void)
{
    ARGS(3);
    int64_t h = I(0), rows = I(1), cols = I(2);
    CHECK();
    ret_bool(rows > 0 && cols > 0 && rows < 65536 && cols < 65536 && pf_pty_resize((int)h, (int)rows, (int)cols));
}

void prim_ptySemaphore(void)
{
    bad = false;
    int argc = prim_argc();
    if (argc != 2 && argc != 3) {
        prim_fail();
        return;
    }
    int64_t h = I(0), r = I(1), w = argc == 3 ? I(2) : 0;
    CHECK();
    ret_bool(pf_pty_semaphores((int)h, (int)r, (int)w));
}

void prim_ptyWait(void)
{
    ARGS(2);
    int64_t h = I(0);
    bool block = B(1);
    CHECK();
    int st = 0;
    bool done = false;
    if (!pf_pty_wait((int)h, block, &st, &done)) prim_fail();
    else prim_return(done ? int_oop(st) : nil_oop);
}

void prim_ptyClose(void) { ARGS(1); int64_t h = I(0); CHECK(); ret_bool(pf_pty_close((int)h)); }

void prim_platformHandleCounts(void)
{
    int64_t v[PF_HANDLE_COUNTS];
    pf_handle_counts(v);
    prim_return(array_of_ints(PF_HANDLE_COUNTS, v));
}
