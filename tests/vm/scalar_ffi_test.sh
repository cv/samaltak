#!/bin/sh
# Usage: scalar_ffi_test.sh IMAGE TEST_EXPORTS_VM [NORMAL_VM]
set -eu
IMAGE=$(realpath "${1:?image}")
VM=$(realpath "${2:?test-enabled VM}")
NORMAL=${3:-}
unset DISPLAY WAYLAND_DISPLAY SAMALTAK_NATIVE_GRANTS
export SDL_VIDEO_DRIVER=scalar_ffi_no_video SDL_VIDEODRIVER=scalar_ffi_no_video
export SAMALTAK_VERIFY_GC=1 SAMALTAK_FFI_BOX_FULL_GC=1 SAMALTAK_FFI_NATIVE_TRACE=1
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
run() {
    if ! "$@" >"$TMP/out" 2>&1 || ! grep -Fxq true "$TMP/out"; then
        cat "$TMP/out" >&2
        exit 1
    fi
}
if [ -n "$NORMAL" ]; then
    run "$NORMAL" "$IMAGE" --headless --eval "
        (FFI tryBindCall: #(call 'vm:core' 'ffi_test_nonnegative_i64' (i64) nonNegativeI64)) isNil"
fi
for mode in none baseline opt; do
    run "$VM" --jit "$mode" --jit-threshold 0 --jit-flags eager "$IMAGE" --headless --eval "
        | binding old f64 values check valuesForFloat |
        check := [:ok | ok ifFalse: [self error: 'Scalar wrapper contract']].
        binding := FFI bind: #(call 'vm:core' 'ffi_test_nonnegative_i64' (i64) nonNegativeI64).
        old := FFI bind: #(call 'vm:core' 'ffi_test_nonnegative_i64' (i64) i64).
        f64 := FFI bind: #(call 'vm:core' 'core_float_fraction_part' (f64) f64).
        values := {0. 1. 16r3FFFFFFFFFFFFFFF. 16r4000000000000000. 16r7FFFFFFFFFFFFFFF}.
        valuesForFloat := {1.5. -0.0. 1.0e-200. -1.0e-200. 1.0e200}.
        5 timesRepeat: [
            values do: [:n |
                check value: (binding tryInvoke1: n) = n.
                check value: (binding invoke: {n}) = n].
            check value: (binding tryInvoke1: -1) isNil.
            check value: (binding tryInvoke1: 16r8000000000000000 negated) isNil.
            check value: (old tryInvoke1: -1) = -1.
            check value: (binding tryInvoke1: '1') == false.
            check value: (binding tryInvoke1: 16r8000000000000000) == false.
            check value: (binding tryInvoke1: (16r8000000000000001 negated)) == false.
            valuesForFloat do: [:f | check value: (f64 tryInvoke1: f) = f fractionPart].
            check value: (f64 tryInvoke1: 1) == false].
        true"
    # Includes each successful invocation (including nil), excludes all pre-entry rejections.
    test "$(grep -Fxc 'ffi-native-entry 5118' "$TMP/out")" -eq 65
    test "$(grep -Fxc 'ffi-native-entry 1076' "$TMP/out")" -eq 25
done
echo 'scalar_ffi_test: passed'
