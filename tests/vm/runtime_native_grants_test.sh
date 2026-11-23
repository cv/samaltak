#!/bin/sh
# Usage: tests/vm/runtime_native_grants_test.sh IMAGE [VM]
# Works with either hosted VM build, including NO_PLATFORM=1.
set -eu
IMAGE=${1:?supply a full image with FFI}
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
VM=${2:-"$ROOT/vm/build/samaltak"}
TMP=$(mktemp -d /tmp/samaltak-native-grants.XXXXXXXX)
trap 'rm -rf "$TMP"' EXIT
unset SAMALTAK_NATIVE_GRANTS

cat >"$TMP/fixture.c" <<'C'
#include <stdint.h>

int32_t ffi_test_i32_pair(int32_t a, int32_t b)
{
    return (int32_t)((uint32_t)a * 10u + (uint32_t)b);
}

double ffi_test_mix(int32_t a, double b, uint64_t c, int64_t d, uint32_t e, double f)
{
    return (double)a + b + (double)c + (double)d + (double)e + f;
}

void ffi_test_void(void) {}
int32_t ffi_test_ungranted(int32_t a, int32_t b)
{
    return a - b;
}
C

case "$(uname -s)" in
    Darwin) LINK=-dynamiclib; EXT=dylib ;;
    Linux) LINK=-shared; EXT=so ;;
    *) echo "runtime_native_grants_test: unsupported host" >&2; exit 77 ;;
esac
LIB="$TMP/fixture.$EXT"
"${CC:-cc}" "$LINK" -fPIC -o "$LIB" "$TMP/fixture.c"

PAIR="fixture|ffi_test_i32_pair|i32(i32,i32)|$LIB"
MIX="fixture|ffi_test_mix|f64(i32,f64,u64,i64,u32,f64)|$LIB"
VOID="fixture|ffi_test_void|void()|$LIB"

expect() {
    expected=$1
    shift
    if ! "$VM" "$@" >"$TMP/out" 2>&1 || ! grep -Fxq -e "$expected" "$TMP/out"; then
        cat "$TMP/out" >&2
        echo "runtime_native_grants_test: expected $expected" >&2
        exit 1
    fi
}

reject_manifest() {
    code=0
    SAMALTAK_NATIVE_GRANTS=$1 "$VM" "$IMAGE" --headless --eval true >"$TMP/out" 2>&1 || code=$?
    if [ "$code" -ne 64 ] || ! grep -Fq 'invalid or unresolved SAMALTAK_NATIVE_GRANTS' "$TMP/out"; then
        cat "$TMP/out" >&2
        echo "runtime_native_grants_test: expected launch rejection, got $code" >&2
        exit 1
    fi
}

expect true "$IMAGE" --headless --eval "
    [FFI bind: #(call 'fixture' 'ffi_test_i32_pair' (i32 i32) i32). false]
        on: FFIError do: [:e | true]"
SAMALTAK_NATIVE_GRANTS="$PAIR
$MIX
$VOID"
export SAMALTAK_NATIVE_GRANTS

expect true "$IMAGE" --headless --eval "
    | binding reject |
    binding := FFI bind: #(call 'fixture' 'ffi_test_i32_pair' (i32 i32) i32).
    reject := [:block | [block value. false] on: FFIError do: [:e | true]].
    ((binding invoke: #(-11 5)) = -105
        and: [((FFI bind: #(call 'fixture' 'ffi_test_mix' (i32 f64 u64 i64 u32 f64) f64))
            invoke: #(-5 1.25 20 -7 13 0.25)) = 22.5
        and: [((FFI bind: #(call 'fixture' 'ffi_test_void' () void)) invoke: #()) isNil
        and: [
            (#((call 'fixturE' 'ffi_test_i32_pair' (i32 i32) i32)
               (call 'fixture' 'ffi_test_i32_pair' (u32 i32) i32)
               (call 'fixture' 'ffi_test_i32_pair' (i32 i32) u32)
               (call 'fixture' 'ffi_test_i32_pair' (i32) i32)
               (call 'fixture' 'ffi_test_i32_pair' (byteSlice i32) i32)
               (call 'fixture' 'ffi_test_ungranted' (i32 i32) i32))
                allSatisfy: [:d | reject value: [FFI bind: d]]
            and: [(reject value: [binding invoke: #(2147483648 5)])
                and: [reject value: [
                    binding primInvoke: (binding instVarNamed: 'id')
                        library: 'fixture' symbol: 'ffi_test_i32_pair'
                        types: #[2 1] result: 1 arguments: #(11 5)]]]]]])"

reject_manifest "fixture|ffi_test_i32_pair|i32(i32,i32)|fixture.$EXT"
reject_manifest "fixture|missing_symbol|i32(i32,i32)|$LIB"
reject_manifest "fixture|ffi_test_i32_pair|i32(i32,i32)|$TMP/missing.$EXT"
reject_manifest "fixture|ffi_test_i32_pair|i32(i32,)|$LIB"
reject_manifest "fixture|ffi_test_i32_pair|i32(ptr,i32)|$LIB"
reject_manifest "$PAIR
$PAIR"
reject_manifest "libm|ffi_test_i32_pair|i32(i32,i32)|$LIB"
reject_manifest "$(printf '%4097s' x)"
too_many=$(i=0; while [ "$i" -lt 33 ]; do
    printf 'fixture%d|ffi_test_i32_pair|i32(i32,i32)|%s\n' "$i" "$LIB"
    i=$((i+1))
done)
reject_manifest "$too_many"

# Keep the binding across restarts; no row index or address may survive as authority.
SNAP="$TMP/granted.image"
expect 0 "$IMAGE" --headless --eval "
    | binding |
    binding := FFI bind: #(call 'fixture' 'ffi_test_i32_pair' (i32 i32) i32).
    (Smalltalk snapshot: '$SNAP') ifTrue: [
        ^[binding invoke: #(12 3)] on: FFIError do: [:e | -999]].
    0"
SAMALTAK_NATIVE_GRANTS="fixture|ffi_test_ungranted|i32(i32,i32)|$LIB" expect -999 "$SNAP" --headless
SAMALTAK_NATIVE_GRANTS="$MIX
$PAIR" expect 123 "$SNAP" --headless
unset SAMALTAK_NATIVE_GRANTS
expect -999 "$SNAP" --headless

echo "runtime_native_grants_test: passed"
