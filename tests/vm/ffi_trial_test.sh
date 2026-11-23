#!/bin/sh
# Run only a disposable copy of the hosted image; never starts video.
set -eu
IMAGE=$(realpath "${1:?image}")
VM=$(realpath "${2:?VM}")
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
    "$VM" --jit "$mode" trial.image --headless >out 2>err || { cat out err >&2; exit 1; }
    grep -Fxq 'trial restored' out || { cat out err >&2; exit 1; }
done
echo 'ffi_trial_test: install, native entry, legacy fallback, uninstall, snapshot passed'
