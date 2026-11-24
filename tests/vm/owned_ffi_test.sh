#!/bin/sh
# Usage: tests/vm/owned_ffi_test.sh IMAGE TEST_VM [--trace]
set -eu
image=${1:?supply a full image}
vm=${2:?supply a hosted test VM}
root=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
log=${OWNED_FFI_LOG_DIR:-"$tmp"}
mkdir -p "$log"
unset DISPLAY WAYLAND_DISPLAY SAMALTAK_NATIVE_GRANTS SAMALTAK_FFI_NATIVE_TRACE
export SAMALTAK_VERIFY_GC=1 SAMALTAK_FFI_OWNED_TEST=1
export SDL_VIDEO_DRIVER=owned_ffi_no_video SDL_VIDEODRIVER=owned_ffi_no_video
case ${3:-} in
    '') ;;
    --trace) export SAMALTAK_FFI_NATIVE_TRACE=1 ;;
    *) exit 2 ;;
esac
proof=$(sed "s/'/''/g" "$root/tests/vm/owned_ffi.st")
for mode in none baseline opt; do
    if ! "$vm" --jit "$mode" --jit-threshold 0 --jit-opt 8 --eden 1 "$image" --headless --eval "
        [Compiler fileInString: '$proof'.
         Compiler evaluate: 'OwnedFFIProof wire. OwnedFFIProof capture'] on: Error do: [:e |
            Smalltalk vm stderrWrite: e messageText, (String with: Character lf).
            Smalltalk quit: 1]" >"$log/$mode.stdout" 2>"$log/$mode.stderr" ||
        ! grep -Fxq true "$log/$mode.stdout"; then
        tail -n 80 "$log/$mode.stdout" "$log/$mode.stderr" >&2
        echo "owned_ffi_test: FAILED in $mode" >&2
        exit 1
    fi
    if [ "${3:-}" = --trace ] &&
        ! awk '/^ffi-native-entry 5028$/ {n++} END {exit n != 135}' "$log/$mode.stderr"; then
        echo "owned_ffi_test: incorrect native producer entry count in $mode" >&2
        exit 1
    fi
    echo "owned_ffi_test: passed in $mode"
done
