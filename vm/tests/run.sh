#!/bin/sh
# VM + image builder end-to-end tests: build the mini kernel image (vm/tests/mini), run each
# Smalltalk test headless and compare stdout with vm/tests/expected/<Test>.txt.
# Every test also runs with a 1 MB eden under the heap verifier (GC stress).
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
VM=${VM:-"$ROOT/vm/build/samaltak"}
OUT="$ROOT/build/test-vm"
EXP="$ROOT/vm/tests/expected"
mkdir -p "$OUT"
"$ROOT/boot/build-image.sh" "$ROOT/vm/tests/mini" "$OUT/mini.image" "$VM" >/dev/null 2>&1 || exit 1
IMG="$OUT/mini.image"
pass=0
fail=0

check() { # name expected-file actual-file
    if cmp -s "$2" "$3"; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL $1"
        diff "$2" "$3" | head -20
    fi
}

for t in Arith Float Strings Closures Unwind Errors Processes Context Married Perform Instances Sampling GC Misc Weak StackOverflow; do
    "$VM" "$IMG" --headless "$t" >"$OUT/$t.out" 2>&1
    check "$t" "$EXP/$t.txt" "$OUT/$t.out"
    SAMALTAK_VERIFY_GC=1 "$VM" --eden 1 "$IMG" --headless "$t" >"$OUT/$t.stress.out" 2>&1
    check "$t (eden 1 MB, verified)" "$EXP/$t.txt" "$OUT/$t.stress.out"
done

"$VM" --max-heap 64 "$IMG" --headless OutOfMemory >"$OUT/OutOfMemory.out" 2>&1
check OutOfMemory "$EXP/OutOfMemory.txt" "$OUT/OutOfMemory.out"
SAMALTAK_VERIFY_GC=1 "$VM" --max-heap 64 --eden 1 "$IMG" --headless OutOfMemory >"$OUT/OutOfMemory.stress.out" 2>&1
check "OutOfMemory (eden 1 MB, verified)" "$EXP/OutOfMemory.txt" "$OUT/OutOfMemory.stress.out"

for opts in "" "--eden 1"; do
    # shellcheck disable=SC2086
    SAMALTAK_VERIFY_GC=$([ -n "$opts" ] && echo 1) "$VM" --max-heap 64 $opts "$IMG" --headless StackOverflowHeap >"$OUT/StackOverflowHeap.out" 2>&1
    check "StackOverflowHeap $opts" "$EXP/StackOverflowHeap.txt" "$OUT/StackOverflowHeap.out"
done

rm -f "$OUT/snap.image"
{
    MINI_SNAPSHOT="$OUT/snap.image" "$VM" "$IMG" --headless Snapshot
    "$VM" "$OUT/snap.image" --headless
} >"$OUT/Snapshot.out" 2>&1
check Snapshot "$EXP/Snapshot.txt" "$OUT/Snapshot.out"

expect_fatal() { # name pattern vm-args...
    name=$1 pattern=$2
    shift 2
    "$VM" "$@" >"$OUT/$name.out" 2>&1
    code=$?
    if [ $code -eq 70 ] && grep -q "$pattern" "$OUT/$name.out"; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL $name (exit $code)"
        tail -5 "$OUT/$name.out"
    fi
}
expect_fatal Recurse 'MiniTests>>recurse:' --max-heap 64 "$IMG" --headless Recurse
expect_fatal FatalDNU 'not understood (ProtoThing>>foo)' "$IMG" --headless FatalDNU

if [ "${BENCH:-1}" = 1 ]; then
    "$VM" "$IMG" --headless Bench 2>&1 >/dev/null | sed 's/^/bench: /'
fi
echo "test-vm: $pass passed, $fail failed"
[ $fail -eq 0 ]
