# Standalone build of the platform internals + test (the VM build compiles *.c itself).
SDL_CFLAGS ?= $(shell pkg-config --cflags sdl3 2>/dev/null || echo -I/opt/homebrew/include)
SDL_LIBS ?= $(shell pkg-config --libs sdl3 2>/dev/null || echo -L/opt/homebrew/lib -lSDL3)
CFLAGS ?= -std=c11 -O2 -g -Wall -Wextra -Wno-unused-parameter
BUILD := ../build/platform-test
SRCS := pf_common.c pf_events.c pf_window.c pf_gpu.c pf_file.c pf_socket.c pf_vsync.c

test: $(BUILD)/gpu_test $(BUILD)/prims_test
	$(BUILD)/gpu_test
	$(BUILD)/prims_test

$(BUILD)/gpu_test: tests/gpu_test.c $(SRCS) platform.h
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -D_DARWIN_C_SOURCE $(SDL_CFLAGS) -o $@ tests/gpu_test.c $(SRCS) $(SDL_LIBS) -lpthread

$(BUILD)/prims_test: tests/prims_test.c prims_platform.c prims_platform.def $(SRCS) platform.h
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -D_DARWIN_C_SOURCE $(SDL_CFLAGS) -o $@ tests/prims_test.c prims_platform.c $(SRCS) $(SDL_LIBS) -lpthread

# Through the real VM (built into its own directory so it never clobbers vm/build/samaltak).
st-test:
	$(MAKE) -C .. BUILD=build/platform-vm
	tests/st_test.sh $(CURDIR)/../build/platform-vm/samaltak

clean:
	rm -rf $(BUILD)

.PHONY: test st-test clean
