#!/bin/sh
# Smalltalk-level platform test: the production image and Platform-Tests through the real VM.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
VM=${1:-"$ROOT/vm/build/samaltak"}
OUT="$ROOT/vm/build/platform-test"
mkdir -p "$OUT"
cd "$ROOT" || exit 1
"$ROOT/boot/build-image.sh" "$ROOT/src" "$OUT/seed.image" "$VM" || exit 1
"$VM" "$OUT/seed.image" --headless --stage2 "$OUT/st.image" || exit 1
fixture="$HERE/st/Platform-Tests"
{
    echo '--- Platform'
    perl -e 'alarm 30; exec @ARGV' "$VM" "$OUT/st.image" --headless \
        --load "$fixture/PlatformPrims.st" --load "$fixture/PlatformPrims.extension.st" \
        --eval '[PlatformPrims testPlatform. Smalltalk quit: 0] on: Error do: [:e | Smalltalk vm stderrWrite: e messageText, String lf. Smalltalk quit: 1]'
} >"$OUT/Platform.out" 2>&1 || {
    cat "$OUT/Platform.out" >&2
    exit 1
}
if cmp -s "$HERE/st/Platform.expected" "$OUT/Platform.out"; then
    echo "st-test: Platform passed"
else
    echo "st-test: Platform FAILED"
    diff "$HERE/st/Platform.expected" "$OUT/Platform.out" | head -20
    exit 1
fi
