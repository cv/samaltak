#!/bin/sh
# Usage: tests/vm/ffi_arity_test.sh IMAGE [VM [TEST_EXPORTS_VM]]
# Calls with 7 to 16 arguments (stack arguments on arm64 and x86-64) through launcher grants of
# tests/vm/ffi_arity_fixture.c in the interpreter, baseline and optimized code (bound sites), and with
# TEST_EXPORTS_VM (compiled with -DSAMALTAK_FFI_TEST_EXPORTS) the approved ffi_test_arity* exports too.
# RUN (e.g. qemu-x86_64 -L SYSROOT) and CC (its compiler) run another architecture's VM.
set -eu
IMAGE=${1:?supply a full image}
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
VM=${2:-"$ROOT/vm/build/samaltak"}
EXPORTS_VM=${3:-}
RUN=${RUN:-}
TMP=$(mktemp -d /tmp/samaltak-ffi-arity.XXXXXXXX)
trap 'rm -rf "$TMP"' EXIT
unset DISPLAY WAYLAND_DISPLAY SAMALTAK_NATIVE_GRANTS
export SDL_VIDEO_DRIVER=ffi_arity_no_video SDL_VIDEODRIVER=ffi_arity_no_video LC_ALL=C

case "$(uname -s)" in
    Darwin) LINK=-dynamiclib; EXT=dylib ;;
    Linux) LINK=-shared; EXT=so ;;
    *) echo 'ffi_arity_test: unsupported host' >&2; exit 77 ;;
esac
LIB="$TMP/fixture.$EXT"
${CC:-cc} -std=c99 -O2 -Wall -Wextra -Werror $LINK -fPIC -o "$LIB" "$ROOT/tests/vm/ffi_arity_fixture.c"
SAMALTAK_NATIVE_GRANTS="arity|arity_calls|u32()|$LIB
arity|arity7|u64(i32,i64,u32,u64,i32,i64,i32)|$LIB
arity|arity8|u64(i32,i64,i32,i64,i32,i64,i32,bytesWithLength)|syncBorrow|$LIB
arity|arity9|f32(i32,i64,i32,i64,i32,bytesWithLength,f64,f32,i64)|syncBorrow|$LIB
arity|arity14|u64(u64,i32,i32,i32,i32,i32,bytesWithLength,u64,i32,u64,i32,bytesWithLength,u64,i32)|syncBorrow|$LIB
arity|arity16|f64(f64,i32,f32,i64,f64,u32,f32,u64,f64,i32,f32,i64,f64,i32,f32,f64)|$LIB"
export SAMALTAK_NATIVE_GRANTS
PROOF=$(sed "s/'/''/g" "$ROOT/tests/vm/ffi_arity.st")

# run NAME VM APPROVED ITERATIONS VM-ARGS...: the proof (RUN_PROOF, default run) must answer true.
run() {
    name=$1 vm=$2 approved=$3 iterations=$4
    shift 4
    if ! SAMALTAK_FFI_SITE_TRACE=1 $RUN "$vm" --eden 1 "$@" "$IMAGE" --headless --eval "
        [Compiler fileInString: '$PROOF'.
         Compiler evaluate: 'FFIArityProof ${PROOF_RUN:-run}: $approved iterations: $iterations'] on: Error do: [:e |
            Smalltalk vm stderrWrite: e messageText, (String with: Character lf).
            Smalltalk quit: 1]" >"$TMP/$name.out" 2>"$TMP/$name.err" || ! grep -Fxq true "$TMP/$name.out"; then
        tail -n 40 "$TMP/$name.out" "$TMP/$name.err" >&2
        echo "ffi_arity_test: $name failed" >&2
        exit 1
    fi
}
hits() { sed -n 's/^ffi-site trace hits=\([0-9]*\) .*/\1/p' "$TMP/$1.err"; }
# Optimized code must call through bound sites: of the witness's 2 calls an iteration, at least 3 in 4
# hits (the rest are primitive calls before optimization). Unbound, all would be primitive calls.
witness() {
    name=$1 vm=$2 approved=$3
    PROOF_RUN=witness run "$name" "$vm" "$approved" 4000 --jit opt --jit-opt 8
    [ "$(hits "$name")" -ge 6000 ] || {
        cat "$TMP/$name.err" >&2
        echo "ffi_arity_test: $name: too few bound-site hits" >&2
        exit 1
    }
}
modes() {
    prefix=$1 vm=$2 approved=$3
    run "$prefix-none" "$vm" "$approved" 40 --jit none
    run "$prefix-baseline" "$vm" "$approved" 40 --jit baseline --jit-threshold 0
    run "$prefix-opt" "$vm" "$approved" 400 --jit opt --jit-opt 8
    witness "$prefix-witness" "$vm" "$approved"
    run "$prefix-deopt" "$vm" "$approved" 100 --jit opt --jit-threshold 0 --jit-flags eager,deopt
    run "$prefix-no-site" "$vm" "$approved" 40 --jit opt --jit-opt 8 --jit-flags -ffi-site
}
modes grants "$VM" false
if [ -n "$EXPORTS_VM" ]; then
    modes approved "$EXPORTS_VM" true
    # A release VM does not register the test exports.
    out=$($RUN "$VM" "$IMAGE" --headless --eval "(FFI tryBindCall: #(call 'vm:core' 'ffi_test_arity7' (i32 i64 u32 u64 i32 i64 i32) u64)) isNil")
    [ "$out" = true ] || { echo "ffi_arity_test: release VM registered ffi_test_arity7: $out" >&2; exit 1; }
fi
echo "ffi_arity_test: passed${EXPORTS_VM:+ (and approved exports)}"
