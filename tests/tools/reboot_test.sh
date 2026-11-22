#!/bin/sh
# Rebuild and reboot: an image opened on a scratch copy of the sources changes VMMain>>banner, World menu › Rebuild VM &
# reboot translates and compiles the VM beside that copy and execs it: the same process (pid, control port, session)
# runs the new binary, the windows come back, and the VM answers the new banner.
# usage: tests/tools/reboot_test.sh [image]   (default: build/samaltak.image)
set -u
cd "$(dirname "$0")/../.."
IMAGE=${1:-build/samaltak.image}
CTL=tools/samaltak-ctl
export SAMALTAK_SESSION=reboot-test-$$
SCRATCH=$(mktemp -d)
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
check() { # name expected actual
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1: expected [$2], got [$3]"; fi
}
cleanup() { $CTL close >/dev/null 2>&1; rm -rf "$SCRATCH"; }
trap cleanup EXIT

cp "$IMAGE" "$SCRATCH/reboot.image"
cp -R src "$SCRATCH/src"
$CTL open --hidden --image "$SCRATCH/reboot.image" --source-dir "$SCRATCH/src" >/dev/null 2>&1 || { echo "FAIL open"; exit 1; }
i=0; until $CTL wait '@w6' 10000 >/dev/null 2>&1 || [ $i -ge 100 ]; do i=$((i + 1)); sleep 0.1; done
# the System Browser's title names its class once its own Process has selected it: compare the windows after that
$CTL wait 'System Browser: Window' 10000 >/dev/null
pid=$(sed -n 's/.*"pid": \([0-9]*\).*/\1/p' "${TMPDIR:-/tmp}/samaltak-ctl/$SAMALTAK_SESSION.json")
windows() { $CTL snapshot --depth 1 | grep '^window' | grep -v 'VM Rebuild' | sed 's/ focused//; s/ process=.*//'; }
before=$(windows)
gen=$(cat vm/gen/* | cksum)
check "banner before" "'Samaltak VM'" "$($CTL eval 'Smalltalk vm banner')"

$CTL eval "VMMain compile: 'banner <function> ^''Samaltak VM, rebooted''' classified: 'running'. 1" >/dev/null
$CTL click 1000,893 >/dev/null
$CTL click @menu.rebuild-vm-reboot >/dev/null
# The image goes away for a moment; samaltak-ctl waits while the same pid comes back on the same port. The whole VM
# is compiled first, niced: 90 s on two idle cores, 10 min on two cores beside this desktop drawn by lavapipe; allow 30 min.
i=0; until [ "$($CTL eval 'Smalltalk vm banner' 2>/dev/null)" = "'Samaltak VM, rebooted'" ] || [ $i -ge 3600 ]; do i=$((i + 1)); sleep 0.5; done
check "the rebuilt VM answers the new banner" "'Samaltak VM, rebooted'" "$($CTL eval 'Smalltalk vm banner')"
running() { # pid of the process whose command line has $1 (pgrep -f; /proc where there is no pgrep, as in a slim container)
  if command -v pgrep >/dev/null 2>&1; then pgrep -f "$1" | head -1; return; fi
  for d in /proc/[0-9]*; do case "$(tr '\0' ' ' <"$d/cmdline" 2>/dev/null)" in *"$1"*) echo "${d#/proc/}"; return ;; esac; done
}
check "same process" "$pid" "$(running "$SCRATCH/build/vm/samaltak")"
$CTL wait 'rebooted in' 10000 >/dev/null || fail "the rebuild log says rebooted"
check "every window back" "$before" "$(windows)"
check "top bar shows it" 'topbar @top "reboot.image | Samaltak VM, rebooted"' "$($CTL snapshot --depth 0 | grep '^topbar' | sed 's/ compositor=.*//')"
[ -x "$SCRATCH/build/vm/samaltak" ] && pass "binary beside the sources" || fail "no $SCRATCH/build/vm/samaltak"
check "vm/gen untouched" "$gen" "$(cat vm/gen/* | cksum)"

[ $fails -eq 0 ] && echo "reboot test: all passed" || echo "reboot test: $fails failed"
[ $fails -eq 0 ]
