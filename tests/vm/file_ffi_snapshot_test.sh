#!/bin/sh
# Usage: file_ffi_snapshot_test.sh IMAGE VM (SDL hosted; no display).
set -eu
IMAGE=$(realpath "${1:?image}")
VM=$(realpath "${2:?VM}")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
unset DISPLAY WAYLAND_DISPLAY XAUTHORITY SAMALTAK_NATIVE_GRANTS
export SDL_VIDEODRIVER=ffi_no_video SDL_VIDEO_DRIVER=ffi_no_video
export SAMALTAK_FFI_NATIVE_TRACE=1 LC_ALL=C
cd "$TMP"
printf abc > payload
expect() {
    expected=$1; size=$2; position=$3
    shift 3
    if ! "$VM" "$@" >out 2>err || ! grep -Fxq "$expected" out ||
        ! awk -v size="$size" -v position="$position" '
            $0 == "file-ffi-begin" { active = 1; begins++ }
            $0 == "file-ffi-end" { active = 0; ends++ }
            active && $0 == "ffi-native-entry 1528" { sizes++ }
            active && $0 == "ffi-native-entry 1529" { positions++ }
            END { exit !(begins == 1 && ends == 1 && sizes == size && positions == position) }
        ' err; then
        cat out err >&2
        echo "file_ffi_snapshot_test: expected '$expected' with $size size and $position position entries" >&2
        exit 1
    fi
}
for mode in none baseline opt; do
    set -- --jit "$mode" --jit-threshold 0
    [ "$mode" != opt ] || set -- "$@" --jit-flags eager
    expect true 3 3 "$@" "$IMAGE" --headless --eval "
    [
        | signedSize typedSize signedPosition typedPosition |
        signedSize := FFI bind: #(call 'platform' 'platform_files_size' (i64) i64).
        typedSize := FFI bind: #(call 'platform' 'platform_files_size' (i64) nonNegativeI64).
        signedPosition := FFI bind: #(call 'platform' 'platform_files_position' (i64) i64).
        typedPosition := FFI bind: #(call 'platform' 'platform_files_position' (i64) nonNegativeI64).
        Smalltalk vm stderrWrite: 'file-ffi-begin', (String with: Character lf).
        FileStream readOnlyFileNamed: 'payload' do: [:f |
            (f size = 3 and: [f position = 0])
                ifFalse: [Error signal: 'FileStream size/position changed']].
        ((File primSize: nil) isNil and: [(File primPosition: nil) isNil])
            ifFalse: [Error signal: 'public sends did not reject malformed handles'].
        ((signedSize tryInvoke1: -1) = -1 and: [
            (typedSize tryInvoke1: -1) isNil and: [
            (signedPosition tryInvoke1: -1) = -1 and: [
            (typedPosition tryInvoke1: -1) isNil and: [
            (typedSize tryInvoke1: nil) == false and: [
            (typedPosition tryInvoke1: nil) == false]]]]])
               ifFalse: [Error signal: 'guard and completed failure became indistinguishable'].
        Smalltalk vm stderrWrite: 'file-ffi-end', (String with: Character lf).
        (Smalltalk snapshot: 'files.image') ifTrue: [
            Smalltalk vm stderrWrite: 'file-ffi-begin', (String with: Character lf).
            FileStream readOnlyFileNamed: 'payload' do: [:f |
                | h |
                h := f instVarNamed: 'handle'.
                ((f size = 3 and: [f position = 0]) and: [
                    (typedSize tryInvoke1: h) = 3 and: [(typedPosition tryInvoke1: h) = 0]])
                        ifFalse: [Error signal: 'size/position did not rebind after restore']].
            Smalltalk vm stderrWrite: 'file-ffi-end', (String with: Character lf).
            Smalltalk vm stdoutWrite: 'file routes restored', (String with: Character lf).
            Smalltalk quit].
        true
    ] on: Error do: [:e | Smalltalk vm stderrWrite: e messageText. Smalltalk quit: 1]"
    expect 'file routes restored' 2 2 "$@" files.image --headless
done
echo 'file_ffi_snapshot_test: public sends, guard, native failure and snapshot restore passed'
