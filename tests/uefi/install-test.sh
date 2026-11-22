#!/bin/sh
# make test-install (docs/uefi.md, Installing): SamaltakInstaller under QEMU, never on this machine's disks or
# firmware variables. An NVMe disk image like the DGX Spark's (a GPT: 1 an EFI system partition with a fake
# \EFI\ubuntu\grub, which is the VM with its own samaltak.args, 2 an ext4 root "ubuntu", free space after it) and a
# copy of the firmware's variable store of its own; the boot stick (make usb-disk). Boot 1, stick and NVMe: a boot
# option for Ubuntu as its installer makes one (first in BootOrder), the installer's dry run, a refusal, the
# install (store=end) and reboot=samaltak. On the host: sgdisk -v, the new partition, the files on the ESP (mcopy),
# Boot#### and BootOrder in the variable store (tests/uefi/efivars.py). Boot 2, the stick removed: BootNext boots
# Samaltak from the NVMe, which finds its store there and sets BootNext to Ubuntu. Boot 3: the fake Ubuntu boots.
#
# usage: tests/uefi/install-test.sh   (environment from the Makefile: UEFI OUT UEFI_ARCH UEFI_BOOT OVMF_CODE OVMF_VARS
#   QEMU_UEFI_MACHINE USB_IMAGE)
set -eu
D=$UEFI/install-test
NVME=$D/nvme.img
VARS=$D/vars.fd
LOG=$D/console.log
rm -rf "$D" && mkdir -p "$D"
case $UEFI_ARCH in arm64) GRUB=grubaa64.efi ;; *) GRUB=grubx64.efi ;; esac
mt() { MTOOLS_SKIP_CHECK=1 "$@"; }
fail() { echo "test-install: $*"; [ -f "$LOG" ] && tail -n 40 "$LOG"; exit 1; }
args() { printf '%s\n' --max-heap 256 disk: --headless --eval "$1"; }

# The NVMe disk: 1 MB, ESP 64 MB, ext4 32 MB, 520 MB free, the backup GPT.
truncate -s 64M "$D/esp" && mt mformat -i "$D/esp" -F -v ESP :: && mt mmd -i "$D/esp" ::/EFI ::/EFI/ubuntu
mt mcopy -i "$D/esp" "$UEFI/esp/EFI/BOOT/$UEFI_BOOT" "::/EFI/ubuntu/$GRUB"
args "Smalltalk vm stderrWrite: 'booted ubuntu', (String with: Character lf). 'ubuntu done'" > "$D/ubuntu.args"
mt mcopy -i "$D/esp" "$D/ubuntu.args" ::/EFI/ubuntu/samaltak.args
mkdir -p "$D/root/etc" && echo 'NAME="Ubuntu"' > "$D/root/etc/os-release"
truncate -s 32M "$D/root.ext4" && PATH=$PATH:/sbin:/usr/sbin mkfs.ext4 -q -F -L ubuntu-root -d "$D/root" "$D/root.ext4"
truncate -s 620M "$NVME"
sgdisk -n 1:2048:+64M -t 1:ef00 -c 1:EFI -n 2:0:+32M -t 2:8300 -c 2:ubuntu "$NVME" > /dev/null
dd if="$D/esp" of="$NVME" bs=1M seek=1 conv=notrunc status=none
dd if="$D/root.ext4" of="$NVME" bs=1M seek=65 conv=notrunc status=none
BEFORE=$(sgdisk -p "$NVME" | grep -E '^ +[12] ')
cp "$OVMF_VARS" "$VARS"

qemu() { # $1: with the stick or not
	timeout 300 $QEMU_UEFI_MACHINE -smp 2 -m 2048 -no-reboot -nic none -device virtio-rng-pci \
		-drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" -drive if=pflash,format=raw,file="$VARS" \
		-drive if=none,id=nvme,format=raw,file="$NVME" -device nvme,serial=nvme,drive=nvme \
		$([ "$1" = stick ] && echo "-device qemu-xhci -drive if=none,id=stick,format=raw,file=$USB_IMAGE -device usb-storage,drive=stick") \
		-nographic > "$LOG" 2>&1 || true
}

# Boot 1: from the stick.
args "SamaltakInstallerTest addUbuntuOption. SamaltakInstaller runScript: 'dry-run'. SamaltakInstaller runScript: 'yes store=2'. SamaltakInstaller runScript: 'yes store=end mb=400 reboot=samaltak'" > "$D/install.args"
mt mcopy -o -i "$USB_IMAGE@@1M" "$D/install.args" ::/samaltak.args
qemu stick
cp "$LOG" "$D/boot1.log"
grep -q 'install plan (dry run: nothing is written):' "$LOG" || fail "boot 1: no dry run"
grep -q "install refused: partition 2 'ubuntu' holds ext2/3/4" "$LOG" || fail "boot 1: store=2 not refused"
grep -q 'install done: Samaltak is installed as boot option Boot' "$LOG" || fail "boot 1: not installed"
grep -q 'install rebooting into samaltak' "$LOG" || fail "boot 1: no reboot"
grep -q 'install reboot failed' "$LOG" && fail "boot 1: the reboot failed"

