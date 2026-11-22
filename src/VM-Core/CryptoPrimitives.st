VMPrimitiveModule subclass: #CryptoPrimitives
	instanceVariableNames: 'kernels'
	classVariableNames: ''
	package: 'VM-Core'!

CryptoPrimitives comment: 'Cryptography''s hot loops as primitives (NativeCrypto in System-Crypto, docs/crypto.md): SHA-256 and SHA-512 compression of whole blocks, AES encryption of blocks and in counter mode (GCM''s 32-bit counter), GHASH, and the CRC-32 and CRC-32C register update. Arguments are byte objects with a 1-based start and a count (blocks or bytes), hash states Arrays of 32-bit SmallIntegers, AES round keys a ByteArray (16 bytes a round and 16, as FIPS 197 orders them); a primitive fails on anything else, and the image does the work in Smalltalk. The work is CryptoKernels'', C in my preamble: portable, and with the CPU''s instructions where it has them (Armv8''s AES, PMULL, SHA-256, SHA-512 and CRC32; x86-64''s AES-NI, PCLMULQDQ, SHA-NI and SSE4.2), each kernel compiled for them alone and chosen by what the CPU says it has. cryptoFeatures answers what they do and masks them (the tests run the portable C so on any CPU). Not simulated: the primitives fail in the simulation.'!

!CryptoPrimitives class methodsFor: 'declaring'!
declarations
	^#((kernels CryptoKernels))
!
cPreamble
	^'/* The kernels of CryptoPrimitives: SHA-256 and SHA-512 compression, AES encryption (blocks, CTR with a 32-bit
   big-endian counter as GCM''s), GHASH and the CRC-32 and CRC-32C register update, each in portable C and, where the
   CPU has them, with its instructions: on arm64 the Armv8 cryptographic extensions (AES and PMULL, SHA-256, SHA-512)
   and CRC32; on x86-64 AES-NI, PCLMULQDQ, SHA-NI and SSE4.2 (CRC-32C only). The compiler''s default target has none
   of them: each kernel that uses them enables them for itself alone (a target attribute) and runs only once the CPU
   has said it has them (crypto_hardware: the auxiliary vector on Linux, ID_AA64ISAR0_EL1 on UEFI, every Apple
   arm64 CPU has them, CPUID on x86-64). crypto_use masks them, so the portable C can be tested on any CPU. */
#include <stdint.h>
#include <stddef.h>
#if defined(__aarch64__)
#include <arm_neon.h>
#include <arm_acle.h>
#if defined(__linux__) && !!defined(SAMALTAK_UEFI)
#include <sys/auxv.h>
#endif
#define CK_T_AES __attribute__((target("+aes")))
#define CK_T_SHA2 __attribute__((target("+sha2")))
#define CK_T_SHA3 __attribute__((target("+sha3")))
#define CK_T_CRC __attribute__((target("+crc")))
#elif defined(__x86_64__)
#include <immintrin.h>
#include <cpuid.h>
#define CK_T_AES __attribute__((target("aes,sse4.1")))
#define CK_T_CLMUL __attribute__((target("pclmul,ssse3")))
#define CK_T_SHA __attribute__((target("sha,sse4.1")))
#define CK_T_CRC __attribute__((target("sse4.2")))
#endif

#define CK_AES 1
#define CK_GHASH 2
#define CK_SHA256 4
#define CK_SHA512 8
#define CK_CRC32 16
#define CK_CRC32C 32
#define CK_ALL 63

static int64_t ck_hardware = -1;
static int64_t ck_mask = CK_ALL;

