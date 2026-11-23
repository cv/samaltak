#!/bin/sh
# Usage: tests/vm/wrapped_ffi_specialization_test.sh IMAGE [VM [--no-pty]]
set -eu
IMAGE=${1:?supply a full image}
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
VM=${2:-"$ROOT/vm/build/samaltak"}
PTY=${3:-}
case "$PTY" in ''|--no-pty) ;; *) echo "expected --no-pty" >&2; exit 2 ;; esac
TMP=$(mktemp -d /tmp/samaltak-wrapped-ffi.XXXXXXXX)
trap 'rm -rf "$TMP"' EXIT
unset DISPLAY WAYLAND_DISPLAY SAMALTAK_NATIVE_GRANTS
export SDL_VIDEO_DRIVER=wrapped_ffi_no_video SDL_VIDEODRIVER=wrapped_ffi_no_video
export SAMALTAK_VERIFY_GC=1
export LC_ALL=C


# Structural split: neither invocation primitive nor any FFI-specific method
# reachable on success may consult descriptors, resolve names, marshal a word
# vector, or enter an encoder. The native fixture also inspects the executed
# code at the return PC; this source check is not a substitute for that witness.
WARM="$TMP/warm.st"
awk '
    /^(primFFIBoundInvoke(Array)?|invokeBoundArray: args|callBound: entry args: args|boundEntry: owner into: arity|isBindingShape: owner)$/ {
        active = 1
        ++methods
    }
    /^!/ { active = 0 }
    active { print }
    END { if (methods != 6) exit 1 }
' "$ROOT/src/VM-Jit/FFIPrimitives.st" >"$WARM"
if grep -nE 'resolve|descriptor|prepareEntry|ffiStubs|runtimeNative|Tags?:|encode|while(True|False):|to:.*do:|words|downcall:' "$WARM"; then
    echo 'wrapped_ffi_specialization_test: generic work in the warm path' >&2
    exit 1
fi
grep -Fq "oop (*)(const oop *)" "$WARM"
grep -Fq 'interpreter primStackBase + 1' "$WARM"
grep -Fq 'self slotsOf: args' "$WARM"

case "$(uname -s)" in
    Darwin) LINK=-dynamiclib; EXT=dylib ;;
    Linux) LINK=-shared; EXT=so ;;
    *) echo 'wrapped_ffi_specialization_test: unsupported host' >&2; exit 77 ;;
esac
LIB="$TMP/fixture.$EXT"
"${CC:-cc}" -std=c99 -Wall -Wextra -Werror "$LINK" -fPIC -o "$LIB" "$ROOT/tests/vm/wrapped_ffi_fixture.c"

STEP="wrapped|wrapped_step|i32(i32)|$LIB"
OTHER="wrapped|wrapped_other|i32(i32)|$LIB"
SAMALTAK_NATIVE_GRANTS="$STEP
$OTHER
wrapped|wrapped_mixed|u64(i32,f64,u64,i64,u32,f64)|$LIB
wrapped|wrapped_floats|f64(f64,f64,f64,f64,f64,f64)|$LIB
wrapped|wrapped_signed|i64(i64)|$LIB
wrapped|wrapped_void|void()|$LIB
wrapped|wrapped_calls|u32()|$LIB
wrapped|wrapped_prove_target|i32(i32)|$LIB
wrapped|wrapped_borrows|u64(u64,bytesWithLength,bytesWithLength,u64)|syncBorrow|$LIB"
export SAMALTAK_NATIVE_GRANTS

expect() {
    expected=$1
    shift
    if ! "$VM" "$@" >"$TMP/out" 2>&1 || ! grep -Fxq -e "$expected" "$TMP/out"; then
        cat "$TMP/out" >&2
        echo "wrapped_ffi_specialization_test: expected $expected" >&2
        exit 1
    fi
}

PROOF="$ROOT/tests/vm/wrapped_ffi_specialization.st"
expect true --eden 1 --jit none "$IMAGE" --headless --load "$PROOF" --eval "
    WrappedFFIProof scalars.
    WrappedFFIProof borrows.
    WrappedFFIProof boxingGC.
    true"
expect true --jit opt --jit-threshold 0 --jit-flags eager,deopt "$IMAGE" --headless --load "$PROOF" --eval "
    | counts |
    counts := WrappedFFIProof scalars.
    WrappedFFIProof require: counts optMethodsCompiled > 0 description: 'no opt compilation'.
    WrappedFFIProof require: counts optDeoptimizations > 0 description: 'no deoptimization'.
    WrappedFFIProof borrows.
    true"

if [ -z "$PTY" ]; then
    expect true --jit none "$IMAGE" --headless --load "$PROOF" --eval "
        WrappedFFIProof pty.
        true"
fi

# Persist two same-signature bindings, already called, across an export reorder.
# A still-present target must restore, and a missing one must reject rather than
# call its old row's new occupant. Calling twice also exercises the warmed token.
SNAP="$TMP/wrapped.image"
expect 0 --jit none "$IMAGE" --headless --eval "
    | step other reject |
    step := FFI bind: #(call 'wrapped' 'wrapped_step' (i32) i32).
    other := FFI bind: #(call 'wrapped' 'wrapped_other' (i32) i32).
    ((step tryInvoke1: 3) = -2 and: [(other invoke: #(3)) = 23]) ifFalse: [self error: 'initial targets'].
    (Smalltalk snapshot: '$SNAP') ifTrue: [
        reject := [:aBlock | [aBlock value] on: FFIError do: [:e | #denied]].
        ^{reject value: [step invoke: #(4)]. step tryInvoke1: 5.
            reject value: [other invoke: #(6)]. other tryInvoke1: 7}].
    0"
SAMALTAK_NATIVE_GRANTS="$OTHER
$STEP" expect '#(-3 -4 26 27)' "$SNAP" --headless
SAMALTAK_NATIVE_GRANTS="$OTHER" expect '#(#denied false 26 27)' "$SNAP" --headless
unset SAMALTAK_NATIVE_GRANTS
expect '#(#denied false #denied false)' "$SNAP" --headless

echo 'wrapped_ffi_specialization_test: passed'
