/* The cryptography exports (crypto.h) on mbedTLS (vm/third_party/mbedtls), on UEFI. Hash states are mbedTLS's
   sha256 and sha512 contexts (plain structs) in the image's buffer. */
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <stdlib.h>
#include "mbedtls/sha256.h"
#include "mbedtls/sha512.h"
#include "mbedtls/gcm.h"
#include "mbedtls/chachapoly.h"
#include "mbedtls/chacha20.h"
#include "mbedtls/ecp.h"
#include "mbedtls/pk.h"
#include "mbedtls/rsa.h"
#include "mbedtls/md.h"
#include "mbedtls/version.h"
#include "crypto.h"

#define KIND_GCM 1
#define KIND_CHACHAPOLY 2
#define KIND_PUBLIC 3

#include "crypto_keys.h"
static void key_destroy(key_slot *s)
{
    if (s->kind == KIND_GCM) mbedtls_gcm_free(s->object);
    else if (s->kind == KIND_CHACHAPOLY) mbedtls_chachapoly_free(s->object);
    else if (s->kind == KIND_PUBLIC) mbedtls_pk_free(s->object);
    free(s->object);
    s->kind = 0;
    s->object = NULL;
}

static size_t digest_size(int64_t alg) { return alg == SAMALTAK_SHA256 ? 32 : alg == SAMALTAK_SHA384 ? 48 : alg == SAMALTAK_SHA512 ? 64 : 0; }
static mbedtls_md_type_t md_of(int64_t alg)
{
    return alg == SAMALTAK_SHA256 ? MBEDTLS_MD_SHA256 : alg == SAMALTAK_SHA384 ? MBEDTLS_MD_SHA384 : alg == SAMALTAK_SHA512 ? MBEDTLS_MD_SHA512 : MBEDTLS_MD_NONE;
}

int64_t samaltak_crypto_digest(int64_t alg, const uint8_t *in, uint64_t inLen, uint8_t *out, uint64_t outLen)
{
    size_t n = digest_size(alg);
    int r;
    if (n == 0 || outLen < n) return SAMALTAK_CRYPTO_REFUSED;
    r = alg == SAMALTAK_SHA256 ? mbedtls_sha256(in, inLen, out, 0) : mbedtls_sha512(in, inLen, out, alg == SAMALTAK_SHA384);
    return r ? SAMALTAK_CRYPTO_FAILED : (int64_t)n;
}
/* the state is copied in and out: the image's buffer need not be aligned */
int64_t samaltak_crypto_digest_init(int64_t alg, uint8_t *state, uint64_t stateLen)
{
    if (stateLen < SAMALTAK_CRYPTO_STATE) return SAMALTAK_CRYPTO_REFUSED;
    if (alg == SAMALTAK_SHA256) {
        mbedtls_sha256_context c; mbedtls_sha256_init(&c); mbedtls_sha256_starts(&c, 0); memcpy(state, &c, sizeof c); return 0;
    }
    if (alg == SAMALTAK_SHA384 || alg == SAMALTAK_SHA512) {
        mbedtls_sha512_context c; mbedtls_sha512_init(&c); mbedtls_sha512_starts(&c, alg == SAMALTAK_SHA384); memcpy(state, &c, sizeof c); return 0;
    }
    return SAMALTAK_CRYPTO_REFUSED;
}
int64_t samaltak_crypto_digest_update(int64_t alg, uint8_t *state, uint64_t stateLen, const uint8_t *in, uint64_t inLen)
{
    if (stateLen < SAMALTAK_CRYPTO_STATE) return SAMALTAK_CRYPTO_REFUSED;
    if (alg == SAMALTAK_SHA256) {
        mbedtls_sha256_context c; memcpy(&c, state, sizeof c); mbedtls_sha256_update(&c, in, inLen); memcpy(state, &c, sizeof c); return 0;
    }
    if (alg == SAMALTAK_SHA384 || alg == SAMALTAK_SHA512) {
        mbedtls_sha512_context c; memcpy(&c, state, sizeof c); mbedtls_sha512_update(&c, in, inLen); memcpy(state, &c, sizeof c); return 0;
    }
    return SAMALTAK_CRYPTO_REFUSED;
}
/* the digest of the state's bytes; the state is left as it was (the image may go on) */
int64_t samaltak_crypto_digest_final(int64_t alg, uint8_t *state, uint64_t stateLen, uint8_t *out, uint64_t outLen)
{
    size_t n = digest_size(alg);
    uint8_t full[64];
    if (stateLen < SAMALTAK_CRYPTO_STATE || n == 0 || outLen < n) return SAMALTAK_CRYPTO_REFUSED;
    if (alg == SAMALTAK_SHA256) { mbedtls_sha256_context c; memcpy(&c, state, sizeof c); mbedtls_sha256_finish(&c, out); return 32; }
    mbedtls_sha512_context c; memcpy(&c, state, sizeof c); mbedtls_sha512_finish(&c, full);
    memcpy(out, full, n);
    return (int64_t)n;
}

