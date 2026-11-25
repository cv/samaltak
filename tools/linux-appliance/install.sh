#!/bin/sh
# Install the Samaltak Linux appliance on this machine's disk next to DGX OS (or any UEFI Linux), run there as root
# (docs/linux-appliance.md, The Spark's first boot). It changes nothing of DGX OS but adds files and one boot option:
#   - the UKI (samaltak-linux.efi, from the stick: next to this script) as \EFI\samaltak-linux\samaltak-linux.efi on the
#     ESP mounted at /boot/efi (the one before it kept as samaltak-linux.efi.old: the way back to it);
#   - the data volume, an ext4 image file /var/lib/samaltak/data.img on DGX OS's root (samaltak.args, the control token
#     and VNC password: copied from the stick's data partition when it is mounted, given with --data-from, else made
#     here, 0600, copies in /var/lib/samaltak), unless it is there already;
#   - the CUDA root (docs/cuda.md), /var/lib/samaltak/samaltak-cuda-13.squashfs: the stick's SAMALTAK-CUDA partition
#     (or --cuda FILE), checked against the sha256 next to this script, unless the same one is there already;
#   - a boot option "Samaltak Linux" for the UKI whose load options are its command line plus samaltak.data=UUID=<the
#     root's>:/var/lib/samaltak/data.img and samaltak.cuda=UUID=<the same>:<the squashfs> (Secure Boot off: systemd's stub takes them over its built-in one); BootOrder
#     is put back as it was, so the machine still boots DGX OS unless asked (--bootnext, or efibootmgr -n).
#
# usage: sudo sh install.sh [--uki FILE] [--data-from DIR] [--data-mb N] [--cuda FILE | --no-cuda] [--no-old] [--bootnext]
#        [--dry-run]
#   --no-old   replace the installed UKI without keeping it as .old (DGX OS's 300 MB ESP holds one Spark UKI, 164 MB)
# The way back: power-cycle (BootNext is used once), or from DGX OS: efibootmgr -b NNNN -B (the option), rm -r
# /boot/efi/EFI/samaltak-linux /var/lib/samaltak.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
uki=$here/samaltak-linux.efi
from=
data_mb=4096
bootnext=0
keep=1
dry=0
cfrom=
cuda=1
while [ $# -gt 0 ]; do
	case $1 in
	--uki) uki=$2; shift ;;
	--data-from) from=$2; shift ;;
	--data-mb) data_mb=$2; shift ;;
	--cuda) cfrom=$2; shift ;;
	--no-cuda) cuda=0 ;;
	--bootnext) bootnext=1 ;;
	--no-old) keep=0 ;;
	--dry-run | -n) dry=1 ;;
	-h | --help) sed -n '2,20p' "$0"; exit 0 ;;
	*) echo "install.sh: unknown option $1" >&2; exit 2 ;;
	esac
	shift
done
say() { echo "install.sh: $*"; }
run() { if [ $dry = 1 ]; then echo "would run: $*"; else "$@"; fi; }
die() { echo "install.sh: $*" >&2; exit 1; }
[ -f "$uki" ] || die "no UKI at $uki (--uki FILE)"
[ -d /sys/firmware/efi ] || die "this Linux was not booted by UEFI"
command -v efibootmgr > /dev/null || die "needs efibootmgr (apt install efibootmgr)"
[ $dry = 1 ] || [ "$(id -u)" = 0 ] || die "run it as root (sudo)"
esp=$(findmnt -no SOURCE /boot/efi) || die "no ESP mounted at /boot/efi"
disk=/dev/$(lsblk -no PKNAME "$esp" | head -1)
part=$(cat "/sys/class/block/${esp##*/}/partition")
root_uuid=$(findmnt -no UUID /)
[ -n "$root_uuid" ] || die "no UUID for the root file system"
t=$(mktemp)
objcopy -O binary --only-section=.cmdline "$uki" "$t"
cmdline=$(tr -d '\000' < "$t")
rm -f "$t"
[ -n "$cmdline" ] || cmdline="console=tty0 quiet loglevel=3"
size=$(($(wc -c < "$uki") / 1048576))
free=$(($(df -Pk /boot/efi | awk 'NR == 2 { print $4 }') / 1024))
# Room: what is free, plus what goes: the .old one (replaced by the installed one), or with --no-old the installed one.
e=/boot/efi/EFI/samaltak-linux
mb() { [ -f "$1" ] && echo $(($(wc -c < "$1") / 1048576)) || echo 0; }
gone=$(mb $e/samaltak-linux.efi.old); [ $keep = 0 ] && gone=$(mb $e/samaltak-linux.efi)
say "ESP $esp (disk $disk, partition $part, $free MB free), UKI $size MB, root UUID $root_uuid"
[ $((free + gone)) -gt $((size + 8)) ] || die "not enough room on the ESP for the UKI ($free MB free, $gone MB to go: --no-old drops the installed one)"

# The UKI.
run mkdir -p /boot/efi/EFI/samaltak-linux
if [ -f $e/samaltak-linux.efi ]; then
	if [ $keep = 1 ]; then run mv -f $e/samaltak-linux.efi $e/samaltak-linux.efi.old; else run rm -f $e/samaltak-linux.efi; fi
fi
run cp "$uki" /boot/efi/EFI/samaltak-linux/samaltak-linux.efi
run sync

# The data volume.
img=/var/lib/samaltak/data.img
if [ -f "$img" ]; then
	say "keeping the data volume $img"
