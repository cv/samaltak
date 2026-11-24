#!/bin/sh
# The image builder's layering check: the mini kernel plus three small packages on layers 1-3.
set -u
cd "$(dirname "$0")/../.."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }

cp -RL vm/tests/mini/Mini-Kernel vm/tests/mini/Mini-Tests "$TMP"/
mkdir "$TMP/Lower" "$TMP/Middle" "$TMP/Upper"
printf "Object subclass: #LowThing\n\tinstanceVariableNames: ''\n\tclassVariableNames: ''\n\tpackage: 'Lower'!\n" >"$TMP/Lower/LowThing.st"
printf "Object subclass: #MidThing\n\tinstanceVariableNames: ''\n\tclassVariableNames: ''\n\tpackage: 'Middle'!\n\n!MidThing methodsFor: 'x'!\nlow\n\t^LowThing\n! !\n" >"$TMP/Middle/MidThing.st"
printf "Object subclass: #UpThing\n\tinstanceVariableNames: ''\n\tclassVariableNames: ''\n\tpackage: 'Upper'!\n\n!UpThing methodsFor: 'x'!\nmid\n\t^MidThing\n!\nlow\n\t^LowThing\n! !\n" >"$TMP/Upper/UpThing.st"

run() { # packages.txt tail -> bootstrap output in $TMP/out, exit code in $code
  printf "Mini-Kernel 0\nMini-Tests 0\nLower 1\nMiddle 2\n%s\n" "$1" >"$TMP/packages.txt"
  boot/build-image.sh "$TMP" "$TMP/out.image" >"$TMP/out" 2>&1
  code=$?
}

run "Upper 3"
if [ $code -ne 0 ] && grep -q "Upper/UpThing.st:11: Upper (layer 3) uses LowThing of Lower (layer 1)" "$TMP/out" \
    && ! grep -q "MidThing of" "$TMP/out" && grep -q "1 layering violation" "$TMP/out"; then
  pass "two layers down is rejected with file:line; one layer down is fine"
else fail "violation not reported: $(cat "$TMP/out")"; fi

run "Upper 3 uses Lower"
[ $code -eq 0 ] && pass "uses allows the listed package" || fail "uses: $(cat "$TMP/out")"

run "export Lower 3 LowThing
Upper 3"
[ $code -eq 0 ] && pass "export allows the global from its layer up" || fail "export: $(cat "$TMP/out")"

run "export Lower 4 LowThing
Upper 3"
[ $code -ne 0 ] && pass "export does not apply below its layer" || fail "export below its layer was accepted"

printf "LowThing subclass: #UpSub\n\tinstanceVariableNames: ''\n\tclassVariableNames: ''\n\tpackage: 'Upper'!\n" >"$TMP/Upper/UpSub.st"
run "Upper 3 uses Middle"
grep -q "Upper/UpSub.st:1: Upper (layer 3) uses LowThing of Lower (layer 1)" "$TMP/out" \
  && pass "superclasses are checked" || fail "superclass: $(cat "$TMP/out")"

[ $fails -eq 0 ] && echo "layering_test: all passed" || echo "layering_test: $fails failed"
exit $fails
