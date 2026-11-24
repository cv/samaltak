/* Samaltak's TLS engine: a TLS 1.3 and 1.2 client on mbedTLS (vm/third_party/mbedtls) over memory buffers. The image
   moves the ciphertext over its own TCP (UEFI's NetworkStack) or the OS's; each step takes the ciphertext the image
   has received and room for what to send, borrowed for the call only, so a record is copied once on its way in (into
   mbedTLS's record buffer, where it is decrypted) and once on its way out. Entropy (seed), the time (set_time) and the
   trust anchors (store_add) come from the image; nothing here calls the OS or the firmware. The calls take scalars and
   byte ranges only, so each is an approved vm:core export (FFIPrimitives-tls). docs/tls.md. */
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <stdlib.h>
#include <time.h>
#include "mbedtls/ssl.h"
#include "mbedtls/ctr_drbg.h"
#include "mbedtls/x509_crt.h"
#include "mbedtls/error.h"
#include "mbedtls/platform.h"
#include "mbedtls/platform_time.h"
#include "psa/crypto.h"
#include "tls.h"

#define TLS_STORES 16
#define TLS_CONNECTIONS 64
#define TLS_COUNT_MAX 0xFFFFFFu
#define TLS_PENDING_MAX (1u << 20)

typedef struct {
    mbedtls_ssl_config conf;
    mbedtls_x509_crt cas;
    int refs; /* the image's, until store_free, and one per connection */
} tls_store;

typedef struct {
    mbedtls_ssl_context ssl;
    int store;
    const uint8_t *in; size_t inLen, inPos;   /* this call's ciphertext received */
    uint8_t *out; size_t outLen, outPos;      /* this call's room for ciphertext to send */
    uint8_t *pend; size_t pendLen, pendCap;   /* ciphertext produced without room: goes first */
    int error;                                /* why it failed, once it has */
    int closed;                               /* the peer's close_notify came */
} tls_conn;

static tls_store *stores[TLS_STORES];
static tls_conn *conns[TLS_CONNECTIONS];
static mbedtls_ctr_drbg_context drbg;
static const uint8_t *seedBytes; static size_t seedLen, seedPos;
static int ready;
static int64_t nowSeconds;
static const char *alpn[] = { "http/1.1", NULL };
/* AES-GCM first (the CPU's instructions), then ChaCha20-Poly1305; TLS 1.2 with ECDHE and AEADs only */
static const int suites[] = {
    MBEDTLS_TLS1_3_AES_128_GCM_SHA256, MBEDTLS_TLS1_3_AES_256_GCM_SHA384, MBEDTLS_TLS1_3_CHACHA20_POLY1305_SHA256,
    MBEDTLS_TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256, MBEDTLS_TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,
    MBEDTLS_TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384, MBEDTLS_TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,
    MBEDTLS_TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256, MBEDTLS_TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256,
    0
};

/* the platform's hooks: randomness, time */
static int seed_entropy(void *p, unsigned char *out, size_t n)
{
    if (seedLen - seedPos < n) return MBEDTLS_ERR_CTR_DRBG_ENTROPY_SOURCE_FAILED;
    memcpy(out, seedBytes + seedPos, n);
    seedPos += n;
    return 0;
}
psa_status_t mbedtls_psa_external_get_random(mbedtls_psa_external_random_context_t *ctx, uint8_t *out, size_t n, size_t *len)
{
    (void)ctx;
    *len = 0;
    if (!ready) return PSA_ERROR_INSUFFICIENT_ENTROPY;
    while (n > 0) {
        size_t k = n < MBEDTLS_CTR_DRBG_MAX_REQUEST ? n : MBEDTLS_CTR_DRBG_MAX_REQUEST;
        if (mbedtls_ctr_drbg_random(&drbg, out, k) != 0) return PSA_ERROR_INSUFFICIENT_ENTROPY;
        out += k; n -= k; *len += k;
    }
    return PSA_SUCCESS;
}
int64_t samaltak_tls_now(void) { return nowSeconds; }
mbedtls_ms_time_t mbedtls_ms_time(void) { return (mbedtls_ms_time_t)nowSeconds * 1000; }
static mbedtls_time_t tls_time(mbedtls_time_t *t) { if (t) *t = nowSeconds; return nowSeconds; }
struct tm *mbedtls_platform_gmtime_r(const mbedtls_time_t *tt, struct tm *tm)
{
    int64_t s = *tt, days = s / 86400, rem = s % 86400;
    if (rem < 0) { rem += 86400; days--; }
    tm->tm_hour = (int)(rem / 3600); tm->tm_min = (int)(rem % 3600 / 60); tm->tm_sec = (int)(rem % 60);
    /* civil_from_days (Howard Hinnant's algorithm) */
    int64_t z = days + 719468, era = (z >= 0 ? z : z - 146096) / 146097;
    unsigned doe = (unsigned)(z - era * 146097), yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    int64_t y = (int64_t)yoe + era * 400;
    unsigned doy = doe - (365 * yoe + yoe / 4 - yoe / 100), mp = (5 * doy + 2) / 153;
    unsigned d = doy - (153 * mp + 2) / 5 + 1, m = mp < 10 ? mp + 3 : mp - 9;
    tm->tm_year = (int)(y + (m <= 2) - 1900); tm->tm_mon = (int)m - 1; tm->tm_mday = (int)d;
    tm->tm_wday = (int)(((days % 7) + 11) % 7); tm->tm_yday = 0; tm->tm_isdst = 0;
    return tm;
}

