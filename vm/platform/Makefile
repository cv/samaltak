# Tests of the platform layer (src/VM-Platform, translated into ../gen): gpu_test links the generated platform
# internals without the VM; st-test runs Smalltalk through the real VM.
SDL_CFLAGS ?= $(shell pkg-config --cflags sdl3 2>/dev/null || echo -I/opt/homebrew/include)
SDL_LIBS ?= $(shell pkg-config --libs sdl3 2>/dev/null || echo -L/opt/homebrew/lib -lSDL3)
CFLAGS ?= -std=gnu11 -O2 -g -Wall -Wextra -Wno-unused-parameter
BUILD := ../build/platform-test
GEN := ../gen
include $(GEN)/sources.mk
INTERNALS := $(addprefix $(GEN)/,$(filter-out platform_primitives.c,$(VM_PLATFORM_SOURCES)))

test: $(BUILD)/gpu_test
	$(BUILD)/gpu_test

$(BUILD)/gpu_test: tests/gpu_test.c $(INTERNALS) $(GEN)/samaltak.h
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -D_DARWIN_C_SOURCE -I$(GEN) $(SDL_CFLAGS) -o $@ tests/gpu_test.c $(INTERNALS) $(SDL_LIBS) -framework CoreVideo -lpthread

# Through the real VM (built into its own directory so it never clobbers vm/build/samaltak).
st-test:
	$(MAKE) -C .. BUILD=build/platform-vm
	tests/st_test.sh $(CURDIR)/../build/platform-vm/samaltak

clean:
	rm -rf $(BUILD)

.PHONY: test st-test clean
