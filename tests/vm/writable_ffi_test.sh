#!/bin/sh
# Usage: tests/vm/writable_ffi_test.sh IMAGE [VM [--expect-no-fixture]]
# Positive checks require a hosted VM compiled with -DSAMALTAK_FFI_TEST_EXPORTS.
set -eu
IMAGE=${1:?supply a full image}
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
VM=${2:-"$ROOT/vm/build/samaltak"}
TMP=$(mktemp -d /tmp/samaltak-writable-ffi.XXXXXXXX)
trap 'rm -rf "$TMP"' EXIT
LOG=${WRITABLE_FFI_LOG_DIR:-"$TMP"}
mkdir -p "$LOG"
unset DISPLAY WAYLAND_DISPLAY SAMALTAK_NATIVE_GRANTS
export SDL_VIDEO_DRIVER=writable_ffi_no_video SDL_VIDEODRIVER=writable_ffi_no_video
export LC_ALL=C SAMALTAK_VERIFY_GC=1

expect() {
    name=$1
    shift
    if ! "$VM" "$@" >"$LOG/$name.stdout" 2>"$LOG/$name.stderr" ||
       ! grep -Fxq true "$LOG/$name.stdout"; then
        tail -n 80 "$LOG/$name.stdout" "$LOG/$name.stderr" >&2
        echo "writable_ffi_test: $name failed" >&2
        exit 1
    fi
}

if [ "${3:-}" = --expect-no-fixture ]; then
    expect not-registered "$IMAGE" --headless --eval "
        (FFI typeTag: #writableBytesWithLength) = 9 and: [
            [FFI bind: #(call 'vm:core' 'ffi_test_writable_pair' (writableBytesWithLength f64 i32 writableBytesWithLength) i64).
             false] on: FFIError do: [:e | true]]"
    echo 'writable_ffi_test: fixture not registered'
    exit 0
fi
if [ -n "${3:-}" ]; then
    echo 'writable_ffi_test: expected --expect-no-fixture' >&2
    exit 2
fi
export SAMALTAK_FFI_BOX_FULL_GC=1 SAMALTAK_FFI_SITE_TRACE=1 SAMALTAK_FFI_NATIVE_TRACE=1
# File in from a string so hosted NO_PLATFORM builds can run the same proof.
PROOF=$(sed "s/'/''/g" "$ROOT/tests/vm/writable_ffi.st")
run() {
    name=$1
    shift
    expect "$name" --eden 1 "$@" "$IMAGE" --headless --eval "
        [Compiler fileInString: '$PROOF'.
         Compiler evaluate: 'WritableFFIProof run'] on: Error do: [:e |
            Smalltalk vm stderrWrite: e messageText, (String with: Character lf).
            Smalltalk quit: 1]"
}
run interpreter --jit none
run baseline --jit baseline --jit-threshold 0
run optimized --jit opt --jit-opt 8
run optimized-no-site --jit opt --jit-opt 8 --jit-flags -ffi-site
for name in interpreter baseline optimized optimized-no-site; do
    # 4 completions per checkBinding (twice), 72 during the GC stress.
    if [ "$(grep -cx 'ffi-native-entry 5119' "$LOG/$name.stderr" || true)" != 80 ]; then
        tail -n 80 "$LOG/$name.stderr" >&2
        echo "writable_ffi_test: $name wrong native entry count" >&2
        exit 1
    fi
    awk -v name="$name" '/^ffi-site trace hits=[0-9]+ misses=[0-9]+ primitive=[0-9]+$/ {
        ++rows
        split($3, h, "="); split($5, p, "=")
        good = name == "optimized" ? h[2] >= 24 && p[2] >= 1 : h[2] == 0 && p[2] >= 24
    } END { exit !(rows == 1 && good) }' "$LOG/$name.stderr" || {
        cat "$LOG/$name.stderr" >&2
        echo "writable_ffi_test: $name missing required path witness" >&2
        exit 1
    }
done
echo 'writable_ffi_test: passed'
