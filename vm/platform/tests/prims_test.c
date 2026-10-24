/* Primitive-level test of prims_platform.c against a tiny mock of vm.h
 * (malloc'd objects, no GC), so argument handling is checked without the VM. */
#include "../../src/vm.h"
#include "../platform.h"

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* ---- mock VM ------------------------------------------------------------- */
char *vm_young_lo, *vm_young_hi;
void vm_remember(oop o) {}
oop nil_oop, true_oop, false_oop;
bool vm_headless = true;
int vm_argc;
char **vm_argv;

static oop classes[SO_COUNT];
static oop mk(oop cls, int fmt, uint32_t nslots)
{
    uint64_t *p = calloc(2 + nslots, 8);
    p[0] = nslots | ((uint64_t)fmt << H_FMT_SHIFT);
    p[1] = cls;
    if (fmt >= F_FIXED && fmt <= F_WEAK)
        for (uint32_t i = 0; i < nslots; i++) p[2 + i] = nil_oop;
    return (oop)p;
}
oop special(int i) { return classes[i]; }
oop class_of(oop o)
{
    if (is_int(o)) return classes[SO_SMALLINTEGER];
    if (is_char(o)) return classes[SO_CHARACTER];
    return ((oop *)o)[1];
}
bool is_float(oop o) { return is_ptr(o) && class_of(o) == classes[SO_BOXEDFLOAT]; }
double float_val(oop o) { return *(double *)(o + 16); }
oop float_oop(double d)
{
    oop o = mk(classes[SO_BOXEDFLOAT], F_W64, 1);
    *(double *)(o + 16) = d;
    return o;
}
uint8_t *bytes_of(oop o) { return (uint8_t *)(o + 16); }
size_t byte_size(oop o) { return format_of(o) >= F_BYTES ? num_slots(o) * 8 - (format_of(o) - F_BYTES) : num_slots(o) * 8; }
uint32_t *words32_of(oop o) { return (uint32_t *)(o + 16); }
size_t word32_size(oop o) { return num_slots(o) * 2 - (format_of(o) - F_W32); }
oop alloc_slots(oop cls, uint32_t n) { return cls == classes[SO_POINT] ? mk(cls, F_FIXED, 2) : mk(cls, F_VAR, n); }
oop alloc_bytes(oop cls, size_t n)
{
    uint32_t slots = (uint32_t)((n + 7) / 8);
    return mk(cls, F_BYTES + (int)(slots * 8 - n), slots);
}
oop alloc_words32(oop cls, size_t n)
{
    uint32_t slots = (uint32_t)((n + 1) / 2);
    return mk(cls, F_W32 + (int)(slots * 2 - n), slots);
}
oop string_from_utf8(const char *s, size_t n)
{
    oop o = alloc_bytes(classes[SO_BYTESTRING], n);
    memcpy(bytes_of(o), s, n);
    return o;
}
char *utf8_of(oop s)
{
    size_t n = byte_size(s);
    char *r = malloc(n + 1);
    memcpy(r, bytes_of(s), n);
    r[n] = 0;
    return r;
}
oop int64_oop(int64_t v) { return int_oop(v); }
bool int64_of(oop o, int64_t *out)
{
    if (!is_int(o)) return false;
    *out = int_val(o);
    return true;
}
void push_root(oop *p) {}
void pop_root(void) {}

static oop args[16], result;
static int argc;
static bool failed;
int prim_argc(void) { return argc; }
oop prim_receiver(void) { return nil_oop; }
oop prim_arg(int i) { return args[i]; }
void prim_return(oop v) { result = v; }
void prim_fail(void) { failed = true; }
void prim_fail_code(int c) { failed = true; }
bool prim_failed(void) { return failed; }
static int signals[64], nsignals;
void signal_external_semaphore(int i) { signals[nsignals++ & 63] = i; }
void request_interrupt_check(void) {}
void request_periodic_poll(int64_t interval_us) {}

/* ---- helpers --------------------------------------------------------------- */
#define PRIM(n, name, fn) void fn(void);
#include "../prims_platform.def"
#undef PRIM

