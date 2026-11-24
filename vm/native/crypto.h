/* Samaltak's cryptography exports (core_crypto_*, FFIPrimitives-crypto): hashes, AEADs, X25519, signature
   verification and ChaCha20's key stream, on libcrypto hosted (crypto_openssl.c); none on UEFI
   (crypto_none.c). Buffers are the image's, borrowed for the call: a hash's state, an AEAD's text (sealed and
   opened in place). Keys (AEAD and public) are handles into a table of SAMALTAK_CRYPTO_KEYS: the least recently used
   goes when it is full, and its handle (slot and generation) then answers SAMALTAK_CRYPTO_STALE, so the image makes it
   again. docs/crypto.md. */
#ifndef SAMALTAK_NATIVE_CRYPTO_H
#define SAMALTAK_NATIVE_CRYPTO_H
#include <stdint.h>

#define SAMALTAK_SHA256 1
#define SAMALTAK_SHA384 2
#define SAMALTAK_SHA512 3
#define SAMALTAK_AES_GCM 1
#define SAMALTAK_CHACHA20_POLY1305 2
/* verify's params: scheme | hash << 4 | (salt length + 1) << 8 (0: any salt length) */
#define SAMALTAK_PKCS1 1
#define SAMALTAK_PSS 2
#define SAMALTAK_ECDSA 3
#define SAMALTAK_CRYPTO_STATE 256     /* a hash state's bytes */
#define SAMALTAK_CRYPTO_KEYS 64
#define SAMALTAK_CRYPTO_FAILED (-1)   /* a tag that does not verify; a key that does not parse */
#define SAMALTAK_CRYPTO_STALE (-2)    /* a key handle whose key is gone: make it again */
#define SAMALTAK_CRYPTO_REFUSED (-3)  /* arguments refused */

int64_t samaltak_crypto_digest(int64_t alg, const uint8_t *in, uint64_t inLen, uint8_t *out, uint64_t outLen);
int64_t samaltak_crypto_digest_init(int64_t alg, uint8_t *state, uint64_t stateLen);
int64_t samaltak_crypto_digest_update(int64_t alg, uint8_t *state, uint64_t stateLen, const uint8_t *in, uint64_t inLen);
int64_t samaltak_crypto_digest_final(int64_t alg, uint8_t *state, uint64_t stateLen, uint8_t *out, uint64_t outLen);
/* AEAD: op is the key's handle | nonce length << 24 (16 bits) | 1 << 40 to open; nonceAad the nonce, then the additional data;
   text the plaintext and 16 bytes for the tag (seal) or the ciphertext and its tag (open), in place: the length of
   the result, SAMALTAK_CRYPTO_FAILED if the tag does not verify */
int64_t samaltak_crypto_aead_key(int64_t alg, const uint8_t *key, uint64_t keyLen);
int64_t samaltak_crypto_aead(int64_t op, const uint8_t *nonceAad, uint64_t nonceAadLen, uint8_t *text, uint64_t textLen);
/* X25519(k, u) into out (RFC 7748, both 32 bytes, little-endian): 0, or 1 if the result is all zeros */
int64_t samaltak_crypto_x25519(const uint8_t *k, uint64_t kLen, const uint8_t *u, uint64_t uLen, uint8_t *out, uint64_t outLen);
/* a public key from its DER SubjectPublicKeyInfo (RSA, EC P-256 / P-384): its handle */
int64_t samaltak_crypto_public_key(const uint8_t *spki, uint64_t spkiLen);
/* 1 if sig is the key's signature of digest, else 0 */
int64_t samaltak_crypto_verify(int64_t key, int64_t params, const uint8_t *digest, uint64_t digestLen, const uint8_t *sig, uint64_t sigLen);
/* text xor ChaCha20's key stream (RFC 8439) under keyNonce (the 32-byte key, the 12-byte nonce) from block counter */
int64_t samaltak_crypto_chacha20(const uint8_t *keyNonce, uint64_t keyNonceLen, int64_t counter, uint8_t *text, uint64_t textLen);
/* the backend's name and version into out: its length */
int64_t samaltak_crypto_backend(uint8_t *out, uint64_t outLen);
#endif
