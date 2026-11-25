#!/bin/sh
# The Linux appliance on a USB stick (docs/linux-appliance.md, The Spark's first boot): after make linux-appliance, a
# unified kernel image (UKI: systemd's EFI stub with the kernel, the initramfs, the command line and an os-release, one
# EFI application the firmware starts without load options) and a GPT disk image to write to a stick: an ESP with the
# UKI as \EFI\BOOT\BOOTAA64.EFI (removable media boot) and as \EFI\samaltak-linux\samaltak-linux.efi with install.sh
# (to install it on the machine's NVMe next to DGX OS), the data volume (ext4, SAMALTAK-DATA): samaltak.args with
# control and RFB on every address, a control token and a VNC password of its own (0600, copies kept in OUT), and,
# after make linux-appliance-cuda, the CUDA root: a partition named SAMALTAK-CUDA that is the squashfs (rcS mounts it
# at /opt/cuda; install.sh copies it, checked against the sha256 on the ESP).
#
#   tools/linux-appliance/usb.sh            (make linux-appliance-usb)  ->  OUT/linux-appliance/{samaltak-linux.efi,usb.img}
#   sudo dd if=build/linux-appliance/usb.img of=/dev/sdX bs=4M conv=fsync    (the stick: check the device with lsblk)
#
# Environment: OUT (build), LINUX_CMDLINE (the kernel's command line; default: console=tty0 console=ttyAMA0 quiet
# loglevel=3), LINUX_USB_DATA_MB (the data volume, 1024), LINUX_USB_ARGS_FILE (samaltak.args instead of the default),
# LINUX_USB_CUDA (the CUDA root's squashfs: OUT/linux-appliance/samaltak-cuda-13.squashfs when there; none: without),
# LINUX_USB_TOKEN_FILE and LINUX_USB_VNC_PASSWORD_FILE (the control token and VNC password; default: made here, kept as
# OUT/linux-appliance/usb-control-token and usb-vnc-password, 0600), LINUX_CACHE (systemd-boot-efi's stub is downloaded
# there). Needs: objcopy (binutils 2.42: PE for aarch64), mtools, sfdisk, mkfs.ext4 (-d), apt-get download. No root.
set -eu
OUT=${OUT:-build}
W=$OUT/linux-appliance
U=$W/usb
CACHE=${LINUX_CACHE:-$HOME/.cache/samaltak/linux-appliance}
HERE=$(cd "$(dirname "$0")" && pwd)
CMDLINE=${LINUX_CMDLINE:-console=tty0 console=ttyAMA0 quiet loglevel=3}
DATA_MB=${LINUX_USB_DATA_MB:-1024}
PATH=$PATH:/sbin:/usr/sbin
say() { echo "linux-appliance-usb: $*"; }
[ -f "$W/vmlinuz" ] && [ -f "$W/initrd.zst" ] || { echo "linux-appliance-usb: no $W/vmlinuz or initrd.zst: make linux-appliance first" >&2; exit 1; }
# The CUDA root (make linux-appliance-cuda), if there is one: the stick's third partition.
CUDA=${LINUX_USB_CUDA:-$W/samaltak-cuda-13.squashfs}
if [ "$CUDA" = none ]; then CUDA=""
elif [ ! -f "$CUDA" ]; then
	[ -z "${LINUX_USB_CUDA:-}" ] || { echo "linux-appliance-usb: no $CUDA (LINUX_USB_CUDA)" >&2; exit 1; }
	say "no $CUDA: a stick without the CUDA root (make linux-appliance-cuda first)"; CUDA=""
fi
cuda_mb=0; [ -z "$CUDA" ] || cuda_mb=$(( ($(wc -c < "$CUDA") + 1048575) / 1048576 ))
rm -rf "$U" && mkdir -p "$U" "$CACHE/debs"

# systemd's EFI stub (systemd-boot-efi, the build host's version): it runs the kernel in its .linux section with the
# .initrd and the .cmdline (load options replace that only while Secure Boot is off: install.sh's samaltak.data=).
STUB=$CACHE/sdboot/usr/lib/systemd/boot/efi/linuxaa64.efi.stub
if [ ! -f "$STUB" ]; then
	ls "$CACHE/debs"/systemd-boot-efi_*.deb >/dev/null 2>&1 || (cd "$CACHE/debs" && apt-get download systemd-boot-efi)
	dpkg-deb -x "$CACHE/debs"/systemd-boot-efi_*.deb "$CACHE/sdboot"
