/* The cryptography exports (crypto.h) on libcrypto (OpenSSL 3), hosted. Hash states are OpenSSL's SHA256_CTX and
   SHA512_CTX (plain structs) in the image's buffer. */
#define OPENSSL_SUPPRESS_DEPRECATED
#include <stdint.h>
#include <string.h>
#include <limits.h>
#include <openssl/evp.h>
#include <openssl/sha.h>
#include <openssl/rsa.h>
#include <openssl/x509.h>
#include <openssl/opensslv.h>
#include "crypto.h"

#define KIND_AEAD 1
#define KIND_PUBLIC 2

static void key_destroy_object(int kind, void *o);
#include "crypto_keys.h"
static void key_destroy(key_slot *s) { key_destroy_object(s->kind, s->object); s->kind = 0; s->object = NULL; }
static void key_destroy_object(int kind, void *o)
{
    if (kind == KIND_AEAD) EVP_CIPHER_CTX_free(o);
    else if (kind == KIND_PUBLIC) EVP_PKEY_free(o);
}

static const EVP_MD *md_of(int64_t alg)
{
    switch (alg) {
    case SAMALTAK_SHA256: return EVP_sha256();
    case SAMALTAK_SHA384: return EVP_sha384();
    case SAMALTAK_SHA512: return EVP_sha512();
    default: return NULL;
    }
}
static size_t digest_size(int64_t alg) { return alg == SAMALTAK_SHA256 ? 32 : alg == SAMALTAK_SHA384 ? 48 : alg == SAMALTAK_SHA512 ? 64 : 0; }

int64_t samaltak_crypto_digest(int64_t alg, const uint8_t *in, uint64_t inLen, uint8_t *out, uint64_t outLen)
{
    size_t n = digest_size(alg);
    if (n == 0 || outLen < n) return SAMALTAK_CRYPTO_REFUSED;
    /* the low-level contexts: OpenSSL 3's SHA256() fetches the algorithm from a provider on every call */
    if (alg == SAMALTAK_SHA256) { SHA256_CTX c; SHA256_Init(&c); SHA256_Update(&c, in, inLen); SHA256_Final(out, &c); }
    else if (alg == SAMALTAK_SHA384) { SHA512_CTX c; SHA384_Init(&c); SHA384_Update(&c, in, inLen); SHA384_Final(out, &c); }
    else { SHA512_CTX c; SHA512_Init(&c); SHA512_Update(&c, in, inLen); SHA512_Final(out, &c); }
    return (int64_t)n;
}
/* the state is copied in and out: the image's buffer need not be aligned */
int64_t samaltak_crypto_digest_init(int64_t alg, uint8_t *state, uint64_t stateLen)
{
    if (stateLen < SAMALTAK_CRYPTO_STATE) return SAMALTAK_CRYPTO_REFUSED;
    if (alg == SAMALTAK_SHA256) { SHA256_CTX c; SHA256_Init(&c); memcpy(state, &c, sizeof c); return 0; }
    if (alg == SAMALTAK_SHA384) { SHA512_CTX c; SHA384_Init(&c); memcpy(state, &c, sizeof c); return 0; }
    if (alg == SAMALTAK_SHA512) { SHA512_CTX c; SHA512_Init(&c); memcpy(state, &c, sizeof c); return 0; }
    return SAMALTAK_CRYPTO_REFUSED;
}
int64_t samaltak_crypto_digest_update(int64_t alg, uint8_t *state, uint64_t stateLen, const uint8_t *in, uint64_t inLen)
{
    if (stateLen < SAMALTAK_CRYPTO_STATE) return SAMALTAK_CRYPTO_REFUSED;
    if (alg == SAMALTAK_SHA256) { SHA256_CTX c; memcpy(&c, state, sizeof c); SHA256_Update(&c, in, inLen); memcpy(state, &c, sizeof c); return 0; }
    if (alg == SAMALTAK_SHA384 || alg == SAMALTAK_SHA512) {
        SHA512_CTX c; memcpy(&c, state, sizeof c);
        if (alg == SAMALTAK_SHA384) SHA384_Update(&c, in, inLen); else SHA512_Update(&c, in, inLen);
        memcpy(state, &c, sizeof c); return 0;
    }
    return SAMALTAK_CRYPTO_REFUSED;
}
/* the digest of the state's bytes; the state is left as it was (the image may go on) */
int64_t samaltak_crypto_digest_final(int64_t alg, uint8_t *state, uint64_t stateLen, uint8_t *out, uint64_t outLen)
{
    size_t n = digest_size(alg);
    if (stateLen < SAMALTAK_CRYPTO_STATE || n == 0 || outLen < n) return SAMALTAK_CRYPTO_REFUSED;
    if (alg == SAMALTAK_SHA256) { SHA256_CTX c; memcpy(&c, state, sizeof c); SHA256_Final(out, &c); }
    else { SHA512_CTX c; memcpy(&c, state, sizeof c); if (alg == SAMALTAK_SHA384) SHA384_Final(out, &c); else SHA512_Final(out, &c); }
    return (int64_t)n;
}

