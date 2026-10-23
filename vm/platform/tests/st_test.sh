#!/bin/sh
# Smalltalk-level platform test: mini kernel + Platform-Tests through the real VM.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
VM=${1:-"$ROOT/vm/build/samaltak"}
OUT="$ROOT/vm/build/platform-test"
mkdir -p "$OUT"
python3 "$ROOT/boot/bootstrap.py" "$HERE/st" "$OUT/st.image" >/dev/null || exit 1
perl -e 'alarm 30; exec @ARGV' "$VM" "$OUT/st.image" --headless Platform >"$OUT/Platform.out" 2>&1
if cmp -s "$HERE/st/Platform.expected" "$OUT/Platform.out"; then
    echo "st-test: Platform passed"
else
    echo "st-test: Platform FAILED"
    diff "$HERE/st/Platform.expected" "$OUT/Platform.out" | head -20
    exit 1
fi
