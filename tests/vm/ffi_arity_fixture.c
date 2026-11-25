/* Launcher-grant fixture for tests/vm/ffi_arity_test.sh: 7 to 16 arguments,
 * mixing integer, floating-point and slice lanes past the argument registers.
 * Each hashes its arguments in order (FNV-1a over 64-bit lanes) the way
 * tests/vm/ffi_arity.st and the approved ffi_test_arity* exports do. */
#include <stdint.h>
#include <string.h>

static uint32_t calls;

uint32_t arity_calls(void) { return calls; }

static uint64_t mix(uint64_t h, uint64_t v) { return (h ^ v) * 0x100000001b3ULL; }
static uint64_t mixi(uint64_t h, int64_t v) { return mix(h, (uint64_t)v); }
static uint64_t mixd(uint64_t h, double d)
{
    uint64_t bits;
    memcpy(&bits, &d, sizeof bits);
    return mix(h, bits);
}
static uint64_t mixf(uint64_t h, float f)
{
    uint32_t bits;
    memcpy(&bits, &f, sizeof bits);
    return mix(h, bits);
}
static uint64_t mixs(uint64_t h, const uint8_t *p, uint64_t n)
{
    for (uint64_t i = 0; i < n; i++) h = mix(h, p[i]);
    return mix(h, n);
}
#define START uint64_t h = 0xcbf29ce484222325ULL; ++calls

uint64_t arity7(int32_t a, int64_t b, uint32_t c, uint64_t d, int32_t e, int64_t f, int32_t g)
{
    START;
    h = mixi(h, a); h = mixi(h, b); h = mix(h, c); h = mix(h, d); h = mixi(h, e); h = mixi(h, f);
    return mixi(h, g);
}

uint64_t arity8(int32_t a, int64_t b, int32_t c, int64_t d, int32_t e, int64_t f, int32_t g,
                const uint8_t *p, uint64_t n)
{
    START;
    h = mixi(h, a); h = mixi(h, b); h = mixi(h, c); h = mixi(h, d); h = mixi(h, e); h = mixi(h, f);
    h = mixi(h, g);
    return mixs(h, p, n);
}

float arity9(int32_t a, int64_t b, int32_t c, int64_t d, int32_t e, const uint8_t *p, uint64_t n,
             double f, float g, int64_t i)
{
    START;
    h = mixi(h, a); h = mixi(h, b); h = mixi(h, c); h = mixi(h, d); h = mixi(h, e);
    h = mixs(h, p, n); h = mixd(h, f); h = mixf(h, g); h = mixi(h, i);
    return (float)(h & 0xffffff);
}

/* cublasSgemm's shape: handle, transa, transb, m, n, k, alpha, A, lda, B, ldb, beta, C, ldc. */
uint64_t arity14(uint64_t handle, int32_t transa, int32_t transb, int32_t m, int32_t n, int32_t k,
                 const uint8_t *alpha, uint64_t alphaLength, uint64_t a, int32_t lda, uint64_t b, int32_t ldb,
                 const uint8_t *beta, uint64_t betaLength, uint64_t c, int32_t ldc)
{
    START;
    h = mix(h, handle); h = mixi(h, transa); h = mixi(h, transb); h = mixi(h, m); h = mixi(h, n);
    h = mixi(h, k); h = mixs(h, alpha, alphaLength); h = mix(h, a); h = mixi(h, lda); h = mix(h, b);
    h = mixi(h, ldb); h = mixs(h, beta, betaLength); h = mix(h, c);
    return mixi(h, ldc);
}

double arity16(double a, int32_t b, float c, int64_t d, double e, uint32_t f, float g, uint64_t i,
               double j, int32_t k, float l, int64_t m, double n, int32_t o, float p, double q)
{
    START;
    h = mixd(h, a); h = mixi(h, b); h = mixf(h, c); h = mixi(h, d); h = mixd(h, e); h = mix(h, f);
    h = mixf(h, g); h = mix(h, i); h = mixd(h, j); h = mixi(h, k); h = mixf(h, l); h = mixi(h, m);
    h = mixd(h, n); h = mixi(h, o); h = mixf(h, p); h = mixd(h, q);
    return (double)(h >> 11);
}