int64_t samaltak_crypto_aead_key(int64_t alg, const uint8_t *key, uint64_t keyLen)
{
    const EVP_CIPHER *cipher = NULL;
    if (alg == SAMALTAK_AES_GCM) cipher = keyLen == 16 ? EVP_aes_128_gcm() : keyLen == 24 ? EVP_aes_192_gcm() : keyLen == 32 ? EVP_aes_256_gcm() : NULL;
    else if (alg == SAMALTAK_CHACHA20_POLY1305 && keyLen == 32) cipher = EVP_chacha20_poly1305();
    if (!cipher) return SAMALTAK_CRYPTO_REFUSED;
    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    if (!ctx || EVP_CipherInit_ex(ctx, cipher, NULL, key, NULL, 1) != 1) { EVP_CIPHER_CTX_free(ctx); return SAMALTAK_CRYPTO_FAILED; }
    return key_handle(key_new(KIND_AEAD, ctx));
}
static int update(EVP_CIPHER_CTX *ctx, uint8_t *out, const uint8_t *in, uint64_t n)
{
    while (n > 0) {
        int k = n > (1u << 30) ? (1 << 30) : (int)n, outl;
        if (EVP_CipherUpdate(ctx, out, &outl, in, k) != 1) return 0;
        if (out) out += k;
        in += k; n -= (uint64_t)k;
    }
    return 1;
}
int64_t samaltak_crypto_aead(int64_t op, const uint8_t *nonceAad, uint64_t nonceAadLen, uint8_t *text, uint64_t textLen)
{
    key_slot *s = key_get(op & 0xFFFFFF, KIND_AEAD);
    int nonceLen = (int)((op >> 24) & 0xFFFF), open = (int)((op >> 40) & 1), outl;
    uint64_t n;
    if (!s) return SAMALTAK_CRYPTO_STALE;
    if (nonceLen == 0 || (uint64_t)nonceLen > nonceAadLen || textLen < 16) return SAMALTAK_CRYPTO_REFUSED;
    n = textLen - 16;
    EVP_CIPHER_CTX *ctx = s->object;
    if (EVP_CipherInit_ex(ctx, NULL, NULL, NULL, NULL, !open) != 1
        || EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_AEAD_SET_IVLEN, nonceLen, NULL) != 1
        || EVP_CipherInit_ex(ctx, NULL, NULL, NULL, nonceAad, !open) != 1) return SAMALTAK_CRYPTO_REFUSED;
    if (open && EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_AEAD_SET_TAG, 16, text + n) != 1) return SAMALTAK_CRYPTO_REFUSED;
    if (nonceAadLen > (uint64_t)nonceLen && !update(ctx, NULL, nonceAad + nonceLen, nonceAadLen - (uint64_t)nonceLen)) return SAMALTAK_CRYPTO_FAILED;
    if (!update(ctx, text, text, n)) return SAMALTAK_CRYPTO_FAILED;
    if (EVP_CipherFinal_ex(ctx, text + n, &outl) != 1) return SAMALTAK_CRYPTO_FAILED;
    if (open) return (int64_t)n;
    if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_AEAD_GET_TAG, 16, text + n) != 1) return SAMALTAK_CRYPTO_FAILED;
    return (int64_t)textLen;
}

