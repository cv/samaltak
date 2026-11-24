# The VM as a UEFI application (make uefi at the top): the C of GEN (VMTranslator generateVMInto:os:arch: with #uefi,
# docs/uefi.md) compiled freestanding for UEFI_TARGET (x86_64 or aarch64) with the ABI the JIT assumes (on x86-64 System V;
# calls into the firmware are ms_abi), linked into a static PIE that UefiImageWriter turns into PE32+. No C library:
# VM-UEFI's modules take its place.
GEN ?= gen-uefi
OBJ ?= build/uefi
UEFI_CC ?= clang
UEFI_LD ?= ld.lld
UEFI_TARGET ?= x86_64
# The C that is not translated from Lowtalk (native/native.mk): mbedTLS and the TLS engine, against the few C library
# headers of native/uefi-include (UefiLibC and native/uefi_libc.c are the library); on arm64 with the Armv8
# cryptographic extensions.
NATIVE_DIR := $(patsubst %/,%,$(dir $(lastword $(MAKEFILE_LIST))))
include $(NATIVE_DIR)/native/native.mk
UEFI_CFLAGS := -target $(UEFI_TARGET)-unknown-none-elf -ffreestanding -fno-builtin -fno-stack-protector -fPIE -mno-red-zone \
	-fno-math-errno -ffp-contract=off -ftls-model=local-exec -O2 -std=gnu11 -fsigned-char -DSAMALTAK_UEFI -I$(GEN) -MMD -MP \
	-I$(NATIVE_DIR)/native -Wall -Wextra -Wno-unused-parameter -Wno-unused-function -Wno-type-limits -Wno-parentheses -Wno-unused-value -Wno-self-assign
OBJS := $(patsubst $(GEN)/%.c,$(OBJ)/%.o,$(wildcard $(GEN)/*.c))
UEFI_NATIVE_CFLAGS := -target $(UEFI_TARGET)-unknown-none-elf -ffreestanding -fno-stack-protector -fPIE -mno-red-zone \
	-fno-math-errno -ffp-contract=off -ftls-model=local-exec -O2 -std=gnu11 -DSAMALTAK_UEFI -MMD -MP \
	$(if $(filter aarch64,$(UEFI_TARGET)),-march=armv8-a+crypto) -nostdlibinc -I$(NATIVE_DIR)/native/uefi-include $(NATIVE_CPPFLAGS)
NATIVE_OBJS := $(patsubst $(NATIVE_DIR)/%.c,$(OBJ)/native-src/%.o,$(NATIVE_SRCS) $(NATIVE_UEFI_SRCS))

$(OBJ)/samaltak.elf: $(OBJS) $(NATIVE_OBJS)
	$(UEFI_LD) -pie --no-dynamic-linker -z norelro -e efi_main -o $@ $(OBJS) $(NATIVE_OBJS)

$(OBJ)/native-src/%.o: $(NATIVE_DIR)/%.c
	@mkdir -p $(dir $@)
	$(if $(BRIEF),@echo "cc   $<";) $(UEFI_CC) $(UEFI_NATIVE_CFLAGS) -c -o $@ $<

$(OBJ)/%.o: $(GEN)/%.c
	@mkdir -p $(OBJ)
	$(if $(BRIEF),@echo "cc   $<";) $(UEFI_CC) $(UEFI_CFLAGS) -c -o $@ $<

-include $(OBJS:.o=.d) $(NATIVE_OBJS:.o=.d)
