#!/bin/sh
# The USB stick end to end in QEMU (make linux-appliance-usb-test, after make linux-appliance-usb): AAVMF boots a copy
# of usb.img from a USB stick on xHCI (removable media: \EFI\BOOT\BOOTAA64.EFI, the UKI, no load options); the data
# volume is the stick's partition; the World on the screen; the control service with the stick's token; the RFB
# server; the agent's account configured, kept by a snapshot on the data volume across the VM's restart (its API key
# not: keys are never saved, agent-config sends one again after each start); then the World's quit powers off.
set -eu
OUT=${OUT:-build}
W=$OUT/linux-appliance
T=$W/usb-test
CP=${LINUX_CONTROL_PORT:-17342}
RP=${LINUX_RFB_PORT:-15938}
HERE=$(cd "$(dirname "$0")" && pwd)
QMP="python3 $HERE/qmp.py $T/qmp.sock"
CTL="$HERE/../samaltak-ctl --session linux-appliance-usb-test"
now() { date +%s.%N; }
since() { echo "$(now) $1" | awk '{ printf "%.2f", $1 - $2 }'; }
fail() { echo "linux-appliance-usb-test: FAILED: $*"; tr -d '\r' < "$T/console.log" | tail -20; exit 1; }
say() { echo "linux-appliance-usb-test: $*"; }
[ -f "$W/usb.img" ] && [ -f "$W/usb-control-token" ] || { echo "linux-appliance-usb-test: no $W/usb.img (and its usb-control-token): make linux-appliance-usb first" >&2; exit 1; }
rm -rf "$T" && mkdir -p "$T"
cp --sparse=always "$W/usb.img" "$T/usb.img"
connect() {
	i=0; until $CTL connect --host 127.0.0.1 --port "$CP" --token-file "$W/usb-control-token" > /dev/null 2>&1; do
		sleep 0.5; i=$((i + 1)); [ $i -gt 60 ] && fail "control service not reachable on 127.0.0.1:$CP"; done
}

t0=$(now)
OUT=$OUT LINUX_USB=$T/usb.img LINUX_VARS=$T/vars.fd LINUX_QMP=$T/qmp.sock LINUX_CONTROL_PORT=$CP LINUX_RFB_PORT=$RP "$HERE/run.sh" > "$T/console.log" 2>&1 &
qemu=$!
trap 'kill $qemu 2>/dev/null || true' EXIT
i=0; while :; do
	sleep 0.2; i=$((i + 1)); [ $i -gt 300 ] && fail "no World on the screen in 60 s"
	kill -0 $qemu 2>/dev/null || fail "QEMU ended"
	[ -S "$T/qmp.sock" ] || continue
	$QMP screendump "$T/first.png" 2>/dev/null || continue
	[ "$(wc -c < "$T/first.png")" -gt 100000 ] && break
done
say "World on the screen $(since "$t0") s after QEMU started (the firmware reads the 97 MB UKI over emulated USB)"
tr -d '\r' < "$T/console.log" | grep -q 'BdsDxe: starting .*USB' || fail "not booted from the USB stick"
tr -d '\r' < "$T/console.log" | grep -q 'data on /dev/sd' || fail "the data volume is not the stick's"
say "$(tr -d '\r' < "$T/console.log" | grep -o 'samaltak-linux: data on [^ ]* at [0-9.]* s')"

connect
r=$($CTL eval '3 + 4') && [ "$r" = 7 ] || fail "eval 3 + 4: $r"
r=$($CTL eval "{GPUPlatform display class name. GPUPlatform display screen description. (Directory entries: '/data') asArray}") || fail "eval: $r"
say "control: 3 + 4 = 7; $r"
b=$(python3 -c "import socket; s = socket.create_connection(('127.0.0.1', $RP), 5); print(s.recv(12).decode().strip())") || fail "RFB server not reachable"
say "RFB banner: $b"

# The agent's account: configured, snapshotted on the data volume, the VM restarted (exit 1: samaltak-run starts it
# again, now from /data/samaltak.image).
$CTL eval "ApiKeyAccount default providerName: 'usb-test' baseURL: 'https://example.invalid/v1' model: 'test-model' thinking: nil maxTokens: 1000; apiKey: 'not-a-key'. Smalltalk snapshot: '/data/samaltak.image'" > /dev/null || fail "snapshot"
$CTL eval 'Smalltalk quit: 1' > /dev/null 2>&1 || true
i=0; until [ "$(tr -d '\r' < "$T/console.log" | grep -c 'vm start .*/data/samaltak.image')" -ge 1 ]; do
	sleep 0.5; i=$((i + 1)); [ $i -gt 60 ] && fail "the VM did not start again from /data/samaltak.image"; done
connect
r=$($CTL eval "ApiKeyAccount default printString") || fail "after the restart: $r"
case $r in *test-model*"no key"*) ;; *) fail "the account after the restart: $r" ;; esac
say "the account after the VM's restart from the data volume's snapshot: $r"

tq=$(now)
$CTL eval 'Smalltalk quit: 0' > /dev/null 2>&1 || true
i=0; while kill -0 $qemu 2>/dev/null; do sleep 0.1; i=$((i + 1)); [ $i -gt 200 ] && fail "no power off 20 s after quit"; done
say "powered off $(since "$tq") s after the quit"
$CTL close > /dev/null 2>&1 || true
say passed
