#!/bin/sh
# Usage: tests/vm/bigint_ffi_test.sh IMAGE VM [--trace]
set -eu
image=${1:?image required}
vm=${2:?vm required}
trace=${3:-}
case "$trace" in ''|--trace) ;; *) exit 2 ;; esac
root=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
log=${BIGINT_FFI_LOG_DIR:-"$tmp"}
mkdir -p "$log"
unset DISPLAY WAYLAND_DISPLAY SAMALTAK_NATIVE_GRANTS SAMALTAK_FFI_NATIVE_TRACE
export LC_ALL=C SAMALTAK_VERIFY_GC=1
export SDL_VIDEO_DRIVER=bigint_ffi_no_video SDL_VIDEODRIVER=bigint_ffi_no_video
[ "$trace" = --trace ] && export SAMALTAK_FFI_NATIVE_TRACE=1
proof=$(sed "s/'/''/g" "$root/tests/vm/bigint_ffi.st")
for mode in none baseline opt; do
    if ! "$vm" "$image" --headless --jit "$mode" --jit-threshold 0 --jit-opt 20 \
        --eval "[Compiler fileInString: '$proof'. Compiler evaluate: 'BigIntegerFFIProof proof']
            on: Error do: [:e | Smalltalk vm stderrWrite: e messageText. Smalltalk quit: 1]" \
        >"$log/$mode.out" 2>"$log/$mode.err" ||
        ! grep -Fxq true "$log/$mode.out"; then
        cat "$log/$mode.out" "$log/$mode.err" >&2
        exit 1
    fi
    if [ "$trace" = --trace ]; then
        # 23^2 combinations × positional, array and facade; plus post-GC and strict facade.
        count=$(grep -Fxc 'ffi-native-entry 1051' "$log/$mode.err")
        test "$count" -eq 1589
    fi
done
echo 'bigint_ffi_test: passed'
