# Samaltak VM. `make` → build/samaltak. NO_PLATFORM=1 builds a headless-only VM.
# The sources are gen/: C translated from the Lowtalk modules in src/VM-Core and src/VM-Platform (make translate at
# the top level regenerates them); gen/sources.mk says which files make the core and which the platform layer, and
# which of them are for one OS only (VM_CORE_SOURCES_LINUX ...: this build adds those of its uname -s) or for one CPU
# (VM_CORE_SOURCES_X86_64: this build adds those of its uname -m, arm64's on any CPU but x86-64).
# macOS: Homebrew sdl3 and openssl@3, clang. Linux: sdl3, shaderc (GLSL → SPIR-V for SDL_GPU on Vulkan), OpenSSL 3
# and libwayland-client (desktop windows);
# clang (linked with lld if there is one) when it is installed, else cc; CC=gcc builds with gcc.
# Profile-guided (clang): pgo/<os>-<arch>.profdata (pgo/darwin-arm64.profdata, pgo/linux-arm64.profdata), if there is one
# for this platform and this clang reads it, steers optimization; `make pgo IMAGE=...` retrains it (llvm-profdata of
# clang's version: LLVM_PROFDATA=...). NO_PGO=1 skips it.
# BRIEF=1 prints one line per file instead of the commands.
UNAME_S := $(shell uname -s)
OS := $(shell echo $(UNAME_S) | tr a-z A-Z)
ARCH := $(if $(filter x86_64 amd64,$(shell uname -m)),X86_64,ARM64)
CC ?= cc
ifeq ($(and $(filter default,$(origin CC)),$(filter Linux,$(UNAME_S))),Linux)
  # clang's interpreter loop is about 6 % faster than gcc 13's (Cortex-X925, without a profile)
  CC := $(if $(shell command -v clang 2>/dev/null),clang,cc)
endif
IS_CLANG := $(shell $(CC) --version 2>/dev/null | grep -q clang && echo yes)
ifeq ($(IS_CLANG),yes)
  CFLAGS ?= -O2 -g -flto
  # LTO through lld (the system linker would need clang's LLVMgold plugin)
  ifeq ($(UNAME_S),Linux)
    LDFLAGS += $(if $(shell command -v ld.lld 2>/dev/null),-fuse-ld=lld)
  endif
else
  # gcc: -flto=auto spreads the link over the cores. Its extra warnings about generated code are not bugs: comparisons
  # always true for some types, && inside ||, uninitialized locals on paths the code never takes, and messages cut to
  # the error buffer's size on purpose.
  CFLAGS ?= -O2 -g -flto=auto
  CFLAGS += -Wno-type-limits -Wno-parentheses -Wno-maybe-uninitialized -Wno-format-truncation
endif
CFLAGS += -std=gnu11 -Wall -Wextra -Wno-unused-parameter -MMD -MP -Igen
ifeq ($(UNAME_S),Darwin)
  CFLAGS += -D_DARWIN_C_SOURCE
  OS_PLATFORM_LIBS := -framework CoreVideo -lobjc
else
  # The VM was written for Darwin's arm64 ABI, where char is signed; Linux's makes it unsigned.
  CFLAGS += -D_GNU_SOURCE -fsigned-char
  OS_PLATFORM_LIBS := $(shell pkg-config --libs shaderc 2>/dev/null || echo -lshaderc_shared)
  # libwayland-client: desktop windows as wlr-layer-shell surfaces (WaylandDesktop).
  OS_PLATFORM_LIBS += $(shell pkg-config --libs wayland-client 2>/dev/null || echo -lwayland-client)
  OS_PLATFORM_CFLAGS := $(shell pkg-config --cflags wayland-client 2>/dev/null)
endif
LDLIBS += -lm -lpthread
ifeq ($(UNAME_S),Linux)
  LDLIBS += -ldl
endif

BUILD := build
PGO_PROFILE := pgo/$(shell echo $(UNAME_S) | tr A-Z a-z)-$(if $(filter X86_64,$(ARCH)),x86_64,arm64).profdata
# llvm-profdata of clang's own version (a profile is read only by an LLVM as new as the one that wrote it)
LLVM_PROFDATA ?= $(firstword $(wildcard $(dir $(realpath $(shell command -v $(CC) 2>/dev/null)))llvm-profdata) \
  $(shell xcrun -f llvm-profdata 2>/dev/null || command -v llvm-profdata))
ifneq ($(IS_CLANG),yes)
  # The profile is clang's (llvm-profdata); gcc builds without it.
  NO_PGO := 1
endif
ifeq ($(and $(wildcard $(PGO_PROFILE)),$(if $(NO_PGO)$(PGO_GEN),,yes)),yes)
  # a profile this clang cannot read (an older LLVM than the one that wrote it): build without it
  ifneq ($(shell $(CC) -fprofile-instr-use=$(PGO_PROFILE) -x c -c -o /dev/null /dev/null 2>/dev/null && echo ok),ok)
    $(warning $(PGO_PROFILE) is not readable by $(CC): building without profile-guided optimization)
    NO_PGO := 1
  endif
endif
ifneq ($(PGO_GEN),)
  CFLAGS += -fprofile-instr-generate=$(CURDIR)/$(BUILD)/prof/%p.profraw
  LDFLAGS += -fprofile-instr-generate
