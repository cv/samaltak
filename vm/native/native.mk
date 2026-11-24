# The VM's C that is not translated from Lowtalk: vendored libraries (vm/third_party, README.md there) and their glue
# (vm/native), compiled with flags of their own; included by vm/Makefile (hosted) and vm/uefi.mk (UEFI). Paths are
# relative to vm/ (NATIVE_DIR: vm/ itself, as the includer sees it).
NATIVE_DIR ?= .
MBEDTLS_DIR := $(NATIVE_DIR)/third_party/mbedtls
# all of mbedTLS's library; vm/native/mbedtls_config.h leaves out what we don't use, so most of the rest compiles to nothing
MBEDTLS_SRCS := $(sort $(wildcard $(MBEDTLS_DIR)/library/*.c))
NATIVE_GLUE_SRCS := $(NATIVE_DIR)/native/tls.c
NATIVE_SRCS := $(MBEDTLS_SRCS) $(NATIVE_GLUE_SRCS)
# The cryptography exports (native/crypto.h): libcrypto hosted, mbedTLS on UEFI; and on UEFI the C library's rest.
NATIVE_HOSTED_SRCS := $(NATIVE_DIR)/native/crypto_openssl.c
NATIVE_UEFI_SRCS := $(NATIVE_DIR)/native/crypto_mbedtls.c $(NATIVE_DIR)/native/uefi_libc.c
NATIVE_CPPFLAGS := -I$(MBEDTLS_DIR)/include -I$(NATIVE_DIR)/native '-DMBEDTLS_USER_CONFIG_FILE="samaltak_mbedtls_config.h"'
