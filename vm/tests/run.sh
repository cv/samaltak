#!/bin/sh
# VM + image builder end-to-end tests: build the mini kernel image (vm/tests/mini), run each
# Smalltalk test headless and compare stdout with vm/tests/expected/<Test>.txt.
# Every test also runs with a 1 MB eden under the heap verifier (GC stress), and all of it again under the baseline
# JIT with every method compiled on its first activation, and under the optimizing tier (opt) optimizing after one
# activation, also with deoptimization stress; the tests also run under the JITs' default thresholds (counting
# activations, on-stack replacement). MODES selects (default: none baseline opt).
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
VM=${VM:-"$ROOT/vm/build/samaltak"}
OUT="$ROOT/build/test-vm"
EXP="$ROOT/vm/tests/expected"
mkdir -p "$OUT"
"$ROOT/boot/build-image.sh" "$ROOT/vm/tests/mini" "$OUT/mini.image" "$VM" >/dev/null 2>&1 || exit 1
IMG="$OUT/mini.image"
TESTS="Arith Float Strings Closures Unwind Errors Processes Context Married Perform Instances Sampling GC Misc Weak StackOverflow Jit"
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

suite() { # label vm-options...
    label=$1
    shift
    for t in $TESTS; do
        "$VM" "$@" "$IMG" --headless "$t" >"$OUT/$t.out" 2>&1
        check "$t$label" "$EXP/$t.txt" "$OUT/$t.out"
        SAMALTAK_VERIFY_GC=1 "$VM" --eden 1 "$@" "$IMG" --headless "$t" >"$OUT/$t.stress.out" 2>&1
        check "$t (eden 1 MB, verified)$label" "$EXP/$t.txt" "$OUT/$t.stress.out"
    done

    "$VM" --max-heap 64 "$@" "$IMG" --headless OutOfMemory >"$OUT/OutOfMemory.out" 2>&1
    check "OutOfMemory$label" "$EXP/OutOfMemory.txt" "$OUT/OutOfMemory.out"
    SAMALTAK_VERIFY_GC=1 "$VM" --max-heap 64 --eden 1 "$@" "$IMG" --headless OutOfMemory >"$OUT/OutOfMemory.stress.out" 2>&1
    check "OutOfMemory (eden 1 MB, verified)$label" "$EXP/OutOfMemory.txt" "$OUT/OutOfMemory.stress.out"

    for eden in "" 1; do
        # shellcheck disable=SC2046
        SAMALTAK_VERIFY_GC=$([ -n "$eden" ] && echo 1) "$VM" --max-heap 64 $([ -n "$eden" ] && echo --eden $eden) "$@" "$IMG" --headless StackOverflowHeap >"$OUT/StackOverflowHeap.out" 2>&1
        check "StackOverflowHeap ${eden:+--eden $eden}$label" "$EXP/StackOverflowHeap.txt" "$OUT/StackOverflowHeap.out"
    done

    rm -f "$OUT/snap.image"
    {
        MINI_SNAPSHOT="$OUT/snap.image" "$VM" "$@" "$IMG" --headless Snapshot
        "$VM" "$@" "$OUT/snap.image" --headless
    } >"$OUT/Snapshot.out" 2>&1
    check "Snapshot$label" "$EXP/Snapshot.txt" "$OUT/Snapshot.out"

    expect_fatal "Recurse$label" 'MiniTests>>recurse:' --max-heap 64 "$@" "$IMG" --headless Recurse
    expect_fatal "FatalDNU$label" 'not understood (ProtoThing>>foo)' "$@" "$IMG" --headless FatalDNU
}

MODES=${MODES:-"none baseline opt"}
for mode in $MODES; do
    case $mode in
    none) suite "" ;;
    opt)
        # optimized after one activation of compiled code, then again with deoptimization stress
        suite " (jit opt, eager)" --jit opt --jit-threshold 0 --jit-flags eager
        suite " (jit opt, eager, deopt stress)" --jit opt --jit-threshold 0 --jit-flags eager,deopt ;;
    *) suite " (jit $mode)" --jit $mode --jit-threshold 0 ;;
    esac
    [ $mode = none ] && continue
    for t in $TESTS; do
        "$VM" --jit $mode "$IMG" --headless "$t" >"$OUT/$t.out" 2>&1
        check "$t (jit $mode, default thresholds)" "$EXP/$t.txt" "$OUT/$t.out"
    done
done

if [ "${BENCH:-1}" = 1 ]; then
    "$VM" "$IMG" --headless Bench 2>&1 >/dev/null | sed 's/^/bench: /'
    "$VM" --jit baseline "$IMG" --headless Bench 2>&1 >/dev/null | sed 's/^/bench (jit baseline): /'
fi
echo "test-vm: $pass passed, $fail failed"
[ $fail -eq 0 ]
