#!/bin/sh
# samaltak-ctl against a real headless VM: open, eval, errors, wait, state, concurrent clients, missing UI commands, close.
# usage: tests/remote/cli_test.sh [image]   (default: build/samaltak.image; e.g. build/remote/samaltak.image)
set -u
cd "$(dirname "$0")/../.."
IMAGE=${1:-build/samaltak.image}
CTL=tools/samaltak-ctl
export SAMALTAK_SESSION=cli-test-$$
TMP=$(mktemp -d)
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
check() { # name expected actual
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1: expected [$2], got [$3]"; fi
}
cleanup() { $CTL close >/dev/null 2>&1; rm -rf "$TMP"; }
trap cleanup EXIT

$CTL open --headless --image "$IMAGE" >"$TMP/open" 2>&1 || { cat "$TMP/open"; echo "FAIL open"; exit 1; }
pass "open"

check "eval 3+4" "7" "$($CTL eval '3+4')"

out=$($CTL eval '1/0'); code=$?
check "eval 1/0 exit code" "3" "$code"
case "$out" in *ZeroDivide*) pass "eval 1/0 reports ZeroDivide" ;; *) fail "eval 1/0 output: $out" ;; esac

$CTL eval 'remoteCliVar := 6 * 7' >/dev/null
check "bindings persist" "42" "$($CTL eval 'remoteCliVar')"

$CTL eval '[| t | t := Time millisecondClockValue. [Time millisecondClockValue - t < 400] whileTrue] fork' >/dev/null
out=$($CTL wait idle); code=$?
check "wait idle exit code" "0" "$code"
ms=$(printf '%s' "$out" | sed 's/.*"ms":\([0-9]*\).*/\1/')
[ "${ms:-0}" -ge 200 ] && pass "wait idle waited for the busy process (${ms} ms)" || fail "wait idle returned too early: $out"

check "wait ms" "0" "$($CTL wait 50 >/dev/null; echo $?)"

out=$($CTL state); code=$?
check "state exit code" "0" "$code"
case "$out" in *'"processes"'*'"remote control"'*) pass "state lists processes" ;; *) fail "state: $out" ;; esac

# concurrent clients: a slow eval must not block others
start=$(date +%s)
$CTL eval '(Delay forSeconds: 2) wait. #slow' >"$TMP/slow" &
slow=$!
sleep 0.3
fast=""
for i in 1 2 3 4 5; do $CTL eval "$i * 10" >"$TMP/fast$i" & fast="$fast $!"; done
for p in $fast; do wait $p; done
fast_done=$(date +%s)
check "fast eval during slow eval" "30" "$(cat "$TMP/fast3")"
[ $((fast_done - start)) -lt 2 ] && pass "fast evals did not wait for the slow one" || fail "fast evals took $((fast_done - start)) s"
wait $slow
check "slow eval" "#slow" "$(cat "$TMP/slow")"

out=$($CTL snapshot 2>&1); code=$?
check "snapshot without UI exit code" "1" "$code"
case "$out" in *"not available"*) pass "snapshot without UI explains" ;; *) fail "snapshot: $out" ;; esac

out=$($CTL wait '{"cmd":"x","bogus":1}' 2>&1); code=$?
check "wait unknown condition exit code" "1" "$code"

pid=$(sed -n 's/.*"pid": *\([0-9]*\).*/\1/p' "${TMPDIR:-/tmp}/samaltak-ctl/$SAMALTAK_SESSION.json" 2>/dev/null || true)
$CTL close >/dev/null; code=$?
check "close exit code" "0" "$code"
if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then fail "VM $pid still running after close"; else pass "VM exited"; fi
out=$($CTL eval '1' 2>&1); code=$?
check "eval after close exit code" "1" "$code"

[ $fails -eq 0 ] && echo "cli_test: all passed" || echo "cli_test: $fails failed"
exit $fails
