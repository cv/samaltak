#!/bin/sh
# Usage: tests/vm/window_ffi_test.sh IMAGE VM [--display-ci]
# Only the CI display branch may initialize video or the clipboard.
set -eu
IMAGE=${1:?image required}
VM=${2:?VM required}
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
unset SAMALTAK_FFI_TRIAL SAMALTAK_NATIVE_GRANTS
case ${3:-} in
    '') unset DISPLAY WAYLAND_DISPLAY
        export SDL_VIDEO_DRIVER=window_ffi_no_display SDL_VIDEODRIVER=window_ffi_no_display
        test_case=headless ;;
    --display-ci)
        [ "${CI:-}" = true ] && [ -n "${DISPLAY:-}" ] || {
            echo 'window_ffi_test: display test is CI-only' >&2; exit 2; }
        test_case=display ;;
    *) echo 'window_ffi_test: expected --display-ci or no option' >&2; exit 2 ;;
esac
for mode in none baseline opt; do
    echo "window_ffi_test: $test_case $mode"
    set -- --jit "$mode" --jit-threshold 0
    [ "$mode" != opt ] || set -- "$@" --jit-opt 80
    "$VM" "$@" "$IMAGE" --headless --load "$ROOT/tests/vm/window_ffi_fixture.st" --eval \
        "[WindowFFIProof $test_case. Smalltalk quit: 0] on: Error do: [:e |
            Smalltalk vm stderrWrite: e messageText, (String with: Character lf). Smalltalk quit: 1]"
done
