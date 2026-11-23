#!/bin/sh
# Usage: bigint_owned_ffi_test.sh IMAGE VM LOG_DIR
set -eu
image=${1:?}
vm=${2:?}
out=${3:?}
mkdir -p "$out"
here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
proof=$(cat "$here/bigint_ffi.st" "$here/bigint_owned_ffi.st" | sed "s/'/''/g")
unset DISPLAY WAYLAND_DISPLAY SAMALTAK_NATIVE_GRANTS SAMALTAK_FFI_BOX_FULL_GC
export LC_ALL=C SAMALTAK_FFI_NATIVE_TRACE=1 SAMALTAK_VERIFY_GC=1
export SDL_VIDEO_DRIVER=bigint_no_video SDL_VIDEODRIVER=bigint_no_video
run() {
  mode=$1
  label=$2
  method=$3
  "$vm" --jit "$mode" --jit-opt 8 --eden 1 "$image" --headless \
    --eval "[Compiler fileInString: '$proof'. Compiler evaluate: 'BigIntegerFFIProof $method']
      on: Error do: [:e | Smalltalk vm stderrWrite: e messageText, (String with: Character lf).
      Smalltalk vm stderrWrite: (e signalerContext stack first: 15) printString.
      Smalltalk quit: 1]" >"$out/$label.out" 2>"$out/$label.err"
  grep -Fxq true "$out/$label.out"
}
for mode in none baseline opt; do
  run "$mode" "owned-$mode" 'ownedResults: false'
  run "$mode" "production-$mode" production
  for id in 1044 1045 1046 1047 1048 1049 1050 1051 1052 1053 1054 1055; do
    # Production run has no manually prepared bindings.
    grep -Fxq "ffi-native-entry $id" "$out/production-$mode.err"
  done
  SAMALTAK_FFI_BOX_FULL_GC=1 SAMALTAK_FFI_SITE_TRACE=1 run "$mode" "gc-$mode" forceGC
  n=$(grep -Fxc 'ffi-native-entry 1044' "$out/gc-$mode.err")
  test "$n" -ge 74
  grep -Fxq 'ffi-native-entry 1055' "$out/gc-$mode.err"
  run "$mode" "portable-$mode" forcePortable
  awk '/^begin portable bigint$/ { in_portable=1; seen=1 }
       /^end portable bigint$/ { in_portable=0 }
       in_portable && /^ffi-native-entry 10(4[4-9]|5[0-5])$/ { bad=1 }
       END { exit !seen || in_portable || bad }' "$out/portable-$mode.err"
done
awk '/^ffi-site trace hits=/ { split($3,h,"="); hit=(h[2]>0)} END {exit !hit}' "$out/gc-opt.err"
echo 'bigint_owned_ffi_test: passed'
