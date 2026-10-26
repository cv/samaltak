# Samaltak VM. `make` → build/samaltak. NO_PLATFORM=1 builds a headless-only VM.
# The sources are gen/: C translated from the Lowtalk modules in src/VM-Core and src/VM-Platform (make translate at
# the top level regenerates them); gen/sources.mk says which files make the core and which the platform layer.
# Profile-guided: pgo.profdata (if present) steers optimization; `make pgo IMAGE=...` retrains it. NO_PGO=1 skips it.
# BRIEF=1 prints one line per file instead of the commands.
CC ?= cc
CFLAGS ?= -O2 -g -flto
CFLAGS += -std=gnu11 -Wall -Wextra -Wno-unused-parameter -MMD -MP -Igen -D_DARWIN_C_SOURCE
LDLIBS += -lm -lpthread

BUILD := build
PGO_PROFILE := pgo.profdata
LLVM_PROFDATA := $(shell xcrun -f llvm-profdata 2>/dev/null || command -v llvm-profdata)
ifneq ($(PGO_GEN),)
  CFLAGS += -fprofile-instr-generate=$(CURDIR)/$(BUILD)/prof/%p.profraw
  LDFLAGS += -fprofile-instr-generate
else ifeq ($(and $(wildcard $(PGO_PROFILE)),$(if $(NO_PGO),,yes)),yes)
  CFLAGS += -fprofile-instr-use=$(PGO_PROFILE) -Wno-profile-instr-out-of-date -Wno-profile-instr-unprofiled
  PGO_DEP := $(PGO_PROFILE)
endif
include gen/sources.mk
CORE_SRCS := $(addprefix gen/,$(VM_CORE_SOURCES))
HEADLESS_SRCS := $(addprefix gen/,$(VM_HEADLESS_SOURCES))
PLATFORM_SRCS := $(addprefix gen/,$(VM_PLATFORM_SOURCES))

SDL_CFLAGS := $(shell pkg-config --cflags sdl3 2>/dev/null)
SDL_LIBS := $(shell pkg-config --libs sdl3 2>/dev/null)
ifeq ($(SDL_LIBS),)
  ifneq ($(wildcard /opt/homebrew/include/SDL3/SDL.h),)
    SDL_CFLAGS := -I/opt/homebrew/include
    SDL_LIBS := -L/opt/homebrew/lib -Wl,-rpath,/opt/homebrew/lib -lSDL3
  endif
endif

ifneq ($(and $(PLATFORM_SRCS),$(SDL_LIBS),$(if $(NO_PLATFORM),,yes)),)
  VARIANT := platform
  SRCS := $(CORE_SRCS) $(PLATFORM_SRCS)
  CFLAGS += $(SDL_CFLAGS)
  LDLIBS += $(SDL_LIBS) -framework CoreVideo
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
	$(if $(BRIEF),@echo "cc   $<";) $(CC) $(CFLAGS) -c -o $@ $<

# Retrain the profile: an instrumented VM runs the benchmarks (also under the baseline JIT) and the kernel/compiler tests on IMAGE.
pgo:
	@test -n "$(IMAGE)" || { echo "usage: make pgo IMAGE=path/to/samaltak.image"; exit 1; }
	rm -rf build/pgo-gen/prof
	$(MAKE) BUILD=build/pgo-gen PGO_GEN=1
	build/pgo-gen/samaltak $(IMAGE) --headless --eval "$$(cat tests/bench/suite-samaltak.st)" > /dev/null
	build/pgo-gen/samaltak $(IMAGE) --headless --eval "$$(cat tests/bench/bench.st)" > /dev/null
	build/pgo-gen/samaltak --jit baseline $(IMAGE) --headless --eval "$$(cat tests/bench/suite-samaltak.st)" > /dev/null
	build/pgo-gen/samaltak $(IMAGE) --headless --test KernelTestProxy CollectionTest StringTest IntegerTest CompilerTest > /dev/null
	$(LLVM_PROFDATA) merge -o $(PGO_PROFILE) build/pgo-gen/prof/*.profraw

clean:
	rm -rf $(BUILD)/samaltak $(BUILD)/obj-* $(BUILD)/.variant-*

.PHONY: clean pgo
-include $(OBJS:.o=.d)
