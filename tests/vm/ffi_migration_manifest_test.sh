#!/bin/sh
# Usage: ffi_migration_manifest_test.sh IMAGE VM
set -eu
IMAGE=${1:?supply a full image}
VM=${2:?supply a hosted VM (SDL or NO_PLATFORM)}
TMP=$(mktemp -d /tmp/samaltak-ffi-manifest.XXXXXXXX)
trap 'rm -rf "$TMP"' EXIT
unset DISPLAY WAYLAND_DISPLAY SAMALTAK_NATIVE_GRANTS
export LC_ALL=C
export SDL_VIDEO_DRIVER=ffi_manifest_no_video SDL_VIDEODRIVER=ffi_manifest_no_video
export FFI_MANIFEST_MARKER="$TMP/loaded"

cat >"$TMP/fixture.c" <<'C'
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

__attribute__((constructor))
static void mark_loaded(void)
{
    const char *path = getenv("FFI_MANIFEST_MARKER");
    FILE *out = path ? fopen(path, "w") : NULL;
    if (out)
        fclose(out);
}

static int32_t calls;
int32_t migration_step(int32_t n) { ++calls; return n; }
int32_t migration_calls(void) { return calls; }

int32_t migration_readonly(const uint8_t *bytes, uint64_t length)
{
    ++calls;
    return length ? bytes[0] + bytes[length - 1] : 0;
}
C

case $(uname -s) in
    Linux) link=-shared; ext=so ;;
    Darwin) link=-dynamiclib; ext=dylib ;;
    *) echo 'ffi_migration_manifest_test: unsupported host' >&2; exit 77 ;;
esac
LIB="$TMP/fixture.$ext"
"${CC:-cc}" -std=c99 -Wall -Wextra -Werror "$link" -fPIC -o "$LIB" "$TMP/fixture.c"

STEP="migration|migration_step|i32(i32)|$LIB"
COUNT="migration|migration_calls|i32()|$LIB"
BORROW="migration|migration_readonly|i32(bytesWithLength)|syncBorrow|$LIB"

reject() {
    name=$1; bad=$2
    rm -f "$FFI_MANIFEST_MARKER"
    code=0
    # The entire manifest must pass grammar/authority checks before opening even
    # its first (valid) row. Constructor execution is an independent witness.
    SAMALTAK_NATIVE_GRANTS="$STEP
$bad" "$VM" "$IMAGE" --headless --eval true >"$TMP/out" 2>&1 || code=$?
    if [ "$code" != 64 ] || [ -e "$FFI_MANIFEST_MARKER" ] ||
        ! grep -Fq 'invalid or unresolved SAMALTAK_NATIVE_GRANTS' "$TMP/out"; then
        cat "$TMP/out" >&2
        echo "ffi_migration_manifest_test: $name must fail before loading any library (exit $code)" >&2
        exit 1
    fi
}

reject writable-argument "migration|migration_readonly|i32(writableBytesWithLength)|syncBorrow|$LIB"
reject writable-result "migration|migration_readonly|writableBytesWithLength(bytesWithLength)|syncBorrow|$LIB"
reject raw-pointer-argument "migration|migration_readonly|i32(ptr,u64)|$LIB"
reject raw-pointer-result "migration|migration_step|ptr(i32)|$LIB"
reject uncounted-borrow "migration|migration_readonly|i32(byteSlice)|syncBorrow|$LIB"
reject counted-borrow-result "migration|migration_readonly|bytesWithLength(bytesWithLength)|syncBorrow|$LIB"
reject missing-sync-contract "migration|migration_readonly|i32(bytesWithLength)|$LIB"
reject unrecognized-sync-contract "migration|migration_readonly|i32(bytesWithLength)|syncWrite|$LIB"
reject scalar-with-sync-contract "migration|migration_calls|i32()|syncBorrow|$LIB"
reject excess-expanded-slots "migration|migration_readonly|i32(bytesWithLength,bytesWithLength,bytesWithLength,u64)|syncBorrow|$LIB"
reject platform-namespace "platform|migration_step|i32(i32)|$LIB"
reject builtin-core-namespace "vm:core|migration_step|i32(i32)|$LIB"
reject integer-magnitude-argument "migration|migration_readonly|i32(integerMagnitude)|syncBorrow|$LIB"
reject integer-magnitude-result "migration|migration_step|integerMagnitude(i32)|$LIB"
reject owned-magnitude-result "migration|migration_step|ownedIntegerMagnitude(i32)|$LIB"

# A real (const) external borrow continues to accept mutable and read-only
# ByteArrays, rejects malformed slices before entry, and does not mutate them.
if ! SAMALTAK_NATIVE_GRANTS="$STEP
$COUNT
$BORROW
core|migration_step|i32(i32)|$LIB" "$VM" "$IMAGE" --headless --eval '
    | step oldCore count read bindDenied bytes literal slice results before |
    step := FFI bind: #(call migration migration_step (i32) i32).
    oldCore := FFI bind: #(call core migration_step (i32) i32).
    count := FFI bind: #(call migration migration_calls () i32).
    read := FFI bind: #(call migration migration_readonly (bytesWithLength) i32).
    bindDenied := [:d | [FFI bind: d. false] on: FFIError do: [:e | true]].
    (#((call migration migration_readonly (writableBytesWithLength) i32)
       (call migration migration_readonly (byteSlice) i32)
       (call migration migration_readonly (bytesWithLength) bytesWithLength)
       (call migration migration_readonly (u64 u64) i32)
       (call migration migration_step (i32) u32))
        allSatisfy: bindDenied) ifFalse: [^false].
    (count tryInvoke0 = 0) ifFalse: [^false].
    bytes := #[90 7 8 15 91] copy.
    literal := #[90 7 8 15 91].
    slice := {bytes. 2. 3}.
    results := {step tryInvoke1: -8. read tryInvoke: {slice}.
        read tryInvoke1: {literal. 2. 3}. read tryInvoke1: {bytes. 6. 0}}.
    results = #(-8 22 22 0) ifFalse: [^false].
    (oldCore tryInvoke1: 13) = 13 ifFalse: [^false].
    count tryInvoke0 = 5 ifFalse: [^false].
    before := count tryInvoke0.
    ({ {bytes. 0. 1}. {bytes. 6. 1}. {bytes. 7. 0}. {bytes. 1. -1}.
        {bytes. 2. 16r4000000000000000}. {bytes. 2. 1. 0}. {bytes. 2. 1.0}.
        {#notBytes. 1. 1} } allSatisfy: [:candidate |
            (read tryInvoke1: candidate) == false and: [(read tryInvoke: {candidate}) == false]])
        ifFalse: [^false].
    count tryInvoke0 = before and: [bytes = literal]
' >"$TMP/out" 2>&1 || ! grep -Fxq true "$TMP/out" || [ ! -f "$FFI_MANIFEST_MARKER" ]; then
    cat "$TMP/out" >&2
    echo 'ffi_migration_manifest_test: valid external controls failed' >&2
    exit 1
fi
echo 'ffi_migration_manifest_test: passed'
