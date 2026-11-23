#!/bin/sh
# Usage: tests/vm/bound_ffi_site_test.sh IMAGE [VM [--no-pty]]
# Set SITEFFI_TEST_LOG_DIR to preserve the witness route, counters and other logs.
set -eu
IMAGE=${1:?supply a full image}
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
VM=${2:-"$ROOT/vm/build/samaltak"}
case ${3:-} in ''|--no-pty) ;; *) echo 'expected --no-pty' >&2; exit 2 ;; esac
TMP=$(mktemp -d /tmp/samaltak-ffi-site.XXXXXXXX)
trap 'rm -rf "$TMP"' EXIT
LOG=${SITEFFI_TEST_LOG_DIR:-"$TMP"}
mkdir -p "$LOG"
unset DISPLAY WAYLAND_DISPLAY SAMALTAK_FFI_SITE_TRACE SAMALTAK_FFI_BOX_FULL_GC SITEFFI_SNAPSHOT_DENIED
export LC_ALL=C SAMALTAK_VERIFY_GC=1
export SDL_VIDEO_DRIVER=siteffi_no_video SDL_VIDEODRIVER=siteffi_no_video
case $(uname -s) in
    Linux) link=-shared; ext=so ;;
    Darwin) link=-dynamiclib; ext=dylib ;;
    *) echo 'bound_ffi_site_test: unsupported host' >&2; exit 77 ;;
esac
lib="$TMP/fixture.$ext"
"${CC:-cc}" -std=c99 -Wall -Wextra -Werror "$link" -fPIC -o "$lib" "$ROOT/tests/vm/wrapped_ffi_fixture.c"
STEP="wrapped|wrapped_step|i32(i32)|$lib"
OTHER="wrapped|wrapped_other|i32(i32)|$lib"
COUNT="wrapped|wrapped_calls|u32()|$lib"
export SAMALTAK_NATIVE_GRANTS="$STEP
$OTHER
$COUNT
wrapped|wrapped_void|void()|$lib
wrapped|wrapped_signed|i64(i64)|$lib
wrapped|wrapped_mixed|u64(i32,f64,u64,i64,u32,f64)|$lib
wrapped|wrapped_floats|f64(f64,f64,f64,f64,f64,f64)|$lib
wrapped|wrapped_borrows|u64(u64,bytesWithLength,bytesWithLength,u64)|syncBorrow|$lib
wrapped|wrapped_prove_target|i32(i32)|$lib"

expect() {
    name=$1; expected=$2; shift 2
    if ! "$VM" "$@" >"$LOG/$name.stdout" 2>"$LOG/$name.stderr" ||
       ! grep -Fxq -e "$expected" "$LOG/$name.stdout"; then
        tail -80 "$LOG/$name.stdout" >&2
        tail -80 "$LOG/$name.stderr" >&2
        echo "bound_ffi_site_test: $name expected $expected" >&2
        exit 1
    fi
}
eval_case() {
    name=$1; src=$2; shift 2
    expect "$name" true "$@" "$IMAGE" --headless --load "$ROOT/tests/vm/bound_ffi_site.st" --eval \
        "[$src] on: Error do: [:e | Smalltalk vm stderrWrite: e messageText, (String with: Character lf). Smalltalk quit: 1]"
}
trace() {
    awk -v mode="$2" '/^ffi-site trace hits=[0-9]+ misses=[0-9]+ primitive=[0-9]+$/ {
        rows++
        split($3, h, "="); split($4, m, "="); split($5, p, "=")
        # A miss falls through to the primitive; it is not a separate invocation.
        if (mode == "on") good = h[2] >= 3000 && m[2] >= 2 && p[2] >= 1 && h[2]+p[2] == 4099
        if (mode == "off") good = h[2] == 0 && m[2] == 0 && p[2] == 4099
        if (mode == "boxing") good = h[2] >= 24 && p[2] >= 1
        if (mode == "pty") good = h[2] >= 1000 && p[2] >= 1
        print
    } END { exit !(rows == 1 && good) }' "$LOG/$1.stderr" || {
        cat "$LOG/$1.stderr" >&2
        echo "bound_ffi_site_test: $1 missing/wrong executed-site counters" >&2
        exit 1
    }
}

# Scope the process-wide counters by doing startup and file-in in an untraced
# process. Both traces resume at the same point and count only the 4099 fixture sends.
WITNESS="$TMP/witness.image"
expect witness-setup '#saved' --jit none "$IMAGE" --headless \
    --load "$ROOT/tests/vm/bound_ffi_site.st" --eval "BoundFFISiteProof saveWitness: '$WITNESS'"
SAMALTAK_FFI_SITE_TRACE=1 expect witness-on 'witness direct wrapper' --jit opt --jit-opt 200 "$WITNESS" --headless
trace witness-on on
SAMALTAK_FFI_SITE_TRACE=1 expect witness-off 'witness ordinary send' --jit opt --jit-opt 200 --jit-flags -ffi-site "$WITNESS" --headless
trace witness-off off
eval_case interpreter 'BoundFFISiteProof leaf. BoundFFISiteProof boxing. BoundFFISiteProof deopt: false' --eden 1 --jit none
eval_case optimized 'BoundFFISiteProof leaf. BoundFFISiteProof boxing. BoundFFISiteProof deopt: false' --eden 1 --jit opt --jit-opt 200
# Keep these callers as separate compiled activations so traced names identify the FFI send.
SAMALTAK_OPT_TRACE=1 eval_case stress-deopt "Smalltalk vm jitParameters: #(nil 'deopt,-inline' nil nil). BoundFFISiteProof deopt: true" \
    --eden 1 --jit opt --jit-opt 100
grep -E 'deopt mode 2 .*BoundFFISiteProof.*(nativeThenAdd:|wide:)' "$LOG/stress-deopt.stderr" >/dev/null || {
    echo 'bound_ffi_site_test: no traced post-call deopt in fixture callers' >&2
    exit 1
}
eval_case weak-slot-reuse 'BoundFFISiteProof reuse' --eden 1 --jit opt --jit-opt 200
SAMALTAK_FFI_SITE_TRACE=1 SAMALTAK_FFI_BOX_FULL_GC=1 eval_case force-box-gc \
    'BoundFFISiteProof boxing' --eden 1 --jit opt --jit-opt 8
trace force-box-gc boxing

SNAP="$TMP/site.image"
expect snapshot '#saved' --jit opt --jit-opt 200 "$IMAGE" --headless \
    --load "$ROOT/tests/vm/bound_ffi_site.st" --eval "BoundFFISiteProof snapshot: '$SNAP'"
SAMALTAK_NATIVE_GRANTS="$COUNT
$OTHER
$STEP" expect restore-reordered '#restored' --jit opt "$SNAP" --headless
SAMALTAK_NATIVE_GRANTS="$COUNT
$OTHER" SITEFFI_SNAPSHOT_DENIED=1 expect restore-denied '#restored' --jit opt "$SNAP" --headless

if [ -z "${3:-}" ]; then
    SAMALTAK_FFI_SITE_TRACE=1 expect production-pty true --jit opt --jit-opt 200 "$IMAGE" --headless \
        --load "$ROOT/tests/vm/wrapped_ffi_specialization.st" --eval 'WrappedFFIProof pty. true'
    trace production-pty pty
fi
echo 'bound_ffi_site_test: passed'