int64_t samaltak_crypto_aead_key(int64_t alg, const uint8_t *key, uint64_t keyLen)
{
    if (alg == SAMALTAK_AES_GCM && (keyLen == 16 || keyLen == 24 || keyLen == 32)) {
        mbedtls_gcm_context *c = calloc(1, sizeof *c);
        if (!c) return SAMALTAK_CRYPTO_FAILED;
        mbedtls_gcm_init(c);
        if (mbedtls_gcm_setkey(c, MBEDTLS_CIPHER_ID_AES, key, (unsigned)keyLen * 8)) { mbedtls_gcm_free(c); free(c); return SAMALTAK_CRYPTO_FAILED; }
        return key_handle(key_new(KIND_GCM, c));
    }
    if (alg == SAMALTAK_CHACHA20_POLY1305 && keyLen == 32) {
        mbedtls_chachapoly_context *c = calloc(1, sizeof *c);
        if (!c) return SAMALTAK_CRYPTO_FAILED;
        mbedtls_chachapoly_init(c);
        if (mbedtls_chachapoly_setkey(c, key)) { mbedtls_chachapoly_free(c); free(c); return SAMALTAK_CRYPTO_FAILED; }
        return key_handle(key_new(KIND_CHACHAPOLY, c));
    }
    return SAMALTAK_CRYPTO_REFUSED;
}
int64_t samaltak_crypto_aead(int64_t op, const uint8_t *nonceAad, uint64_t nonceAadLen, uint8_t *text, uint64_t textLen)
{
    int64_t h = op & 0xFFFFFF;
    size_t nonceLen = (size_t)((op >> 24) & 0xFFFF), n;
    int open = (int)((op >> 40) & 1), r;
    key_slot *s = key_get(h, KIND_GCM);
    if (!s) s = key_get(h, KIND_CHACHAPOLY);
    if (!s) return SAMALTAK_CRYPTO_STALE;
    if (nonceLen == 0 || nonceLen > nonceAadLen || textLen < 16) return SAMALTAK_CRYPTO_REFUSED;
    n = textLen - 16;
    const uint8_t *aad = nonceAad + nonceLen;
    size_t aadLen = nonceAadLen - nonceLen;
    if (s->kind == KIND_GCM) {
        r = open ? mbedtls_gcm_auth_decrypt(s->object, n, nonceAad, nonceLen, aad, aadLen, text + n, 16, text, text)
                 : mbedtls_gcm_crypt_and_tag(s->object, MBEDTLS_GCM_ENCRYPT, n, nonceAad, nonceLen, aad, aadLen, text, text, 16, text + n);
    } else {
        if (nonceLen != 12) return SAMALTAK_CRYPTO_REFUSED;
        r = open ? mbedtls_chachapoly_auth_decrypt(s->object, n, nonceAad, aad, aadLen, text + n, text, text)
                 : mbedtls_chachapoly_encrypt_and_tag(s->object, n, nonceAad, aad, aadLen, text, text, text + n);
    }
    if (r) return SAMALTAK_CRYPTO_FAILED;
    return open ? (int64_t)n : (int64_t)textLen;
}

