#!/bin/sh
# Writable FAT volumes and crash reports on UEFI (docs/uefi.md, Files and crash reports), from make test-uefi-fat:
# boots the VM from a real FAT32 EFI system partition (QEMU's fat:rw: directory loses writes) with three more FAT
# disks: FATDATA (written), FATRO (attached read-only), FATFULL (nearly full); runs tests/uefi/fat.st, checks its
# lines (tests/uefi/fat.expected) and what it wrote with mtools on the host, byte for byte, and that the volumes are
# clean (fsck.fat -n). Then a forced fatal error with the World on the screen (VirtualMachine>>fatalErrorForTesting): the crash report on the ESP,
# the red panel on the screen (QEMU's screendump), a key (sendkey) and the reset.
# Environment: QEMU (QEMU_UEFI with the ESP drive left out), UEFI (the build's uefi-<arch> directory), VARS (the
# firmware's variables template, copied to UEFI/vars.fd, QEMU's), BOOT (BOOTAA64.EFI or BOOTX64.EFI), EXT4 (test-uefi's ext4 fixture disk, optional).
set -eu
case "$QEMU" in *fat:rw:*) echo "test-uefi-fat: QEMU still has the fat:rw: ESP"; exit 1;; esac
T=$UEFI/fat-test
rm -rf "$T" && mkdir -p "$T"
export MTOOLS_SKIP_CHECK=1
fail() { echo "test-uefi-fat: $*"; exit 1; }
args() { printf '%s\n' --max-heap 256 disk: $2 --eval "$1" > "$T/args" && mcopy -o -i "$T/esp.img" "$T/args" ::/samaltak.args; }
# The disks.
truncate -s 64M "$T/esp.img" && mformat -i "$T/esp.img" -F -v SAMALTAK ::
mmd -i "$T/esp.img" ::/EFI ::/EFI/BOOT && mcopy -i "$T/esp.img" "$UEFI/esp/EFI/BOOT/$BOOT" ::/EFI/BOOT/
printf 'Hello from FAT\n' > "$T/hello.txt"
truncate -s 16M "$T/data.img" && mformat -i "$T/data.img" -v FATDATA :: && mcopy -i "$T/data.img" "$T/hello.txt" ::/hello.txt
printf 'read only\n' > "$T/ro.txt"
truncate -s 4M "$T/ro.img" && mformat -i "$T/ro.img" -v FATRO :: && mcopy -i "$T/ro.img" "$T/ro.txt" ::/ro.txt
mformat -C -i "$T/full.img" -f 1440 -v FATFULL :: && head -c 1300000 /dev/zero > "$T/filler" && mcopy -i "$T/full.img" "$T/filler" ::/filler
DISKS="-drive format=raw,file=$T/esp.img -drive if=none,id=fatdata,format=raw,file=$T/data.img -device virtio-blk-pci,drive=fatdata \
	-drive if=none,id=fatro,format=raw,readonly=on,file=$T/ro.img -device virtio-blk-pci,drive=fatro \
	-drive if=none,id=fatfull,format=raw,file=$T/full.img -device virtio-blk-pci,drive=fatfull"
