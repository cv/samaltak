#!/bin/sh
# The Samaltak Linux appliance (docs/linux-appliance.md): Ubuntu's NVIDIA kernel (the DGX Spark's) booted by its EFI
# stub with an initramfs that holds busybox (PID 1 and the boot scripts), the hosted VM and image, an SDL3 built for
# KMS/DRM (no X11, no Wayland), the kernel modules and certificates. The World draws itself and presents on KMS
# (KmsDisplay: a dumb buffer, evdev input) unless a variant brings the userspace SDL's own KMS path needs.
#
#   tools/linux-appliance/build.sh          (make linux-appliance)  ->  OUT/linux-appliance/{vmlinuz,initrd.zst}
#
# Environment: OUT (build), VM (vm/build/samaltak), IMAGE (OUT/samaltak.image), LINUX_KVER (the kernel's version,
# 7.0.0-1024-nvidia), LINUX_GPU (virtio, the default: QEMU's virtio-gpu, the World a SoftwareGPU on the image's KMS
# screen, no GPU userspace; mesa: instead SDL's KMS/DRM window with Mesa's EGL/GBM and lavapipe, the World's frames in
# its surface; nvidia: the Spark's, the open kernel modules and the GSP firmware, no NVIDIA userspace: the World an
# NvComputeGPU (System-NV over the RM ioctls) on the image's KMS screen on nvidia-drm; nvidia-vulkan: also NVIDIA's
# Vulkan, EGL and GBM userspace, the default World on SDL_GPU through VK_KHR_display; both: mesa and nvidia-vulkan),
# LINUX_MODULES (more modules,
# by name), LINUX_ARGS_FILE (the VM's arguments, one per line, into /etc/samaltak.args), LINUX_CONTROL_TOKEN_FILE
# (the control service's token, into the root 0600: anyone who can read the initramfs can read it), SDL_SRC (an SDL3
# checkout of the version the VM was built against; default: cloned into the cache), LINUX_CACHE
# (~/.cache/samaltak/linux-appliance: the downloaded packages, the extracted kernel, SDL). Needs: an Ubuntu 24.04
# host of the target's architecture with the VM's build dependencies (its libraries are copied from here), apt-get
# download, dpkg-deb, cmake, ninja, cpio, zstd, depmod. No root.
set -eu
OUT=${OUT:-build}
VM=${VM:-vm/build/samaltak}
IMAGE=${IMAGE:-$OUT/samaltak.image}
KVER=${LINUX_KVER:-7.0.0-1024-nvidia}
GPU=${LINUX_GPU:-virtio}
CACHE=${LINUX_CACHE:-$HOME/.cache/samaltak/linux-appliance}
W=$OUT/linux-appliance
R=$W/root
HERE=$(cd "$(dirname "$0")" && pwd)
TRIPLE=$(gcc -dumpmachine | sed 's/-unknown//')
LIB=/usr/lib/$TRIPLE
PATH=$PATH:/sbin:/usr/sbin
case $GPU in virtio|mesa|nvidia|nvidia-vulkan|both) ;; *) echo "linux-appliance: LINUX_GPU=$GPU: virtio, mesa, nvidia, nvidia-vulkan or both" >&2; exit 1 ;; esac
mesa() { [ "$GPU" = mesa ] || [ "$GPU" = both ]; }
nvidia() { [ "$GPU" = nvidia ] || [ "$GPU" = nvidia-vulkan ] || [ "$GPU" = both ]; }
nvuser() { [ "$GPU" = nvidia-vulkan ] || [ "$GPU" = both ]; }
say() { echo "linux-appliance: $*"; }
[ -x "$VM" ] && [ -f "$IMAGE" ] || { echo "linux-appliance: no $VM or $IMAGE: make all first" >&2; exit 1; }
mkdir -p "$CACHE/debs" "$W"

# The packages: the kernel, its modules, and the headers SDL's KMS/DRM backend builds against.
NVVER=$(dpkg-query -W -f '${Version}' libnvidia-gl-580 2>/dev/null | cut -d- -f1 || true)
debs="linux-image-$KVER linux-modules-$KVER libdrm-dev libgbm-dev libudev-dev"
nvidia && debs="$debs linux-modules-nvidia-580-open-$KVER nvidia-firmware-580-$NVVER"
for p in $debs; do
	ls "$CACHE/debs/$p"_*.deb >/dev/null 2>&1 || (cd "$CACHE/debs" && apt-get download "$p")