/* ciphertext in and out of mbedTLS: the call's slices, the pending buffer when the out slice is full */
static int pend_append(tls_conn *c, const unsigned char *buf, size_t n)
{
    if (c->pendLen + n > c->pendCap) {
        size_t cap = c->pendCap ? c->pendCap : 4096;
        while (cap < c->pendLen + n) cap *= 2;
        if (cap > TLS_PENDING_MAX) return MBEDTLS_ERR_SSL_ALLOC_FAILED;
        uint8_t *p = realloc(c->pend, cap);
        if (!p) return MBEDTLS_ERR_SSL_ALLOC_FAILED;
        c->pend = p; c->pendCap = cap;
    }
    memcpy(c->pend + c->pendLen, buf, n);
    c->pendLen += n;
    return (int)n;
}
static int bio_send(void *p, const unsigned char *buf, size_t n)
{
    tls_conn *c = p;
    if (c->pendLen == 0 && c->outPos < c->outLen) {
        size_t k = c->outLen - c->outPos;
        if (k > n) k = n;
        memcpy(c->out + c->outPos, buf, k);
        c->outPos += k;
        return (int)k;
    }
    return pend_append(c, buf, n);
}
static int bio_recv(void *p, unsigned char *buf, size_t n)
{
    tls_conn *c = p;
    size_t have = c->inLen - c->inPos;
    if (have == 0) return MBEDTLS_ERR_SSL_WANT_READ;
    if (n > have) n = have;
    memcpy(buf, c->in + c->inPos, n);
    c->inPos += n;
    return (int)n;
}
static void drain(tls_conn *c)
{
    size_t k = c->outLen - c->outPos;
    if (k > c->pendLen) k = c->pendLen;
    if (k == 0) return;
    memcpy(c->out + c->outPos, c->pend, k);
    c->outPos += k;
    memmove(c->pend, c->pend + k, c->pendLen - k);
    c->pendLen -= k;
}
static tls_conn *get(int64_t h) { return h >= 1 && h <= TLS_CONNECTIONS ? conns[h - 1] : NULL; }
static void begin(tls_conn *c, const uint8_t *in, uint64_t inLen, uint8_t *out, uint64_t outLen)
{
    c->in = in; c->inLen = inLen > TLS_COUNT_MAX ? TLS_COUNT_MAX : inLen; c->inPos = 0;
    c->out = out; c->outLen = outLen > TLS_COUNT_MAX ? TLS_COUNT_MAX : outLen; c->outPos = 0;
    drain(c);
}
static int64_t end(tls_conn *c, size_t produced, size_t consumed, int64_t flags)
{
    c->in = NULL; c->inLen = c->inPos = 0;
    c->out = NULL; c->outLen = c->outPos = 0;
    if (c->pendLen > 0) flags |= SAMALTAK_TLS_PENDING;
    if (c->error) flags |= SAMALTAK_TLS_FAILED;
    return (int64_t)produced | ((int64_t)consumed << 24) | flags;
}
static int64_t status(tls_conn *c, int r)
{
    if (r == MBEDTLS_ERR_SSL_WANT_READ) return SAMALTAK_TLS_INPUT;
    if (r == MBEDTLS_ERR_SSL_WANT_WRITE) return 0;
    if (!c->error) c->error = r;
    return 0;
}

