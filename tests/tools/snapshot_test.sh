#!/bin/sh
# Save the image with a Debugger stopped mid-step, quit, relaunch: every window comes back, the debugged Process is still
# suspended, Over steps on from where it stopped, Proceed finishes the do-it. Works on a copy of the image in a scratch dir.
# usage: tests/tools/snapshot_test.sh [image]   (default: build/samaltak.image)
set -u
cd "$(dirname "$0")/../.."
IMAGE=${1:-build/samaltak.image}
OUT=${OUT:-.context}
CTL=tools/samaltak-ctl
export SAMALTAK_SESSION=snapshot-test-$$
SCRATCH=$(mktemp -d)
SAVED=$SCRATCH/saved.image
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
check() { # name expected actual
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1: expected [$2], got [$3]"; fi
}
contains() { # name haystack needle
  case "$2" in *"$3"*) pass "$1" ;; *) fail "$1: [$3] not in [$2]" ;; esac
}
windows() { $CTL snapshot --depth 1 | grep '^window' | sed 's/\(process=#[0-9]*\).*/\1/'; }
pc() { $CTL snapshot @w7.source | grep ' pc$' | sed 's/^ *mark [^ ]* //'; }
cleanup() { $CTL close >/dev/null 2>&1; rm -rf "$SCRATCH"; }
trap cleanup EXIT

cp "$IMAGE" "$SAVED"
$CTL open --hidden --image "$SAVED" >/dev/null 2>&1 || { echo "FAIL open"; exit 1; }
$CTL eval 'SourceFiler default enabled: false. 1' >/dev/null
i=0; until $CTL wait '@w6' 10000 >/dev/null 2>&1 || [ $i -ge 100 ]; do i=$((i + 1)); sleep 0.1; done

# a breakpoint on Integer>>gcd:, 48 gcd: 18 printed in the Workspace, one step Over
$CTL eval 'Breakpoint on: Integer selector: #gcd:. 1' >/dev/null
$CTL type @w1.text '
48 gcd: 18' --end >/dev/null
$CTL select @w1.text '48 gcd: 18' >/dev/null
$CTL key Meta+p @w1.text >/dev/null
$CTL wait '@w7.over' 5000 >/dev/null
$CTL click @w7.over >/dev/null
$CTL wait idle 3000 >/dev/null
check "stepped over once" '"b := anInteger abs" pc' "$(pc)"
before=$(windows)

# World menu › Save image, then quit
$CTL click 1000,893 >/dev/null
$CTL click @menu.save-image >/dev/null
$CTL wait 'saved' 10000 >/dev/null || fail "saved toast"
$CTL close >/dev/null

# relaunch the saved image
$CTL open --hidden --image "$SAVED" >/dev/null 2>&1 || { echo "FAIL relaunch"; exit 1; }
$CTL wait 'saved.image resumed' 10000 >/dev/null || fail "resumed toast"
$CTL wait '@w7.over' 10000 >/dev/null
$CTL wait idle 6000 >/dev/null
check "every window back (refs, titles, bounds, focus, Processes)" "$before" "$(windows)"
check "debugged Process still suspended" "'Workspace doIt'->true" \
  "$($CTL eval '| p | p := (Tools windowsOf: Debugger) first content session process. p name -> p isSuspended')"
check "pc where it was saved" '"b := anInteger abs" pc' "$(pc)"
contains "workspace text restored" "$($CTL snapshot @w1.text)" '48 gcd: 18'
$CTL screenshot "$OUT/snapshot-test-resumed.png" >/dev/null

# Over continues stepping; Proceed finishes the do-it
$CTL click @w7.over >/dev/null
$CTL wait idle 3000 >/dev/null
contains "Over steps to the loop" "$(pc)" '"[b = 0] whileFalse: ['
$CTL click @w7.over >/dev/null
$CTL wait idle 3000 >/dev/null
check "Over steps into the loop condition" '"b = 0" pc' "$(pc)"
$CTL eval 'Breakpoint removeAll. 1' >/dev/null
$CTL click @w7.proceed >/dev/null
$CTL wait idle 5000 >/dev/null
i=0; until $CTL snapshot @w1.text | grep -q '"6" result' || [ $i -ge 50 ]; do i=$((i + 1)); sleep 0.1; done
contains "Proceed prints the result" "$($CTL snapshot @w1.text | grep ' result')" '"6" result'
check "Debugger closed" "" "$($CTL snapshot --depth 1 | grep '^window @w7 ')"
contains "nothing busy" "$($CTL snapshot --depth 1 | head -1)" 'busy=0'

if [ $fails -eq 0 ]; then echo "all passed"; else echo "$fails failed"; fi
exit $fails
