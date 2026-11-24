/* No cryptography (crypto.h) where there is no libcrypto: on UEFI. Every export fails, and the image has none to call
   (UefiFFIStubMemory wraps none of them): System-Crypto's classes signal CryptoError there. docs/crypto.md. */
#include "crypto.h"

int64_t samaltak_crypto_digest(int64_t alg, const uint8_t *in, uint64_t inLen, uint8_t *out, uint64_t outLen)
{ (void)alg; (void)in; (void)inLen; (void)out; (void)outLen; return SAMALTAK_CRYPTO_FAILED; }
int64_t samaltak_crypto_digest_init(int64_t alg, uint8_t *state, uint64_t stateLen)
{ (void)alg; (void)state; (void)stateLen; return SAMALTAK_CRYPTO_FAILED; }
int64_t samaltak_crypto_digest_update(int64_t alg, uint8_t *state, uint64_t stateLen, const uint8_t *in, uint64_t inLen)
{ (void)alg; (void)state; (void)stateLen; (void)in; (void)inLen; return SAMALTAK_CRYPTO_FAILED; }
int64_t samaltak_crypto_digest_final(int64_t alg, uint8_t *state, uint64_t stateLen, uint8_t *out, uint64_t outLen)
{ (void)alg; (void)state; (void)stateLen; (void)out; (void)outLen; return SAMALTAK_CRYPTO_FAILED; }
int64_t samaltak_crypto_aead_key(int64_t alg, const uint8_t *key, uint64_t keyLen)
{ (void)alg; (void)key; (void)keyLen; return SAMALTAK_CRYPTO_FAILED; }
int64_t samaltak_crypto_aead(int64_t op, const uint8_t *nonceAad, uint64_t nonceAadLen, uint8_t *text, uint64_t textLen)
{ (void)op; (void)nonceAad; (void)nonceAadLen; (void)text; (void)textLen; return SAMALTAK_CRYPTO_FAILED; }
int64_t samaltak_crypto_x25519(const uint8_t *k, uint64_t kLen, const uint8_t *u, uint64_t uLen, uint8_t *out, uint64_t outLen)
{ (void)k; (void)kLen; (void)u; (void)uLen; (void)out; (void)outLen; return SAMALTAK_CRYPTO_FAILED; }
int64_t samaltak_crypto_public_key(const uint8_t *spki, uint64_t spkiLen)
{ (void)spki; (void)spkiLen; return SAMALTAK_CRYPTO_FAILED; }
int64_t samaltak_crypto_verify(int64_t key, int64_t params, const uint8_t *digest, uint64_t digestLen, const uint8_t *sig, uint64_t sigLen)
{ (void)key; (void)params; (void)digest; (void)digestLen; (void)sig; (void)sigLen; return SAMALTAK_CRYPTO_FAILED; }
int64_t samaltak_crypto_chacha20(const uint8_t *keyNonce, uint64_t keyNonceLen, int64_t counter, uint8_t *text, uint64_t textLen)
{ (void)keyNonce; (void)keyNonceLen; (void)counter; (void)text; (void)textLen; return SAMALTAK_CRYPTO_FAILED; }
int64_t samaltak_crypto_backend(uint8_t *out, uint64_t outLen)
{ (void)out; (void)outLen; return SAMALTAK_CRYPTO_FAILED; }