fi
# Ubuntu's arm64 vmlinuz is a gzipped Image (GRUB and QEMU's -kernel unpack it); the Image itself is the EFI application.
if [ "$(head -c 2 "$W/vmlinuz" | od -An -tx1 | tr -d ' ')" = 1f8b ]; then gzip -dc "$W/vmlinuz" > "$U/Image"; else cp "$W/vmlinuz" "$U/Image"; fi
printf 'MZ' | cmp -s -n 2 - "$U/Image" || { echo "linux-appliance-usb: the kernel is not an EFI application" >&2; exit 1; }
printf '%s' "$CMDLINE" > "$U/cmdline"
VERSION=$(git -C "$HERE" describe --always --dirty 2>/dev/null || echo unknown)
printf 'NAME="Samaltak"\nID=samaltak\nPRETTY_NAME="Samaltak Linux appliance %s (%s)"\nVERSION_ID=%s\n' "$VERSION" "$(cat "$W/variant" 2>/dev/null || echo ?)" "$VERSION" > "$U/os-release"
# The sections after the stub's, each at the next section-aligned address (as ukify places them).
align=$((0x$(objdump -p "$STUB" | awk '$1 == "SectionAlignment" { print $2 }')))
end=$(objdump -h "$STUB" | awk 'NF == 7 && $1 ~ /^[0-9]+$/ { print $3, $4 }' | while read -r size vma; do echo $((0x$vma + 0x$size)); done | sort -n | tail -1)
at=$(( (end + align - 1) / align * align ))
set --
for s in osrel:os-release cmdline:cmdline initrd:../initrd.zst linux:Image; do
	name=${s%%:*}; file=$U/${s#*:}; [ "${s#*:}" = ../initrd.zst ] && file=$W/initrd.zst
	set -- "$@" --add-section ".$name=$file" --change-section-vma ".$name=$(printf 0x%x $at)"
	at=$(( (at + $(wc -c < "$file") + align - 1) / align * align ))
done
objcopy "$@" "$STUB" "$W/samaltak-linux.efi"
say "$W/samaltak-linux.efi $(($(wc -c < "$W/samaltak-linux.efi") / 1048576)) MB (UKI: $CMDLINE)"

# The data volume: samaltak.args, the control token and VNC password (0600), the log directory.
mkdir -p "$U/data/log"
(umask 077
 if [ -n "${LINUX_USB_TOKEN_FILE:-}" ]; then tr -d ' \n' < "$LINUX_USB_TOKEN_FILE" > "$U/data/control-token"
 else head -c 24 /dev/urandom | base64 | tr -d '/+=\n' > "$U/data/control-token"; cp "$U/data/control-token" "$W/usb-control-token"; fi
 if [ -n "${LINUX_USB_VNC_PASSWORD_FILE:-}" ]; then tr -d ' \n' < "$LINUX_USB_VNC_PASSWORD_FILE" > "$U/data/vnc-password"
 else head -c 6 /dev/urandom | base64 | tr -d '/+=\n' | cut -c1-8 > "$U/data/vnc-password"; cp "$U/data/vnc-password" "$W/usb-vnc-password"; fi
 if [ -n "${LINUX_USB_ARGS_FILE:-}" ]; then cp "$LINUX_USB_ARGS_FILE" "$U/data/samaltak.args"
 else printf '%s\n' --max-heap 4096 --control --control-host 0.0.0.0 --control-port 7341 --control-token-file /data/control-token \
	--display --display-host 0.0.0.0 --display-port 5900 --display-vnc-auth --display-password-file /data/vnc-password > "$U/data/samaltak.args"; fi)
truncate -s "${DATA_MB}M" "$U/data.part" && mkfs.ext4 -q -F -L SAMALTAK-DATA -d "$U/data" "$U/data.part"

# The ESP: the UKI where removable media boot looks, and where install.sh copies it from.
esp_mb=$(( $(wc -c < "$W/samaltak-linux.efi") / 1048576 * 2 + 32 ))
truncate -s "${esp_mb}M" "$U/esp.part"
mformat -i "$U/esp.part" -F -v SAMALTAK-USB ::
mmd -i "$U/esp.part" ::/EFI ::/EFI/BOOT ::/EFI/samaltak-linux
mcopy -i "$U/esp.part" "$W/samaltak-linux.efi" ::/EFI/BOOT/BOOTAA64.EFI
mcopy -i "$U/esp.part" "$W/samaltak-linux.efi" "$HERE/install.sh" ::/EFI/samaltak-linux/
if [ -n "$CUDA" ]; then
	echo "$(sha256sum < "$CUDA" | cut -d' ' -f1)  samaltak-cuda-13.squashfs" > "$U/samaltak-cuda-13.squashfs.sha256"
	mcopy -i "$U/esp.part" "$U/samaltak-cuda-13.squashfs.sha256" ::/EFI/samaltak-linux/
fi

# The disk: GPT, the ESP, the data volume and the CUDA root at 1 MiB boundaries.
img=$W/usb.img
rm -f "$img" && truncate -s $((1 + esp_mb + DATA_MB + cuda_mb + 1))M "$img"
{ echo "label: gpt"
  echo "start=1MiB, size=${esp_mb}MiB, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name=\"SAMALTAK-ESP\""
  echo "size=${DATA_MB}MiB, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name=\"SAMALTAK-DATA\""
  [ -z "$CUDA" ] || echo "size=${cuda_mb}MiB, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name=\"SAMALTAK-CUDA\""; } | sfdisk -q "$img"
dd if="$U/esp.part" of="$img" bs=1M seek=1 conv=notrunc status=none
dd if="$U/data.part" of="$img" bs=1M seek=$((1 + esp_mb)) conv=notrunc status=none
[ -z "$CUDA" ] || dd if="$CUDA" of="$img" bs=1M seek=$((1 + esp_mb + DATA_MB)) conv=notrunc,sparse status=none
chmod 600 "$img"
rm -f "$U/esp.part" "$U/data.part"
say "$img $(($(wc -c < "$img") / 1048576)) MB (ESP $esp_mb MB, data $DATA_MB MB${CUDA:+, CUDA $cuda_mb MB}); write it with: sudo dd if=$img of=/dev/sdX bs=4M conv=fsync"
