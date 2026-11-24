#!/bin/sh
# The Linux appliance end to end in QEMU (make linux-appliance-test, after make linux-appliance): a data volume with
# samaltak.args, a control token and a VNC password (made here, 0600); boot; the time to the World's first frame on KMS
# (QMP screendumps); the control service (samaltak-ctl connect: eval, an HTTPS request from the guest, a screenshot);
# the image's RFB server (its banner); keyboard and tablet through evdev (QMP input into the Workspace); on the virtio
# variant (the default) that the World is on the image's KMS screen in the display's mode (no SDL window, no SDL_GPU)
# and that its presents were damage-limited (DIRTYFB of the changed rectangles); then the World's quit, which powers
# the machine off. Screenshots and the console go to OUT/linux-appliance/test/.
set -eu
OUT=${OUT:-build}
W=$OUT/linux-appliance
T=$W/test
CP=${LINUX_CONTROL_PORT:-17341}
RP=${LINUX_RFB_PORT:-15937}
HERE=$(cd "$(dirname "$0")" && pwd)
QMP="python3 $HERE/qmp.py $T/qmp.sock"
CTL="$HERE/../samaltak-ctl --session linux-appliance-test"
PATH=$PATH:/sbin:/usr/sbin
now() { date +%s.%N; }
since() { echo "$(now) $1" | awk '{ printf "%.2f", $1 - $2 }'; }
fail() { echo "linux-appliance-test: FAILED: $*"; tail -20 "$T/console.log"; exit 1; }
VARIANT=$(cat "$W/variant" 2>/dev/null || echo mesa)
# On KMS the screen's mode is the World's size; SDL's window needs to be told it.
SIZE="--window-size 1920x1080"; [ "$VARIANT" = virtio ] && SIZE=""
rm -rf "$T" && mkdir -p "$T/data"
(umask 077
 head -c 24 /dev/urandom | base64 | tr -d '/+=\n' > "$T/control-token"
 head -c 6 /dev/urandom | base64 | tr -d '/+=\n' | cut -c1-8 > "$T/vnc-password"
 cp "$T/control-token" "$T/data/control-token"; cp "$T/vnc-password" "$T/data/vnc-password"
 printf '%s\n' --max-heap 2048 $SIZE --control --control-host 0.0.0.0 --control-port 7341 \
	--control-token-file /data/control-token --display --display-host 0.0.0.0 --display-port 5900 --display-vnc-auth \
	--display-password-file /data/vnc-password > "$T/data/samaltak.args")
truncate -s 512M "$T/data.img" && mkfs.ext4 -q -F -L SAMALTAK-DATA -d "$T/data" "$T/data.img"

t0=$(now)
OUT=$OUT LINUX_QMP=$T/qmp.sock LINUX_DATA=$T/data.img LINUX_CONTROL_PORT=$CP LINUX_RFB_PORT=$RP "$HERE/run.sh" > "$T/console.log" 2>&1 &
qemu=$!
trap 'kill $qemu 2>/dev/null || true' EXIT
# The World's first frame: the screen's PNG grows from a console's few KB to the World's hundreds.
i=0; while :; do
	sleep 0.1; i=$((i + 1)); [ $i -gt 300 ] && fail "no World on the screen in 30 s"
	[ -S "$T/qmp.sock" ] || continue
	$QMP screendump "$T/first.png" 2>/dev/null || continue
	[ "$(wc -c < "$T/first.png")" -gt 100000 ] && break
done
world=$(since "$t0")
vmstart=$(sed -n 's/.*vm start at \([0-9.]*\) s.*/\1/p' "$T/console.log")
echo "linux-appliance-test: World on KMS $world s after QEMU started (kernel uptime at the VM's start: $vmstart s)"

# The control service, with the token from the data volume.
i=0; until $CTL connect --host 127.0.0.1 --port "$CP" --token-file "$T/control-token" > /dev/null 2>&1; do
	sleep 0.5; i=$((i + 1)); [ $i -gt 40 ] && fail "control service not reachable on 127.0.0.1:$CP"; done
