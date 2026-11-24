#!/bin/sh
# Usage: tests/vm/ffi_external_notification_test.sh IMAGE [VM]
set -eu
IMAGE=${1:?supply a full image with FFI}
DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
VM=${2:-"$DIR/../../vm/build/samaltak"}
TMP=$(mktemp -d /tmp/samaltak-notification.XXXXXXXX)
trap 'rm -rf "$TMP"' EXIT
unset SAMALTAK_NATIVE_GRANTS
case "$(uname -s)" in
    Darwin) LINK=-dynamiclib; EXT=dylib ;;
    Linux) LINK=-shared; EXT=so ;;
    *) exit 77 ;;
esac

expect() {
    expected=$1
    shift
    if ! "$VM" "$@" >"$TMP/out" 2>&1 || ! grep -Fxq -e "$expected" "$TMP/out"; then
        cat "$TMP/out" >&2
        echo "ffi_external_notification_test: expected $expected" >&2
        exit 1
    fi
}

if "$VM" "$IMAGE" --headless --eval "(Smalltalk vm primitiveNumberFor: 'ffiExternalNotificationBind') = 0" >"$TMP/out" 2>&1 \
    && grep -Fxq true "$TMP/out"; then
    # NO_PLATFORM deliberately lacks the native module; it must fail closed.
    expect true "$IMAGE" --headless --eval "
        [FFI bind: #(notification external 'fixture' 'fixture_subscribe' (u32 context u64) i32). false]
            on: FFIError do: [:e | true]"
    echo "ffi_external_notification_test: native notification unavailable"
    exit 77
fi

LIB="$TMP/fixture.$EXT"
VOIDLIB="$TMP/fixture-void.$EXT"
"${CC:-cc}" -std=c11 -Wall -Wextra -Werror "$LINK" -fPIC -pthread -o "$LIB" "$DIR/ffi_external_notification_fixture.c"
"${CC:-cc}" -std=c11 -Wall -Wextra -Werror "$LINK" -fPIC -pthread -DVOID_LAYOUT -o "$VOIDLIB" "$DIR/ffi_external_notification_fixture.c"

D="(notification external 'fixture' 'fixture_subscribe' (u32 context u64) i32)"
V="(notification external 'fixture' 'fixture_subscribe' (i32 u32 u64 i64 i32 context) void)"
ROW="fixture|fixture_subscribe|notifyI32(u32,context,u64)|fixture_unsubscribe|$LIB"
MANIFEST="$ROW
fixture|fixture_fire|i32()|$LIB"
VOIDMANIFEST="fixture|fixture_subscribe|notifyVoid(i32,u32,u64,i64,i32,context)|fixture_unsubscribe|$VOIDLIB
fixture|fixture_fire|i32()|$VOIDLIB"

expect true "$IMAGE" --headless --eval "[FFI bind: #$D. false] on: FFIError do: [:e | true]"

SAMALTAK_NATIVE_GRANTS="$MANIFEST" expect true "$IMAGE" --headless --jit none --eval "
    | bad |
    bad := #((notification external 'other' 'fixture_subscribe' (u32 context u64) i32)
        (notification external 'fixture' 'fixture_unsubscribe' (u32 context u64) i32)
        (notification external 'fixture' 'fixture_subscribe' (context u32 u64) i32)
        (notification external 'fixture' 'fixture_subscribe' (u32 context i64) i32)
        (notification external 'fixture' 'fixture_subscribe' (context) i32)
        (notification external 'fixture' 'fixture_subscribe' (u32 context u64) void)
        (notification external 'fixture' 'fixture_subscribe' (u32 context context) i32)
        (notification external 'fixture' 'fixture_subscribe' (u32 ptr u64) i32)
        (call 'fixture' 'fixture_subscribe' (u32 u64) i32)
        (call 'fixture' 'fixture_unsubscribe' () void)).
    bad allSatisfy: [:d | [FFI bind: d. false] on: FFIError do: [:e | true]]"

exercise() {
    desc=$1
    expect true "$IMAGE" --headless --jit none --eval "
        | sub again fire busy ok |
        fire := FFI bind: #(call 'fixture' 'fixture_fire' () i32).
        sub := FFI bind: #$desc.
        [
            busy := [FFI bind: #$desc. false] on: FFIError do: [:e | true].
            ok := busy and: [sub poll and: [sub poll not and: [
                (fire invoke: #()) = 1 and: [sub poll and: [sub poll not]]]]]
        ] ensure: [sub close. sub close].
        (fire invoke: #()) = 0 ifFalse: [^false].
        again := FFI bind: #$desc.
        [ok and: [sub close. again poll and: [again poll not]]]
            ensure: [again close]"
}
SAMALTAK_NATIVE_GRANTS="$MANIFEST" exercise "$D"
SAMALTAK_NATIVE_GRANTS="$VOIDMANIFEST" exercise "$V"

reject_manifest() {
    code=0
    SAMALTAK_NATIVE_GRANTS=$1 "$VM" "$IMAGE" --headless --eval true >"$TMP/out" 2>&1 || code=$?
    if [ "$code" -ne 64 ] || ! grep -Fq 'invalid or unresolved SAMALTAK_NATIVE_GRANTS' "$TMP/out"; then
        cat "$TMP/out" >&2
        echo "ffi_external_notification_test: expected launch rejection, got $code" >&2
        exit 1
    fi
}
reject_manifest "fixture|fixture_subscribe|notifyI32(u32,u64)|fixture_unsubscribe|$LIB"
reject_manifest "fixture|fixture_subscribe|notifyI32(context,context)|fixture_unsubscribe|$LIB"
reject_manifest "fixture|fixture_subscribe|notifyI32(context,f64)|fixture_unsubscribe|$LIB"
reject_manifest "fixture|fixture_subscribe|notifyI32(context)|missing|$LIB"
reject_manifest "$ROW
other|fixture_subscribe|notifyI32(u32,context,u64)|fixture_unsubscribe|$LIB"

# A stale saved token must not read or close a new live registration.
SNAP="$TMP/saved.image"
SAMALTAK_NATIVE_GRANTS="$MANIFEST" expect 0 "$IMAGE" --headless --eval "
    | old fresh stale |
    old := FFI bind: #$D.
    (Smalltalk snapshot: '$SNAP') ifTrue: [
        fresh := FFI bind: #$D.
        ^[
            stale := [old poll. false] on: FFIError do: [:e | true].
            old close.
            stale and: [fresh poll]
        ] ensure: [fresh close]].
    old close.
    0"
SAMALTAK_NATIVE_GRANTS="$MANIFEST" expect true "$SNAP" --headless

echo "ffi_external_notification_test: passed"