done
K=$CACHE/kernel-$KVER
if [ ! -f "$K/.done" ]; then
	rm -rf "$K" && mkdir -p "$K"
	for p in linux-image-$KVER linux-modules-$KVER; do dpkg-deb -x "$CACHE/debs/$p"_*.deb "$K"; done
	touch "$K/.done"
fi
if nvidia && [ ! -f "$K/.nvidia-$NVVER" ]; then
	dpkg-deb -x "$CACHE/debs/linux-modules-nvidia-580-open-$KVER"_*.deb "$K"
	dpkg-deb -x "$CACHE/debs/nvidia-firmware-580-$NVVER"_*.deb "$K"
	touch "$K/.nvidia-$NVVER"
fi
# The package's modules.dep is made when it is installed (depmod): make it here, for what was extracted.
depmod -b "$K" "$KVER"

# SDL3 with KMS/DRM (and udev for input devices), of the version the VM's headers are; X11 and Wayland off.
SDLVER=$(pkg-config --modversion sdl3)
SDL_SRC=${SDL_SRC:-$CACHE/SDL-$SDLVER}
[ -f "$SDL_SRC/CMakeLists.txt" ] || git clone -q --depth 1 --branch "release-$SDLVER" https://github.com/libsdl-org/SDL "$SDL_SRC"
SDLB=$CACHE/sdl-$SDLVER
if [ ! -f "$SDLB/libSDL3.so.0" ]; then
	S=$CACHE/sysroot && rm -rf "$S" && mkdir -p "$S"
	for p in libdrm-dev libgbm-dev libudev-dev; do dpkg-deb -x "$CACHE/debs/$p"_*.deb "$S"; done
	for f in "$S$LIB"/*.so; do t=$(readlink "$f"); [ -e "$S$LIB/$t" ] || ln -sf "$LIB/$t" "$S$LIB/$t"; done
	PKG_CONFIG_PATH=$S$LIB/pkgconfig:$S/usr/share/pkgconfig PKG_CONFIG_SYSROOT_DIR=$S \
	cmake -S "$SDL_SRC" -B "$SDLB" -G Ninja -DCMAKE_BUILD_TYPE=Release -DSDL_UNIX_CONSOLE_BUILD=ON -DCMAKE_LIBRARY_PATH="$S$LIB" \
		-DCMAKE_C_FLAGS="-I$S/usr/include" -DSDL_X11=OFF -DSDL_WAYLAND=OFF -DSDL_KMSDRM=ON -DSDL_VULKAN=ON -DSDL_OPENGLES=ON \
		-DSDL_OPENGL=OFF -DSDL_ALSA=OFF -DSDL_PULSEAUDIO=OFF -DSDL_PIPEWIRE=OFF -DSDL_JACK=OFF -DSDL_SNDIO=OFF -DSDL_DBUS=OFF \
		-DSDL_IBUS=OFF -DSDL_TESTS=OFF -DSDL_TEST_LIBRARY=OFF -DSDL_STATIC=OFF > "$CACHE/sdl-cmake.log"
	grep -q 'SDL_KMSDRM .*: ON' "$CACHE/sdl-cmake.log" && grep -q 'SDL_LIBUDEV .*: ON' "$CACHE/sdl-cmake.log" \
		|| { echo "linux-appliance: SDL without KMS/DRM or udev: $CACHE/sdl-cmake.log" >&2; exit 1; }
	ninja -C "$SDLB" > "$CACHE/sdl-ninja.log"
fi

# The root.
rm -rf "$R" && mkdir -p "$R"
cp -a "$HERE/root/." "$R/"
mkdir -p "$R/bin" "$R/sbin" "$R/usr/bin" "$R/usr/sbin" "$R/proc" "$R/sys" "$R/dev" "$R/run" "$R/tmp" "$R/data" \
	"$R/samaltak" "$R/opt/cuda" "$R/usr/local/lib" "$R/etc/ssl/certs" "$R/usr/lib/ssl" "$R$LIB" "$R/var/log"
cp /usr/bin/busybox "$R/bin/busybox"
file -L "$R/bin/busybox" | grep -q 'statically linked' || { echo "linux-appliance: busybox is not static (busybox-static)" >&2; exit 1; }
for a in $(busybox --list-full); do [ -e "$R/$a" ] || ln -s /bin/busybox "$R/$a"; done
ln -sf bin/busybox "$R/init"
[ -n "${LINUX_ARGS_FILE:-}" ] && cp "$LINUX_ARGS_FILE" "$R/etc/samaltak.args"
if [ -n "${LINUX_CONTROL_TOKEN_FILE:-}" ]; then
	(umask 077 && printf '%s\n' --control-token-file /etc/samaltak-control-token >> "$R/etc/samaltak.args" \
		&& tr -d ' \n' < "$LINUX_CONTROL_TOKEN_FILE" > "$R/etc/samaltak-control-token")
fi
cp "$VM" "$R/samaltak/samaltak"
cp "$IMAGE" "$R/samaltak/samaltak.image"
cp -L "$SDLB/libSDL3.so.0" "$R/usr/local/lib/libSDL3.so.0"
cp -L /etc/ssl/certs/ca-certificates.crt "$R/etc/ssl/certs/"
cp -L /etc/ssl/openssl.cnf "$R/etc/ssl/"
ln -s /etc/ssl/certs/ca-certificates.crt "$R/usr/lib/ssl/cert.pem"; ln -s /etc/ssl/certs "$R/usr/lib/ssl/certs"
ln -s /etc/ssl/openssl.cnf "$R/usr/lib/ssl/openssl.cnf"

# What SDL and the VM load at run time (dlopen), by GPU: Mesa's EGL/GBM (SDL's KMS/DRM windows) and lavapipe; NVIDIA's.
# What the CUDA root's libraries need of the system besides the VM's own (cuda.sh checks): glibc's compatibility
# stubs, zlib (cuOpt's client library).
dl="$LIB/libudev.so.1 $LIB/libdl.so.2 $LIB/libpthread.so.0 $LIB/librt.so.1 $LIB/libz.so.1"
{ mesa || nvuser; } && dl="$dl $LIB/libdrm.so.2 $LIB/libgbm.so.1 $LIB/libEGL.so.1 $LIB/libGLESv2.so.2 $LIB/libvulkan.so.1"
data=""
if mesa; then
	dl="$dl $LIB/libEGL_mesa.so.0 $LIB/gbm/dri_gbm.so $LIB/dri/kms_swrast_dri.so $LIB/dri/virtio_gpu_dri.so $LIB/dri/swrast_dri.so $LIB/libvulkan_lvp.so"
	data="$data /usr/share/glvnd/egl_vendor.d/50_mesa.json /usr/share/vulkan/icd.d/lvp_icd.json"
fi
if nvuser; then
	dl="$dl $LIB/libGLX_nvidia.so.0 $LIB/libEGL_nvidia.so.0 $LIB/libnvidia-egl-gbm.so.1 $LIB/gbm/nvidia-drm_gbm.so $LIB/libnvidia-glvkspirv.so.$NVVER $LIB/libnvidia-eglcore.so.$NVVER $LIB/libnvidia-gpucomp.so.$NVVER"
	data="$data /usr/share/glvnd/egl_vendor.d/10_nvidia.json /usr/share/vulkan/icd.d/nvidia_icd.json /usr/share/egl/egl_external_platform.d/15_nvidia_gbm.json"
fi
for f in $data; do mkdir -p "$R$(dirname "$f")" && cp -L "$f" "$R$f"; done
# The World's GPU and screen: virtio, a SoftwareGPU on the image's KMS screen (no SDL window); with Mesa alone (QEMU)
# lavapipe cannot show on KMS (no VK_KHR_display), so a SoftwareGPU draws and HostFramePresenter copies its frames into
# SDL's window surface (GLES over GBM); NVIDIA's Vulkan shows on KMS itself.
# nvidia: an NvComputeGPU on the KMS screen (a SoftwareGPU on it where the GPU does not open: GPUPlatform falls back).
[ "$GPU" = virtio ] && echo 'export SAMALTAK_SCREEN=kms SAMALTAK_GPU=software' >> "$R/etc/samaltak.env"
[ "$GPU" = nvidia ] && echo 'export SAMALTAK_SCREEN=kms SAMALTAK_GPU=nv' >> "$R/etc/samaltak.env"
mesa && ! nvuser && echo 'export SAMALTAK_GPU=software' >> "$R/etc/samaltak.env"
echo "$GPU" > "$W/variant"
# Copy files and their shared-library closure (ldd), each at the path the loader finds it under (the host's layout).
seen=$W/libs.seen; : > "$seen"
todo="$R/samaltak/samaltak $R/usr/local/lib/libSDL3.so.0 $dl"
while [ -n "$todo" ]; do
	next=""
	for f in $todo; do
		grep -qx "$f" "$seen" && continue; echo "$f" >> "$seen"
		case $f in "$R"/*) ;; *) mkdir -p "$R$(dirname "$f")" && cp -L "$f" "$R$f" ;; esac
		for d in $(ldd "$f" 2>/dev/null | awk '/=> \// { print $3 } /^\t\/.*ld-linux/ { print $1 }'); do
			case $d in /usr/local/lib/libSDL3*) continue ;; esac
			grep -qx "$d" "$seen" || next="$next $d"
		done
	done
	todo=$next
done
# /lib is /usr/lib on the host (merged /usr): make it so here too.
[ -d "$R/lib" ] && { cp -a "$R/lib/." "$R/usr/lib/" && rm -rf "$R/lib"; }
ln -s usr/lib "$R/lib"

# Kernel modules: the devices of QEMU and of the Spark that are not built in, with what they depend on, uncompressed
# (busybox's modprobe reads no zstd), and depmod's tables for them.
mods="virtio-gpu virtio_input virtio_rng hid hid-generic usbhid usb-storage uas nvme r8169 r8127 ${LINUX_MODULES:-}"
nvidia && mods="$mods nvidia nvidia-modeset nvidia-drm nvidia-uvm"
M=lib/modules/$KVER
mkdir -p "$R/usr/$M"
dep=$K/$M/modules.dep
want=""
for m in $mods; do
	n=$(echo "$m" | sed 's/[-_]/[-_]/g')
	line=$(grep -E "(^|/)$n\.ko(\.zst)?:" "$dep" | head -1)
	[ -n "$line" ] || { echo "linux-appliance: no module $m in $dep" >&2; exit 1; }
	want="$want $(echo "$line" | tr -d :)"
done
for p in $(echo "$want" | tr ' ' '\n' | sort -u); do
	mkdir -p "$R/usr/$M/$(dirname "$p")"
	case $p in *.zst) zstd -q -d -f "$K/$M/$p" -o "$R/usr/$M/${p%.zst}" ;; *) cp "$K/$M/$p" "$R/usr/$M/$p" ;; esac
done
for f in modules.order modules.builtin modules.builtin.modinfo; do [ -f "$K/$M/$f" ] && cp "$K/$M/$f" "$R/usr/$M/"; done
depmod -b "$R" "$KVER"
# Firmware: the GPU's GSP (75 MB, the GB10 boots it), and the Realtek NICs'.
mkdir -p "$R/usr/lib/firmware"
nvidia && mkdir -p "$R/usr/lib/firmware/nvidia/$NVVER" && cp "$K/lib/firmware/nvidia/$NVVER/gsp_ga10x.bin" "$R/usr/lib/firmware/nvidia/$NVVER/"
if [ -d /lib/firmware/rtl_nic ]; then mkdir -p "$R/usr/lib/firmware/rtl_nic" && cp /lib/firmware/rtl_nic/rtl8127* /lib/firmware/rtl_nic/rtl8125* "$R/usr/lib/firmware/rtl_nic/" 2>/dev/null || true; fi

# The kernel and the initramfs.
cp "$K/boot/vmlinuz-$KVER" "$W/vmlinuz"
chmod 755 "$R/etc/init.d/"* "$R/sbin/samaltak-run" "$R/sbin/samaltak-hotplug" "$R/usr/share/udhcpc/default.script"
(cd "$R" && find . | LC_ALL=C sort | cpio -o -H newc -R 0:0 --quiet) | zstd -q -T0 -"${LINUX_ZSTD_LEVEL:-12}" > "$W/initrd.zst"
[ -n "${LINUX_CONTROL_TOKEN_FILE:-}" ] && chmod 600 "$W/initrd.zst"
say "$W/vmlinuz $(($(wc -c < "$W/vmlinuz") / 1048576)) MB, $W/initrd.zst $(($(wc -c < "$W/initrd.zst") / 1048576)) MB ($(du -sm "$R" | cut -f1) MB unpacked; gpu $GPU)"
