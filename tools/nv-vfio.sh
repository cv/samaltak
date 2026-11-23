#!/bin/sh
# Hands the GB10 between nvidia.ko and vfio-pci on a DEDICATED DGX Spark, for the hosted GSP loop (docs/nv-dayone.md).
#   tools/nv-vfio.sh status    read only: the GPU's driver, its IOMMU group and the group's other functions, the
#                              group's reserved regions (non-relaxable "direct" ones make the kernel refuse VFIO), the
#                              VFIO devices, who has /dev/nvidia* open
#   tools/nv-vfio.sh bind      (root) stop what uses the GPU, unload nvidia_drm/nvidia_modeset/nvidia_uvm, unbind
#                              nvidia, bind vfio-pci (driver_override), check the group, give /dev/vfio/<group> to
#                              $SUDO_USER
#   tools/nv-vfio.sh unbind    (root) back: unbind vfio-pci, clear the override, reprobe (nvidia binds), reload the
#                              modules, restart the services stopped by bind; then nvidia-smi
# NV_BDF (default 000f:01:00.0) is the GPU. bind and unbind refuse to run unless NV_VFIO_DEDICATED=yes: never on a
# shared Spark, whose GPU serves other users (display, services, other people's jobs). Nothing here writes the GPU's
# registers, its configuration space, its firmware (SPI/VBIOS) or resets it: a reset is VfioPciDevice reset, by hand.
set -eu
BDF=${NV_BDF:-000f:01:00.0}
DEV=/sys/bus/pci/devices/$BDF
SERVICES="display-manager nvidia-persistenced nvidia-dcgm dcgm nvidia-fabricmanager"
STATE=/run/nv-vfio.stopped

say() { printf '%s\n' "nv-vfio: $*"; }
die() { printf '%s\n' "nv-vfio: $*" >&2; exit 1; }

group() { basename "$(readlink -f "$DEV/iommu_group")"; }
driver() { if [ -e "$1/driver" ]; then basename "$(readlink -f "$1/driver")"; else echo none; fi; }

status() {
    [ -d "$DEV" ] || die "no PCI function $BDF"
    say "function $BDF: $(cat "$DEV/vendor"):$(cat "$DEV/device"), driver $(driver "$DEV"), override $(cat "$DEV/driver_override")"
    [ -e "$DEV/iommu_group" ] || { say "no IOMMU group (no IOMMU for it): VFIO needs one"; return 0; }
    g=$(group)
    say "IOMMU group $g, type $(cat /sys/kernel/iommu_groups/"$g"/type 2>/dev/null || echo ?)"
    for f in /sys/kernel/iommu_groups/"$g"/devices/*; do
        say "  group member $(basename "$f"): driver $(driver "$f")"
    done
    while read -r start end type; do
        say "  reserved region $start-$end $type"
        [ "$type" = direct ] && direct=yes
    done < /sys/kernel/iommu_groups/"$g"/reserved_regions
    if [ "${direct:-}" = yes ]; then
        say "  WARNING: non-relaxable direct regions (firmware RMRs): Linux refuses user-space DMA ownership of such a"
        say "  device ('Firmware has requested this device have a 1:1 IOMMU mapping'); VFIO_GROUP_SET_CONTAINER will"
        say "  most likely fail with EINVAL. Check dmesg after the first VfioPciDevice open:, and stop there (docs/nv-dayone.md)."
    fi
    say "/dev/vfio: $(find /dev/vfio -mindepth 1 -maxdepth 1 -printf "%f\n" 2>/dev/null | tr '\n' ' ')"
    say "modules: $(lsmod | awk '/^(nvidia|nvidia_drm|nvidia_modeset|nvidia_uvm|vfio|vfio_pci|vfio_pci_core|iommufd) /{printf "%s ", $1}')"
    users=$(fuser /dev/nvidia* 2>/dev/null | tr -s ' ' || true)
    say "processes with /dev/nvidia* open: ${users:-none}"
}

dedicated() {
    [ "${NV_VFIO_DEDICATED:-}" = yes ] || die "refused: set NV_VFIO_DEDICATED=yes, and only on a dedicated Spark (never a shared one)"
    [ "$(id -u)" = 0 ] || die "run as root (sudo -E)"
    [ -d "$DEV" ] || die "no PCI function $BDF"
}

bind() {
    dedicated
    [ "$(driver "$DEV")" = vfio-pci ] && { say "already vfio-pci's"; status; return 0; }
    : > "$STATE"
    for s in $SERVICES; do
        if systemctl is-active --quiet "$s" 2>/dev/null; then systemctl stop "$s"; echo "$s" >> "$STATE"; say "stopped $s"; fi
    done
    for m in nvidia_drm nvidia_modeset nvidia_uvm; do
        if lsmod | grep -q "^$m "; then modprobe -r "$m" || die "cannot unload $m: $(fuser /dev/nvidia* 2>/dev/null || true) still use the GPU"; fi
    done
    if [ "$(driver "$DEV")" != none ]; then echo "$BDF" > "$DEV/driver/unbind"; say "unbound $BDF"; fi
    modprobe vfio-pci
    echo vfio-pci > "$DEV/driver_override"
    echo "$BDF" > /sys/bus/pci/drivers_probe
    [ "$(driver "$DEV")" = vfio-pci ] || die "vfio-pci did not bind $BDF (dmesg)"
    g=$(group)
    for f in /sys/kernel/iommu_groups/"$g"/devices/*; do
        d=$(driver "$f")
        [ "$d" = vfio-pci ] || [ "$d" = none ] || die "group $g is not viable: $(basename "$f") is bound to $d"
    done
    [ -n "${SUDO_USER:-}" ] && chown "$SUDO_USER" "/dev/vfio/$g"
    say "$BDF is vfio-pci's, group $g (/dev/vfio/$g)"
    status
}

unbind() {
    dedicated
    if [ "$(driver "$DEV")" = vfio-pci ]; then echo "$BDF" > "$DEV/driver/unbind"; say "unbound $BDF from vfio-pci"; fi
    echo > "$DEV/driver_override"
    modprobe nvidia
    echo "$BDF" > /sys/bus/pci/drivers_probe
    for m in nvidia_uvm nvidia_modeset nvidia_drm; do modprobe "$m" || say "could not load $m"; done
    if [ -f "$STATE" ]; then
        while read -r s; do systemctl start "$s" && say "started $s"; done < "$STATE"
        rm -f "$STATE"
    fi
    say "$BDF: driver $(driver "$DEV")"
    nvidia-smi -L || say "nvidia-smi failed: the GPU did not come back (docs/nv-dayone.md, recovery)"
}

case "${1:-status}" in
    status) status ;;
    bind) bind ;;
    unbind) unbind ;;
    *) die "usage: $0 status|bind|unbind" ;;
esac
