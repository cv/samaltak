#!/bin/sh
# Usage: ffi_trial_test.sh IMAGE VM [OLD_VM [OLD_IMAGE]] (headless).
set -eu
IMAGE=$(realpath "${1:?image}")
VM=$(realpath "${2:?VM}")
OLD_VM=${3:+$(realpath "$3")}
OLD_IMAGE=${4:+$(realpath "$4")}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
unset DISPLAY WAYLAND_DISPLAY SAMALTAK_NATIVE_GRANTS SAMALTAK_FFI_NATIVE_TRACE
export SDL_VIDEODRIVER=ffi_no_video SDL_VIDEO_DRIVER=ffi_no_video
cd "$TMP"
printf abc > payload
for mode in none baseline opt; do
    SAMALTAK_FFI_TRIAL=1 SAMALTAK_FFI_NATIVE_TRACE=1 "$VM" --jit "$mode" --jit-threshold 0 "$IMAGE" --headless --eval "
    [
        | selector original sibling ok |
        selector := #primSize:.
        original := File class compiledMethodAt: selector.
        sibling := File class compiledMethodAt: #ffiCandidatePrimSize:.
        FFITrial withInstalled: selector on: File class do: [
            ((File class compiledMethodAt: selector) == original) ifTrue: [Error signal: 'not published'].
            FileStream readOnlyFileNamed: 'payload' do: [:f |
                f size = 3 ifFalse: [Error signal: 'wrong installed native size']].
            (File primSize: nil) isNil ifFalse: [Error signal: 'wrong guard-miss fallback']].
        ((File class compiledMethodAt: selector) == original and: [
            (File class compiledMethodAt: #ffiCandidatePrimSize:) == sibling and: [
                (File class includesSelector: #ffiLegacyPrimSize:) not]])
            ifFalse: [Error signal: 'uninstall failed'].
        FFITrial install: selector on: File class.
        (Smalltalk snapshot: 'trial.image') ifTrue: [
            ((File class compiledMethodAt: selector) == original and: [
                (File class includesSelector: #ffiLegacyPrimSize:) not])
                ifFalse: [Error signal: 'trial persisted in snapshot'].
            Smalltalk vm stdoutWrite: 'trial restored', (String with: Character lf). Smalltalk quit].
        true
    ] on: Error do: [:e | Smalltalk vm stderrWrite: e messageText. Smalltalk quit: 1]" >out 2>err || { cat out err >&2; exit 1; }
    grep -Fxq true out
    test "$(grep -Fxc 'ffi-native-entry 1528' err)" = 1 || { cat err >&2; exit 1; }
    SAMALTAK_FFI_NATIVE_TRACE=1 "$VM" --jit "$mode" "$IMAGE" --headless --eval "
        | signedSize typedSize signedPosition typedPosition |
        signedSize := FFI bind: #(call 'platform' 'platform_files_size' (i64) i64).
        typedSize := FFI bind: #(call 'platform' 'platform_files_size' (i64) nonNegativeI64).
        typedPosition := FFI bind: #(call 'platform' 'platform_files_position' (i64) nonNegativeI64).
        signedPosition := FFI bind: #(call 'platform' 'platform_files_position' (i64) i64).
        (signedSize tryInvoke1: -1) = -1 and: [
            (typedSize tryInvoke1: -1) isNil and: [
            (typedPosition tryInvoke1: -1) isNil and: [
            (signedPosition tryInvoke1: -1) = -1 and: [
            (typedSize tryInvoke1: nil) == false and: [
            (typedPosition tryInvoke1: nil) == false]]]]]" >out 2>err || { cat out err >&2; exit 1; }
    grep -Fxq true out || { cat out err >&2; exit 1; }
    test "$(grep -Fxc 'ffi-native-entry 1528' err)" = 2 || { cat err >&2; exit 1; }
    test "$(grep -Fxc 'ffi-native-entry 1529' err)" = 2 || { cat err >&2; exit 1; }
    "$VM" --jit "$mode" trial.image --headless >out 2>err || { cat out err >&2; exit 1; }
    grep -Fxq 'trial restored' out || { cat out err >&2; exit 1; }
done
if [ -n "$OLD_VM" ]; then
    SAMALTAK_FFI_TRIAL=1 SAMALTAK_FFI_NATIVE_TRACE=1 "$OLD_VM" "$IMAGE" --headless --eval "
        | selector original handle rejected |
        selector := #primSize:.
        original := File class compiledMethodAt: selector.
        rejected := [FFITrial install: selector on: File class. false]
            on: Error do: [:e | e messageText = 'Native target not available in this VM'].
        (rejected and: [(File class compiledMethodAt: selector) == original and: [
            (File class includesSelector: #ffiLegacyPrimSize:) not]])
                ifFalse: [Error signal: 'Legacy VM admitted or mutated typed trial'].
        handle := File primOpen: 'payload' mode: 0.
        [(File ffiCandidatePrimSize: handle) = 3 and: [
            (File ffiCandidatePrimPosition: handle) = 0]]
                ensure: [File primClose: handle]" >out 2>err || { cat out err >&2; exit 1; }
    grep -Fxq true out
    ! grep -q 'ffi-native-entry 152[89]' err
fi
if [ -n "$OLD_IMAGE" ]; then
    SAMALTAK_FFI_NATIVE_TRACE=1 "$VM" "$OLD_IMAGE" --headless --eval "
        | binding |
        binding := FFI bind: #(call 'platform' 'platform_files_size' (i64) i64).
        (binding tryInvoke1: -1) = -1" >out 2>err || { cat out err >&2; exit 1; }
    grep -Fxq true out
    test "$(grep -Fxc 'ffi-native-entry 1528' err)" = 1
fi
echo 'ffi_trial_test: install, native entry, legacy fallback, uninstall, snapshot passed'
