/* Samaltak's TLS engine (tls.c): a TLS 1.3 and 1.2 client on mbedTLS over memory buffers. docs/tls.md. */
#ifndef SAMALTAK_NATIVE_TLS_H
#define SAMALTAK_NATIVE_TLS_H
#include <stdint.h>

/* A step's answer, for a connection that exists: what it produced (ciphertext into out, or plaintext read) in the low
   24 bits, what it consumed (ciphertext from in, or plaintext written) in the next 24, and these flags above. -1: no
   such connection or store, -2: arguments it refuses. */
#define SAMALTAK_TLS_DONE    (1LL << 48) /* the handshake is done; a read: the peer's close_notify */
#define SAMALTAK_TLS_PENDING (1LL << 49) /* ciphertext waits in the engine: core_tls_take */
#define SAMALTAK_TLS_INPUT   (1LL << 50) /* it needs more ciphertext */
#define SAMALTAK_TLS_FAILED  (1LL << 51) /* the connection failed: core_tls_info 3 says why; send what it produced */

int64_t samaltak_tls_seed(const uint8_t *bytes, uint64_t n);
int64_t samaltak_tls_set_time(int64_t unixSeconds);
int64_t samaltak_tls_store_new(void);
int64_t samaltak_tls_store_add(int64_t store, const uint8_t *der, uint64_t n);
int64_t samaltak_tls_store_free(int64_t store);
int64_t samaltak_tls_new(int64_t store, const uint8_t *host, uint64_t n);
int64_t samaltak_tls_handshake(int64_t h, const uint8_t *in, uint64_t inLen, uint8_t *out, uint64_t outLen);
int64_t samaltak_tls_read(int64_t h, uint8_t *plain, uint64_t plainLen, const uint8_t *in, uint64_t inLen);
int64_t samaltak_tls_write(int64_t h, const uint8_t *plain, uint64_t plainLen, uint8_t *out, uint64_t outLen);
int64_t samaltak_tls_take(int64_t h, uint8_t *out, uint64_t outLen);
int64_t samaltak_tls_close(int64_t h, uint8_t *out, uint64_t outLen);
int64_t samaltak_tls_info(int64_t h, int64_t what, uint8_t *out, uint64_t outLen);
int64_t samaltak_tls_free(int64_t h);
int64_t samaltak_tls_now(void);
#endif
