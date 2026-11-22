#!/bin/sh
# The command line's quitting entry points: --test quits with 0 when all passed and 1 when one failed; an image not
# started with --test refuses Smalltalk runTestsAndQuit with an Error (no test runs, the VM goes on).
# usage: tests/boot/cli_quit_test.sh IMAGE
set -u
cd "$(dirname "$0")/../.."
IMAGE=$1
VM=vm/build/samaltak
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; sed 's/^/     /' "$TMP/out" | tail -15; fails=$((fails + 1)); }
vm() { timeout 120 "$VM" "$IMAGE" --headless "$@" </dev/null >"$TMP/out" 2>&1; code=$?; }

printf "TestCase subclass: #CliQuitFailingTest\n\tinstanceVariableNames: ''\n\tclassVariableNames: ''\n\tpackage: 'Tests-Kernel'!\n\n!CliQuitFailingTest methodsFor: 'tests'!\ntestFails\n\tself assert: false\n! !\n" >"$TMP/fail.st"

vm --test SystemTest
if [ $code -eq 0 ] && grep -Eq '^[0-9]+ run, [0-9]+ passed, 0 failed, 0 errors' "$TMP/out"; then pass "--test, all passed: exit 0"
else fail "--test, all passed: exit $code"; fi

vm --load "$TMP/fail.st" --test CliQuitFailingTest
if [ $code -eq 1 ] && grep -q '^1 run, 0 passed, 1 failed' "$TMP/out"; then pass "--test, one failed: exit 1"
else fail "--test, one failed: exit $code"; fi

vm --eval "[Smalltalk runTestsAndQuit. 'ran'] on: Error do: [:e | e messageText]"
if [ $code -eq 0 ] && grep -q 'use the run-tests tool' "$TMP/out" && ! grep -Eq '^[0-9]+ run, ' "$TMP/out"; then
  pass "runTestsAndQuit without --test: an Error, no test ran, no quit"
else fail "runTestsAndQuit without --test: exit $code"; fi

[ $fails -eq 0 ] || { echo "cli_quit_test: $fails failed"; exit 1; }
echo "cli_quit_test: all passed"