/* setup */
int64_t samaltak_tls_seed(const uint8_t *bytes, uint64_t n)
{
    int r;
    if (n < 96) return -2;
    seedBytes = bytes; seedLen = n; seedPos = 0;
    if (!ready) {
        mbedtls_ctr_drbg_init(&drbg);
        r = mbedtls_ctr_drbg_seed(&drbg, seed_entropy, NULL, NULL, 0);
        if (r == 0) {
            ready = 1;
            mbedtls_platform_set_time(tls_time);
            if (psa_crypto_init() != PSA_SUCCESS) { ready = 0; r = -3; }
        }
    } else {
        r = mbedtls_ctr_drbg_reseed(&drbg, NULL, 0);
    }
    seedBytes = NULL; seedLen = seedPos = 0;
    return r;
}
int64_t samaltak_tls_set_time(int64_t unixSeconds) { nowSeconds = unixSeconds; return 0; }

static void store_release(int i)
{
    tls_store *s = stores[i];
    if (--s->refs > 0) return;
    mbedtls_ssl_config_free(&s->conf);
    mbedtls_x509_crt_free(&s->cas);
    free(s);
    stores[i] = NULL;
}
int64_t samaltak_tls_store_new(void)
{
    if (!ready) return -2;
    for (int i = 0; i < TLS_STORES; i++) if (!stores[i]) {
        tls_store *s = calloc(1, sizeof *s);
        if (!s) return -3;
        mbedtls_x509_crt_init(&s->cas);
        mbedtls_ssl_config_init(&s->conf);
        int r = mbedtls_ssl_config_defaults(&s->conf, MBEDTLS_SSL_IS_CLIENT, MBEDTLS_SSL_TRANSPORT_STREAM, MBEDTLS_SSL_PRESET_DEFAULT);
        if (r == 0) r = mbedtls_ssl_conf_alpn_protocols(&s->conf, alpn);
        if (r) { mbedtls_ssl_config_free(&s->conf); free(s); return r; }
        mbedtls_ssl_conf_rng(&s->conf, mbedtls_ctr_drbg_random, &drbg);
        mbedtls_ssl_conf_ciphersuites(&s->conf, suites);
        mbedtls_ssl_conf_authmode(&s->conf, MBEDTLS_SSL_VERIFY_REQUIRED);
        mbedtls_ssl_conf_ca_chain(&s->conf, &s->cas, NULL);
        s->refs = 1;
        stores[i] = s;
        return i + 1;
    }
    return -4;
}
int64_t samaltak_tls_store_add(int64_t store, const uint8_t *der, uint64_t n)
{
    if (store < 1 || store > TLS_STORES || !stores[store - 1]) return -1;
    return mbedtls_x509_crt_parse_der(&stores[store - 1]->cas, der, n);
}
int64_t samaltak_tls_store_free(int64_t store)
{
    if (store < 1 || store > TLS_STORES || !stores[store - 1]) return -1;
    store_release((int)store - 1);
    return 0;
}

