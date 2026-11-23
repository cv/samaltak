#!/bin/sh
# Usage: ffi_migration_gate_test.sh IMAGE VM sdl|no-platform release|test|prior-release
# Deliberately uses --eval, not --load (the latter needs platform file support).
set -eu
IMAGE=${1:?supply a full image}
VM=${2:?supply a hosted VM}
case ${3:-} in sdl) PLATFORM=true ;; no-platform) PLATFORM=false ;; *) exit 2 ;; esac
case ${4:-} in
    test) NEW=true; TEST=true ;;
    release) NEW=true; TEST=false ;;
    prior-release) NEW=false; TEST=false ;;
    *) exit 2 ;;
esac
TMP=$(mktemp -d /tmp/samaltak-ffi-gates.XXXXXXXX)
trap 'rm -rf "$TMP"' EXIT
unset DISPLAY WAYLAND_DISPLAY SAMALTAK_NATIVE_GRANTS
export LC_ALL=C
export SDL_VIDEO_DRIVER=ffi_gate_no_video SDL_VIDEODRIVER=ffi_gate_no_video

for mode in none baseline opt; do
    if ! SAMALTAK_FFI_TEST_EXPORTS=1 "$VM" --jit "$mode" "$IMAGE" --headless --eval "
    | must bindDenied legacyBind legacyInvoke rawDescriptor sqrtId cmpId parts writable names f |
    must := [:ok :label | ok ifFalse: [Error signal: label]].
    bindDenied := [:d | [FFI bind: d. false] on: FFIError do: [:e | true]].
    Compiler compile: 'migrationLegacyBind: library symbol: name tags: tags result: result
        <primitive: ''ffiBind''>
        ^#rejected' in: FFI class.
    Compiler compile: 'migrationLegacyInvoke: id library: library symbol: name tags: tags result: result args: args
        <primitive: ''ffiInvoke''>
        ^#rejected' in: FFI class.
    legacyBind := [:d | FFI migrationLegacyBind: d first symbol: d second tags: d third result: d fourth].
    legacyInvoke := [:id :d :args | FFI migrationLegacyInvoke: id library: d first
        symbol: d second tags: d third result: d fourth args: args].
    rawDescriptor := [:library :name :tags :result |
        | descriptor |
        descriptor := {library. name. tags. result}.
        descriptor do: [:part | part isInteger ifFalse: [part beReadOnlyObject]].
        descriptor beReadOnlyObject.
        FFIBinding new initializeDescriptor: descriptor].

    parts := #('libm' 'sqrt' #[6] 6).
    sqrtId := legacyBind value: parts.
    must value: (sqrtId = 6) value: 'legacy 250 sqrt ID changed'.
    must value: ((legacyInvoke value: sqrtId value: parts value: #(9.0)) = 3.0)
        value: 'legacy 251 sqrt mismatch'.
    parts := #('libc' 'memcmp' #[5 5 4] 1).
    cmpId := legacyBind value: parts.
    must value: (cmpId = 11) value: 'legacy 250 memcmp ID changed'.
    must value: ((legacyInvoke value: cmpId value: parts value: #((#[9 4 5] 2 2) (#[4 5] 1 2) 2)) = 0)
        value: 'legacy 251 counted memcmp mismatch'.
    must value: ((legacyInvoke value: cmpId value: parts value: #((#[9 4 5] 2 2) (#[4 5] 1 2) 3)) == #rejected)
        value: 'legacy memcmp count exceeds slice'.
    must value: ((bindDenied value: #(call platform pty_foreground (i64) i32)) = $PLATFORM not)
        value: 'old platform export availability changed'.
    must value: ((legacyBind value: #('platform' 'pty_foreground' #[3] 1))
        = ($PLATFORM ifTrue: [40] ifFalse: [#rejected])) value: 'legacy platform 250 ID or availability changed'.

    $NEW ifTrue: [
        must value: ((bindDenied value: #(call platform platform_files_position (i64) i64)) = $PLATFORM not)
            value: 'generated platform export has wrong backend availability'.
        f := FFI bind: #(call 'vm:core' ffi_owned_size (u64) i32).
        must value: ((f tryInvoke1: 0) = -1) value: 'hosted core export did not return its native status'.
        names := #(
          ('vm:core' 'ffi_owned_size' #[4] 1 5025 #(0))
          ('vm:core' 'ffi_owned_release' #[4] 1 5027 #(0))
          ('vm:core' 'ffi_owned_reserve' #[2 9] 1 5024 #(0 (#[] 1 0)))
          ('platform' 'platform_files_position' #[3] 3 1529 #(-1))).
        names do: [:row |
            must value: ((legacyBind value: row) == #rejected) value: 'legacy 250 admitted generated export'.
            must value: ((legacyInvoke value: (row at: 5) value: row value: (row at: 6)) == #rejected)
                value: 'legacy 251 admitted generated export'].
        f := rawDescriptor value: 'vm:core' value: 'ffi_owned_size' value: #[4] value: 3.
        must value: f prepare not value: 'raw wrong-signature descriptor admitted'.
        f := rawDescriptor value: 'vm:core' value: 'ffi_owned_reserve' value: #[2 8] value: 1.
        must value: f prepare not value: 'raw descriptor downgraded writable borrow to const'.
        f := rawDescriptor value: 'vm:core' value: 'ffi_owned_size' value: #[4] value: 9.
        must value: f prepare not value: 'raw pointer-like result tag admitted'].

    writable := #(call 'vm:core' ffi_test_writable_pair (writableBytesWithLength f64 i32 writableBytesWithLength) i64).
    must value: ((bindDenied value: writable) = $TEST not) value: 'writable fixture build gate mismatch'.
    must value: (bindDenied value: #(call 'vm:core' ffi_test_writable_pair
        (bytesWithLength f64 i32 writableBytesWithLength) i64)) value: 'writable fixture accepted const substitution'.
    must value: (bindDenied value: #(call 'vm:core' ffi_test_writable_pair
        (writableBytesWithLength f64 i32 writableBytesWithLength u64) i64)) value: 'seven native slots accepted'.
    must value: (bindDenied value: #(call 'vm:core' ffi_test_writable_pair
        (writableBytesWithLength f64 i32 writableBytesWithLength) writableBytesWithLength)) value: 'writable result was accepted'.
    true
    " >"$TMP/out" 2>&1 || ! grep -Fxq true "$TMP/out"; then
        cat "$TMP/out" >&2
        echo "ffi_migration_gate_test: $3/$4/$mode failed" >&2
        exit 1
    fi
done
echo "ffi_migration_gate_test: $3/$4 passed"