static int failures, checks;
#define CHECK(c, ...)                                                          \
    do {                                                                       \
        checks++;                                                              \
        if (!(c)) {                                                            \
            failures++;                                                        \
            printf("FAIL %s:%d: %s -- ", __FILE__, __LINE__, #c);              \
            printf(__VA_ARGS__);                                               \
            printf(" [%s]\n", pf_last_error());                                \
        }                                                                      \
    } while (0)

static oop call(void (*fn)(void), int n, ...)
{
    va_list ap;
    va_start(ap, n);
    for (int i = 0; i < n; i++) args[i] = va_arg(ap, oop);
    va_end(ap);
    argc = n;
    failed = false;
    result = 0;
    fn();
    return failed ? 0 : result;
}
#define I(v) int_oop(v)
static oop str(const char *s) { return string_from_utf8(s, strlen(s)); }
static oop bytes(size_t n) { return alloc_bytes(classes[SO_BYTEARRAY], n); }
static oop array(int n, ...)
{
    oop a = alloc_slots(classes[SO_ARRAY], n);
    va_list ap;
    va_start(ap, n);
    for (int i = 0; i < n; i++) store_ref(a, i, va_arg(ap, oop));
    va_end(ap);
    return a;
}
static int64_t ival(oop o) { return is_int(o) ? int_val(o) : -999; }

int main(void)
{
    nil_oop = mk(0, F_EMPTY, 0);
    true_oop = mk(0, F_EMPTY, 0);
    false_oop = mk(0, F_EMPTY, 0);
    for (int i = 0; i < SO_COUNT; i++) classes[i] = mk(0, F_FIXED, 3);

    /* events */
    oop buf = alloc_slots(classes[SO_ARRAY], 8);
    CHECK(call(prim_nextEvent, 1, buf) == nil_oop, "empty queue answers nil");
    CHECK(call(prim_inputSemaphore, 1, I(4)), "inputSemaphore");
    oop pt = alloc_slots(classes[SO_POINT], 0);
    store_ref(pt, 0, float_oop(1.5));
    store_ref(pt, 1, I(-2));
    CHECK(call(prim_injectEvent, 1, array(8, I(4), nil_oop, float_oop(3.25), I(7), nil_oop, I(9), pt, I(2))), "inject");
    CHECK(call(prim_injectEvent, 1, array(8, I(7), I(5), I(0), I(0), I(0), I(0), str("hi"), nil_oop)), "inject text");
    CHECK(!call(prim_injectEvent, 1, array(8, str("x"), I(5), I(0), I(0), I(0), I(0), nil_oop, nil_oop)), "bad type fails");
    CHECK(!call(prim_injectEvent, 1, array(3, I(1), I(5), I(0))), "short array fails");
    nsignals = 0;
    platform_poll();
    CHECK(nsignals == 1 && signals[0] == 4, "semaphore signaled");
    oop e = call(prim_nextEvent, 1, buf);
    CHECK(e == buf && ival(load_ref(e, 0)) == 4 && float_val(load_ref(e, 2)) == 3.25 && float_val(load_ref(e, 3)) == 7 &&
              ival(load_ref(e, 4)) == 0 && ival(load_ref(e, 5)) == 9 && ival(load_ref(e, 7)) == 2 && ival(load_ref(e, 1)) >= 0,
          "wheel event");
    oop d = load_ref(e, 6);
    CHECK(class_of(d) == classes[SO_POINT] && float_val(load_ref(d, 0)) == 1.5 && float_val(load_ref(d, 1)) == -2, "wheel delta");
    e = call(prim_nextEvent, 1, buf);
    CHECK(e && ival(load_ref(e, 0)) == 7 && ival(load_ref(e, 1)) == 5 && byte_size(load_ref(e, 6)) == 2 &&
              !memcmp(bytes_of(load_ref(e, 6)), "hi", 2) && load_ref(e, 7) == nil_oop,
          "text event");
    CHECK(call(prim_nextEvent, 1, buf) == nil_oop, "drained");
    int64_t dropped = ival(call(prim_droppedEvents, 0));
    for (int i = 0; i < PF_EVENT_QUEUE_MAX + 5; i++)
        call(prim_injectEvent, 1, array(8, I(1), I(i), I(0), I(0), I(0), I(0), str("t"), nil_oop));
    CHECK(ival(call(prim_droppedEvents, 0)) == dropped + 5, "overflow drops %lld", (long long)ival(call(prim_droppedEvents, 0)) - dropped);
    int queued = 0;
    while ((e = call(prim_nextEvent, 1, buf)) && e != nil_oop && ival(load_ref(e, 1)) == queued) queued++;
    CHECK(queued == PF_EVENT_QUEUE_MAX && e == nil_oop, "queue kept the first %d events", queued);
    CHECK(call(prim_injectEvent, 1, array(8, I(1), I(5), I(0), I(0), I(0), I(0), nil_oop, nil_oop)) &&
              ival(load_ref(call(prim_nextEvent, 1, buf), 1)) == 5 && ival(call(prim_droppedEvents, 0)) == dropped + 5,
          "queue usable after overflow");
    CHECK(!call(prim_nextEvent, 1, alloc_slots(classes[SO_ARRAY], 4)), "short buffer fails");

    /* files */
    char path[] = "/tmp/samaltak-prims-XXXXXX";
    close(mkstemp(path));
    oop f = call(prim_fileOpen, 2, str(path), I(3));
    CHECK(f && is_int(f), "fileOpen");
    CHECK(ival(call(prim_fileWrite, 4, f, str("abcdef"), I(2), I(4))) == 4, "fileWrite start 2");
    CHECK(ival(call(prim_fileSize, 1, f)) == 4, "fileSize");
    CHECK(call(prim_fileSeek, 2, f, I(1)), "fileSeek");
    oop b = bytes(10);
    CHECK(ival(call(prim_fileRead, 4, f, b, I(5), I(6))) == 3 && !memcmp(bytes_of(b) + 4, "cde", 3), "fileRead");
    CHECK(!call(prim_fileRead, 4, f, b, I(5), I(7)), "fileRead out of bounds fails");
    CHECK(!call(prim_fileRead, 4, f, b, I(0), I(1)), "fileRead start 0 fails");
    CHECK(ival(call(prim_filePosition, 1, f)) == 4, "filePosition");
    CHECK(call(prim_fileClose, 1, f), "fileClose");
    oop st = call(prim_fileStat, 1, str(path));
    CHECK(st && load_ref(st, 0) == true_oop && load_ref(st, 1) == false_oop && ival(load_ref(st, 2)) == 4 &&
              ival(load_ref(st, 3)) > 0,
          "fileStat");
    oop ents = call(prim_dirEntries, 1, str("/tmp"));
    bool found = false;
    for (uint32_t i = 0; ents && i < num_slots(ents); i++)
        found |= byte_size(load_ref(ents, i)) == strlen(path) - 5 && !memcmp(bytes_of(load_ref(ents, i)), path + 5, strlen(path) - 5);
    CHECK(found, "dirEntries contains the file");
    CHECK(call(prim_fileDelete, 1, str(path)), "fileDelete");
    st = call(prim_fileStat, 1, str(path));
    CHECK(st && load_ref(st, 0) == false_oop, "deleted");
    CHECK(!call(prim_fileOpen, 2, I(1), I(0)), "fileOpen with non-string fails");
    CHECK(!call(prim_fileOpen, 2, str(path), I(0)), "fileOpen missing fails");
    CHECK(strstr(pf_last_error(), "No such file"), "platformLastError");
    oop le = call(prim_platformLastError, 0);
    CHECK(le && byte_size(le) == strlen(pf_last_error()), "platformLastError primitive");
    oop pid = call(prim_spawnProcess, 1, array(3, str("sh"), str("-c"), str("exit 4")));
    CHECK(pid && ival(call(prim_processWait, 2, pid, true_oop)) == 4, "spawn/wait");
    CHECK(call(prim_cwd, 0), "cwd");

    /* sockets */
    oop srv = call(prim_socketListen, 3, str("127.0.0.1"), I(0), I(4));
    oop port = call(prim_socketLocalPort, 1, srv);
    CHECK(srv && ival(port) > 0, "listen");
    CHECK(call(prim_socketAccept, 1, srv) == nil_oop, "accept nil");
    oop cli = call(prim_socketConnect, 2, str("localhost"), port);
    CHECK(cli, "connect");
    usleep(2000);
    oop con = call(prim_socketAccept, 1, srv);
    CHECK(con && is_int(con), "accept");
    CHECK(call(prim_socketRecv, 4, con, b, I(1), I(10)) == nil_oop, "recv nil");
    CHECK(call(prim_socketSemaphore, 2, con, I(6)), "socketSemaphore");
    CHECK(ival(call(prim_socketSend, 4, cli, str("xyz"), I(1), I(3))) == 3, "send");
    usleep(2000);
    nsignals = 0;
    platform_poll();
    CHECK(nsignals == 1 && signals[0] == 6, "socket semaphore");
    CHECK(ival(call(prim_socketRecv, 4, con, b, I(2), I(9))) == 3 && !memcmp(bytes_of(b) + 1, "xyz", 3), "recv");
    call(prim_socketClose, 1, cli);
    usleep(2000);
    CHECK(ival(call(prim_socketRecv, 4, con, b, I(1), I(10))) == 0, "recv EOF");
    CHECK(call(prim_socketClose, 1, con) && call(prim_socketClose, 1, srv), "close");

    /* pseudo-terminals */
    oop spawned = call(prim_ptySpawn, 5, array(3, str("sh"), str("-c"), str("stty size; printf \"$TERM\"; pwd")), nil_oop, str("/"), I(7), I(33));
    CHECK(spawned && num_slots(spawned) == 2 && ival(load_ref(spawned, 1)) > 0, "ptySpawn");
    oop pty = load_ref(spawned, 0);
    CHECK(call(prim_ptySemaphore, 2, pty, I(9)), "ptySemaphore");
    nsignals = 0;
    for (int i = 0; i < 2000 && !nsignals; i++) {
        usleep(1000);
        platform_poll();
    }
    CHECK(nsignals >= 1 && signals[0] == 9, "pty semaphore");
    char out[256] = {0};
    size_t got = 0;
    for (int i = 0; i < 3000 && got < sizeof out - 11; i++) {
        oop r = call(prim_ptyRead, 4, pty, b, I(1), I(10));
        if (r == nil_oop) {
            usleep(1000);
            continue;
        }
        if (!r || ival(r) == 0) break;
        memcpy(out + got, bytes_of(b), (size_t)ival(r));
        got += (size_t)ival(r);
    }
    CHECK(strstr(out, "7 33") && strstr(out, "xterm-256color/\r\n"), "pty output (rows cols, TERM, cwd)");
    CHECK(ival(call(prim_ptyWait, 2, pty, true_oop)) == 0, "ptyWait");
    CHECK(call(prim_ptyClose, 1, pty) && !call(prim_ptyClose, 1, pty) && !call(prim_socketRecv, 4, pty, b, I(1), I(10)), "ptyClose");
    spawned = call(prim_ptySpawn, 5, array(1, str("cat")), array(1, str("PATH=/bin:/usr/bin")), nil_oop, I(24), I(80));
    pty = spawned ? load_ref(spawned, 0) : nil_oop;
    CHECK(spawned && call(prim_ptyResize, 3, pty, I(30), I(100)), "ptyResize");
    CHECK(call(prim_ptyWait, 2, pty, false_oop) == nil_oop, "ptyWait running");
    CHECK(ival(call(prim_ptyWrite, 4, pty, str("abc\r"), I(1), I(4))) == 4, "ptyWrite");
    CHECK(call(prim_ptyClose, 1, pty), "ptyClose hangs up cat");

    /* GPU */
    oop dev = call(prim_gpuCreateDevice, 1, false_oop);
    CHECK(dev, "device");
    oop tex = call(prim_gpuCreateTexture, 5, dev, I(16), I(8), I(PF_TEX_RGBA8), I(3));
    CHECK(tex, "texture");
    oop sz = call(prim_gpuTextureSize, 1, tex);
    CHECK(sz && ival(load_ref(sz, 0)) == 16 && ival(load_ref(sz, 1)) == 8 && ival(load_ref(sz, 2)) == 2, "textureSize");
    oop cmd = call(prim_gpuAcquireCommandBuffer, 1, dev);
    oop pass = call(prim_gpuBeginPass, 3, cmd, tex, array(4, float_oop(1.0), I(0), float_oop(0.5), I(1)));
    CHECK(pass, "beginPass");
    CHECK(!call(prim_gpuBeginPass, 3, cmd, tex, array(3, I(0), I(0), I(0))), "bad clear fails");
    CHECK(call(prim_gpuEndPass, 1, pass), "endPass");
    oop fence = call(prim_gpuSubmit, 2, cmd, true_oop);
    CHECK(fence && is_int(fence), "submit fence");
    CHECK(call(prim_gpuWaitFence, 1, fence) && call(prim_gpuFenceDone, 1, fence) == true_oop, "fence");
    CHECK(call(prim_gpuRelease, 1, fence), "release fence");
    oop px = bytes(16 * 8 * 4);
    CHECK(call(prim_gpuDownload, 6, tex, I(0), I(0), I(16), I(8), px) == px && bytes_of(px)[0] == 255 &&
              bytes_of(px)[1] == 0 && abs(bytes_of(px)[2] - 128) <= 1 && bytes_of(px)[3] == 255,
          "download");
    CHECK(!call(prim_gpuDownload, 6, tex, I(0), I(0), I(16), I(9), px), "download out of bounds fails");
    oop bm = alloc_words32(classes[SO_BITMAP], 4);
    for (int i = 0; i < 4; i++) words32_of(bm)[i] = 0x11223344u * (i + 1);
    CHECK(call(prim_gpuUploadTexture, 7, tex, bm, I(2), I(3), I(2), I(2), I(8)), "upload Bitmap");
    oop px2 = bytes(16);
    CHECK(call(prim_gpuDownload, 6, tex, I(2), I(3), I(2), I(2), px2) && !memcmp(bytes_of(px2), words32_of(bm), 16),
          "upload/download Bitmap region");
    oop vs = call(prim_gpuCreateShader, 8, dev,
                  str("#include <metal_stdlib>\nusing namespace metal;\nstruct V { float2 p [[attribute(0)]]; float4 c "
                      "[[attribute(1)]]; };\nstruct O { float4 p [[position]]; float4 c; };\nvertex O vm(V v "
                      "[[stage_in]]) { O o; o.p = float4(v.p, 0, 1); o.c = v.c; return o; }\nfragment float4 fm(O i "
                      "[[stage_in]]) { return i.c; }\n"),
                  str("vm"), I(0), I(0), I(0), I(0), I(0));
    CHECK(vs, "shader");
    oop fs = call(prim_gpuCreateShader, 8, dev,
                  str("#include <metal_stdlib>\nusing namespace metal;\nstruct O { float4 p [[position]]; float4 c; };\n"
                      "fragment float4 fm(O i [[stage_in]]) { return i.c; }\n"),
                  str("fm"), I(1), I(0), I(0), I(0), I(0));
    oop pipe = call(prim_gpuCreatePipeline, 8, dev, vs, fs, I(12), array(4, I(PF_VA_FLOAT2), I(0), I(PF_VA_UBYTE4_NORM), I(8)),
                    I(0), I(1), I(PF_TEX_RGBA8));
    CHECK(pipe, "pipeline");
    CHECK(!call(prim_gpuCreatePipeline, 8, dev, vs, fs, I(12), array(3, I(2), I(0), I(5)), I(0), I(1), I(2)),
          "odd attribute array fails");
    oop vb = call(prim_gpuCreateBuffer, 3, dev, I(1), I(36));
    float tri[9] = {-1, -1, 0, 3, -1, 0, -1, 3, 0};
    uint8_t *tb = (uint8_t *)tri;
    uint32_t green = 0xFF00FF00u;
    for (int i = 0; i < 3; i++) memcpy(tb + i * 12 + 8, &green, 4);
    oop vdata = bytes(36);
    memcpy(bytes_of(vdata), tri, 36);
    CHECK(call(prim_gpuUploadBuffer, 4, vb, vdata, I(36), I(0)), "uploadBuffer");
    CHECK(!call(prim_gpuUploadBuffer, 4, vb, vdata, I(37), I(0)), "upload count > bytes fails");
    cmd = call(prim_gpuAcquireCommandBuffer, 1, dev);
    pass = call(prim_gpuBeginPass, 3, cmd, tex, nil_oop);
    CHECK(call(prim_gpuBindPipeline, 2, pass, pipe) && call(prim_gpuBindVertexBuffer, 4, pass, I(0), vb, I(0)) &&
              call(prim_gpuSetViewport, 5, pass, I(0), I(0), float_oop(16), I(8)) &&
              call(prim_gpuSetScissor, 5, pass, I(0), I(0), I(8), I(8)) && call(prim_gpuDraw, 3, pass, I(3), I(0)) &&
              call(prim_gpuEndPass, 1, pass),
          "draw");
    CHECK(call(prim_gpuSubmit, 2, cmd, false_oop) == nil_oop, "submit without fence");
    CHECK(call(prim_gpuDownload, 6, tex, I(0), I(0), I(16), I(8), px), "download 2");
    uint8_t *q = bytes_of(px);
    CHECK(q[0] == 0 && q[1] == 255 && q[2] == 0, "drawn left half green");
    CHECK(q[12 * 4] == 255 && q[12 * 4 + 1] == 0, "right half kept clear color (scissor)");
    CHECK(!call(prim_gpuDraw, 3, pass, I(3), I(0)), "ended pass handle is invalid");
    CHECK(call(prim_gpuRelease, 1, dev), "release device");
    CHECK(!call(prim_gpuRelease, 1, tex), "texture released with device");

    printf("%d/%d primitive checks passed\n", checks - failures, checks);
    return failures ? 1 : 0;
}
