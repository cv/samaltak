#!/bin/sh
# Usage: tests/vm/core_getenv_large_test.sh IMAGE VM [none|baseline|opt]
set -eu

if [ "$(uname -s)" != Linux ] || ! getconf GNU_LIBC_VERSION >/dev/null 2>&1; then
    echo 'large core getenv: skipped (requires Linux/glibc)'
    exit 0
fi
image=$(realpath "${1:?image required}")
vm=$(realpath "${2:?VM required}")
modes=${3:-'none baseline opt'}
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT HUP INT TERM

# Linux execve would reject this environment. Install the value in the VM
# process via real glibc setenv, and forward/count just its getenv reads.
cat >"$dir/large_env.c" <<'C'
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static const char key[] = "SAMALTAK_FFI_REAL_LARGE_VALUE";
static char *(*next_getenv)(const char *);
static unsigned reads;

static char *(*resolve(void))(const char *)
{
    char *(*fn)(const char *) = dlsym(RTLD_NEXT, "getenv");
    if (!fn)
        _exit(90);
    return fn;
}

char *getenv(const char *name)
{
    if (!next_getenv)
        next_getenv = resolve();
    if (strcmp(name, key) == 0)
        ++reads;
    return next_getenv(name);
}

__attribute__((constructor)) static void install_large_value(void)
{
    const size_t length = (64UL << 20) + 1;
    if (!next_getenv)
        next_getenv = resolve();
    const char *lane = next_getenv("SAMALTAK_FFI_LARGE_LANE");
    char *value = malloc(length + 1);
    if (!lane || !value)
        _exit(91);
    memset(value, 'x', length);
    value[0] = 'A';
    value[length / 2] = 'C';
    value[length - 1] = 'Z';
    if (strcmp(lane, "wide") == 0)
        memcpy(value + length - 5, "\xff\xe2\x82\xacZ", 5);
    value[length] = '\0';
    if (setenv(key, value, 1) != 0)
        _exit(92);
    free(value);
}

__attribute__((destructor)) static void read_count(void)
{
    fprintf(stderr, "large-env libc reads %u\n", reads);
    if (reads != 1)
        _exit(93);
}
C
${CC:-cc} -std=gnu11 -Wall -Wextra -Werror -shared -fPIC -o "$dir/large_env.so" "$dir/large_env.c" -ldl

unset DISPLAY WAYLAND_DISPLAY XAUTHORITY SAMALTAK_NATIVE_GRANTS SAMALTAK_FFI_TEST_EXPORTS
export LC_ALL=C SDL_VIDEODRIVER=ffi_no_video SDL_VIDEO_DRIVER=ffi_no_video
export SAMALTAK_FFI_NATIVE_TRACE=1 SAMALTAK_FFI_BOX_FULL_GC=1 SAMALTAK_VERIFY_GC=1
for mode in $modes; do
    case "$mode" in
        none) set -- --jit none ;;
        baseline) set -- --jit baseline --jit-threshold 0 ;;
        opt) set -- --jit opt --jit-threshold 0 --jit-flags eager ;;
        *) echo "Unknown tier: $mode" >&2; exit 2 ;;
    esac
    for lane in ascii wide; do
        case "$lane" in
            ascii) checks='s class == ByteString and: [s size = 67108865]' ;;
            wide) checks='s class == WideString and: [s size = 67108863 and: [
                (s at: s size - 2) value = 16rDCFF and: [(s at: s size - 1) value = 16r20AC]]]' ;;
        esac
        if ! LD_PRELOAD="$dir/large_env.so" SAMALTAK_FFI_LARGE_LANE="$lane" \
            "$vm" --max-heap 768 "$@" "$image" --headless --eval "
            | s |
            s := Smalltalk vm getenv: 'SAMALTAK_FFI_REAL_LARGE_VALUE'.
            (s notNil and: [($checks)
                and: [(s at: 1) = \$A and: [(s at: 33554433) = \$C and: [s last = \$Z]]]])
                ifFalse: [Smalltalk quit: 94].
            Smalltalk vm stdoutWrite: 'large-env OK', (String with: Character lf).
            Smalltalk quit: 0
            " >"$dir/stdout" 2>"$dir/stderr" ||
            ! grep -qx 'large-env OK' "$dir/stdout" ||
            ! grep -qx 'large-env libc reads 1' "$dir/stderr" ||
            [ "$(grep -cx 'ffi-native-entry 2196' "$dir/stderr")" != 1 ]; then
            echo "large core getenv ($mode, $lane): failed" >&2
            cat "$dir/stdout" "$dir/stderr" >&2
            exit 1
        fi
        echo "large core getenv ($mode, $lane): passed"
    done
done
