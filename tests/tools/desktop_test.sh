#!/bin/sh
# The default desktop driven through samaltak-ctl, as a user (or Claude) does: browse Integer>>gcd:, set a breakpoint in the
# gutter, print it in the Workspace, a syntax error, halt on write in an Inspector, Run long computation from the World menu,
# clicks queued in the busy Mandelbrot window, the Process Browser. Screenshots go to $OUT (default .context).
# usage: tests/tools/desktop_test.sh [image]   (default: build/tools/samaltak.image)
set -u
cd "$(dirname "$0")/../.."
IMAGE=${1:-build/tools/samaltak.image}
OUT=${OUT:-.context}
CTL=tools/samaltak-ctl
export SAMALTAK_SESSION=tools-test-$$
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
check() { # name expected actual
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1: expected [$2], got [$3]"; fi
}
contains() { # name haystack needle
  case "$2" in *"$3"*) pass "$1" ;; *) fail "$1: [$3] not in [$2]" ;; esac
}
cleanup() { $CTL close >/dev/null 2>&1; }
trap cleanup EXIT

$CTL open --hidden --image "$IMAGE" >/dev/null 2>&1 || { echo "FAIL open"; exit 1; }
$CTL eval 'SourceFiler default enabled: false. 1' >/dev/null
# the ref condition fails at once until the World registers its snapshot root
i=0; until $CTL wait '@w6' 10000 >/dev/null 2>&1 || [ $i -ge 100 ]; do i=$((i + 1)); sleep 0.1; done
check "default layout: six windows" "6" "$($CTL snapshot --depth 1 | grep -c '^window')"
contains "w1 is the Workspace" "$($CTL snapshot --depth 1 | grep '^window @w1 ')" '"Workspace"'
contains "w6 is the System Browser" "$($CTL snapshot --depth 1 | grep '^window @w6 ')" '"System Browser: Window"'

# System Browser: Kernel-Numbers, Integer, -- all --, gcd:, the gutter dot
$CTL select @w6.packages Kernel-Numbers >/dev/null
$CTL select @w6.classes Integer >/dev/null
$CTL select @w6.protocols all >/dev/null
$CTL select @w6.methods 'gcd:' >/dev/null
contains "code pane shows gcd:" "$($CTL snapshot @w6.code | head -1)" 'gcd: anInteger'
contains "status bar" "$($CTL snapshot @w6.status)" 'Integer>>gcd:'
$CTL click @w6.methods.gcd.breakpoint-toggle >/dev/null
check "gutter click sets a real breakpoint" "'Integer>>gcd: (break)'" "$($CTL eval '(Breakpoint forClass: Integer selector: #gcd:) description')"
contains "gutter shows it" "$($CTL snapshot @w6.methods.gcd)" 'breakpoint=break'
$CTL click @w6.methods.gcd.breakpoint-toggle >/dev/null
check "second click removes it" "nil" "$($CTL eval 'Breakpoint forClass: Integer selector: #gcd:')"
$CTL screenshot "$OUT/tools-test-browser.png" >/dev/null

# Workspace: print it, a syntax error
$CTL type @w1.text '
6 * 7' --end >/dev/null
$CTL select @w1.text '6 * 7' >/dev/null
$CTL key Meta+p @w1.text >/dev/null
$CTL wait idle 5000 >/dev/null
contains "print it marks the result" "$($CTL snapshot @w1.text | grep ' result')" '"42" result'
$CTL type @w1.text '
(3 + 4' --end >/dev/null
$CTL key Meta+p @w1.text >/dev/null
contains "syntax error marked inline" "$($CTL snapshot @w1.text | grep ' error')" 'expected'

# Inspector on p, halt on write on x
$CTL select @w1.text 'p := 3 @ 4' >/dev/null
$CTL key Meta+i @w1.text >/dev/null
$CTL wait '"Inspector: a Point"' 5000 >/dev/null
insp=$($CTL snapshot --depth 1 | grep '"Inspector: a Point"' | grep -o '@w[0-9]*' | head -1)
contains "inspect it opens an Inspector" "$insp" "@w"
$CTL rightclick "$insp.fields.x" >/dev/null
$CTL click @menu.halt-on-write >/dev/null
check "halt on write sets a watchpoint" "'watchpoint on #x of 3@4'" "$($CTL eval 'Watchpoint all first description')"
contains "field shows the tag" "$($CTL snapshot "$insp.fields" | grep "$insp.fields.x ")" 'halt-on-write'
$CTL eval 'Watchpoint removeAll. 1' >/dev/null

# World menu › Run long computation; the Process Browser shows it
$CTL click 891,300 >/dev/null
$CTL click @menu.run-long-computation >/dev/null
# two refreshes of the Process Browser's CPU column
$CTL wait 500 >/dev/null
contains "crunch runs" "$($CTL snapshot @w3.processes | grep 'crunch')" 'running'

# Mandelbrot: clicks while it renders are queued and counted. One rendering can end before the snapshots are taken:
# the window renders again and again until they are.
$CTL eval '| w | Smalltalk at: #DesktopTestLooked put: false. w := (Tools windowsOf: MandelbrotView) first. w do: [[Smalltalk at: #DesktopTestLooked] whileFalse: [w content render]]. 1' >/dev/null
$CTL wait '{"eval": "(Tools windowsOf: MandelbrotView) first content isRendering"}' >/dev/null
$CTL click @w4.view --settle 0 >/dev/null
# a refresh of the Process Browser's CPU column
$CTL wait 300 >/dev/null
contains "Mandelbrot busy with a queued click" "$($CTL snapshot @w4.view)" 'queued=1'
contains "Process Browser shows Mandelbrot running" "$($CTL snapshot @w3.processes | grep '"Mandelbrot"')" 'running'
$CTL screenshot "$OUT/tools-test-desktop.png" >/dev/null
$CTL eval 'Smalltalk at: #DesktopTestLooked put: true. 1' >/dev/null
# crunch was adopted by the Workspace's evaluator
$CTL eval '(Tools windowsOf: Workspace) first content evaluator children do: [:p | p terminate]. 1' >/dev/null

if [ $fails -eq 0 ]; then echo "all passed"; else echo "$fails failed"; fi
exit $fails
