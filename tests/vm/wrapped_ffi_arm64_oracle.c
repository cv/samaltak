/* Standalone AAPCS64 oracle. See wrapped_ffi_arm64_test.sh. */
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef uint64_t oop;
typedef oop (*launcher)(const oop *);

static inline long syscall6(long nr, long a, long b, long c, long d, long e, long f)
{
    register long x0 __asm__("x0") = a;
    register long x1 __asm__("x1") = b;
    register long x2 __asm__("x2") = c;
    register long x3 __asm__("x3") = d;
    register long x4 __asm__("x4") = e;
    register long x5 __asm__("x5") = f;
    register long x8 __asm__("x8") = nr;
    __asm__ volatile ("svc #0" : "+r"(x0) : "r"(x1), "r"(x2), "r"(x3), "r"(x4), "r"(x5), "r"(x8) : "memory");
    return x0;
}

static void say(const char *s)
{
    long n = 0;
    while (s[n]) ++n;
    syscall6(64, 2, (long)s, n, 0, 0, 0); /* write */
}

static _Noreturn void quit(int code)
{
    syscall6(93, code, 0, 0, 0, 0, 0); /* exit */
    __builtin_unreachable();
}

#define CHECK(c) do { if (!(c)) { say("FAIL: " #c "\n"); quit(1); } } while (0)
#define ADDR(f) ((uintptr_t)(f))
static oop small(int64_t x) { return (uint64_t)x * 2 + 1; }

void *memset(void *dst, int v, size_t len)
{
    for (size_t i = 0; i < len; ++i) ((unsigned char *)dst)[i] = v;
    return dst;
}

/* Fixed helper stand-ins: even oops name synthetic non-immediate values. */
static unsigned helper_calls, calls;
static const unsigned char left[] = {0, 2, 255}, right[] = {0, 2, 240};

static bool arg_i32(oop o, int32_t *p)
{
    ++helper_calls;
    *p = INT32_MIN;
    return o == 2;
}

static bool arg_u32(oop o, uint32_t *p)
{
    ++helper_calls;
    *p = UINT32_MAX;
    return o == 4;
}

static bool arg_i64(oop o, int64_t *p)
{
    ++helper_calls;
    *p = INT64_MIN;
    return o == 6;
}

static bool arg_u64(oop o, uint64_t *p)
{
    ++helper_calls;
    *p = UINT64_MAX;
    return o == 8;
}

static bool arg_double(oop o, double *p)
{
    /* Destroy every caller-saved FP argument lane. Preserved d8-d15 are untouched. */
    __asm__ volatile (
        "movi v0.16b,#0; movi v1.16b,#0; movi v2.16b,#0; movi v3.16b,#0;"
        "movi v4.16b,#0; movi v5.16b,#0; movi v6.16b,#0; movi v7.16b,#0"
        ::: "v0", "v1", "v2", "v3", "v4", "v5", "v6", "v7");
    *p = (double)o / 2.0;
    return o >= 12 && o <= 22 && !(o & 1);
}

static bool arg_slice(oop o, uint64_t *p, uint64_t *n)
{
    if (o != 24 && o != 26 && o != 28 && o != 30) return false;
    *p = ADDR(o == 24 || o == 28 ? left : right);
    *n = o >= 28 ? 1 : 3;
    return true;
}

static oop box_i64(int64_t x) { return x < 0 ? 32 : 34; }
static oop box_u64(uint64_t x) { return x == UINT64_MAX ? 36 : 38; }
static oop box_double(double x) { return x == 449.0 ? 40 : 42; }
static oop box_void(void) { return 44; }

static uint64_t wrapped_argument_helper(int32_t tag)
{
    static const uintptr_t helpers[] = {
        0, ADDR(arg_i32), ADDR(arg_u32), ADDR(arg_i64), ADDR(arg_u64), ADDR(arg_slice), ADDR(arg_double), 0, ADDR(arg_slice)
    };
    return helpers[tag];
}

