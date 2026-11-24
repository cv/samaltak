#!/bin/sh
# Usage: ffi_migration_owned_test.sh IMAGE VM sdl|no-platform release|test
# 'test' requires a SAMALTAK_FFI_TEST_EXPORTS build. Snapshot I/O needs SDL.
set -eu
IMAGE=${1:?supply a full image}
VM=${2:?supply a hosted VM}
case ${3:-} in sdl|no-platform) ;; *) exit 2 ;; esac
backend=$3
case ${4:-} in release|test) ;; *) exit 2 ;; esac
TMP=$(mktemp -d /tmp/samaltak-ffi-owned.XXXXXXXX)
trap 'rm -rf "$TMP"' EXIT
unset DISPLAY WAYLAND_DISPLAY SAMALTAK_NATIVE_GRANTS SAMALTAK_FFI_OWNED_TEST
export LC_ALL=C SAMALTAK_VERIFY_GC=1
export SDL_VIDEO_DRIVER=ffi_owned_no_video SDL_VIDEODRIVER=ffi_owned_no_video

expect() {
    label=$1 marker=$2
    shift 2
    if ! "$VM" "$@" >"$TMP/out" 2>&1 || ! grep -Fxq -e "$marker" "$TMP/out"; then
        cat "$TMP/out" >&2
        echo "ffi_migration_owned_test: $backend $label failed (expected $marker)" >&2
        exit 1
    fi
}

init="
    must := [:ok :label | ok ifFalse: [Error signal: label]].
    reserve := FFI bind: #(call 'vm:core' ffi_owned_reserve (u32 writableBytesWithLength) i32).
    size := FFI bind: #(call 'vm:core' ffi_owned_size (u64) i32).
    copy := FFI bind: #(call 'vm:core' ffi_owned_copy (u64 writableBytesWithLength) i32).
    release := FFI bind: #(call 'vm:core' ffi_owned_release (u64) i32).
    alloc := [:cap | | buffer |
        buffer := ByteArray new: 8.
        (reserve tryInvoke2: cap with: {buffer. 1. 8}) = 1
            ifTrue: [FFIWire uint64At: 1 in: buffer] ifFalse: [0]].