# The disk and the variables, on the host.
sgdisk -v "$NVME" | grep -q 'No problems found' || { sgdisk -v "$NVME"; fail "sgdisk -v: the GPT is not valid"; }
sgdisk -p "$NVME" | grep -E '^ +3 .*samaltak-image' > /dev/null || { sgdisk -p "$NVME"; fail "no partition 3 samaltak-image"; }
sgdisk -i 3 "$NVME" | grep -qi '5AA3A57F-0F7E-4C2B-9B5E-53414D53544F' || fail "partition 3 is not of the store's type"
[ "$(sgdisk -p "$NVME" | grep -E '^ +[12] ')" = "$BEFORE" ] || fail "partitions 1 or 2 changed"
START=$(sgdisk -i 3 "$NVME" | sed -n 's/^First sector: \([0-9]*\).*/\1/p')
[ "$(dd if="$NVME" bs=512 skip="$START" count=1 status=none | head -c 8)" = SAMSTORE ] || fail "no store in partition 3"
mt mcopy -n -i "$NVME@@1M" "::/EFI/samaltak/$UEFI_BOOT" "$D/installed.efi" && cmp -s "$D/installed.efi" "$UEFI/esp/EFI/BOOT/$UEFI_BOOT" || fail "the ESP's EFI/samaltak/$UEFI_BOOT is not the VM"
mt mcopy -n -i "$NVME@@1M" ::/EFI/samaltak/samaltak.args "$D/installed.args" || fail "no EFI/samaltak/samaltak.args"
[ "$(tr '\n' ' ' < "$D/installed.args")" = "--max-heap 256 disk: --headless " ] || fail "samaltak.args: $(cat "$D/installed.args")"
mt mcopy -n -i "$NVME@@1M" "::/EFI/ubuntu/$GRUB" "$D/grub" || fail "the ESP lost EFI/ubuntu"
python3 tests/uefi/efivars.py "$VARS" > "$D/vars1.txt"; cat "$D/vars1.txt"
SAM=$(sed -n "s/^Boot\([0-9A-F]*\) 7 1 'Samaltak' HD(1,GPT,.*) .EFI.samaltak.$UEFI_BOOT$/\1/p" "$D/vars1.txt")
UBU=$(sed -n "s/^Boot\([0-9A-F]*\) 7 1 'ubuntu' HD(1,GPT,.*) .EFI.ubuntu.$GRUB$/\1/p" "$D/vars1.txt")
[ -n "$SAM" ] || fail "no Boot#### Samaltak for EFI/samaltak/$UEFI_BOOT in the variables"
[ -n "$UBU" ] || fail "no Boot#### ubuntu in the variables"
ORDER=$(sed -n 's/^BootOrder //p' "$D/vars1.txt")
case $ORDER in "$UBU"*) ;; *) fail "BootOrder $ORDER does not start with Ubuntu's $UBU" ;; esac
case ",$ORDER," in *",$SAM,"*) fail "BootOrder $ORDER has Samaltak's $SAM" ;; esac
grep -q "^BootNext $SAM$" "$D/vars1.txt" || fail "BootNext is not Samaltak's $SAM"

# Boot 2: without the stick, BootNext: Samaltak from the NVMe, its store, then BootNext Ubuntu.
args "Smalltalk vm stderrWrite: 'booted samaltak from ', Smalltalk vm imagePath, ' ', (FirmwareBoot current bootCurrent printString: 16), (String with: Character lf). FirmwareBoot rebootInto: #ubuntu" > "$D/samaltak.args"
mt mcopy -o -i "$NVME@@1M" "$D/samaltak.args" ::/EFI/samaltak/samaltak.args
qemu nostick
cp "$LOG" "$D/boot2.log"
grep -q "booted samaltak from disk: $(echo "$SAM" | sed 's/^0*//')" "$LOG" || fail "boot 2: Samaltak did not boot from the NVMe (Boot$SAM)"
python3 tests/uefi/efivars.py "$VARS" > "$D/vars2.txt"
grep -q "^BootNext $UBU$" "$D/vars2.txt" || fail "boot 2: BootNext is not Ubuntu's $UBU"
# The firmware drops the stick's own option (it enumerated it) once the stick is gone: the rest stays as it was.
KEPT=$(for n in $(echo "$ORDER" | tr ',' ' '); do grep -q "^Boot$n " "$D/vars2.txt" && printf '%s,' "$n"; done; true)
[ "$(sed -n 's/^BootOrder //p' "$D/vars2.txt")," = "$KEPT" ] || fail "boot 2: BootOrder changed: $(sed -n 's/^BootOrder //p' "$D/vars2.txt") after $ORDER"

# Boot 3: Ubuntu (the fake one).
qemu nostick
cp "$LOG" "$D/boot3.log"
grep -q '^booted ubuntu' "$LOG" || fail "boot 3: BootNext did not boot Ubuntu's option"
python3 tests/uefi/efivars.py "$VARS" | grep -q '^BootNext' && fail "boot 3: BootNext is still set"
echo "test-install: passed ($UEFI_ARCH: Boot$SAM Samaltak, Boot$UBU ubuntu, BootOrder $ORDER)"
