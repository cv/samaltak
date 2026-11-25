#!/bin/sh
# The recording clock with a real UI (a hidden window): it stands still between commands, advance moves it, a query is
# served meanwhile, a program outside the image is paced to real time, and every video slot gets its frame.
# usage: tests/remote/recording_test.sh [image]   (default: build/samaltak.image)
set -u
cd "$(dirname "$0")/../.."
IMAGE=${1:-build/samaltak.image}
CTL=tools/samaltak-ctl
export SAMALTAK_SESSION=recording-test-$$
TMP=$(mktemp -d)
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
cleanup() { $CTL close >/dev/null 2>&1; rm -rf "$TMP"; }
trap cleanup EXIT
micros() { $CTL state | grep '"micros"' | tr -dc '0-9'; }

$CTL open --hidden --work-clock --image "$IMAGE" --window-size 640x400 >"$TMP/open" 2>&1 || { cat "$TMP/open"; echo "FAIL open"; exit 1; }
pass "open --work-clock"

a=$(micros); sleep 1; b=$(micros)
if [ "$a" = "$b" ]; then pass "the clock stands still between commands"; else fail "the clock moved between commands: $a $b"; fi

$CTL advance 500 >/dev/null
c=$(micros)
if [ $((c - b)) -ge 500000 ] && [ $((c - b)) -lt 600000 ]; then pass "advance 500 moves it half a second"; else fail "advance 500: $b $c"; fi

$CTL record start "$TMP/video.rgba" --size 64x40 --fps 30 --raw >/dev/null
$CTL advance 1000 >/dev/null
frames=$($CTL record stop | grep -o '"frames":[0-9]*' | tr -dc '0-9')
size=$(wc -c <"$TMP/video.rgba" | tr -d ' ')
if [ "$frames" -ge 29 ] && [ "$frames" -le 31 ] && [ "$size" = "$((frames * 64 * 40 * 4))" ]; then pass "every video slot is written"; else fail "frames $frames, size $size"; fi

# The Terminal's Processes run below the control server: the query must not wait for them with the clock standing still.
$CTL eval 'Terminal open. 1' >/dev/null
$CTL advance 1000 >/dev/null
TERMINAL=$($CTL snapshot --depth 1 | grep '^window' | grep Terminal | sed -E 's/.*(@w[0-9]+).*/\1/')
if [ -n "$TERMINAL" ]; then pass "a query is served while the clock stands still"; else fail "no Terminal in the snapshot"; fi

# the clock before the Enter that starts the job: read after it, a loaded machine has the job running already
$CTL --settle 0 type "$TERMINAL.terminal" 'sleep 1; echo PACED-$((1+1))' --delay 0 >/dev/null
d=$(micros)
$CTL --settle 0 key Enter "$TERMINAL.terminal" >/dev/null
$CTL wait PACED-2 15000 >/dev/null
e=$(micros)
if [ $((e - d)) -ge 900000 ]; then pass "a program outside the image paces the clock to real time"; else fail "the 1 s job took $((e - d)) us of the clock"; fi

if [ "$fails" = 0 ]; then echo "recording test: all passed"; else echo "recording test: $fails failed"; exit 1; fi