"
decl='must reserve size copy release alloc'
for mode in none baseline opt; do
    expect "reserve-$mode" true --jit "$mode" "$IMAGE" --headless --eval "
    | $decl buffer t entries refused |
    $init
    buffer := ByteArray new: 10.
    buffer at: 1 put: 91; at: 10 put: 92.
    must value: ((reserve tryInvoke2: 1 with: {buffer. 2. 7}) = 0)
        value: 'wrong ticket output length accepted'.
    must value: ((reserve tryInvoke2: 1 with: {#[0 0 0 0 0 0 0 0]. 1. 8}) == false)
        value: 'immutable ticket output accepted'.
    must value: ((reserve tryInvoke2: 67108865 with: {buffer. 2. 8}) = 0)
        value: 'over-budget reservation accepted'.
    must value: (buffer = #[91 0 0 0 0 0 0 0 0 92]) value: 'rejection modified ticket buffer'.
    must value: ((reserve tryInvoke2: 67108864 with: {buffer. 2. 8}) = 1)
        value: 'exact-budget reservation rejected'.
    t := FFIWire uint64At: 2 in: buffer.
    must value: (t class == SmallInteger and: [t > 0])
        value: 'ticket is not a positive immediate'.
    must value: ((buffer at: 1) = 91 and: [(buffer at: 10) = 92])
        value: 'reserve wrote outside slice'.
    must value: ((reserve tryInvoke2: 0 with: {buffer. 2. 8}) = 0)
        value: 'nonzero ticket output accepted'.
    must value: ((FFIWire uint64At: 2 in: buffer) = t)
        value: 'failed reserve modified existing ticket'.
    must value: ((alloc value: 1) = 0) value: 'aggregate budget not enforced'.
    must value: ((size tryInvoke1: t) = -1) value: 'unpublished ticket has output'.
    must value: ((copy tryInvoke2: t with: {buffer. 2. 8}) = 0)
        value: 'unpublished ticket copied output'.
    must value: ((FFIWire uint64At: 2 in: buffer) = t)
        value: 'unpublished copy modified destination'.
    Smalltalk vm scavenge; garbageCollect.
    must value: ((release tryInvoke1: t) = 1) value: 'ordinary GC revoked live reservation'.
    must value: ((release tryInvoke1: t) = 0) value: 'released ticket consumed twice'.
    entries := (1 to: 16) collect: [:i | alloc value: 1].
    must value: (entries allSatisfy: [:each | each > 0]) value: 'reservation slots leaked'.
    must value: ((entries asSet size = 16) and: [(entries includes: t) not]) value: 'ticket reused'.
    refused := alloc value: 0.
    must value: (refused = 0) value: 'slot bound not enforced for empty reservation'.
    must value: (entries allSatisfy: [:each | (release tryInvoke1: each) = 1]) value: 'release failed'.
    t := alloc value: 67108864.
    must value: (t > 0 and: [(release tryInvoke1: t) = 1]) value: 'release did not restore byte quota'.
    true"

    if [ "$4" = release ]; then
        SAMALTAK_FFI_OWNED_TEST=1 SAMALTAK_FFI_TEST_EXPORTS=1 expect "fixture-gate-$mode" true --jit "$mode" "$IMAGE" --headless --eval "
            [FFI bind: #(call 'vm:core' ffi_test_owned_octets (u64 i32) i32). false]
                on: FFIError do: [:e | true]"
        continue
    fi

    expect "fixture-runtime-gate-$mode" true --jit "$mode" "$IMAGE" --headless --eval "
        | $decl f t |
        $init
        f := FFI bind: #(call 'vm:core' ffi_test_owned_octets (u64 i32) i32).
        t := alloc value: 5.
        (f tryInvoke2: t with: 1) = -37 and: [(release tryInvoke1: t) = 1]"

    SAMALTAK_FFI_OWNED_TEST=1 expect "published-$mode" true --jit "$mode" "$IMAGE" --headless --eval "
    | $decl f t next bytes values calls failed signal worker capture |
    $init
    f := FFI bind: #(call 'vm:core' ffi_test_owned_octets (u64 i32) i32).
    t := alloc value: 5.
    must value: ((f tryInvoke: {t. 1}) = 1) value: 'array publisher failed'.
    must value: ((f tryInvoke2: t with: 3) = -29) value: 'published ticket produced twice'.
    Smalltalk vm scavenge; garbageCollect.
    must value: ((size tryInvoke1: t) = 5) value: 'ordinary GC discarded payload'.
    bytes := #[91 8 8 8 8 8 92] copy.
    must value: ((copy tryInvoke2: t with: {bytes. 2. 4}) = 0) value: 'short copy accepted'.
    must value: ((copy tryInvoke2: t with: {bytes. 2. 6}) = 0) value: 'long copy accepted'.
    must value: ((copy tryInvoke2: t with: {#[91 8 8 8 8 8 92]. 2. 5}) == false)
        value: 'immutable copy destination accepted'.
    must value: (bytes = #[91 8 8 8 8 8 92]) value: 'rejected copy mutated bytes'.
    must value: ((copy tryInvoke: {t. {bytes. 2. 5}}) = 1) value: 'exact copy failed'.
    must value: (bytes = #[91 0 255 65 128 0 92]) value: 'copy data or bounds mismatch'.
    must value: ((release tryInvoke1: t) = 1) value: 'published release failed'.
    next := alloc value: 5.
    must value: ((f tryInvoke2: t with: 1) = -29 and: [(size tryInvoke1: t) = -1])
        value: 'freed ticket reused'.
    must value: ((f tryInvoke2: next with: 0) = 0 and: [(f tryInvoke2: next with: 1) = -29])
        value: 'absent producer replay allowed'.
    must value: ((release tryInvoke1: next) = 1) value: 'absent result not released'.

    values := {nil. #[0 255 65 128 0]. #[]. #[0 255 65 128 0]}.
    calls := 0.
    capture := [:cap :kind | FFIOwnedOutput captureUpTo: cap do: [:ticket |
        calls := calls + 1.
        f tryInvoke2: ticket with: kind]].
    0 to: 3 do: [:kind |
        | result |
        result := capture value: 5 value: kind.
        must value: (result = (values at: kind + 1)) value: 'capture data/status mismatch'.
        kind ~= 0 ifTrue: [must value: (result class == ByteArray) value: 'result not an exact ByteArray']].
    must value: ((capture value: 5 value: -1) = -17) value: 'completed failure was retried or erased'.
    must value: ((capture value: 4 value: 1) = -23) value: 'over-cap payload clipped or retried'.
    must value: ((capture value: 5 value: 1.0) == false) value: 'pre-entry rejection was not false'.
    must value: ((capture value: 67108865 value: 1) == false) value: 'invalid reservation cap admitted'.
    must value: (calls = 7) value: 'producer block count mismatch'.

    20 timesRepeat: [
        failed := [capture value: 67108864 value: 4. false] on: FFIError do: [:e | true].
        must value: failed value: 'post-entry malformed result did not signal'.
        failed := [FFIOwnedOutput captureUpTo: 67108864 do: [:ticket |
            f tryInvoke2: ticket with: 3.
            Error signal: 'cancel after publication']. false]
                on: Error do: [:e | e messageText = 'cancel after publication'].
        must value: failed value: 'producer unwind lost original error'].

    signal := Semaphore new.
    worker := [FFIOwnedOutput captureUpTo: 67108864 do: [:ticket |
        f tryInvoke2: ticket with: 3.
        signal signal.
        Semaphore new wait]] fork.
    signal wait.
    worker terminate.
    must value: ((capture value: 67108864 value: 1) = #[0 255 65 128 0])
        value: 'termination or post-entry failure leaked reservation'.
    true"
done

if [ "$3" = sdl ]; then
    SNAP="$TMP/owned.image"
    expect snapshot '#saved' "$IMAGE" --headless --eval "
    | $decl old fresh |
    $init
    old := alloc value: 67108864.
    must value: (old > 0) value: 'initial reserve failed'.
    (Smalltalk snapshot: '$SNAP') ifTrue: [
        fresh := alloc value: 67108864.
        must value: (fresh > 0 and: [fresh ~= old]) value: 'snapshot retained authority/quota'.
        must value: ((release tryInvoke1: old) = 0) value: 'stale ticket remained live'.
        must value: ((release tryInvoke1: fresh) = 1) value: 'stale release affected fresh row'.
        ^#restored].
    must value: ((alloc value: 1) = 0 and: [(release tryInvoke1: old) = 1])
        value: 'snapshot revoked live process reservation'.
    #saved"
    expect restore '#restored' "$SNAP" --headless
fi
echo "ffi_migration_owned_test: $3/$4 passed"