static inline uint32_t ck_be32(const uint8_t *p) { return (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 8 | p[3]; }
static inline uint64_t ck_be64(const uint8_t *p) { return (uint64_t)ck_be32(p) << 32 | ck_be32(p + 4); }
static inline uint32_t ck_le32(const uint8_t *p) { return (uint32_t)p[3] << 24 | (uint32_t)p[2] << 16 | (uint32_t)p[1] << 8 | p[0]; }
static inline uint64_t ck_le64(const uint8_t *p) { return (uint64_t)ck_le32(p + 4) << 32 | ck_le32(p); }
static inline void ck_put_be32(uint8_t *p, uint32_t v) { p[0] = (uint8_t)(v >> 24); p[1] = (uint8_t)(v >> 16); p[2] = (uint8_t)(v >> 8); p[3] = (uint8_t)v; }
static inline void ck_put_be64(uint8_t *p, uint64_t v) { ck_put_be32(p, (uint32_t)(v >> 32)); ck_put_be32(p + 4, (uint32_t)v); }
static inline void ck_put_le32(uint8_t *p, uint32_t v) { p[0] = (uint8_t)v; p[1] = (uint8_t)(v >> 8); p[2] = (uint8_t)(v >> 16); p[3] = (uint8_t)(v >> 24); }
static inline uint32_t ck_ror32(uint32_t x, int n) { return x >> n | x << (32 - n); }
static inline uint32_t ck_rol32(uint32_t x, int n) { return x << n | x >> (32 - n); }
static inline uint64_t ck_ror64(uint64_t x, int n) { return x >> n | x << (64 - n); }

static int64_t ck_detect(void)
{
    int64_t f = 0;
#if defined(__aarch64__) && defined(__APPLE__)
    f = CK_ALL;
#elif defined(__aarch64__) && defined(SAMALTAK_UEFI)
    uint64_t r;
    __asm__ volatile("mrs %0, ID_AA64ISAR0_EL1" : "=r"(r));
    if (((r >> 4) & 15) >= 2) f |= CK_AES | CK_GHASH;
    if (((r >> 12) & 15) >= 1) f |= CK_SHA256;
    if (((r >> 12) & 15) >= 2) f |= CK_SHA512;
    if (((r >> 16) & 15) >= 1) f |= CK_CRC32 | CK_CRC32C;
#elif defined(__aarch64__) && defined(__linux__)
    unsigned long h = getauxval(AT_HWCAP);
    if ((h & (1UL << 3)) && (h & (1UL << 4))) f |= CK_AES | CK_GHASH;
    if (h & (1UL << 6)) f |= CK_SHA256;
    if (h & (1UL << 21)) f |= CK_SHA512;
    if (h & (1UL << 7)) f |= CK_CRC32 | CK_CRC32C;
#elif defined(__x86_64__)
    unsigned a, b, c, d;
    if (__get_cpuid(1, &a, &b, &c, &d)) {
        if ((c & (1u << 25)) && (c & (1u << 19))) f |= CK_AES;
        if ((c & (1u << 1)) && (c & (1u << 9))) f |= CK_GHASH;
        if (c & (1u << 20)) f |= CK_CRC32C;
        if ((c & (1u << 19)) && __get_cpuid_count(7, 0, &a, &b, &c, &d) && (b & (1u << 29))) f |= CK_SHA256;
    }
#endif
    return f;
}

static int64_t crypto_hardware(void)
{
    if (ck_hardware < 0) ck_hardware = ck_detect();
    return ck_hardware;
}

static int64_t crypto_features(void)
{
    return crypto_hardware() & ck_mask;
}

static int64_t crypto_use(int64_t mask)
{
    int64_t old = ck_mask;
    ck_mask = mask & CK_ALL;
    return old;
}

static inline int64_t ck_has(int64_t feature)
{
    return crypto_hardware() & ck_mask & feature;
}

/* SHA-256 (FIPS 180-4, 6.2) */
static const uint32_t ck_k256[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
};

static void ck_sha256_c(uint32_t *s, const uint8_t *p, int64_t n)
{
    uint32_t w[64], a, b, c, d, e, f, g, h, t1, t2;
    int i;
    for (; n > 0; n--, p += 64) {
        for (i = 0; i < 16; i++) w[i] = ck_be32(p + 4 * i);
        for (i = 16; i < 64; i++)
            w[i] = w[i - 16] + (ck_ror32(w[i - 15], 7) ^ ck_ror32(w[i - 15], 18) ^ (w[i - 15] >> 3))
                + w[i - 7] + (ck_ror32(w[i - 2], 17) ^ ck_ror32(w[i - 2], 19) ^ (w[i - 2] >> 10));
        a = s[0]; b = s[1]; c = s[2]; d = s[3]; e = s[4]; f = s[5]; g = s[6]; h = s[7];
        for (i = 0; i < 64; i++) {
            t1 = h + (ck_ror32(e, 6) ^ ck_ror32(e, 11) ^ ck_ror32(e, 25)) + (g ^ (e & (f ^ g))) + ck_k256[i] + w[i];
            t2 = (ck_ror32(a, 2) ^ ck_ror32(a, 13) ^ ck_ror32(a, 22)) + ((a & b) | (c & (a | b)));
            h = g; g = f; f = e; e = d + t1; d = c; c = b; b = a; a = t1 + t2;
        }
        s[0] += a; s[1] += b; s[2] += c; s[3] += d; s[4] += e; s[5] += f; s[6] += g; s[7] += h;
    }
}

/* SHA-512 (FIPS 180-4, 6.4) */
static const uint64_t ck_k512[80] = {
    0x428a2f98d728ae22ULL, 0x7137449123ef65cdULL, 0xb5c0fbcfec4d3b2fULL, 0xe9b5dba58189dbbcULL,
    0x3956c25bf348b538ULL, 0x59f111f1b605d019ULL, 0x923f82a4af194f9bULL, 0xab1c5ed5da6d8118ULL,
    0xd807aa98a3030242ULL, 0x12835b0145706fbeULL, 0x243185be4ee4b28cULL, 0x550c7dc3d5ffb4e2ULL,
    0x72be5d74f27b896fULL, 0x80deb1fe3b1696b1ULL, 0x9bdc06a725c71235ULL, 0xc19bf174cf692694ULL,
    0xe49b69c19ef14ad2ULL, 0xefbe4786384f25e3ULL, 0x0fc19dc68b8cd5b5ULL, 0x240ca1cc77ac9c65ULL,
    0x2de92c6f592b0275ULL, 0x4a7484aa6ea6e483ULL, 0x5cb0a9dcbd41fbd4ULL, 0x76f988da831153b5ULL,
    0x983e5152ee66dfabULL, 0xa831c66d2db43210ULL, 0xb00327c898fb213fULL, 0xbf597fc7beef0ee4ULL,
    0xc6e00bf33da88fc2ULL, 0xd5a79147930aa725ULL, 0x06ca6351e003826fULL, 0x142929670a0e6e70ULL,
    0x27b70a8546d22ffcULL, 0x2e1b21385c26c926ULL, 0x4d2c6dfc5ac42aedULL, 0x53380d139d95b3dfULL,
    0x650a73548baf63deULL, 0x766a0abb3c77b2a8ULL, 0x81c2c92e47edaee6ULL, 0x92722c851482353bULL,
    0xa2bfe8a14cf10364ULL, 0xa81a664bbc423001ULL, 0xc24b8b70d0f89791ULL, 0xc76c51a30654be30ULL,
    0xd192e819d6ef5218ULL, 0xd69906245565a910ULL, 0xf40e35855771202aULL, 0x106aa07032bbd1b8ULL,
    0x19a4c116b8d2d0c8ULL, 0x1e376c085141ab53ULL, 0x2748774cdf8eeb99ULL, 0x34b0bcb5e19b48a8ULL,
    0x391c0cb3c5c95a63ULL, 0x4ed8aa4ae3418acbULL, 0x5b9cca4f7763e373ULL, 0x682e6ff3d6b2b8a3ULL,
    0x748f82ee5defb2fcULL, 0x78a5636f43172f60ULL, 0x84c87814a1f0ab72ULL, 0x8cc702081a6439ecULL,
    0x90befffa23631e28ULL, 0xa4506cebde82bde9ULL, 0xbef9a3f7b2c67915ULL, 0xc67178f2e372532bULL,
    0xca273eceea26619cULL, 0xd186b8c721c0c207ULL, 0xeada7dd6cde0eb1eULL, 0xf57d4f7fee6ed178ULL,
    0x06f067aa72176fbaULL, 0x0a637dc5a2c898a6ULL, 0x113f9804bef90daeULL, 0x1b710b35131c471bULL,
    0x28db77f523047d84ULL, 0x32caab7b40c72493ULL, 0x3c9ebe0a15c9bebcULL, 0x431d67c49c100d4cULL,
    0x4cc5d4becb3e42b6ULL, 0x597f299cfc657e2aULL, 0x5fcb6fab3ad6faecULL, 0x6c44198c4a475817ULL
};

static void ck_sha512_c(uint64_t *s, const uint8_t *p, int64_t n)
{
    uint64_t w[80], a, b, c, d, e, f, g, h, t1, t2;
    int i;
    for (; n > 0; n--, p += 128) {
        for (i = 0; i < 16; i++) w[i] = ck_be64(p + 8 * i);
        for (i = 16; i < 80; i++)
            w[i] = w[i - 16] + (ck_ror64(w[i - 15], 1) ^ ck_ror64(w[i - 15], 8) ^ (w[i - 15] >> 7))
                + w[i - 7] + (ck_ror64(w[i - 2], 19) ^ ck_ror64(w[i - 2], 61) ^ (w[i - 2] >> 6));
        a = s[0]; b = s[1]; c = s[2]; d = s[3]; e = s[4]; f = s[5]; g = s[6]; h = s[7];
        for (i = 0; i < 80; i++) {
            t1 = h + (ck_ror64(e, 14) ^ ck_ror64(e, 18) ^ ck_ror64(e, 41)) + (g ^ (e & (f ^ g))) + ck_k512[i] + w[i];
            t2 = (ck_ror64(a, 28) ^ ck_ror64(a, 34) ^ ck_ror64(a, 39)) + ((a & b) | (c & (a | b)));
            h = g; g = f; f = e; e = d + t1; d = c; c = b; b = a; a = t1 + t2;
        }
        s[0] += a; s[1] += b; s[2] += c; s[3] += d; s[4] += e; s[5] += f; s[6] += g; s[7] += h;
    }
}

/* AES (FIPS 197) with the round keys as bytes, in the order of the standard: one table of SubBytes and MixColumns of
   a little-endian column word (rotated for the other rows), made at first use. */
static uint32_t ck_te[256];
static uint8_t ck_sbox[256];
static int ck_aes_ready;

static inline uint8_t ck_xtime(uint8_t a) { return (uint8_t)((a << 1) ^ ((a & 0x80) ? 0x1b : 0)); }

static void ck_aes_init(void)
{
    uint8_t exp[256], log[256], t = 1, inv, s;
    int i, k;
    for (i = 0; i < 255; i++) { exp[i] = t; log[t] = (uint8_t)i; t ^= ck_xtime(t); }
    for (i = 0; i < 256; i++) {
        inv = i == 0 ? 0 : exp[(255 - log[i]) % 255];
        s = inv;
        for (k = 1; k <= 4; k++) s ^= (uint8_t)(inv << k | inv >> (8 - k));
        s ^= 0x63;
        ck_sbox[i] = s;
        ck_te[i] = (uint32_t)ck_xtime(s) | (uint32_t)s << 8 | (uint32_t)s << 16 | (uint32_t)(ck_xtime(s) ^ s) << 24;
    }
    ck_aes_ready = 1;
}

static void ck_aes_block_c(const uint8_t *rk, int rounds, const uint8_t *in, uint8_t *out)
{
    uint32_t s0, s1, s2, s3, t0, t1, t2, t3;
    const uint8_t *k;
    int r;
    s0 = ck_le32(in) ^ ck_le32(rk); s1 = ck_le32(in + 4) ^ ck_le32(rk + 4);
    s2 = ck_le32(in + 8) ^ ck_le32(rk + 8); s3 = ck_le32(in + 12) ^ ck_le32(rk + 12);
    for (r = 1; r < rounds; r++) {
        k = rk + 16 * r;
        t0 = ck_te[s0 & 255] ^ ck_rol32(ck_te[(s1 >> 8) & 255], 8) ^ ck_rol32(ck_te[(s2 >> 16) & 255], 16) ^ ck_rol32(ck_te[s3 >> 24], 24) ^ ck_le32(k);
        t1 = ck_te[s1 & 255] ^ ck_rol32(ck_te[(s2 >> 8) & 255], 8) ^ ck_rol32(ck_te[(s3 >> 16) & 255], 16) ^ ck_rol32(ck_te[s0 >> 24], 24) ^ ck_le32(k + 4);
        t2 = ck_te[s2 & 255] ^ ck_rol32(ck_te[(s3 >> 8) & 255], 8) ^ ck_rol32(ck_te[(s0 >> 16) & 255], 16) ^ ck_rol32(ck_te[s1 >> 24], 24) ^ ck_le32(k + 8);
        t3 = ck_te[s3 & 255] ^ ck_rol32(ck_te[(s0 >> 8) & 255], 8) ^ ck_rol32(ck_te[(s1 >> 16) & 255], 16) ^ ck_rol32(ck_te[s2 >> 24], 24) ^ ck_le32(k + 12);
        s0 = t0; s1 = t1; s2 = t2; s3 = t3;
    }
    k = rk + 16 * rounds;
    ck_put_le32(out, ((uint32_t)ck_sbox[s0 & 255] | (uint32_t)ck_sbox[(s1 >> 8) & 255] << 8 | (uint32_t)ck_sbox[(s2 >> 16) & 255] << 16 | (uint32_t)ck_sbox[s3 >> 24] << 24) ^ ck_le32(k));
    ck_put_le32(out + 4, ((uint32_t)ck_sbox[s1 & 255] | (uint32_t)ck_sbox[(s2 >> 8) & 255] << 8 | (uint32_t)ck_sbox[(s3 >> 16) & 255] << 16 | (uint32_t)ck_sbox[s0 >> 24] << 24) ^ ck_le32(k + 4));
    ck_put_le32(out + 8, ((uint32_t)ck_sbox[s2 & 255] | (uint32_t)ck_sbox[(s3 >> 8) & 255] << 8 | (uint32_t)ck_sbox[(s0 >> 16) & 255] << 16 | (uint32_t)ck_sbox[s1 >> 24] << 24) ^ ck_le32(k + 8));
    ck_put_le32(out + 12, ((uint32_t)ck_sbox[s3 & 255] | (uint32_t)ck_sbox[(s0 >> 8) & 255] << 8 | (uint32_t)ck_sbox[(s1 >> 16) & 255] << 16 | (uint32_t)ck_sbox[s2 >> 24] << 24) ^ ck_le32(k + 12));
}

static void ck_aes_ecb_c(const uint8_t *rk, int rounds, const uint8_t *in, uint8_t *out, int64_t n)
{
    if (ck_aes_ready == 0) ck_aes_init();
    for (; n > 0; n--, in += 16, out += 16) ck_aes_block_c(rk, rounds, in, out);
}

static void ck_aes_ctr_c(const uint8_t *rk, int rounds, const uint8_t *ctr, const uint8_t *in, uint8_t *out, int64_t len)
{
    uint8_t block[16], key[16];
    uint32_t c = ck_be32(ctr + 12);
    int i;
    if (ck_aes_ready == 0) ck_aes_init();
    for (i = 0; i < 12; i++) block[i] = ctr[i];
    for (; len > 0; len -= 16, in += 16, out += 16, c++) {
        ck_put_be32(block + 12, c);
        ck_aes_block_c(rk, rounds, block, key);
        for (i = 0; i < 16 && i < len; i++) out[i] = in[i] ^ key[i];
    }
}

/* GHASH (NIST SP 800-38D): a block is the polynomial over GF(2) whose coefficient of x^i is bit i from the first
   byte''s most significant bit on; with each byte''s bits reversed it is a 128-bit little-endian number, and the
   product (Karatsuba, three 64-bit carry-less multiplications) is reduced modulo x^128 + x^7 + x^2 + x + 1 in two
   steps of 64 bits: x^128 = 16r87. Portably the carry-less multiplication is BearSSL''s (integer multiplications of
   every fourth bit, constant time), its high half that of the bit-reversed operands. */
static inline uint64_t ck_bmul64(uint64_t x, uint64_t y)
{
    uint64_t x0 = x & 0x1111111111111111ULL, x1 = x & 0x2222222222222222ULL, x2 = x & 0x4444444444444444ULL, x3 = x & 0x8888888888888888ULL;
    uint64_t y0 = y & 0x1111111111111111ULL, y1 = y & 0x2222222222222222ULL, y2 = y & 0x4444444444444444ULL, y3 = y & 0x8888888888888888ULL;
    uint64_t z0 = (x0 * y0) ^ (x1 * y3) ^ (x2 * y2) ^ (x3 * y1);
    uint64_t z1 = (x0 * y1) ^ (x1 * y0) ^ (x2 * y3) ^ (x3 * y2);
    uint64_t z2 = (x0 * y2) ^ (x1 * y1) ^ (x2 * y0) ^ (x3 * y3);
    uint64_t z3 = (x0 * y3) ^ (x1 * y2) ^ (x2 * y1) ^ (x3 * y0);
    return (z0 & 0x1111111111111111ULL) | (z1 & 0x2222222222222222ULL) | (z2 & 0x4444444444444444ULL) | (z3 & 0x8888888888888888ULL);
}

static inline uint64_t ck_rev64(uint64_t x)
{
    x = ((x >> 1) & 0x5555555555555555ULL) | ((x & 0x5555555555555555ULL) << 1);
    x = ((x >> 2) & 0x3333333333333333ULL) | ((x & 0x3333333333333333ULL) << 2);
    x = ((x >> 4) & 0x0F0F0F0F0F0F0F0FULL) | ((x & 0x0F0F0F0F0F0F0F0FULL) << 4);
    x = ((x >> 8) & 0x00FF00FF00FF00FFULL) | ((x & 0x00FF00FF00FF00FFULL) << 8);
    x = ((x >> 16) & 0x0000FFFF0000FFFFULL) | ((x & 0x0000FFFF0000FFFFULL) << 16);
    return x >> 32 | x << 32;
}

static inline void ck_clmul64(uint64_t a, uint64_t b, uint64_t *lo, uint64_t *hi)
{
    *lo = ck_bmul64(a, b);
    *hi = ck_rev64(ck_bmul64(ck_rev64(a), ck_rev64(b))) >> 1;
}

static void ck_ghash_c(uint8_t *y, const uint8_t *h, const uint8_t *p, int64_t len)
{
    uint64_t h0 = ck_rev64(ck_be64(h)), h1 = ck_rev64(ck_be64(h + 8));
    uint64_t x0 = ck_rev64(ck_be64(y)), x1 = ck_rev64(ck_be64(y + 8));
    uint64_t l0, l1, g0, g1, m0, m1, r0, r1, r2, r3;
    uint8_t last[16];
    const uint8_t *b;
    int i;
    for (; len > 0; len -= 16, p += 16) {
        b = p;
        if (len < 16) {
            for (i = 0; i < 16; i++) last[i] = i < len ? p[i] : 0;
            b = last;
        }
        x0 ^= ck_rev64(ck_be64(b));
        x1 ^= ck_rev64(ck_be64(b + 8));
        ck_clmul64(x0, h0, &l0, &l1);
        ck_clmul64(x1, h1, &g0, &g1);
        ck_clmul64(x0 ^ x1, h0 ^ h1, &m0, &m1);
        m0 ^= l0 ^ g0;
        m1 ^= l1 ^ g1;
        r0 = l0; r1 = l1 ^ m0; r2 = g0 ^ m1; r3 = g1;
        r1 ^= r3 ^ (r3 << 1) ^ (r3 << 2) ^ (r3 << 7);
        r2 ^= (r3 >> 63) ^ (r3 >> 62) ^ (r3 >> 57);
        r0 ^= r2 ^ (r2 << 1) ^ (r2 << 2) ^ (r2 << 7);
        r1 ^= (r2 >> 63) ^ (r2 >> 62) ^ (r2 >> 57);
        x0 = r0; x1 = r1;
    }
    ck_put_be64(y, ck_rev64(x0));
    ck_put_be64(y + 8, ck_rev64(x1));
}

/* CRC-32 (reflected 16rEDB88320) and CRC-32C (reflected 16r82F63B78): the register update alone, without the
   inversions; portably eight bytes at a time with eight tables (slicing-by-8), made at first use. */
static uint32_t ck_crc_table[2][8][256];
static int ck_crc_ready;

static void ck_crc_init(void)
{
    uint32_t c;
    int k, i, j;
    for (k = 0; k < 2; k++) {
        for (i = 0; i < 256; i++) {
            c = (uint32_t)i;
            for (j = 0; j < 8; j++) c = (c & 1) ? (c >> 1) ^ (k ? 0x82F63B78u : 0xEDB88320u) : c >> 1;
            ck_crc_table[k][0][i] = c;
        }
        for (i = 0; i < 256; i++)
            for (j = 1; j < 8; j++) ck_crc_table[k][j][i] = (ck_crc_table[k][j - 1][i] >> 8) ^ ck_crc_table[k][0][ck_crc_table[k][j - 1][i] & 255];
    }
    ck_crc_ready = 1;
}

static uint32_t ck_crc_c(uint32_t c, const uint8_t *p, int64_t n, int castagnoli)
{
    const uint32_t (*t)[256];
    uint32_t lo, hi;
    if (ck_crc_ready == 0) ck_crc_init();
    t = ck_crc_table[castagnoli ? 1 : 0];
    for (; n >= 8; n -= 8, p += 8) {
        lo = c ^ ck_le32(p);
        hi = ck_le32(p + 4);
        c = t[7][lo & 255] ^ t[6][(lo >> 8) & 255] ^ t[5][(lo >> 16) & 255] ^ t[4][lo >> 24]
            ^ t[3][hi & 255] ^ t[2][(hi >> 8) & 255] ^ t[1][(hi >> 16) & 255] ^ t[0][hi >> 24];
    }
    for (; n > 0; n--, p++) c = t[0][(c ^ *p) & 255] ^ (c >> 8);
    return c;
}

#if defined(__aarch64__)
CK_T_SHA2 static void ck_sha256_hw(uint32_t *s, const uint8_t *p, int64_t n)
{
    uint32x4_t abcd = vld1q_u32(s), efgh = vld1q_u32(s + 4), abcd0, efgh0, m0, m1, m2, m3, wk, t;
    for (; n > 0; n--, p += 64) {
        abcd0 = abcd;
        efgh0 = efgh;
        m0 = vreinterpretq_u32_u8(vrev32q_u8(vld1q_u8(p)));
        m1 = vreinterpretq_u32_u8(vrev32q_u8(vld1q_u8(p + 16)));
        m2 = vreinterpretq_u32_u8(vrev32q_u8(vld1q_u8(p + 32)));
        m3 = vreinterpretq_u32_u8(vrev32q_u8(vld1q_u8(p + 48)));
#define CK_R4(m, i) wk = vaddq_u32(m, vld1q_u32(ck_k256 + 4 * (i))); t = abcd; abcd = vsha256hq_u32(abcd, efgh, wk); efgh = vsha256h2q_u32(efgh, t, wk)
#define CK_S4(a, b, c, d) a = vsha256su1q_u32(vsha256su0q_u32(a, b), c, d)
        CK_R4(m0, 0); CK_S4(m0, m1, m2, m3);
        CK_R4(m1, 1); CK_S4(m1, m2, m3, m0);
        CK_R4(m2, 2); CK_S4(m2, m3, m0, m1);
        CK_R4(m3, 3); CK_S4(m3, m0, m1, m2);
        CK_R4(m0, 4); CK_S4(m0, m1, m2, m3);
        CK_R4(m1, 5); CK_S4(m1, m2, m3, m0);
        CK_R4(m2, 6); CK_S4(m2, m3, m0, m1);
        CK_R4(m3, 7); CK_S4(m3, m0, m1, m2);
        CK_R4(m0, 8); CK_S4(m0, m1, m2, m3);
        CK_R4(m1, 9); CK_S4(m1, m2, m3, m0);
        CK_R4(m2, 10); CK_S4(m2, m3, m0, m1);
        CK_R4(m3, 11); CK_S4(m3, m0, m1, m2);
        CK_R4(m0, 12);
        CK_R4(m1, 13);
        CK_R4(m2, 14);
        CK_R4(m3, 15);
#undef CK_R4
#undef CK_S4
        abcd = vaddq_u32(abcd, abcd0);
        efgh = vaddq_u32(efgh, efgh0);
    }
    vst1q_u32(s, abcd);
    vst1q_u32(s + 4, efgh);
}

/* Two rounds per SHA512H and SHA512H2 on the pairs (a b) (c d) (e f) (g h); after them (c d) + the SHA512H result is
   the new (e f), the old (a b) the new (c d), the old (e f) the new (g h). */
CK_T_SHA3 static void ck_sha512_hw(uint64_t *s, const uint8_t *p, int64_t n)
{
    uint64x2_t ab = vld1q_u64(s), cd = vld1q_u64(s + 2), ef = vld1q_u64(s + 4), gh = vld1q_u64(s + 6);
    uint64x2_t ab0, cd0, ef0, gh0, m[8], kw, t, a2;
    int i;
    for (; n > 0; n--, p += 128) {
        ab0 = ab; cd0 = cd; ef0 = ef; gh0 = gh;
        for (i = 0; i < 8; i++) m[i] = vreinterpretq_u64_u8(vrev64q_u8(vld1q_u8(p + 16 * i)));
        for (i = 0; i < 40; i++) {
            kw = vaddq_u64(m[i & 7], vld1q_u64(ck_k512 + 2 * i));
            if (i < 32)
                m[i & 7] = vsha512su1q_u64(vsha512su0q_u64(m[i & 7], m[(i + 1) & 7]), m[(i + 7) & 7], vextq_u64(m[(i + 4) & 7], m[(i + 5) & 7], 1));
            t = vsha512hq_u64(vaddq_u64(gh, vextq_u64(kw, kw, 1)), vextq_u64(ef, gh, 1), vextq_u64(cd, ef, 1));
            a2 = vsha512h2q_u64(t, cd, ab);
            gh = ef;
            ef = vaddq_u64(cd, t);
            cd = ab;
            ab = a2;
        }
        ab = vaddq_u64(ab, ab0); cd = vaddq_u64(cd, cd0); ef = vaddq_u64(ef, ef0); gh = vaddq_u64(gh, gh0);
    }
    vst1q_u64(s, ab); vst1q_u64(s + 2, cd); vst1q_u64(s + 4, ef); vst1q_u64(s + 6, gh);
}

CK_T_AES static inline uint8x16_t ck_aes_hw_block(const uint8x16_t *k, int rounds, uint8x16_t b)
{
    int i;
    for (i = 0; i < rounds - 1; i++) b = vaesmcq_u8(vaeseq_u8(b, k[i]));
    return veorq_u8(vaeseq_u8(b, k[rounds - 1]), k[rounds]);
}

CK_T_AES static void ck_aes_ecb_hw(const uint8_t *rk, int rounds, const uint8_t *in, uint8_t *out, int64_t n)
{
    uint8x16_t k[15];
    int i;
    for (i = 0; i <= rounds; i++) k[i] = vld1q_u8(rk + 16 * i);
    for (; n > 0; n--, in += 16, out += 16) vst1q_u8(out, ck_aes_hw_block(k, rounds, vld1q_u8(in)));
}

CK_T_AES static void ck_aes_ctr_hw(const uint8_t *rk, int rounds, const uint8_t *ctr, const uint8_t *in, uint8_t *out, int64_t len)
{
    uint8x16_t k[15], b[8], ks;
    uint32x4_t base = vreinterpretq_u32_u8(vld1q_u8(ctr));
    uint32_t c = ck_be32(ctr + 12);
    uint8_t last[16];
    int i, j;
    for (i = 0; i <= rounds; i++) k[i] = vld1q_u8(rk + 16 * i);
    for (; len >= 128; len -= 128, in += 128, out += 128, c += 8) {
        for (j = 0; j < 8; j++) b[j] = vreinterpretq_u8_u32(vsetq_lane_u32(__builtin_bswap32(c + (uint32_t)j), base, 3));
        for (i = 0; i < rounds - 1; i++)
            for (j = 0; j < 8; j++) b[j] = vaesmcq_u8(vaeseq_u8(b[j], k[i]));
        for (j = 0; j < 8; j++)
            vst1q_u8(out + 16 * j, veorq_u8(vld1q_u8(in + 16 * j), veorq_u8(vaeseq_u8(b[j], k[rounds - 1]), k[rounds])));
    }
    for (; len > 0; len -= 16, in += 16, out += 16, c++) {
        ks = ck_aes_hw_block(k, rounds, vreinterpretq_u8_u32(vsetq_lane_u32(__builtin_bswap32(c), base, 3)));
        if (len >= 16) {
            vst1q_u8(out, veorq_u8(vld1q_u8(in), ks));
        } else {
            vst1q_u8(last, ks);
            for (i = 0; i < len; i++) out[i] = in[i] ^ last[i];
        }
    }
}

CK_T_AES static inline uint64x2_t ck_pmull_lo(uint64x2_t a, uint64x2_t b)
{
    return vreinterpretq_u64_p128(vmull_p64((poly64_t)vgetq_lane_u64(a, 0), (poly64_t)vgetq_lane_u64(b, 0)));
}

CK_T_AES static inline uint64x2_t ck_pmull_hi(uint64x2_t a, uint64x2_t b)
{
    return vreinterpretq_u64_p128(vmull_high_p64(vreinterpretq_p64_u64(a), vreinterpretq_p64_u64(b)));
}

CK_T_AES static void ck_ghash_hw(uint8_t *y, const uint8_t *h, const uint8_t *p, int64_t len)
{
    uint64x2_t hv = vreinterpretq_u64_u8(vrbitq_u8(vld1q_u8(h)));
    uint64x2_t hk = veorq_u64(hv, vextq_u64(hv, hv, 1));
    uint64x2_t x = vreinterpretq_u64_u8(vrbitq_u8(vld1q_u8(y)));
    uint64x2_t z = vdupq_n_u64(0), poly = vdupq_n_u64(0x87), lo, hi, mid, t;
    uint8x16_t b;
    uint8_t last[16];
    int i;
    for (; len > 0; len -= 16, p += 16) {
        if (len >= 16) {
            b = vld1q_u8(p);
        } else {
            for (i = 0; i < 16; i++) last[i] = i < len ? p[i] : 0;
            b = vld1q_u8(last);
        }
        x = veorq_u64(x, vreinterpretq_u64_u8(vrbitq_u8(b)));
        lo = ck_pmull_lo(x, hv);
        hi = ck_pmull_hi(x, hv);
        mid = veorq_u64(ck_pmull_lo(veorq_u64(x, vextq_u64(x, x, 1)), hk), veorq_u64(lo, hi));
        lo = veorq_u64(lo, vextq_u64(z, mid, 1));
        hi = veorq_u64(hi, vextq_u64(mid, z, 1));
        t = ck_pmull_hi(hi, poly);
        lo = veorq_u64(lo, vextq_u64(z, t, 1));
        hi = veorq_u64(hi, vextq_u64(t, z, 1));
        x = veorq_u64(lo, ck_pmull_lo(hi, poly));
    }
    vst1q_u8(y, vrbitq_u8(vreinterpretq_u8_u64(x)));
}

CK_T_CRC static uint32_t ck_crc_hw(uint32_t c, const uint8_t *p, int64_t n, int castagnoli)
{
    if (castagnoli) {
        for (; n >= 8; n -= 8, p += 8) c = __crc32cd(c, ck_le64(p));
        for (; n > 0; n--, p++) c = __crc32cb(c, *p);
    } else {
        for (; n >= 8; n -= 8, p += 8) c = __crc32d(c, ck_le64(p));
        for (; n > 0; n--, p++) c = __crc32b(c, *p);
    }
    return c;
}
#elif defined(__x86_64__)
/* SHA-NI: the state as (a b e f) and (c d g h), two rounds per SHA256RNDS2 (Intel''s sample code). */
CK_T_SHA static void ck_sha256_hw(uint32_t *s, const uint8_t *p, int64_t n)
{
    const __m128i swap = _mm_set_epi64x(0x0c0d0e0f08090a0bLL, 0x0405060700010203LL);
    __m128i t = _mm_shuffle_epi32(_mm_loadu_si128((const __m128i *)s), 0xB1);
    __m128i s1 = _mm_shuffle_epi32(_mm_loadu_si128((const __m128i *)(s + 4)), 0x1B);
    __m128i s0 = _mm_alignr_epi8(t, s1, 8), s00, s10, m[4], wk;
    int i;
    s1 = _mm_blend_epi16(s1, t, 0xF0);
    for (; n > 0; n--, p += 64) {
        s00 = s0;
        s10 = s1;
        for (i = 0; i < 4; i++) m[i] = _mm_shuffle_epi8(_mm_loadu_si128((const __m128i *)(p + 16 * i)), swap);
        for (i = 0; i < 16; i++) {
            wk = _mm_add_epi32(m[i & 3], _mm_loadu_si128((const __m128i *)(ck_k256 + 4 * i)));
            s1 = _mm_sha256rnds2_epu32(s1, s0, wk);
            if (i < 12)
                m[i & 3] = _mm_sha256msg2_epu32(_mm_add_epi32(_mm_sha256msg1_epu32(m[i & 3], m[(i + 1) & 3]), _mm_alignr_epi8(m[(i + 3) & 3], m[(i + 2) & 3], 4)), m[(i + 3) & 3]);
            s0 = _mm_sha256rnds2_epu32(s0, s1, _mm_shuffle_epi32(wk, 0x0E));
        }
        s0 = _mm_add_epi32(s0, s00);
        s1 = _mm_add_epi32(s1, s10);
    }
    t = _mm_shuffle_epi32(s0, 0x1B);
    s1 = _mm_shuffle_epi32(s1, 0xB1);
    _mm_storeu_si128((__m128i *)s, _mm_blend_epi16(t, s1, 0xF0));
    _mm_storeu_si128((__m128i *)(s + 4), _mm_alignr_epi8(s1, t, 8));
}

CK_T_AES static inline __m128i ck_aes_hw_block(const __m128i *k, int rounds, __m128i b)
{
    int i;
    b = _mm_xor_si128(b, k[0]);
    for (i = 1; i < rounds; i++) b = _mm_aesenc_si128(b, k[i]);
    return _mm_aesenclast_si128(b, k[rounds]);
}

CK_T_AES static void ck_aes_ecb_hw(const uint8_t *rk, int rounds, const uint8_t *in, uint8_t *out, int64_t n)
{
    __m128i k[15];
    int i;
    for (i = 0; i <= rounds; i++) k[i] = _mm_loadu_si128((const __m128i *)(rk + 16 * i));
    for (; n > 0; n--, in += 16, out += 16) _mm_storeu_si128((__m128i *)out, ck_aes_hw_block(k, rounds, _mm_loadu_si128((const __m128i *)in)));
}

CK_T_AES static void ck_aes_ctr_hw(const uint8_t *rk, int rounds, const uint8_t *ctr, const uint8_t *in, uint8_t *out, int64_t len)
{
    __m128i k[15], b[8], ks, base = _mm_loadu_si128((const __m128i *)ctr);
    uint32_t c = ck_be32(ctr + 12);
    uint8_t last[16];
    int i, j;
    for (i = 0; i <= rounds; i++) k[i] = _mm_loadu_si128((const __m128i *)(rk + 16 * i));
    for (; len >= 128; len -= 128, in += 128, out += 128, c += 8) {
        for (j = 0; j < 8; j++) b[j] = _mm_xor_si128(_mm_insert_epi32(base, (int)__builtin_bswap32(c + (uint32_t)j), 3), k[0]);
        for (i = 1; i < rounds; i++)
            for (j = 0; j < 8; j++) b[j] = _mm_aesenc_si128(b[j], k[i]);
        for (j = 0; j < 8; j++)
            _mm_storeu_si128((__m128i *)(out + 16 * j), _mm_xor_si128(_mm_loadu_si128((const __m128i *)(in + 16 * j)), _mm_aesenclast_si128(b[j], k[rounds])));
    }
    for (; len > 0; len -= 16, in += 16, out += 16, c++) {
        ks = ck_aes_hw_block(k, rounds, _mm_insert_epi32(base, (int)__builtin_bswap32(c), 3));
        if (len >= 16) {
            _mm_storeu_si128((__m128i *)out, _mm_xor_si128(_mm_loadu_si128((const __m128i *)in), ks));
        } else {
            _mm_storeu_si128((__m128i *)last, ks);
            for (i = 0; i < len; i++) out[i] = in[i] ^ last[i];
        }
    }
}

/* Each byte''s bits reversed, a nibble at a time (PSHUFB). */
CK_T_CLMUL static inline __m128i ck_rbit8(__m128i v)
{
    const __m128i lut = _mm_setr_epi8(0, 8, 4, 12, 2, 10, 6, 14, 1, 9, 5, 13, 3, 11, 7, 15), m = _mm_set1_epi8(15);
    return _mm_or_si128(_mm_slli_epi16(_mm_shuffle_epi8(lut, _mm_and_si128(v, m)), 4), _mm_shuffle_epi8(lut, _mm_and_si128(_mm_srli_epi16(v, 4), m)));
}

CK_T_CLMUL static void ck_ghash_hw(uint8_t *y, const uint8_t *h, const uint8_t *p, int64_t len)
{
    __m128i hv = ck_rbit8(_mm_loadu_si128((const __m128i *)h));
    __m128i hk = _mm_xor_si128(hv, _mm_shuffle_epi32(hv, 0x4E));
    __m128i x = ck_rbit8(_mm_loadu_si128((const __m128i *)y));
    __m128i poly = _mm_set_epi64x(0x87, 0x87), b, lo, hi, mid, t;
    uint8_t last[16];
    int i;
    for (; len > 0; len -= 16, p += 16) {
        if (len >= 16) {
            b = _mm_loadu_si128((const __m128i *)p);
        } else {
            for (i = 0; i < 16; i++) last[i] = i < len ? p[i] : 0;
            b = _mm_loadu_si128((const __m128i *)last);
        }
        x = _mm_xor_si128(x, ck_rbit8(b));
        lo = _mm_clmulepi64_si128(x, hv, 0x00);
        hi = _mm_clmulepi64_si128(x, hv, 0x11);
        mid = _mm_xor_si128(_mm_clmulepi64_si128(_mm_xor_si128(x, _mm_shuffle_epi32(x, 0x4E)), hk, 0x00), _mm_xor_si128(lo, hi));
        lo = _mm_xor_si128(lo, _mm_slli_si128(mid, 8));
        hi = _mm_xor_si128(hi, _mm_srli_si128(mid, 8));
        t = _mm_clmulepi64_si128(hi, poly, 0x01);
        lo = _mm_xor_si128(lo, _mm_slli_si128(t, 8));
        hi = _mm_xor_si128(hi, _mm_srli_si128(t, 8));
        x = _mm_xor_si128(lo, _mm_clmulepi64_si128(hi, poly, 0x00));
    }
    _mm_storeu_si128((__m128i *)y, ck_rbit8(x));
}

CK_T_CRC static uint32_t ck_crc_hw(uint32_t c, const uint8_t *p, int64_t n, int castagnoli)
{
    uint64_t c64 = c;
    for (; n >= 8; n -= 8, p += 8) c64 = _mm_crc32_u64(c64, ck_le64(p));
    c = (uint32_t)c64;
    for (; n > 0; n--, p++) c = _mm_crc32_u8(c, *p);
    return c;
}
#endif

#if defined(__aarch64__) || defined(__x86_64__)
#define CK_HW(feature) ck_has(feature)
#else
#define CK_HW(feature) 0
#define ck_sha256_hw ck_sha256_c
#define ck_sha512_hw ck_sha512_c
#define ck_aes_ecb_hw ck_aes_ecb_c
#define ck_aes_ctr_hw ck_aes_ctr_c
#define ck_ghash_hw ck_ghash_c
#define ck_crc_hw ck_crc_c
#endif
#if defined(__x86_64__)
#define ck_sha512_hw ck_sha512_c
#endif

static void crypto_sha256(uint32_t *state, const uint8_t *p, int64_t blocks)
{
    if (CK_HW(CK_SHA256)) ck_sha256_hw(state, p, blocks); else ck_sha256_c(state, p, blocks);
}

static void crypto_sha512(uint64_t *state, const uint8_t *p, int64_t blocks)
{
    if (CK_HW(CK_SHA512)) ck_sha512_hw(state, p, blocks); else ck_sha512_c(state, p, blocks);
}

static void crypto_aes_encrypt(const uint8_t *keys, int64_t rounds, const uint8_t *in, uint8_t *out, int64_t blocks)
{
    if (CK_HW(CK_AES)) ck_aes_ecb_hw(keys, (int)rounds, in, out, blocks); else ck_aes_ecb_c(keys, (int)rounds, in, out, blocks);
}

static void crypto_aes_ctr(const uint8_t *keys, int64_t rounds, const uint8_t *counter, const uint8_t *in, uint8_t *out, int64_t size)
{
    if (CK_HW(CK_AES)) ck_aes_ctr_hw(keys, (int)rounds, counter, in, out, size); else ck_aes_ctr_c(keys, (int)rounds, counter, in, out, size);
}

static void crypto_ghash(uint8_t *y, const uint8_t *h, const uint8_t *p, int64_t size)
{
    if (CK_HW(CK_GHASH)) ck_ghash_hw(y, h, p, size); else ck_ghash_c(y, h, p, size);
}

static uint32_t crypto_crc32(uint32_t crc, const uint8_t *p, int64_t size, int64_t castagnoli)
{
    if (CK_HW(castagnoli ? CK_CRC32C : CK_CRC32)) return ck_crc_hw(crc, p, size, (int)castagnoli);
    return ck_crc_c(crc, p, size, (int)castagnoli);
}

static int crypto_available(void)
{
    return 1;
}'
! !

!CryptoPrimitives methodsFor: 'operands'!
bytes: o from: start count: n writable: isWrite
	"The address of the n bytes of the byte object o from the 1-based SmallInteger start, or 0 if o has no such bytes (or is immutable and is to be written)."
	| f i |
	(self isPtr: o) ifFalse: [^0 asUInt64].
	f := self formatOf: o.
	(f >= F_BYTES and: [f < (F_BYTES + 8)]) ifFalse: [^0 asUInt64].
	(isWrite and: [self isImmutable: o]) ifTrue: [^0 asUInt64].
	(self isInt: start) ifFalse: [^0 asUInt64].
	i := self intVal: start.
	(i >= 1 and: [n >= 0 and: [(i - 1 + n) asUInt64 <= (memory byteSize: o)]]) ifFalse: [^0 asUInt64].
	^o + 16 + (i - 1) asUInt64
!
count: o max: m
	"The SmallInteger o if 0 <= o <= m, else -1."
	((self isInt: o) and: [(self intVal: o) >= 0 and: [(self intVal: o) <= m]]) ifFalse: [^-1].
	^self intVal: o
!
roundsOf: keys
	"AES's rounds (10, 12 or 14) for the round keys keys, a byte object of 176, 208 or 240 bytes; else -1."
	| f n |
	(self isPtr: keys) ifFalse: [^-1].
	f := self formatOf: keys.
	(f >= F_BYTES and: [f < (F_BYTES + 8)]) ifFalse: [^-1].
	n := (memory byteSize: keys) asInt64.
	(n = 176 or: [n = 208 or: [n = 240]]) ifFalse: [^-1].
	^(n quo: 16) - 1
!
words: o count: n into: w
	"Whether o is a mutable Array of n SmallIntegers v, 0 <= v < 2^32; their values into w."
	| v |
	((self isPtr: o) and: [(self formatOf: o) = F_VAR and: [(self numSlots: o) = n and: [(self isImmutable: o) not]]]) ifFalse: [^false].
	0 to: n - 1 do: [:i |
		v := self loadRef: o at: i.
		((self isInt: v) and: [(self intVal: v) >= 0 and: [(self intVal: v) <= 16rFFFFFFFF]]) ifFalse: [^false].
		w at: i put: (self intVal: v) asUInt32].
	^true
!
store: w count: n into: o
	"The n words of w into the Array o, as SmallIntegers."
	0 to: n - 1 do: [:i | self storeRef: o at: i put: (self intOop: (w at: i) asInt64)]
! !

!CryptoPrimitives methodsFor: 'primitives'!
primFeatures
	"Without an argument: the features whose work the CPU's instructions do (bits: 1 AES, 2 GHASH, 4 SHA-256, 8 SHA-512, 16 CRC-32, 32 CRC-32C; the others are portable C). With a mask: let them do only those of the mask (0: portable C alone) and answer the previous mask."
	<vmPrimitive: 640 name: 'cryptoFeatures'>
	<leaf>
	| m |
	kernels available = 0 ifTrue: [^self fail].
	self argCount = 0 ifTrue: [^self answerInt: kernels features].
	m := self arg: 0.
	(self argCount = 1 and: [self isInt: m]) ifFalse: [^self fail].
	self answerInt: (kernels use: (self intVal: m))
!
primSha256
	"(state, bytes, start, blocks): SHA-256's compression of blocks 64-byte blocks of bytes from start into state, an Array of the eight 32-bit words; answers true."
	<vmPrimitive: 641 name: 'cryptoSha256'>
	<leaf>
	| s n p |
	s := self local: 'uint32_t[8]'.
	(kernels available ~= 0 and: [self argCount = 4]) ifFalse: [^self fail].
	n := self count: (self arg: 3) max: 16r10000000000.
	n < 0 ifTrue: [^self fail].
	p := self bytes: (self arg: 1) from: (self arg: 2) count: n * 64 writable: false.
	(p = 0 or: [(self words: (self arg: 0) count: 8 into: s) not]) ifTrue: [^self fail].
	kernels sha256: s bytes: (self cCoerce: p to: 'const uint8_t *') blocks: n.
	self store: s count: 8 into: (self arg: 0).
	self answerBool: true
!
primSha512
	"(state, bytes, start, blocks): SHA-512's compression of blocks 128-byte blocks of bytes from start into state, an Array of the eight 64-bit words as sixteen 32-bit halves, the high one first; answers true."
	<vmPrimitive: 642 name: 'cryptoSha512'>
	<leaf>
	| h s n p |
	h := self local: 'uint32_t[16]'.
	s := self local: 'uint64_t[8]'.
	(kernels available ~= 0 and: [self argCount = 4]) ifFalse: [^self fail].
	n := self count: (self arg: 3) max: 16r10000000000.
	n < 0 ifTrue: [^self fail].
	p := self bytes: (self arg: 1) from: (self arg: 2) count: n * 128 writable: false.
	(p = 0 or: [(self words: (self arg: 0) count: 16 into: h) not]) ifTrue: [^self fail].
	0 to: 7 do: [:i | s at: i put: (((h at: 2 * i) asUInt64 << 32) bitOr: (h at: 2 * i + 1) asUInt64)].
	kernels sha512: s bytes: (self cCoerce: p to: 'const uint8_t *') blocks: n.
	0 to: 7 do: [:i |
		h at: 2 * i put: ((s at: i) >> 32) asUInt32.
		h at: 2 * i + 1 put: (s at: i) asUInt32].
	self store: h count: 16 into: (self arg: 0).
	self answerBool: true
!
primAesEncrypt
	"(keys, input, start, output, outStart, blocks): AES encryption of blocks 16-byte blocks of input from start into output from outStart with the round keys keys; answers true."
	<vmPrimitive: 643 name: 'cryptoAesEncrypt'>
	<leaf>
	| r n p q |
	(kernels available ~= 0 and: [self argCount = 6]) ifFalse: [^self fail].
	r := self roundsOf: (self arg: 0).
	n := self count: (self arg: 5) max: 16r10000000000.
	(r < 0 or: [n < 0]) ifTrue: [^self fail].
	p := self bytes: (self arg: 1) from: (self arg: 2) count: n * 16 writable: false.
	q := self bytes: (self arg: 3) from: (self arg: 4) count: n * 16 writable: true.
	(p = 0 or: [q = 0]) ifTrue: [^self fail].
	kernels aes: (self bytesOf: (self arg: 0)) rounds: r encrypt: (self cCoerce: p to: 'const uint8_t *') into: (self cCoerce: q to: 'uint8_t *') blocks: n.
	self answerBool: true
!
primAesCtr
	"(keys, counter, input, start, output, outStart, count): count bytes of input from start xored into output from outStart with AES's key stream in counter mode under the round keys keys: the encryption of the 16-byte counter block, then of it with its last 32 bits (big-endian) incremented modulo 2^32, as GCM's inc32, and so on; answers true."
	<vmPrimitive: 644 name: 'cryptoAesCtr'>
	<leaf>
	| r n c p q |
	(kernels available ~= 0 and: [self argCount = 7]) ifFalse: [^self fail].
	r := self roundsOf: (self arg: 0).
	n := self count: (self arg: 6) max: 16r1000000000.
	(r < 0 or: [n < 0]) ifTrue: [^self fail].
	c := self bytes: (self arg: 1) from: (self intOop: 1) count: 16 writable: false.
	p := self bytes: (self arg: 2) from: (self arg: 3) count: n writable: false.
	q := self bytes: (self arg: 4) from: (self arg: 5) count: n writable: true.
	(c = 0 or: [p = 0 or: [q = 0]]) ifTrue: [^self fail].
	kernels aes: (self bytesOf: (self arg: 0)) rounds: r counter: (self cCoerce: c to: 'const uint8_t *') input: (self cCoerce: p to: 'const uint8_t *') output: (self cCoerce: q to: 'uint8_t *') size: n.
	self answerBool: true
!
primGhash
	"(y, h, bytes, start, count): y := (y xor each 16-byte block of the count bytes of bytes from start, the last padded with zeros) times h in GF(2^128), block after block (GHASH, NIST SP 800-38D); y and h 16 bytes; answers true."
	<vmPrimitive: 645 name: 'cryptoGhash'>
	<leaf>
	| n y h p |
	(kernels available ~= 0 and: [self argCount = 5]) ifFalse: [^self fail].
	n := self count: (self arg: 4) max: 16r10000000000.
	n < 0 ifTrue: [^self fail].
	y := self bytes: (self arg: 0) from: (self intOop: 1) count: 16 writable: true.
	h := self bytes: (self arg: 1) from: (self intOop: 1) count: 16 writable: false.
	p := self bytes: (self arg: 2) from: (self arg: 3) count: n writable: false.
	(y = 0 or: [h = 0 or: [p = 0]]) ifTrue: [^self fail].
	kernels ghash: (self cCoerce: y to: 'uint8_t *') key: (self cCoerce: h to: 'const uint8_t *') bytes: (self cCoerce: p to: 'const uint8_t *') size: n.
	self answerBool: true
!
primCrc32
	"(crc, bytes, start, count): the CRC-32 register crc (0 <= crc < 2^32; reflected, 16rEDB88320) after count bytes of bytes from start, without the inversions."
	<vmPrimitive: 646 name: 'cryptoCrc32'>
	<leaf>
	self crc: 0
!
primCrc32c
	"(crc, bytes, start, count): the same for CRC-32C (16r82F63B78)."
	<vmPrimitive: 647 name: 'cryptoCrc32c'>
	<leaf>
	self crc: 1
!
crc: castagnoli
	| c n p |
	(kernels available ~= 0 and: [self argCount = 4]) ifFalse: [^self fail].
	c := self arg: 0.
	((self isInt: c) and: [(self intVal: c) >= 0 and: [(self intVal: c) <= 16rFFFFFFFF]]) ifFalse: [^self fail].
	n := self count: (self arg: 3) max: 16r10000000000.
	n < 0 ifTrue: [^self fail].
	p := self bytes: (self arg: 1) from: (self arg: 2) count: n writable: false.
	p = 0 ifTrue: [^self fail].
	self answer: (self intOop: (kernels crc: (self intVal: c) asUInt32 bytes: (self cCoerce: p to: 'const uint8_t *') size: n castagnoli: castagnoli) asInt64)
! !

CLibrary subclass: #CryptoKernels
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Core'!

CryptoKernels comment: 'The kernels of CryptoPrimitives: C in its preamble (CryptoPrimitives class>>cPreamble), declared here. Not simulated: available answers 0 in the simulation, and the primitives fail.'!

!CryptoKernels methodsFor: 'kernels'!
available
	<c: 'int crypto_available(void)'>
	^0
!
features
	<c: 'int64_t crypto_features(void)'>
	^0
!
use: mask
	<c: 'int64_t crypto_use(int64_t mask)'>
	^0
!
sha256: state bytes: p blocks: n
	<c: 'void crypto_sha256(uint32_t *state, const uint8_t *p, int64_t blocks)'>
	^self error: 'not simulated'
!
sha512: state bytes: p blocks: n
	<c: 'void crypto_sha512(uint64_t *state, const uint8_t *p, int64_t blocks)'>
	^self error: 'not simulated'
!
aes: keys rounds: r encrypt: p into: q blocks: n
	<c: 'void crypto_aes_encrypt(const uint8_t *keys, int64_t rounds, const uint8_t *in, uint8_t *out, int64_t blocks)'>
	^self error: 'not simulated'
!
aes: keys rounds: r counter: c input: p output: q size: n
	<c: 'void crypto_aes_ctr(const uint8_t *keys, int64_t rounds, const uint8_t *counter, const uint8_t *in, uint8_t *out, int64_t size)'>
	^self error: 'not simulated'
!
ghash: y key: h bytes: p size: n
	<c: 'void crypto_ghash(uint8_t *y, const uint8_t *h, const uint8_t *p, int64_t size)'>
	^self error: 'not simulated'
!
crc: crc bytes: p size: n castagnoli: castagnoli
	<c: 'uint32_t crypto_crc32(uint32_t crc, const uint8_t *p, int64_t size, int64_t castagnoli)'>
	^self error: 'not simulated'
! !