[ -n "${EXT4:-}" ] && DISKS="$DISKS -drive if=none,id=ext4,format=raw,readonly=on,file=$EXT4 -device virtio-blk-pci,drive=ext4"
# Files: write, read back on the host.
args "$(grep -v '^"' tests/uefi/fat.st | tr '\n' ' ')" --headless
cp "$VARS" "$UEFI/vars.fd"
eval "timeout 240 $QEMU $DISKS -nographic" < /dev/null | tee "$T/console.log" | grep '^fat ' || true
tr -d '\r' < "$T/console.log" > "$T/console.txt"
grep -q '^fat done' "$T/console.txt" || fail "the files run did not finish"
while read -r line; do grep -qxF "$line" "$T/console.txt" || { grep '^fat ' "$T/console.txt"; fail "no line: $line"; }; done < tests/uefi/fat.expected
python3 -c 'import sys; sys.stdout.buffer.write(bytes(i * 7 % 256 for i in range(100000)))' > "$T/data.expected"
mcopy -n -i "$T/esp.img" ::/samaltak-test/data.bin "$T/data.bin" && cmp "$T/data.bin" "$T/data.expected" || fail "data.bin on the ESP differs"
check() { mcopy -n -i "$T/data.img" "::/$1" "$T/got" && printf "$2" | cmp - "$T/got" || fail "$1 on FATDATA differs"; }
check notes.txt 'FIRST line\nsecond line\n'
check sub/new.txt 'move me'
check short.txt 'short'
check 'A long file name.text' 'a long name'
check hello.txt 'Hello from FAT\n'
mdir -b -i "$T/data.img" ::/ | grep -qi gone.txt && fail "gone.txt was not deleted"
mdir -b -i "$T/data.img" ::/ | grep -qi old.txt && fail "old.txt was not moved"
mdir -b -i "$T/ro.img" ::/ | grep -qi x.txt && fail "the read-only volume was written"
mcopy -n -i "$T/esp.img" ::/samaltak-crash-1.txt "$T/report.txt" && grep -q '^error: ZeroDivide' "$T/report.txt" || fail "no Smalltalk report on the ESP"
for img in esp data ro full; do fsck.fat -n "$T/$img.img" > "$T/fsck-$img.log" 2>&1 || { cat "$T/fsck-$img.log"; fail "$img.img is not clean"; }; done
# A fatal error while the World is on the screen: the report, the panel over it, a key.
args 'UIWindows startUp. (Delay forSeconds: 3) wait. Smalltalk vm fatalErrorForTesting' ''
cp "$VARS" "$UEFI/vars.fd"
rm -f "$T/monitor.sock"
eval "$QEMU $DISKS -display none -serial file:$T/crash.log -monitor unix:$T/monitor.sock,server,nowait -device qemu-xhci,id=keys -device usb-kbd,bus=keys.0" < /dev/null > "$T/qemu.log" 2>&1 &
qemu=$!
monitor() { python3 -c 'import socket, sys, time
s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1]); s.settimeout(5)
time.sleep(0.3); s.recv(65536)
s.sendall((sys.argv[2] + "\n").encode()); time.sleep(1.5)
try: s.recv(65536)
except Exception: pass' "$T/monitor.sock" "$1"; }
i=0; while ! grep -q 'Press a key to restart' "$T/crash.log" 2>/dev/null; do
	i=$((i + 1)); [ $i -gt 240 ] && { kill $qemu; fail "no crash panel in 120 s"; }
	kill -0 $qemu 2>/dev/null || fail "QEMU ended before the crash panel"; sleep 0.5; done
sleep 2
monitor "screendump $T/screen.ppm"
python3 - "$T/screen.ppm" <<'EOF' || { kill $qemu; fail "the screen shows no crash panel"; }
import sys
data = open(sys.argv[1], 'rb').read()
fields, i = [], 0
while len(fields) < 4:
    while data[i:i + 1].isspace(): i += 1
    if data[i:i + 1] == b'#':
        while data[i:i + 1] != b'\n': i += 1
        continue
    j = i
    while not data[j:j + 1].isspace(): j += 1
    fields.append(data[i:j]); i = j
w, h = int(fields[1]), int(fields[2])
px = data[i + 1:i + 1 + 3 * w * h]
red = sum(1 for k in range(0, len(px), 3) if px[k] > 100 and px[k + 1] < 60 and px[k + 2] < 60)
white = sum(1 for k in range(0, len(px), 3) if px[k] > 160 and px[k + 1] > 160 and px[k + 2] > 160)
print('screen %dx%d: %d%% red, %d white pixels' % (w, h, 100 * red // (w * h), white))
sys.exit(0 if red > w * h // 10 and white > 500 else 1)
EOF
monitor "sendkey ret"
i=0; while kill -0 $qemu 2>/dev/null; do i=$((i + 1)); [ $i -gt 60 ] && { kill $qemu; fail "no reset after a key"; }; sleep 0.5; done
grep -q 'samaltak: a key: reset' "$T/crash.log" || { tail -20 "$T/crash.log"; fail "the key did not reset"; }
grep -q 'samaltak: crash report samaltak-crash-2.txt on the boot volume' "$T/crash.log" || fail "no crash report line"
mcopy -n -i "$T/esp.img" ::/samaltak-crash-2.txt "$T/crash.txt" || fail "no samaltak-crash-2.txt on the ESP"
for p in '^Samaltak crash report$' '^fatal: recursive doesNotUnderstand:$' '^uptime: [0-9]*\.[0-9]* s$' '^vm: Samaltak VM, UEFI ' '^heap: limit 256 MB' \
	'^arguments: samaltak --max-heap 256 disk: --eval UIWindows startUp. (Delay forSeconds: 3) wait. Smalltalk vm fatalErrorForTesting$' '^Smalltalk stack:$' '^VirtualMachine>>fatalErrorForTesting$' \
	'doesNotUnderstand: not understood'; do
	grep -q "$p" "$T/crash.txt" || { cat "$T/crash.txt"; fail "no line $p in the crash report"; }; done
fsck.fat -n "$T/esp.img" > "$T/fsck-esp.log" 2>&1 || { cat "$T/fsck-esp.log"; fail "esp.img is not clean after the crash report"; }
echo "test-uefi-fat: passed"
