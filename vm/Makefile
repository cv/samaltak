# Samaltak VM. `make` → build/samaltak. NO_PLATFORM=1 builds a headless-only VM.
CC ?= cc
CFLAGS ?= -O2 -g -flto
CFLAGS += -std=gnu11 -Wall -Wextra -Wno-unused-parameter -MMD -MP
LDLIBS += -lm -lpthread

BUILD := build
CORE_SRCS := $(wildcard src/*.c)
PLATFORM_SRCS := $(wildcard platform/*.c)

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
  LDLIBS += $(SDL_LIBS)
else
  VARIANT := headless
  SRCS := $(CORE_SRCS)
  CFLAGS += -DSAMALTAK_NO_PLATFORM
endif

OBJDIR := $(BUILD)/obj-$(VARIANT)
OBJS := $(patsubst %.c,$(OBJDIR)/%.o,$(SRCS))
STAMP := $(BUILD)/.variant-$(VARIANT)

$(BUILD)/samaltak: $(OBJS) $(STAMP)
	$(CC) $(CFLAGS) -o $@ $(OBJS) $(LDFLAGS) $(LDLIBS)

$(STAMP):
	@mkdir -p $(BUILD)
	@rm -f $(BUILD)/.variant-* $(BUILD)/samaltak
	@touch $@

$(OBJDIR)/%.o: %.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c -o $@ $<

clean:
	rm -rf $(BUILD)/samaltak $(BUILD)/obj-* $(BUILD)/.variant-*

.PHONY: clean
-include $(OBJS:.o=.d)