static uint64_t wrapped_result_helper(int32_t tag)
{
    static const uintptr_t helpers[] = {
        0, 0, 0, ADDR(box_i64), ADDR(box_u64), 0, ADDR(box_double), ADDR(box_void)
    };
    return helpers[tag];
}

#include "encoder.inc"

static launcher wrap(uintptr_t target, const uint8_t *tags, int n, int result, int op)
{
    /* Emit in a fresh RW page, publish RX before ever branching to it. */
    long page = syscall6(222, 0, 4096, 3, 0x22, -1, 0); /* mmap */
    CHECK(page > 0);
    uint32_t size = encode_wrapped_arm64((uint32_t *)page, target, tags, n, result, op);
    CHECK(size > 0 && size <= 2048);
    /* Maintain the caches explicitly when this oracle runs on hardware. */
    uint64_t ctr;
    __asm__ volatile ("mrs %0, ctr_el0" : "=r"(ctr));
    long dline = 4L << ((ctr >> 16) & 15), iline = 4L << (ctr & 15);
    for (long p = page; p < page + size; p += dline) __asm__ volatile ("dc cvau, %0" :: "r"(p) : "memory");
    __asm__ volatile ("dsb ish" ::: "memory");
    for (long p = page; p < page + size; p += iline) __asm__ volatile ("ic ivau, %0" :: "r"(p) : "memory");
    __asm__ volatile ("dsb ish; isb" ::: "memory");
    CHECK(syscall6(226, page, 4096, 5, 0, 0, 0) == 0); /* mprotect */
    return (launcher)page;
}

/* Exercise both ends of the staging register ranges across the launcher. */
__attribute__((noinline))
static oop guarded(launcher entry, const oop *args)
{
    register uint64_t g0 __asm__("x19") = UINT64_C(0x123456789abcdef0);
    register uint64_t g1 __asm__("x25") = UINT64_C(0xfedcba9876543210);
    register double f0 __asm__("d8") = -8.0;
    register double f1 __asm__("d13") = 13.0;
    __asm__ volatile ("" : "+r"(g0), "+r"(g1), "+w"(f0), "+w"(f1));
    oop result = entry(args);
    __asm__ volatile ("" : "+r"(g0), "+r"(g1), "+w"(f0), "+w"(f1));
    CHECK(g0 == UINT64_C(0x123456789abcdef0) && g1 == UINT64_C(0xfedcba9876543210));
    CHECK(f0 == -8.0 && f1 == 13.0);
    return result;
}

static int32_t i32(int32_t x) { ++calls; return x; }
static uint32_t u32(uint32_t x) { ++calls; return x; }
static int64_t i64(int64_t x) { ++calls; return x; }
static uint64_t u64(uint64_t x) { ++calls; return x; }
static void nothing(void) { ++calls; }
static int32_t cmp(const unsigned char *a, const unsigned char *b, uint64_t n)
{
    ++calls;
    for (uint64_t i = 0; i < n; ++i)
        if (a[i] != b[i]) return a[i] - b[i];
    return 0;
}

static int32_t mixed(int32_t i, double f, const unsigned char *p, uint64_t n, uint64_t u, double g)
{
    uintptr_t sp;
    __asm__ volatile ("mov %0,sp" : "=r"(sp));
    CHECK(sp % 16 == 0);
    CHECK(i == INT32_MIN && f == 6.0 && p == left && n == 3 && u == UINT64_MAX && g == 11.0);
    ++calls;
    return -47;
}

static double six_floats(double a, double b, double c, double d, double e, double f)
{
    return a + 2*b + 3*c + 4*d + 5*e + 29*f; /* 449 */
}

static int64_t six_integers(int32_t a, uint32_t b, int64_t c, uint64_t d, int32_t e, uint64_t f)
{
    CHECK(a == -9 && b == UINT32_MAX && c == -17 && d == UINT64_MAX && e == -25 && f == 29);
    return INT64_C(4611686018427387904);
}

