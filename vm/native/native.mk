# The VM's C that is not translated from Lowtalk (vm/native), compiled with flags of their own; included by
# vm/Makefile (hosted) and vm/uefi.mk (UEFI). Paths are relative to vm/ (NATIVE_DIR: vm/ itself, as the includer sees it).
NATIVE_DIR ?= .
# nvrtc.c: NVRTC behind dlopen (hosted; stubs on UEFI).
NATIVE_SRCS := $(NATIVE_DIR)/native/nvrtc.c
# The cryptography exports (native/crypto.h): libcrypto hosted, none on UEFI (crypto_none.c).
NATIVE_HOSTED_SRCS := $(NATIVE_DIR)/native/crypto_openssl.c
NATIVE_UEFI_SRCS := $(NATIVE_DIR)/native/crypto_none.c
NATIVE_CPPFLAGS := -I$(NATIVE_DIR)/native