/* blinding for the Montgomery ladder: no secret depends on it, so a hash of the inputs and a counter does */
typedef struct { uint8_t seed[64]; uint32_t counter; } blind_t;
static int blind_rng(void *p, unsigned char *out, size_t n)
{
    blind_t *b = p;
    uint8_t block[32];
    while (n > 0) {
        size_t k = n < 32 ? n : 32;
        memcpy(b->seed + 60, &b->counter, 4);
        b->counter++;
        mbedtls_sha256(b->seed, sizeof b->seed, block, 0);
        memcpy(out, block, k);
        out += k; n -= k;
    }
    return 0;
}
int64_t samaltak_crypto_x25519(const uint8_t *k, uint64_t kLen, const uint8_t *u, uint64_t uLen, uint8_t *out, uint64_t outLen)
{
    mbedtls_ecp_group grp;
    mbedtls_ecp_point P, R;
    mbedtls_mpi d;
    uint8_t kc[32];
    blind_t b;
    size_t olen = 0;
    int r, zero = 1;
    if (kLen != 32 || uLen != 32 || outLen < 32) return SAMALTAK_CRYPTO_REFUSED;
    /* decodeScalar25519 */
    memcpy(kc, k, 32);
    kc[0] &= 248; kc[31] &= 127; kc[31] |= 64;
    memcpy(b.seed, k, 32); memcpy(b.seed + 32, u, 28); b.counter = 0;
    mbedtls_ecp_group_init(&grp); mbedtls_ecp_point_init(&P); mbedtls_ecp_point_init(&R); mbedtls_mpi_init(&d);
    r = mbedtls_ecp_group_load(&grp, MBEDTLS_ECP_DP_CURVE25519);
    if (!r) r = mbedtls_mpi_read_binary_le(&d, kc, 32);
    if (!r) r = mbedtls_ecp_point_read_binary(&grp, &P, u, 32);
    if (!r) r = mbedtls_ecp_mul(&grp, &R, &d, &P, blind_rng, &b);
    if (!r) r = mbedtls_ecp_point_write_binary(&grp, &R, MBEDTLS_ECP_PF_UNCOMPRESSED, &olen, out, 32);
    mbedtls_ecp_group_free(&grp); mbedtls_ecp_point_free(&P); mbedtls_ecp_point_free(&R); mbedtls_mpi_free(&d);
    /* the point at infinity (a peer of small order) has no X to write: the all-zero secret */
    if (r || olen != 32) { memset(out, 0, 32); return 1; }
    for (int i = 0; i < 32; i++) if (out[i]) zero = 0;
    return zero;
}

int64_t samaltak_crypto_public_key(const uint8_t *spki, uint64_t spkiLen)
{
    mbedtls_pk_context *pk = calloc(1, sizeof *pk);
    if (!pk) return SAMALTAK_CRYPTO_FAILED;
    mbedtls_pk_init(pk);
    if (mbedtls_pk_parse_public_key(pk, spki, spkiLen)) { mbedtls_pk_free(pk); free(pk); return SAMALTAK_CRYPTO_FAILED; }
    return key_handle(key_new(KIND_PUBLIC, pk));
}
int64_t samaltak_crypto_verify(int64_t key, int64_t params, const uint8_t *digest, uint64_t digestLen, const uint8_t *sig, uint64_t sigLen)
{
    key_slot *s = key_get(key, KIND_PUBLIC);
    int scheme = (int)(params & 15), salt = (int)((params >> 8) & 0xFFFF) - 1;
    mbedtls_md_type_t md = md_of((params >> 4) & 15);
    if (!s) return SAMALTAK_CRYPTO_STALE;
    if (md == MBEDTLS_MD_NONE || digestLen != digest_size((params >> 4) & 15)) return SAMALTAK_CRYPTO_REFUSED;
    mbedtls_pk_context *pk = s->object;
    int isRsa = mbedtls_pk_get_type(pk) == MBEDTLS_PK_RSA;
    if ((scheme == SAMALTAK_ECDSA) == isRsa) return 0;
    if (scheme == SAMALTAK_PSS) {
        mbedtls_pk_rsassa_pss_options o = { md, salt < 0 ? MBEDTLS_RSA_SALT_LEN_ANY : salt };
        return mbedtls_pk_verify_ext(MBEDTLS_PK_RSASSA_PSS, &o, pk, md, digest, digestLen, sig, sigLen) == 0;
    }
    if (scheme == SAMALTAK_PKCS1) {
        if (mbedtls_rsa_set_padding(mbedtls_pk_rsa(*pk), MBEDTLS_RSA_PKCS_V15, MBEDTLS_MD_NONE)) return 0;
        /* mbedTLS answers a signature longer than the key's modulus as an error, as it is */
    }
    return mbedtls_pk_verify(pk, md, digest, digestLen, sig, sigLen) == 0;
}

int64_t samaltak_crypto_chacha20(const uint8_t *keyNonce, uint64_t keyNonceLen, int64_t counter, uint8_t *text, uint64_t textLen)
{
    if (keyNonceLen != 44 || counter < 0 || counter > 0xFFFFFFFFLL) return SAMALTAK_CRYPTO_REFUSED;
    return mbedtls_chacha20_crypt(keyNonce, keyNonce + 32, (uint32_t)counter, textLen, text, text) ? SAMALTAK_CRYPTO_FAILED : 0;
}

int64_t samaltak_crypto_backend(uint8_t *out, uint64_t outLen)
{
    const char *v = "mbedTLS " MBEDTLS_VERSION_STRING;
    size_t n = strlen(v);
    if (n > outLen) n = outLen;
    memcpy(out, v, n);
    return (int64_t)n;
}
