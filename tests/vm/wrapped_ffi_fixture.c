#include <stddef.h>
#include <stdint.h>
#include <string.h>

static uint32_t calls;

uint32_t wrapped_calls(void) { return calls; }
void wrapped_void(void) { ++calls; }

int32_t wrapped_step(int32_t n)
{
    ++calls;
    return n < 1 - INT32_MAX ? INT32_MAX : 1 - n;
}

int32_t wrapped_other(int32_t n)
{
    ++calls;
    return n > INT32_MAX - 20 ? INT32_MAX : n + 20;
}

uint64_t wrapped_mixed(int32_t a, double b, uint64_t c, int64_t d,
                       uint32_t e, double f)
{
    ++calls;
    /* Compare the high bits exactly, not via approximate f64 conversions. */
    if (a < -4096 || a > -1 || b != -a * 0.25 ||
        c != UINT64_MAX - (uint64_t)-a || d != INT64_MIN - a ||
        e != UINT32_MAX - (uint32_t)-a || f != a * 0.125)
        return 0;
    return c;
}

double wrapped_floats(double a, double b, double c, double d, double e, double f)
{
    ++calls;
    return a + 2*b + 4*c + 8*d + 16*e + 32*f;
}

int64_t wrapped_signed(int64_t n)
{
    ++calls;
    return n;
}

uint64_t wrapped_borrows(uint64_t seed, const uint8_t *a, size_t na,
                         const uint8_t *b, size_t nb, uint64_t tail)
{
    ++calls;
    for (size_t i = 0; i < na; ++i)
        seed = seed * 33 + a[i];
    for (size_t i = 0; i < nb; ++i)
        seed = seed * 33 + b[i];
    return seed + tail;
}

/*
 * The return PC is inside the running packet. Require the target immediate to
 * name this exact export, preceded by the scalar ABI lane move and followed by
 * inline i32 boxing. This fixture is only built by the hosted test runner.
 */

__attribute__((noinline))
int32_t wrapped_prove_target(int32_t n)
{
    const uint8_t *pc = __builtin_extract_return_addr(__builtin_return_address(0));
    uintptr_t target = (uintptr_t)&wrapped_prove_target;
#if defined(__x86_64__)
    uintptr_t immediate;
    memcpy(&immediate, pc - 11, sizeof(immediate));
    if (memcmp(pc - 16, "\x40\x89\xc7\x49\xbb", 5) != 0 ||
        immediate != target || memcmp(pc - 3, "\x41\xff\xd3", 3) != 0 ||
        memcmp(pc, "\x48\x63\xc0\x48\x8d\x44\x00\x01", 8) != 0)
        return -1;
#elif defined(__aarch64__) || defined(__arm64__)
    uint32_t words[9];
    uintptr_t immediate = 0;
    memcpy(words, pc - 24, sizeof(words));
    if (words[0] != 0x2a1403e0 || words[5] != 0xd63f0200 ||
        words[6] != 0x93407c00 || words[7] != 0xd37ff800 || words[8] != 0x91000400)
        return -1;
    for (unsigned i = 0; i < 4; ++i) {
        uint32_t op = words[i + 1];
        uint32_t fixed = i == 0 ? 0xd2800010 : 0xf2800010 + (i << 21);
        if ((op & ~UINT32_C(0x001fffe0)) != fixed)
            return -1;
        immediate |= (uintptr_t)((op >> 5) & 0xffff) << (i * 16);
    }
    if (immediate != target)
        return -1;
#else
# error "Unsupported launcher architecture"
#endif
    return n;
}