else ifeq ($(and $(wildcard $(PGO_PROFILE)),$(if $(NO_PGO),,yes)),yes)
  CFLAGS += -fprofile-instr-use=$(PGO_PROFILE) -Wno-profile-instr-out-of-date -Wno-profile-instr-unprofiled
  PGO_DEP := $(PGO_PROFILE)
endif
include gen/sources.mk
CORE_SRCS := $(addprefix gen/,$(VM_CORE_SOURCES) $(VM_CORE_SOURCES_$(OS)) $(VM_CORE_SOURCES_$(ARCH)))
HEADLESS_SRCS := $(addprefix gen/,$(VM_HEADLESS_SOURCES) $(VM_HEADLESS_SOURCES_$(OS)) $(VM_HEADLESS_SOURCES_$(ARCH)))
PLATFORM_SRCS := $(addprefix gen/,$(VM_PLATFORM_SOURCES) $(VM_PLATFORM_SOURCES_$(OS)) $(VM_PLATFORM_SOURCES_$(ARCH)))

SDL_CFLAGS := $(shell pkg-config --cflags sdl3 2>/dev/null)
SDL_LIBS := $(shell pkg-config --libs sdl3 2>/dev/null)
ifeq ($(SDL_LIBS),)
  ifneq ($(wildcard /opt/homebrew/include/SDL3/SDL.h),)
    SDL_CFLAGS := -I/opt/homebrew/include
    SDL_LIBS := -L/opt/homebrew/lib -Wl,-rpath,/opt/homebrew/lib -lSDL3
  endif
endif

# OpenSSL 3 (TLS): pkg-config, else Homebrew's keg-only openssl@3.
SSL_CFLAGS := $(shell pkg-config --cflags openssl 2>/dev/null)
SSL_LIBS := $(shell pkg-config --libs openssl 2>/dev/null)
ifeq ($(SSL_LIBS),)
  SSL_PREFIX := $(shell brew --prefix openssl@3 2>/dev/null)
  SSL_CFLAGS := $(if $(SSL_PREFIX),-I$(SSL_PREFIX)/include)
  SSL_LIBS := $(if $(SSL_PREFIX),-L$(SSL_PREFIX)/lib) -lssl -lcrypto
endif

ifneq ($(and $(PLATFORM_SRCS),$(SDL_LIBS),$(if $(NO_PLATFORM),,yes)),)
  VARIANT := platform
  SRCS := $(CORE_SRCS) $(PLATFORM_SRCS)
  CFLAGS += $(SDL_CFLAGS) $(SSL_CFLAGS) $(OS_PLATFORM_CFLAGS)
  LDLIBS += $(SDL_LIBS) $(SSL_LIBS) $(OS_PLATFORM_LIBS)
else
  VARIANT := headless
  SRCS := $(CORE_SRCS) $(HEADLESS_SRCS)
  CFLAGS += -DSAMALTAK_NO_PLATFORM
endif

OBJDIR := $(BUILD)/obj-$(VARIANT)
OBJS := $(patsubst %.c,$(OBJDIR)/%.o,$(SRCS))
STAMP := $(BUILD)/.variant-$(VARIANT)

$(BUILD)/samaltak: $(OBJS) $(STAMP)
	$(if $(BRIEF),@echo "link $@";) $(CC) $(CFLAGS) -o $@ $(OBJS) $(LDFLAGS) $(LDLIBS)

$(STAMP):
	@mkdir -p $(BUILD)
	@rm -f $(BUILD)/.variant-* $(BUILD)/samaltak
	@touch $@

$(OBJDIR)/%.o: %.c $(PGO_DEP)
	@mkdir -p $(dir $@)
	$(if $(BRIEF),@echo "cc   $<";) $(CC) $(CPPFLAGS) $(CFLAGS) -c -o $@ $<

# Retrain the profile: an instrumented VM runs the benchmarks (also under the baseline JIT) and the kernel/compiler tests on IMAGE.
pgo:
	@test -n "$(IMAGE)" || { echo "usage: make pgo IMAGE=path/to/samaltak.image"; exit 1; }
	@test -n "$(LLVM_PROFDATA)" || { echo "make pgo: no llvm-profdata (LLVM_PROFDATA=...)"; exit 1; }
	rm -rf build/pgo-gen/prof
	$(MAKE) BUILD=build/pgo-gen PGO_GEN=1
	build/pgo-gen/samaltak --jit none $(IMAGE) --headless --eval "$$(cat tests/bench/suite-samaltak.st)" > /dev/null
	build/pgo-gen/samaltak $(IMAGE) --headless --eval "$$(cat tests/bench/suite-samaltak.st)" > /dev/null
	build/pgo-gen/samaltak $(IMAGE) --headless --eval "$$(cat tests/bench/bench.st)" > /dev/null
	build/pgo-gen/samaltak --jit baseline $(IMAGE) --headless --eval "$$(cat tests/bench/suite-samaltak.st)" > /dev/null
	build/pgo-gen/samaltak $(IMAGE) --headless --test KernelTestProxy CollectionTest StringTest IntegerTest CompilerTest > /dev/null
	@mkdir -p $(dir $(PGO_PROFILE))
	$(LLVM_PROFDATA) merge -o $(PGO_PROFILE) build/pgo-gen/prof/*.profraw

clean:
	rm -rf $(BUILD)/samaltak $(BUILD)/obj-* $(BUILD)/.variant-*

.PHONY: clean pgo
-include $(OBJS:.o=.d)