/* connections */
int64_t samaltak_tls_new(int64_t store, const uint8_t *host, uint64_t n)
{
    char name[256];
    if (store < 1 || store > TLS_STORES || !stores[store - 1]) return -1;
    if (n == 0 || n >= sizeof name || memchr(host, 0, n)) return -2;
    memcpy(name, host, n);
    name[n] = 0;
    for (int i = 0; i < TLS_CONNECTIONS; i++) if (!conns[i]) {
        tls_conn *c = calloc(1, sizeof *c);
        if (!c) return -3;
        mbedtls_ssl_init(&c->ssl);
        int r = mbedtls_ssl_setup(&c->ssl, &stores[store - 1]->conf);
        if (r == 0) r = mbedtls_ssl_set_hostname(&c->ssl, name);
        if (r) { mbedtls_ssl_free(&c->ssl); free(c); return r; }
        mbedtls_ssl_set_bio(&c->ssl, c, bio_send, bio_recv, NULL);
        c->store = (int)store - 1;
        stores[c->store]->refs++;
        conns[i] = c;
        return i + 1;
    }
    return -4;
}
int64_t samaltak_tls_handshake(int64_t h, const uint8_t *in, uint64_t inLen, uint8_t *out, uint64_t outLen)
{
    tls_conn *c = get(h);
    int64_t flags = 0;
    if (!c) return -1;
    begin(c, in, inLen, out, outLen);
    if (!c->error) {
        int r = mbedtls_ssl_handshake(&c->ssl);
        flags = r == 0 ? SAMALTAK_TLS_DONE : status(c, r);
    }
    return end(c, c->outPos, c->inPos, flags);
}
int64_t samaltak_tls_read(int64_t h, uint8_t *plain, uint64_t plainLen, const uint8_t *in, uint64_t inLen)
{
    tls_conn *c = get(h);
    size_t got = 0;
    int64_t flags = 0;
    if (!c) return -1;
    if (plainLen > TLS_COUNT_MAX) plainLen = TLS_COUNT_MAX;
    begin(c, in, inLen, NULL, 0);
    if (c->closed) flags = SAMALTAK_TLS_DONE;
    while (!c->error && !c->closed && got < plainLen) {
        int r = mbedtls_ssl_read(&c->ssl, plain + got, plainLen - got);
        if (r > 0) { got += (size_t)r; continue; }
        if (r == MBEDTLS_ERR_SSL_RECEIVED_NEW_SESSION_TICKET) continue;
        if (r == 0 || r == MBEDTLS_ERR_SSL_PEER_CLOSE_NOTIFY) { c->closed = 1; flags = SAMALTAK_TLS_DONE; break; }
        flags = status(c, r);
        break;
    }
    return end(c, got, c->inPos, flags);
}
int64_t samaltak_tls_write(int64_t h, const uint8_t *plain, uint64_t plainLen, uint8_t *out, uint64_t outLen)
{
    tls_conn *c = get(h);
    size_t sent = 0;
    int64_t flags = 0;
    if (!c) return -1;
    if (plainLen > TLS_COUNT_MAX) plainLen = TLS_COUNT_MAX;
    begin(c, NULL, 0, out, outLen);
    /* records until the plaintext is all sent or the room is full */
    while (!c->error && sent < plainLen && c->pendLen == 0) {
        int r = mbedtls_ssl_write(&c->ssl, plain + sent, plainLen - sent);
        if (r >= 0) { sent += (size_t)r; continue; }
        flags = status(c, r);
        break;
    }
    return end(c, c->outPos, sent, flags);
}
int64_t samaltak_tls_take(int64_t h, uint8_t *out, uint64_t outLen)
{
    tls_conn *c = get(h);
    if (!c) return -1;
    begin(c, NULL, 0, out, outLen);
    return end(c, c->outPos, 0, 0);
}
int64_t samaltak_tls_close(int64_t h, uint8_t *out, uint64_t outLen)
{
    tls_conn *c = get(h);
    if (!c) return -1;
    begin(c, NULL, 0, out, outLen);
    if (!c->error) {
        int r = mbedtls_ssl_close_notify(&c->ssl);
        if (r) status(c, r);
    }
    return end(c, c->outPos, 0, SAMALTAK_TLS_DONE);
}
static size_t put(uint8_t *out, size_t at, size_t n, const char *s)
{
    while (s && *s && at < n) out[at++] = (uint8_t)*s++;
    return at;
}
/* text about the connection into out: 0 the version, 1 the cipher suite, 2 the protocol ALPN chose, 3 why it failed */
int64_t samaltak_tls_info(int64_t h, int64_t what, uint8_t *out, uint64_t outLen)
{
    tls_conn *c = get(h);
    char buf[512];
    size_t k = 0;
    if (!c) return -1;
    switch (what) {
    case 0: k = put(out, 0, outLen, mbedtls_ssl_get_version(&c->ssl)); break;
    case 1: k = put(out, 0, outLen, mbedtls_ssl_get_ciphersuite(&c->ssl)); break;
    case 2: k = put(out, 0, outLen, mbedtls_ssl_get_alpn_protocol(&c->ssl)); break;
    case 3: {
        uint32_t v;
        if (!c->error) break;
        mbedtls_strerror(c->error, buf, sizeof buf);
        k = put(out, 0, outLen, buf);
        v = mbedtls_ssl_get_verify_result(&c->ssl);
        if (c->error == MBEDTLS_ERR_X509_CERT_VERIFY_FAILED && v != 0 && v != (uint32_t)-1) {
            int n = mbedtls_x509_crt_verify_info(buf, sizeof buf, "", v);
            if (n > 0) {
                for (int i = 0; i < n; i++) if (buf[i] == '\n') buf[i] = i == n - 1 ? 0 : ';';
                k = put(out, k, outLen, ": ");
                k = put(out, k, outLen, buf);
            }
        }
        break;
    }
    default: return -2;
    }
    return (int64_t)k;
}
int64_t samaltak_tls_free(int64_t h)
{
    tls_conn *c = get(h);
    if (!c) return -1;
    mbedtls_ssl_free(&c->ssl);
    store_release(c->store);
    free(c->pend);
    free(c);
    conns[h - 1] = NULL;
    return 0;
}