int64_t samaltak_crypto_x25519(const uint8_t *k, uint64_t kLen, const uint8_t *u, uint64_t uLen, uint8_t *out, uint64_t outLen)
{
    EVP_PKEY *priv, *peer;
    EVP_PKEY_CTX *ctx = NULL;
    size_t n = 32;
    int ok = 0;
    if (kLen != 32 || uLen != 32 || outLen < 32) return SAMALTAK_CRYPTO_REFUSED;
    priv = EVP_PKEY_new_raw_private_key(EVP_PKEY_X25519, NULL, k, 32);
    peer = EVP_PKEY_new_raw_public_key(EVP_PKEY_X25519, NULL, u, 32);
    if (priv && peer && (ctx = EVP_PKEY_CTX_new(priv, NULL)) && EVP_PKEY_derive_init(ctx) == 1
        && EVP_PKEY_derive_set_peer(ctx, peer) == 1 && EVP_PKEY_derive(ctx, out, &n) == 1) ok = 1;
    EVP_PKEY_CTX_free(ctx);
    EVP_PKEY_free(priv);
    EVP_PKEY_free(peer);
    if (!priv || !peer) return SAMALTAK_CRYPTO_FAILED;
    /* OpenSSL refuses an all-zero shared secret (a peer of small order) */
    if (!ok) { memset(out, 0, 32); return 1; }
    return 0;
}

int64_t samaltak_crypto_public_key(const uint8_t *spki, uint64_t spkiLen)
{
    const unsigned char *p = spki;
    if (spkiLen > LONG_MAX) return SAMALTAK_CRYPTO_REFUSED;
    EVP_PKEY *k = d2i_PUBKEY(NULL, &p, (long)spkiLen);
    if (!k) return SAMALTAK_CRYPTO_FAILED;
    return key_handle(key_new(KIND_PUBLIC, k));
}
int64_t samaltak_crypto_verify(int64_t key, int64_t params, const uint8_t *digest, uint64_t digestLen, const uint8_t *sig, uint64_t sigLen)
{
    key_slot *s = key_get(key, KIND_PUBLIC);
    int scheme = (int)(params & 15), salt = (int)((params >> 8) & 0xFFFF) - 1, r;
    const EVP_MD *md = md_of((params >> 4) & 15);
    EVP_PKEY_CTX *ctx;
    if (!s) return SAMALTAK_CRYPTO_STALE;
    if (!md || digestLen != (uint64_t)EVP_MD_get_size(md)) return SAMALTAK_CRYPTO_REFUSED;
    int isRsa = EVP_PKEY_get_base_id(s->object) == EVP_PKEY_RSA;
    if ((scheme == SAMALTAK_ECDSA) == isRsa) return 0;
    ctx = EVP_PKEY_CTX_new(s->object, NULL);
    if (!ctx) return SAMALTAK_CRYPTO_FAILED;
    r = EVP_PKEY_verify_init(ctx) == 1 && EVP_PKEY_CTX_set_signature_md(ctx, md) == 1;
    if (r && scheme == SAMALTAK_PKCS1) r = EVP_PKEY_CTX_set_rsa_padding(ctx, RSA_PKCS1_PADDING) == 1;
    if (r && scheme == SAMALTAK_PSS)
        r = EVP_PKEY_CTX_set_rsa_padding(ctx, RSA_PKCS1_PSS_PADDING) == 1 && EVP_PKEY_CTX_set_rsa_mgf1_md(ctx, md) == 1
            && EVP_PKEY_CTX_set_rsa_pss_saltlen(ctx, salt < 0 ? RSA_PSS_SALTLEN_AUTO : salt) == 1;
    r = r && EVP_PKEY_verify(ctx, sig, sigLen, digest, digestLen) == 1;
    EVP_PKEY_CTX_free(ctx);
    return r ? 1 : 0;
}

int64_t samaltak_crypto_chacha20(const uint8_t *keyNonce, uint64_t keyNonceLen, int64_t counter, uint8_t *text, uint64_t textLen)
{
    uint8_t iv[16];
    int ok;
    if (keyNonceLen != 44 || counter < 0 || counter > 0xFFFFFFFFLL) return SAMALTAK_CRYPTO_REFUSED;
    iv[0] = (uint8_t)counter; iv[1] = (uint8_t)(counter >> 8); iv[2] = (uint8_t)(counter >> 16); iv[3] = (uint8_t)(counter >> 24);
    memcpy(iv + 4, keyNonce + 32, 12);
    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    ok = ctx && EVP_EncryptInit_ex(ctx, EVP_chacha20(), NULL, keyNonce, iv) == 1 && update(ctx, text, text, textLen);
    EVP_CIPHER_CTX_free(ctx);
    return ok ? 0 : SAMALTAK_CRYPTO_FAILED;
}

int64_t samaltak_crypto_backend(uint8_t *out, uint64_t outLen)
{
    const char *v = OpenSSL_version(OPENSSL_VERSION);
    size_t n = strlen(v);
    if (n > outLen) n = outLen;
    memcpy(out, v, n);
    return (int64_t)n;
}