r=$($CTL eval '3 + 4') && [ "$r" = 7 ] || fail "eval 3 + 4: $r"
echo "linux-appliance-test: control: 3 + 4 = $r"
r=$($CTL eval "| t r | t := Time millisecondClockValue. r := HTTPClient new get: 'https://example.com/' headers: nil. {r status. Time millisecondClockValue - t}") \
	|| fail "HTTPS: $r"
echo "linux-appliance-test: HTTPS from the guest: {status. ms} $r"
$CTL eval "{Smalltalk vm getenv: 'SAMALTAK_GPU'. GPUPlatform device class name. (GPUPlatform display windowPixelSize: 1) printString}" | sed 's/^/linux-appliance-test: gpu: /' || true
if [ "$VARIANT" = virtio ]; then
	r=$($CTL eval "GPUPlatform display class name, ' ', GPUPlatform device class name, ' ', GPUPlatform display screen description, ' ', World current extent printString") || fail "KMS: $r"
	echo "linux-appliance-test: screen: $r"
	case $r in *"KmsDisplay SoftwareGPU /dev/dri/card"*" 1920x1080@"*" 1920@1080"*) ;; *) fail "not the World on KMS in the display's mode: $r" ;; esac
	r=$($CTL eval "(GPUPlatform display input counts at: #devices) printString") || fail "evdev: $r"
	echo "linux-appliance-test: evdev: $r"
fi
$CTL screenshot "$T/control-screenshot.png" > /dev/null 2>&1 && echo "linux-appliance-test: control screenshot $T/control-screenshot.png" || echo "linux-appliance-test: no control screenshot"

# The RFB server.
b=$(python3 -c "import socket; s = socket.create_connection(('127.0.0.1', $RP), 5); print(s.recv(12).decode().strip())") || fail "RFB server not reachable"
echo "linux-appliance-test: RFB banner: $b"

# Keyboard and tablet: click into the Workspace's end, type, print it.
$QMP click 380 908; sleep 0.3
$QMP type "3 + 4"; sleep 0.5
$QMP screendump "$T/typed.png"
echo "linux-appliance-test: clicked into the Workspace and typed '3 + 4' through evdev: $T/typed.png"
sleep 4
r=$($CTL eval '(World current instVarNamed: #topBar) statsText' 2>&1) && echo "linux-appliance-test: frames (the top bar's average of the last 32, while idle): $r" || true
if [ "$VARIANT" = virtio ]; then
	r=$($CTL eval "| s c n f | s := GPUPlatform display screen. c := s counts. n := (c at: #presents ifAbsent: [0]) max: 1. f := c at: #full ifAbsent: [0]. {n. f. c at: #rects ifAbsent: [0]. ((c at: #pixels ifAbsent: [0]) - (f * s extent x * s extent y)) // n. (c at: #us ifAbsent: [0]) // n. c at: #how. c at: #commits ifAbsent: [0]. c at: #busy ifAbsent: [0]. ((c at: #commitUs ifAbsent: [0]) + (c at: #dirtyfbUs ifAbsent: [0])) // ((c at: #commits ifAbsent: [0]) + (c at: #busy ifAbsent: [0]) + (c at: #flushes ifAbsent: [0]) max: 1)}") || fail "counts: $r"
	echo "linux-appliance-test: KMS presents {damaged. whole frames. rectangles. pixels per damaged present. us per damaged present. flushed by. commits. busy. us per flush}: $r"
fi

# Quit: the VM exits 0, samaltak-run powers off, QEMU ends.
tq=$(now)
$CTL eval 'Smalltalk quit: 0' > /dev/null 2>&1 || true
i=0; while kill -0 $qemu 2>/dev/null; do sleep 0.1; i=$((i + 1)); [ $i -gt 200 ] && fail "no power off 20 s after quit"; done
echo "linux-appliance-test: powered off $(since "$tq") s after the quit"
grep -q 'vm exit 0' "$T/console.log" || fail "no 'vm exit 0' on the console"
$CTL close > /dev/null 2>&1 || true
echo "linux-appliance-test: passed"
