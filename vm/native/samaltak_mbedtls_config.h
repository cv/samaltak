/* Samaltak's mbedTLS configuration (MBEDTLS_USER_CONFIG_FILE, applied after mbedTLS's default one): a TLS 1.3 and 1.2
   client over memory buffers (vm/native/tls.c), the same hosted and on UEFI. Entropy, the time and the trust anchors come
   from the image, so nothing here touches files, sockets, clocks or the OS's random source. docs/tls.md. */

/* no OS: the image moves the bytes, seeds the generator and tells the time */
#undef MBEDTLS_NET_C
#undef MBEDTLS_TIMING_C
#undef MBEDTLS_FS_IO
#undef MBEDTLS_PSA_ITS_FILE_C
#undef MBEDTLS_PSA_CRYPTO_STORAGE_C
#undef MBEDTLS_ENTROPY_C
#define MBEDTLS_NO_PLATFORM_ENTROPY
#define MBEDTLS_PSA_CRYPTO_EXTERNAL_RNG
#define MBEDTLS_PLATFORM_MS_TIME_ALT
#define MBEDTLS_PLATFORM_TIME_ALT
#define MBEDTLS_PLATFORM_GMTIME_R_ALT
#undef MBEDTLS_SELF_TEST
#undef MBEDTLS_DEBUG_C
#undef MBEDTLS_VERSION_FEATURES

/* a client of TLS 1.3 and 1.2 only: no server, DTLS, renegotiation or pre-shared keys */
#undef MBEDTLS_SSL_SRV_C
#undef MBEDTLS_SSL_PROTO_DTLS
#undef MBEDTLS_SSL_DTLS_HELLO_VERIFY
#undef MBEDTLS_SSL_DTLS_ANTI_REPLAY
#undef MBEDTLS_SSL_DTLS_CLIENT_PORT_REUSE
#undef MBEDTLS_SSL_DTLS_CONNECTION_ID
#undef MBEDTLS_SSL_DTLS_SRTP
#undef MBEDTLS_SSL_COOKIE_C
#undef MBEDTLS_SSL_TICKET_C
#undef MBEDTLS_SSL_EARLY_DATA
#undef MBEDTLS_SSL_TLS1_3_KEY_EXCHANGE_MODE_PSK_ENABLED
#undef MBEDTLS_SSL_TLS1_3_KEY_EXCHANGE_MODE_PSK_EPHEMERAL_ENABLED

/* TLS 1.2 with forward secrecy only: ECDHE with RSA or ECDSA certificates */
#undef MBEDTLS_KEY_EXCHANGE_PSK_ENABLED
#undef MBEDTLS_KEY_EXCHANGE_DHE_PSK_ENABLED
#undef MBEDTLS_KEY_EXCHANGE_ECDHE_PSK_ENABLED
#undef MBEDTLS_KEY_EXCHANGE_RSA_PSK_ENABLED
#undef MBEDTLS_KEY_EXCHANGE_RSA_ENABLED
#undef MBEDTLS_KEY_EXCHANGE_DHE_RSA_ENABLED
#undef MBEDTLS_KEY_EXCHANGE_ECDH_ECDSA_ENABLED
#undef MBEDTLS_KEY_EXCHANGE_ECDH_RSA_ENABLED
#undef MBEDTLS_KEY_EXCHANGE_ECJPAKE_ENABLED
#undef MBEDTLS_DHM_C
#undef MBEDTLS_ECJPAKE_C

/* ciphers, curves and formats no TLS server we talk to needs; certificates come as DER */
#undef MBEDTLS_ARIA_C
#undef MBEDTLS_CAMELLIA_C
#undef MBEDTLS_DES_C
#undef MBEDTLS_CMAC_C
#undef MBEDTLS_NIST_KW_C
#undef MBEDTLS_RIPEMD160_C
#undef MBEDTLS_LMS_C
#undef MBEDTLS_PKCS7_C
#undef MBEDTLS_X509_CSR_PARSE_C
#undef MBEDTLS_X509_CSR_WRITE_C
#undef MBEDTLS_X509_CRT_WRITE_C
#undef MBEDTLS_X509_CREATE_C
#undef MBEDTLS_PEM_PARSE_C
#undef MBEDTLS_PEM_WRITE_C
#undef MBEDTLS_ECP_DP_SECP192R1_ENABLED
#undef MBEDTLS_ECP_DP_SECP224R1_ENABLED
#undef MBEDTLS_ECP_DP_SECP192K1_ENABLED
#undef MBEDTLS_ECP_DP_SECP224K1_ENABLED
#undef MBEDTLS_ECP_DP_SECP256K1_ENABLED
#undef MBEDTLS_ECP_DP_BP256R1_ENABLED
#undef MBEDTLS_ECP_DP_BP384R1_ENABLED
#undef MBEDTLS_ECP_DP_BP512R1_ENABLED
#undef MBEDTLS_ECP_DP_CURVE448_ENABLED

/* the CPU's instructions: on Linux and macOS when the CPU has them; on UEFI arm64 always (as aesce.c assumes for AES
   off Linux: every arm64 machine the UEFI VM runs on has the Armv8 cryptographic extensions) */
#if defined(__aarch64__)
#  if defined(SAMALTAK_UEFI)
#    define MBEDTLS_SHA256_USE_ARMV8_A_CRYPTO_ONLY
#    define MBEDTLS_SHA512_USE_A64_CRYPTO_ONLY
#  else
#    define MBEDTLS_SHA256_USE_ARMV8_A_CRYPTO_IF_PRESENT
#    define MBEDTLS_SHA512_USE_A64_CRYPTO_IF_PRESENT
#  endif
#endif