else
	if [ -z "$from" ]; then
		for d in /media/*/SAMALTAK-DATA /media/*/*/SAMALTAK-DATA /run/media/*/SAMALTAK-DATA; do
			[ -f "$d/samaltak.args" ] && from=$d && break
		done
	fi
	d=$(mktemp -d)
	(umask 077
	 if [ -n "$from" ]; then
		cp -a "$from/." "$d/" && rm -rf "$d/lost+found"
		say "the data volume from $from"
	 else
		head -c 24 /dev/urandom | base64 | tr -d '/+=\n' > "$d/control-token"
		head -c 6 /dev/urandom | base64 | tr -d '/+=\n' | cut -c1-8 > "$d/vnc-password"
		printf '%s\n' --max-heap 4096 --control --control-host 0.0.0.0 --control-port 7341 --control-token-file /data/control-token \
			--display --display-host 0.0.0.0 --display-port 5900 --display-vnc-auth --display-password-file /data/vnc-password > "$d/samaltak.args"
		say "a new control token and VNC password, in the data volume and in /var/lib/samaltak (root, 0600)"
	 fi
	 mkdir -p "$d/log")
	run mkdir -p /var/lib/samaltak
	run chmod 700 /var/lib/samaltak
	[ -n "$from" ] || run cp "$d/control-token" "$d/vnc-password" /var/lib/samaltak/
	run truncate -s "${data_mb}M" "$img"
	run mkfs.ext4 -q -F -L SAMALTAK-DATA -d "$d" "$img"
	run chmod 600 "$img"
	rm -rf "$d"
fi

# The CUDA root: the stick's SAMALTAK-CUDA partition, --cuda FILE, or samaltak-cuda-13.squashfs next to this script;
# its length is the superblock's (bytes_used, offset 40, padded to 4 KiB as mksquashfs pads), its sha256 the one
# usb.sh put next to this script.
csq=/var/lib/samaltak/samaltak-cuda-13.squashfs
if [ $cuda = 1 ] && [ -z "$cfrom" ]; then
	if [ -e /dev/disk/by-partlabel/SAMALTAK-CUDA ]; then cfrom=$(readlink -f /dev/disk/by-partlabel/SAMALTAK-CUDA)
	elif [ -f "$here/samaltak-cuda-13.squashfs" ]; then cfrom=$here/samaltak-cuda-13.squashfs; fi
fi
if [ $cuda = 1 ] && [ -n "$cfrom" ]; then
	[ "$(head -c 4 "$cfrom")" = hsqs ] || die "$cfrom is no squashfs"
	used=$(od -An -tu8 -j40 -N8 "$cfrom" | tr -d ' ')
	len=$(( (used + 4095) / 4096 * 4096 ))
	want=$(sed -n 's/^\([0-9a-f]\{64\}\) .*/\1/p' "$here/samaltak-cuda-13.squashfs.sha256" 2>/dev/null || true)
	have=""; [ -f "$csq" ] && have=$(sha256sum < "$csq" | cut -d' ' -f1)
	if [ -n "$have" ] && [ "$have" = "$want" ]; then
		say "keeping the CUDA root $csq (the same sha256)"
	else
		room=$(($(df -Pk /var/lib | awk 'NR == 2 { print $4 }') / 1024))
		[ $room -gt $((len / 1048576 + 256)) ] || die "not enough room in /var/lib for the CUDA root ($((len / 1048576)) MB, $room MB free)"
		run mkdir -p /var/lib/samaltak
		run chmod 700 /var/lib/samaltak
		say "copying the CUDA root from $cfrom ($((len / 1048576)) MB)"
		run sh -c 'head -c "$1" "$2" > "$3.new"' sh "$len" "$cfrom" "$csq"
		if [ $dry = 0 ]; then
			got=$(sha256sum < "$csq.new" | cut -d' ' -f1)
			[ -z "$want" ] || [ "$got" = "$want" ] || { rm -f "$csq.new"; die "the CUDA root copied from $cfrom is not the one usb.sh made (sha256 $got, not $want)"; }
			[ -n "$want" ] || say "no sha256 next to this script: the CUDA root's copy is unchecked"
		fi
		run chmod 600 "$csq.new"
		run mv -f "$csq.new" "$csq"
		say "the CUDA root $csq"
	fi
fi
copt=""
{ [ -f "$csq" ] || { [ $dry = 1 ] && [ -n "$cfrom" ]; }; } && copt=" samaltak.cuda=UUID=$root_uuid:$csq"

# The boot option, BootOrder as it was.
option() { efibootmgr | sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\)\*\{0,1\}[[:space:]]*Samaltak Linux\([[:space:]].*\)\{0,1\}$/\1/p'; }
order=$(efibootmgr | sed -n 's/^BootOrder: //p')
for n in $(option); do run efibootmgr -q -b "$n" -B; done
run efibootmgr -q --create --disk "$disk" --part "$part" --label "Samaltak Linux" --loader '\EFI\samaltak-linux\samaltak-linux.efi' \
	--unicode "$cmdline samaltak.data=UUID=$root_uuid:$img$copt"
[ -n "$order" ] && [ "$(efibootmgr | sed -n 's/^BootOrder: //p')" != "$order" ] && run efibootmgr -q -o "$order"
n=$(option | head -1)
say "Boot${n:-NNNN} is Samaltak Linux; BootOrder ${order:-?} as before"
if [ $bootnext = 1 ] && [ -n "$n" ]; then
	run efibootmgr -q -n "$n"
	say "BootNext ${n}: the next boot starts Samaltak, once"
fi
say "to boot it once later: sudo efibootmgr -n ${n:-NNNN} && sudo reboot"
