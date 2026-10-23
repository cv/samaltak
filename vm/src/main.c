/* Entry point: samaltak [--max-heap MB] [--eden MB] image [--headless] [image arguments...] */
#include "core.h"
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

bool vm_headless;
int vm_argc;
char **vm_argv;

__attribute__((weak)) void platform_init(void) {}
__attribute__((weak)) void platform_poll(void) {}
__attribute__((weak)) void platform_shutdown(void) {}
__attribute__((weak)) void platform_wait(int64_t timeout_us)
{
    if (timeout_us < 0) fatal("deadlock: no runnable process and no pending timer");
    usleep((useconds_t)(timeout_us > 1000000 ? 1000000 : timeout_us));
}

static void usage(void)
{
    fputs("usage: samaltak [--max-heap MB] [--eden MB] image [--headless] [arguments...]\n", stderr);
    exit(64);
}

int main(int argc, char **argv)
{
    size_t max_heap = (size_t)4096 << 20, eden = (size_t)16 << 20;
    int i = 1;
    for (; i < argc && argv[i][0] == '-'; i++) {
        if (!strcmp(argv[i], "--max-heap") && i + 1 < argc) max_heap = (size_t)atol(argv[++i]) << 20;
        else if (!strcmp(argv[i], "--eden") && i + 1 < argc) eden = (size_t)atol(argv[++i]) << 20;
        else if (!strcmp(argv[i], "--headless")) vm_headless = true;
        else usage();
    }
    if (i >= argc) usage();
    const char *image = argv[i];
    vm_argc = argc;
    vm_argv = argv;
    vm_args_start = i + 1;
    for (int k = i + 1; k < argc; k++)
        if (!strcmp(argv[k], "--headless")) vm_headless = true;

    memory_init(eden, max_heap);
    load_image(image);
    sched_init();
    if (!vm_headless) platform_init();

    oop proc = load_ref(special(SO_PROCESSOR), SCHED_ACTIVE);
    active_ctx = load_ref(proc, PROC_SUSPENDED);
    if (!is_ptr(active_ctx) || active_ctx == nil_oop) fatal("image has no active context");
    store_ref(proc, PROC_SUSPENDED, nil_oop);
    remember_if_old(active_ctx);
    interpret();
    return 0;
}
