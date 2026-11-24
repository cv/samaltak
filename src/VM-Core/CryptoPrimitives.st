VMPrimitiveModule subclass: #CryptoPrimitives
	instanceVariableNames: 'kernels'
	classVariableNames: ''
	package: 'VM-Core'!

CryptoPrimitives comment: 'The CRC-32 and CRC-32C register update as primitives (Crc32 and Crc32c in System-Storage: PNG''s chunks, ext4''s checksums): a byte object with a 1-based start and a count; a primitive fails on anything else, and the image does the work in Smalltalk. The work is CryptoKernels'', C in my preamble: portable (slicing-by-8), and with the CPU''s CRC instructions where it has them (Armv8''s CRC32, x86-64''s SSE4.2 for CRC-32C), compiled for them alone and chosen by what the CPU says it has. The cryptography that was here (SHA-2, AES, GHASH) is the VM''s exports now (FFIPrimitives-crypto, docs/crypto.md). Not simulated: the primitives fail in the simulation.'!

!CryptoPrimitives class methodsFor: 'declaring'!
declarations
	^#((kernels CryptoKernels))
!
cPreamble
	^'/* The kernels of CryptoPrimitives: the CRC-32 and CRC-32C register update, in portable C and, where the CPU has
   them, with its instructions: CRC32 on arm64, SSE4.2 (CRC-32C only) on x86-64. The compiler''s default target has
   none of them: each kernel that uses them enables them for itself alone (a target attribute) and runs only once
   the CPU has said it has them (the auxiliary vector on Linux, ID_AA64ISAR0_EL1 on UEFI, every Apple arm64 CPU has
   them, CPUID on x86-64). */
#include <stdint.h>
#include <stddef.h>
#if defined(__aarch64__)
#include <arm_acle.h>
#if defined(__linux__) && !!defined(SAMALTAK_UEFI)
#include <sys/auxv.h>
#endif
#define CK_T_CRC __attribute__((target("+crc")))
#elif defined(__x86_64__)
#include <immintrin.h>
#include <cpuid.h>
#define CK_T_CRC __attribute__((target("sse4.2")))
#endif

#define CK_CRC32 16
#define CK_CRC32C 32

static int64_t ck_hardware = -1;

static inline uint32_t ck_le32(const uint8_t *p) { return (uint32_t)p[3] << 24 | (uint32_t)p[2] << 16 | (uint32_t)p[1] << 8 | p[0]; }
static inline uint64_t ck_le64(const uint8_t *p) { return (uint64_t)ck_le32(p + 4) << 32 | ck_le32(p); }

static int64_t ck_detect(void)
{
    int64_t f = 0;
#if defined(__aarch64__) && defined(__APPLE__)
    f = CK_CRC32 | CK_CRC32C;
#elif defined(__aarch64__) && defined(SAMALTAK_UEFI)
    uint64_t r;
    __asm__ volatile("mrs %0, ID_AA64ISAR0_EL1" : "=r"(r));
    if (((r >> 16) & 15) >= 1) f |= CK_CRC32 | CK_CRC32C;
#elif defined(__aarch64__) && defined(__linux__)
    unsigned long h = getauxval(AT_HWCAP);
    if (h & (1UL << 7)) f |= CK_CRC32 | CK_CRC32C;
#elif defined(__x86_64__)
    unsigned a, b, c, d;
    if (__get_cpuid(1, &a, &b, &c, &d) && (c & (1u << 20))) f |= CK_CRC32C;
#endif
    return f;
}

static inline int64_t ck_has(int64_t feature)
{
    if (ck_hardware < 0) ck_hardware = ck_detect();
    return ck_hardware & feature;
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
CK_T_CRC static uint32_t ck_crc_hw(uint32_t c, const uint8_t *p, int64_t n, int castagnoli)
{
    uint64_t c64 = c;
    for (; n >= 8; n -= 8, p += 8) c64 = _mm_crc32_u64(c64, ck_le64(p));
    c = (uint32_t)c64;
    for (; n > 0; n--, p++) c = _mm_crc32_u8(c, *p);
    return c;
}
#endif

static uint32_t crypto_crc32(uint32_t crc, const uint8_t *p, int64_t size, int64_t castagnoli)
{
#if defined(__aarch64__) || defined(__x86_64__)
    if (ck_has(castagnoli ? CK_CRC32C : CK_CRC32)) return ck_crc_hw(crc, p, size, (int)castagnoli);
#endif
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
! !

!CryptoPrimitives methodsFor: 'primitives'!
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
crc: crc bytes: p size: n castagnoli: castagnoli
	<c: 'uint32_t crypto_crc32(uint32_t crc, const uint8_t *p, int64_t size, int64_t castagnoli)'>
	^self error: 'not simulated'
! !
