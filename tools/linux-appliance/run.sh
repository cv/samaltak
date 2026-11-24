#!/bin/sh
# Boot the Linux appliance (build.sh) in QEMU: arm64 virt with KVM on this machine's CPU, the kernel's EFI stub started
# by AAVMF (as the Spark's firmware would), virtio-gpu (KMS: the World's screen), virtio keyboard and tablet (evdev),
# virtio-net on QEMU's user network, virtio-rng, and the data volume when there is one.
#
#   tools/linux-appliance/run.sh            (make linux-appliance-run)
#
# Environment: OUT (build); LINUX_DISPLAY (none: no window, the screen reachable by QMP's screendump; gtk or sdl: a
# window; vnc=127.0.0.1:N: QEMU's VNC server); LINUX_CONTROL_PORT and LINUX_RFB_PORT (host ports on 127.0.0.1
# forwarded to the guest's control service, 7341, and RFB server, 5900); LINUX_DATA (an ext4 disk image labelled
# SAMALTAK-DATA: data-disk.sh makes one); LINUX_QMP (a QMP socket: screendump, input-send-event, system_powerdown);
# LINUX_CMDLINE (more kernel arguments); LINUX_CPUS (4), LINUX_RAM_MB (4096). The serial console is stdio.
set -eu
OUT=${OUT:-build}
W=$OUT/linux-appliance
FW=${LINUX_FIRMWARE:-/usr/share/qemu-efi-aarch64/QEMU_EFI.fd}
fwd=""
[ -n "${LINUX_CONTROL_PORT:-}" ] && fwd="$fwd,hostfwd=tcp:127.0.0.1:$LINUX_CONTROL_PORT-:7341"
[ -n "${LINUX_RFB_PORT:-}" ] && fwd="$fwd,hostfwd=tcp:127.0.0.1:$LINUX_RFB_PORT-:5900"
set -- -M virt -cpu host -enable-kvm -smp "${LINUX_CPUS:-4}" -m "${LINUX_RAM_MB:-4096}" -no-reboot \
	-bios "$FW" -kernel "$W/vmlinuz" -initrd "$W/initrd.zst" \
	-append "console=tty0 console=ttyAMA0 quiet loglevel=3 ${LINUX_CMDLINE:-}" \
	-device virtio-gpu-pci,xres=1920,yres=1080 -device virtio-keyboard-pci -device virtio-tablet-pci \
	-netdev "user,id=n0$fwd" -device virtio-net-pci,netdev=n0,romfile= -device virtio-rng-pci \
	-display "${LINUX_DISPLAY:-none}" -serial stdio -monitor none
[ -n "${LINUX_DATA:-}" ] && set -- "$@" -drive "if=none,id=data,format=raw,file=$LINUX_DATA" -device virtio-blk-pci,drive=data
[ -n "${LINUX_QMP:-}" ] && set -- "$@" -qmp "unix:$LINUX_QMP,server=on,wait=off"
exec qemu-system-aarch64 "$@"
