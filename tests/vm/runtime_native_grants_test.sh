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
#include <stddef.h>
#include <stdint.h>

int32_t ffi_test_i32_pair(int32_t a, int32_t b)
{
    return (int32_t)((uint32_t)a * 10u + (uint32_t)b);
}

double ffi_test_mix(int32_t a, double b, uint64_t c, int64_t d, uint32_t e, double f)
{
    return (double)a + b + (double)c + (double)d + (double)e + f;
}

uint64_t ffi_test_checksum(uint64_t seed, const uint8_t *bytes, size_t length)
{
    for (size_t i = 0; i < length; ++i)
        seed = seed * 33 + bytes[i];
    return seed;
}

uint64_t ffi_test_checksum_two(uint64_t seed, const uint8_t *a, size_t na,
                               const uint8_t *b, size_t nb, uint64_t tail)
{
    return ffi_test_checksum(ffi_test_checksum(seed, a, na), b, nb) + tail;
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
CHECKSUM="fixture|ffi_test_checksum|u64(u64,bytesWithLength)|syncBorrow|$LIB"
CHECKSUM_TWO="fixture|ffi_test_checksum_two|u64(u64,bytesWithLength,bytesWithLength,u64)|syncBorrow|$LIB"

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
$VOID
$CHECKSUM
$CHECKSUM_TWO"
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

expect true "$IMAGE" --headless --eval "
    | checksum two bytes reject |
    checksum := FFI bind: #(call 'fixture' 'ffi_test_checksum' (u64 bytesWithLength) u64).
    two := FFI bind: #(call 'fixture' 'ffi_test_checksum_two' (u64 bytesWithLength bytesWithLength u64) u64).
    bytes := #[9 3 5 7 10] copy.
    reject := [:block | [block value. false] on: FFIError do: [:e | true]].
    (checksum invoke: {7. {bytes. 2. 3}}) = 254998 ifFalse: [^false].
    Smalltalk vm garbageCollect.
    bytes at: 3 put: 6.
    (checksum invoke: {7. {bytes. 2. 3}}) = 255031 ifFalse: [^false].
    bytes at: 3 put: 5.
    Smalltalk vm scavenge.
    (two invoke: {7. {bytes. 2. 2}. {#[201 13 202]. 2. 1}. 23}) = 255027 ifFalse: [^false].
    (checksum invoke: {16rFFFFFFFFFFFFFFFF. {bytes. 6. 0}}) = 16rFFFFFFFFFFFFFFFF ifFalse: [^false].
    (checksum invoke: {7. {ByteArray new: 0. 1. 0}}) = 7 ifFalse: [^false].
    ({1234. {bytes. 0. 1}. {bytes. 2. -1}. {bytes. 2. 5}.
      {bytes. 6. 1}. {bytes. 7. 0}. {bytes. 1. 16rFFFFFFFFFFFFFFFF}.
      {'not a ByteArray'. 1. 1}. {bytes. 2}. {bytes. 2. 3. 4}}
        allSatisfy: [:slice | reject value: [checksum invoke: {7. slice}]]) ifFalse: [^false].
    (reject value: [two invoke: {7. {bytes. 2. 2}. {bytes. 3. 4}. 23}]) ifFalse: [^false].
    (reject value: [checksum invoke: {7. {bytes. 2. 3}. 4}]) ifFalse: [^false].
    (#((call 'fixture' 'ffi_test_checksum' (u64 byteSlice u64) u64)
       (call 'fixture' 'ffi_test_checksum' (u64 bytesWithLength u64) u64)
       (call 'fixture' 'ffi_test_checksum' (u64 bytesWithLength) bytesWithLength)
       (call 'fixture' 'ffi_test_checksum' (u64 u64) u64)
       (call 'fixture' 'ffi_test_checksum' (bytesWithLength bytesWithLength bytesWithLength u64) u64))
        allSatisfy: [:d | reject value: [FFI bind: d]]) ifFalse: [^false].
    (reject value: [
        checksum primInvoke: (checksum instVarNamed: 'id')
            library: 'fixture' symbol: 'ffi_test_checksum'
            types: #[4 5 4] result: 4 arguments: {7. {bytes. 2. 3}. 3}]) ifFalse: [^false].
    reject value: [
        checksum primInvoke: (checksum instVarNamed: 'id')
            library: 'fixture' symbol: 'ffi_test_checksum'
            types: #[3 8] result: 4 arguments: {7. {bytes. 2. 3}}]"

reject_manifest "fixture|ffi_test_checksum|u64(u64,bytesWithLength)|$LIB"
reject_manifest "fixture|ffi_test_checksum|u64(u64,bytesWithLength)|asyncBorrow|$LIB"
reject_manifest "fixture|ffi_test_checksum|bytesWithLength(u64,bytesWithLength)|syncBorrow|$LIB"
reject_manifest "fixture|ffi_test_checksum|u64(bytesWithLength,bytesWithLength,bytesWithLength,u64)|syncBorrow|$LIB"
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
