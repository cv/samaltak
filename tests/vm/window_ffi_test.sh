#!/bin/sh
# Usage: tests/vm/window_ffi_test.sh IMAGE VM [--display-ci] [--logs DIR]
# Only the CI display branch may initialize video or the clipboard.
set -eu
IMAGE=${1:?image required}
VM=${2:?VM required}
shift 2
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
unset SAMALTAK_NATIVE_GRANTS
if [ "${1:-}" = --display-ci ]; then
    [ "${GITHUB_ACTIONS:-}" = true ] && [ -n "${DISPLAY:-}" ] || {
        echo 'window_ffi_test: display test is CI-only' >&2; exit 2; }
    test_case=display
    shift
else
    unset DISPLAY WAYLAND_DISPLAY XAUTHORITY
    export SDL_VIDEO_DRIVER=window_ffi_no_display SDL_VIDEODRIVER=window_ffi_no_display
    test_case=headless
fi
if [ "$#" -eq 0 ]; then
    logs=$(mktemp -d)
    trap 'rm -rf "$logs"' EXIT
else
    [ "$#" = 2 ] && [ "$1" = --logs ] || {
        echo 'window_ffi_test: expected optional --logs DIR' >&2; exit 2; }
    logs=$2
    mkdir -p "$logs"
    export SAMALTAK_FFI_NATIVE_TRACE=1
fi
run() {
    extra=
    [ "$test_case:$mode" != headless:opt ] || extra="WindowFFIProof largeEvent."
    "$VM" "$@" "$IMAGE" --headless --load "$ROOT/tests/vm/window_ffi_fixture.st" --eval \
        "[WindowFFIProof $test_case. $extra #windowFFIOK] on: Error do: [:e |
            Smalltalk vm stderrWrite: e messageText, (String with: Character lf). Smalltalk quit: 1]"
}
for mode in none baseline opt; do
    echo "window_ffi_test: $test_case $mode"
    set -- --jit "$mode" --jit-threshold 0
    [ "$mode" != opt ] || set -- "$@" --jit-flags eager
    log="$logs/window-$mode"
    if ! run "$@" >"$log.stdout" 2>"$log.stderr" ||
       ! grep -Fxq '#windowFFIOK' "$log.stdout"; then
        cat "$log.stdout" "$log.stderr" >&2
        exit 1
    fi
done