_Noreturn void _start(void)
{
    const int64_t min = -INT64_C(4611686018427387904), max = INT64_C(4611686018427387903);
    launcher w = wrap(ADDR(i32), (uint8_t[]){1}, 1, 1, 0);
    CHECK(w((oop[]){small(INT32_MIN)}) == small(INT32_MIN) && helper_calls == 0);
    CHECK(w((oop[]){small(INT32_MAX)}) == small(INT32_MAX) && helper_calls == 0);
    CHECK(w((oop[]){small((int64_t)INT32_MIN - 1)}) == 0);
    CHECK(w((oop[]){small((int64_t)INT32_MAX + 1)}) == 0);
    CHECK(w((oop[]){2}) == small(INT32_MIN) && helper_calls == 1 && calls == 3);
    CHECK(w((oop[]){4}) == 0 && helper_calls == 2 && calls == 3);

    w = wrap(ADDR(u32), (uint8_t[]){2}, 1, 2, 0);
    CHECK(w((oop[]){small(UINT32_MAX)}) == small(UINT32_MAX));
    CHECK(w((oop[]){small((int64_t)UINT32_MAX + 1)}) == 0);
    CHECK(w((oop[]){small(-1)}) == 0);
    CHECK(w((oop[]){4}) == small(UINT32_MAX));

    w = wrap(ADDR(i64), (uint8_t[]){3}, 1, 3, 0);
    CHECK(w((oop[]){small(min)}) == small(min));
    CHECK(w((oop[]){small(max)}) == small(max));
    CHECK(w((oop[]){6}) == 32);
    w = wrap(ADDR(u64), (uint8_t[]){4}, 1, 4, 0);
    CHECK(w((oop[]){small(max)}) == small(max));
    CHECK(w((oop[]){small(-1)}) == 0);
    CHECK(w((oop[]){8}) == 36);

    w = wrap(ADDR(mixed), (uint8_t[]){1, 6, 8, 4, 6}, 5, 1, 0);
    CHECK(w((oop[]){small(INT32_MIN), 12, 24, 8, 22}) == small(-47));
    unsigned entered = calls;
    CHECK(w((oop[]){small(INT32_MIN), 12, 10, 8, 22}) == 0 && calls == entered);
    CHECK(w((oop[]){small(INT32_MIN), 12, 24, 8, 10}) == 0 && calls == entered);
    w = wrap(ADDR(six_floats), (uint8_t[]){6, 6, 6, 6, 6, 6}, 6, 6, 0);
    CHECK(guarded(w, (oop[]){12, 14, 16, 18, 20, 22}) == 40);
    CHECK(guarded(w, (oop[]){12, 14, 16, 18, 20, 10}) == 0);
    w = wrap(ADDR(six_integers), (uint8_t[]){1, 2, 3, 4, 1, 4}, 6, 3, 0);
    CHECK(guarded(w, (oop[]){small(-9), 4, small(-17), 8, small(-25), small(29)}) == 34);
    CHECK(guarded(w, (oop[]){small(-9), 4, small(-17), 8, small(-25), small(-1)}) == 0);

    w = wrap(ADDR(cmp), (uint8_t[]){5, 5, 4}, 3, 1, 1);
    CHECK(w((oop[]){24, 26, small(3)}) == small(15));
    CHECK(w((oop[]){26, 24, small(3)}) == small(-15));
    CHECK(w((oop[]){28, 30, small(0)}) == small(0));
    entered = calls;
    CHECK(w((oop[]){28, 26, small(2)}) == 0 && calls == entered);
    CHECK(w((oop[]){24, 30, small(2)}) == 0 && calls == entered);
    CHECK(w((oop[]){24, 26, 8}) == 0 && calls == entered);
    CHECK(w((oop[]){24, 26, small(-1)}) == 0 && calls == entered);

    w = wrap(ADDR(nothing), NULL, 0, 7, 0);
    CHECK(w(NULL) == 44 && calls == entered + 1);
    say("wrapped_ffi_arm64: PASS\n");
    quit(0);
}
