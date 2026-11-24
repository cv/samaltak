# Samaltak as a minimal Linux appliance (the DGX Spark)

The hosted VM and image, unchanged, booted on Ubuntu's NVIDIA kernel (the Spark's own) with a small initramfs instead
of a desktop: no systemd, no X11, no Wayland. The World draws itself and shows on KMS/DRM through the image's own
KMS screen (`KmsDisplay`: a dumb buffer, damage-limited atomic commits), input comes from evdev read by the image
(`EvdevInput`), the network from Linux (DHCP by busybox), TLS from OpenSSL, the GPU from NVIDIA's open kernel
module; SDL3's kmsdrm backend remains as a variant (section 2). The question behind it is cv/samaltak#20: the bare-metal UEFI app needs its own GB10 driver (GSP boot, RPC
transport, kernel-RM side); an appliance gets all of that from `nvidia.ko` and runs today's System-NV (Phase A, RM
ioctls) and NvComputeGPU as they are.

    make linux-appliance               # OUT/linux-appliance/{vmlinuz,initrd.zst}; LINUX_GPU=virtio (QEMU), nvidia (the Spark)
    make linux-appliance-run           # boot it in QEMU (arm64, KVM), serial console on stdio
    make linux-appliance-test          # end to end in QEMU: World on KMS, control, HTTPS, RFB, input, power off

`tools/linux-appliance/` holds the build (`build.sh`), the QEMU runner (`run.sh`), the end-to-end test (`test.sh`),
a QMP helper for screendumps and input (`qmp.py`) and the root's own files (`root/`: inittab, rcS, rcK,
`samaltak-run`, the DHCP hook). The variables are in each script's header.

## In short

| | Linux appliance (QEMU, measured) | UEFI app (today) |
| --- | --- | --- |
| QEMU start to the World on the screen | **1.5-2.2 s** on the image's KMS screen, under a load of 23-27 (SDL's kmsdrm: 1.85-2.05 s, unloaded) (KVM, AAVMF, 1920x1080 virtio-gpu) | QEMU start to `3 + 4` headless: 5.4 s (vvfat ESP, 512 MB image disk, boot manager scan) |
| kernel start to the VM's start (uptime) | 0.42-0.51 s; DHCP lease at 0.44 s, in the background | - |
| artifacts | kernel 20 MB + initramfs 30 MB (QEMU, the image's KMS screen; 89 MB with Mesa for SDL's) or 136 MB (Spark: GSP firmware 60 MB, NVIDIA userspace 39 MB) | 1.06 MB EFI application + the image on a disk |
| GPU on the Spark | `nvidia.ko` boots GSP; System-NV, NvComputeGPU, CUDA, Vulkan as hosted | #20: our own GSP boot and RM transport, not done |
| NICs, Wi-Fi, NVMe, USB | Linux's (r8127 for the Spark's 10 GbE, mt7925e, nvme, xhci) | virtio, e1000e, the firmware's SNP and Block I/O |
| TCP/TLS | Linux, OpenSSL: an HTTPS GET of example.com from the guest in 68-284 ms | our NetworkStack, mbedTLS (the VM's TLS engine) |
| control, RFB, agent | as hosted, on every address (token, VNC password on the data volume) | as on UEFI |
| what you give up | owning the machine, self-containedness, a small TCB of our own | the Spark's GPU, its 10 GbE, Wi-Fi, and Linux's drivers generally |

**Recommendation.** Make the appliance the way the Spark runs Samaltak on bare metal, and pause #20's Phase B
(the GSP boot from UEFI): almost everything it builds is what `nvidia.ko` already does in the appliance. Keep the
UEFI app for what only it does (QEMU and other machines, firmware exploration, a system that is Smalltalk to the
metal) and stop adding hardware drivers to it. First boot on the Spark: below, The Spark plan.

## 1. Design

### Kernel

Ubuntu's `linux-image-7.0.0-1024-nvidia` (DGX OS's kernel on this Spark), unmodified, from the archive (`apt-get
download`, no root): its EFI stub boots it from the firmware, its config has what the appliance needs, and its
security updates come with Ubuntu's. Checked in `/boot/config-7.0.0-1024-nvidia`:

| need | config |
| --- | --- |
| EFI stub, initramfs (zstd), devtmpfs | `EFI_STUB`, `BLK_DEV_INITRD`, `RD_ZSTD`, `DEVTMPFS` built in |
| DRM/KMS | `DRM`, `DRM_KMS_HELPER`, `DRM_SIMPLEDRM` (the firmware's framebuffer until a driver takes over) built in; `DRM_VIRTIO_GPU` module |
| NVIDIA open modules + GSP firmware | `linux-modules-nvidia-580-open-7.0.0-1024-nvidia` (prebuilt, signed: nvidia, nvidia-modeset, nvidia-drm, nvidia-uvm) and `nvidia-firmware-580-580.178.04` (`gsp_ga10x.bin`, 75 MB) |
| Realtek 10 GbE (the Spark's `10ec:8127`) | `R8127` (and `R8169`) modules; `rtl_nic/rtl8127a-1.fw` |
| NVMe, USB, HID, evdev | `BLK_DEV_NVME`, `USB_HID`, `HID_GENERIC` modules; `USB_XHCI_PCI`, `INPUT_EVDEV` built in |
| ext4, vfat, efivarfs, squashfs | built in |
| Wi-Fi (optional) | `MT7925E` (the Spark's `14c3:7925`), `CFG80211`, `IWLWIFI` modules: not in the spike |
| ConnectX-7 (optional) | `MLX5_CORE` module: `LINUX_MODULES=mlx5_core` |

The build takes the modules the devices need (the list in `build.sh`, plus `LINUX_MODULES`) with what they depend
on (`modules.dep`), uncompressed (busybox's modprobe reads no zstd), and runs depmod for them: 1 MB for QEMU's, 28 MB
with NVIDIA's.

### Root: an initramfs

Everything is in the initramfs (cpio, zstd -12), unpacked into RAM by the kernel; nothing is mounted from a disk
before the VM starts except the data volume.

| part | size, unpacked / compressed | what |
| --- | --- | --- |
| busybox (static) | 2 MB | PID 1 (init), sh, mount, modprobe, udhcpc, ip, findfs, poweroff |
| the VM and image | 70 / 20 MB | `/samaltak/samaltak`, `/samaltak/samaltak.image` |
| the VM's libraries | ~45 MB | glibc, libssl/libcrypto, libffi, shaderc, libstdc++: the host's, by ldd closure |
| SDL3 | 3 MB | built by `build.sh` from SDL's source at the VM's version (3.2.24) with kmsdrm and udev, without X11, Wayland, audio |
| Mesa (QEMU only) | ~250 / 59 MB | EGL/GBM and llvmpipe for SDL's KMS windows, lavapipe; most of it LLVM (133 MB) and ICU (30 MB) |
| NVIDIA userspace (Spark) | 116 / 39 MB | Vulkan ICD (`libGLX_nvidia`, glcore, gpucomp, glvkspirv), EGL and GBM (`nvidia-drm_gbm.so`) |
| GSP firmware (Spark) | 72 / 60 MB | `gsp_ga10x.bin`: GB10's GSP-RM |
| modules, certificates | 1-28 MB, 0.2 MB | the above; `/etc/ssl/certs/ca-certificates.crt` (OpenSSL's default paths point there) |

The userspace is copied from the build host (Ubuntu 24.04 arm64 with the VM's build dependencies, the Spark itself),
so the appliance's libraries are exactly the ones the VM was built and tested against. An initramfs keeps the boot
simple and stateless; a squashfs root on the ESP or a partition would make the kernel's unpacking lazy (the 136 MB
Spark variant unpacks in a few hundred milliseconds) and is the obvious next step if the root grows.

### Init

PID 1 is busybox `init` (`/init` is busybox) with `/etc/inittab`:

- `rcS` (sysinit): proc, sys, devtmpfs, devpts, tmpfs for /run, /tmp, /dev/shm, efivarfs; a module for each
  device's modalias (coldplug, no udevd); on an NVIDIA GPU (vendor `10de`) `nvidia`, `nvidia-uvm` and `nvidia-drm
  modeset=1 fbdev=1`, then the device nodes udev and nvidia-modprobe would make on a desktop (`/dev/nvidiactl`,
  `/dev/nvidia0`, `-modeset`, `-uvm` from `/proc/devices`); the data volume; DHCP on every wired interface in the
  background (`udhcpc -b`: it renews the lease; the hook sets the address, route and `/etc/resolv.conf`).
- `samaltak-run` (respawn): the VM with `/data/samaltak.image` if the data volume holds one (a snapshot the World
  saved), else the shipped image; its arguments from `/data/samaltak.args`, else `/etc/samaltak.args`, one per line
  (as the UEFI app's `samaltak.args`); `/etc/samaltak.env` for the environment; its output to the console and
  `/data/log/samaltak.log`. Exit status 0 (the World's Quit) powers off, 3 reboots, anything else (a crash, a
  signal) respawns it, after 30 s once it died three times in a row.
- `tty2::askfirst:-/bin/sh`: a rescue shell on the second VT (Ctrl-Alt-F2), `rcK` (shutdown): sync and unmount.

busybox init reaps orphans, handles SIGTERM/SIGUSR2 (reboot, poweroff) and Ctrl-Alt-Del, and is already in the
root. A PID 1 of our own (a 200-line C program, or the VM itself) would only pay off if we wanted the VM to be PID 1;
it should not be (a VM crash would panic the kernel).

### Boot

The kernel is an EFI application (an arm64 EFI zboot image), so the Spark's firmware can start it directly; the
stub loads the initramfs named on its command line (`initrd=\EFI\samaltak\initrd.zst`). Secure Boot is off on this
Spark (`mokutil --sb-state`), and its boot options are `Boot0000` Ubuntu (`shimaa64.efi`) and `Boot0003` PXE on the
Realtek NIC.

- **Installed on the NVMe** (like `SamaltakInstaller` and `tools/reboot-into-samaltak` today): copy the kernel
  and initramfs to the ESP's `\EFI\samaltak-linux\`, add a `Boot####` "Samaltak" whose load options are the
  command line (`efibootmgr --create --loader '\EFI\samaltak-linux\vmlinuz.efi' --unicode 'initrd=... quiet'`),
  and use `BootNext` to try it once, as `reboot-into-samaltak` does. The data volume is a partition (or a file
  on Ubuntu's ext4 root: loop-mounting needs nothing more).
- **USB stick** (like `make usb-image`): removable media boot `\EFI\BOOT\BOOTAA64.EFI` without load options, so
  the kernel, initramfs and command line go into one **unified kernel image** (UKI: `ukify` or `objcopy` of
  systemd's stub, or systemd-boot with an entry). One file to sign, copy and roll back.
- **Secure Boot**, where on: the UKI signed by our key enrolled as a MOK and started through Ubuntu's shim, or our
  key in db. A bare kernel plus a separate initramfs is not verified as a whole; the UKI is.

### Updates

A/B with two UKIs on the ESP (`samaltak-a.efi`, `samaltak-b.efi`) and two boot options: install the new one in the
other slot, `BootNext` to it, and make it the default (BootOrder) only after `samaltak-run` saw the World start
(a flag on the data volume); a boot that never gets there falls back to the old slot at the next power cycle. The
image is not part of the UKI's update when it lives on the data volume: snapshots stay as they are today, and a new
shipped image is only a fallback. Kernel and NVIDIA module updates are Ubuntu's packages, rebuilt into a UKI by
`make linux-appliance` (the modules must match the kernel exactly; the build takes both from the same version).

### What maps onto what

| | UEFI app | appliance |
| --- | --- | --- |
| image store | raw store partition with slots (System-Storage) | `/data/samaltak.image`: a file on the ext4 data volume (label `SAMALTAK-DATA`), snapshots as hosted |
| arguments | `samaltak.args` on the ESP | `/data/samaltak.args` (or `/etc/samaltak.args` in the root) |
| remote control | `--control --control-host 0.0.0.0`, token in `samaltak.args` or shown at boot | the same flags; `--control-token-file /data/control-token` (0600 on the data volume), or `LINUX_CONTROL_TOKEN_FILE` into the root (readable to anyone who can read the initramfs) |
| RFB server | `--display --display-host 0.0.0.0 --display-vnc-auth` | the same, `--display-password-file /data/vnc-password` |
| agent, GitHub | as on UEFI (`samaltak-ctl agent-config`, `github-config`) | as hosted: HTTPS through OpenSSL |
| TLS | mbedTLS (the VM's TLS engine) | OpenSSL (`platform_tls_*`), CA bundle in `/etc/ssl` |
| files, volumes | the image's FAT and ext4 readers | Linux's file systems, mounted by `rcS`; System-Files' POSIX side |
| time | RTC (UEFI GetTime) | the RTC through Linux; no NTP in Ubuntu's busybox-static: SNTP in the image (planned for UEFI anyway) or a static `ntpd` |
| randomness | EFI_RNG, RNDR | `getrandom` |
| network | NetworkStack on our drivers | Linux; DHCP by udhcpc; Wi-Fi would add wpa_supplicant and `mt7925e`'s firmware |
| display, input | FirmwareDisplay (GOP: FirmwareScreen), HID | KmsDisplay (KMS: KmsScreen), evdev (EvdevInput): section 2 |

## 2. Display and input without X or Wayland

Under QEMU the display is virtio-gpu (KMS through `virtio_gpu`), the input virtio-keyboard and virtio-tablet; on
the Spark `nvidia-drm` with `modeset=1` drives the GB10's display engine, and USB HID devices are evdev devices.

### The image's KMS screen and evdev input (the default)

`SAMALTAK_SCREEN=kms` (`/etc/samaltak.env` of `LINUX_GPU=virtio` and `nvidia`) makes `FirmwareDisplay current`
a **`KmsDisplay`** (System-Devices), the UEFI World's structure with Linux below it: one window, the screen, a
`SoftwareGPU` (or `--gpu nv`, an `NvComputeGPU`) drawing into memory and presenting through it, the frame tap,
RFB input and clipboard as on UEFI. No SDL window, no SDL_GPU, no Mesa, no NVIDIA userspace; SDL's video is never
started. `kms:/dev/dri/card1` names a device; without one, the first card with a connected output, a real driver
before `simpledrm`. A screen that cannot be opened leaves the VM's (SDL) windows to it, with a line on stderr.

- **`KmsScreen`** (a `FirmwareScreen` on a mapped buffer, through `PosixDevice` ioctl and mmap, linux/drm_mode.h):
  GETRESOURCES, GETCONNECTOR (the first connected one with modes), GETENCODER (its CRTC), CREATE_DUMB, ADDFB2
  (XRGB8888: the bytes the World draws), MAP_DUMB and mmap, SETCRTC. **The display's mode is the World's size**: the
  connector's preferred mode (virtio-gpu's 1920x1080 at 75 Hz in the test, without `--window-size`), or the
  `--window-size` mode if the connector has it. The damaged rectangles (and the pointer's) go from the shadow copy
  into the buffer and are then flushed as a **non-blocking atomic commit** of the same framebuffer with them as
  `FB_DAMAGE_CLIPS` (universal planes and atomic client caps, the plane that shows the framebuffer, its `FB_ID` and
  `FB_DAMAGE_CLIPS` properties, a blob of `drm_mode_rect`s); while the last commit is still being done (`EBUSY`)
  the rectangles wait for the next one, 4 ms later at the latest. A driver without damage clips gets `DIRTYFB`, and
  one without that (it scans out the buffer as it is) nothing. The first version used `DIRTYFB` throughout: on
  virtio-gpu it blocks for the host's flush, **7.7 ms a frame** (the VM's one thread waits); the commit takes
  **0.1-0.3 ms**, a damaged present 0.3-0.75 ms in all. `KmsScreen>>counts` keeps the numbers; the RefreshClock runs
  at the mode's rate. The buffer is the one being scanned out (no page flips), so a frame can tear.
- **`EvdevInput`** reads every `/dev/input/event*` that is a keyboard or pointer (`EvdevDevice`: EVIOCGBIT,
  EVIOCGPROP, EVIOCGABS) with non-blocking `read(2)`s every 8 ms (the one VM change: `deviceRead` and
  `deviceWrite` use `read(2)` and `write(2)` for a negative offset, as evdev refuses `pread`; `PosixDevice
  read:into:count:` answers nil for EAGAIN), and looks for new nodes every 2 s: devtmpfs makes them, so **hotplug
  works without udev**. Keys become the image's events with SDL's keycodes and Linux's modifiers (Alt is cmd, the logo
  key alt); text by **the kernel's keymap** (its plain, shift and AltGr tables through KDGKBENT on `/dev/tty0`, so
  busybox `loadkmap` sets the layout), the US one where it has none (the keypad); Caps Lock; Right Alt types as AltGr
  where the keymap's AltGr table has a character. Mice move the pointer by their motion, tablets and touch screens by
  their point, touchpads by the finger's motion (no tap-to-click: their buttons click); wheels scroll. 1.3% of a
  core while idle under QEMU.

`make linux-appliance-test` checks it on the default (`virtio`) variant: `KmsDisplay SoftwareGPU /dev/dri/card0
(virtio_gpu) 1920x1080@75`, the World 1920@1080, evdev's `QEMU Virtio Keyboard` and `QEMU Virtio Tablet`, a click
and typed text in the Workspace, and the presents' counts (e.g. 35 damaged presents of 128,000 pixels on average
and 7 whole frames, 42 commits, 9 of them retried after EBUSY, 0.2 ms a flush).

### SDL's kmsdrm (`LINUX_GPU=mesa`; NVIDIA's Vulkan)

SDL3's kmsdrm backend opens `/dev/dri/card0`, sets the mode and pages through GBM; SDL's evdev code reads
`/dev/input/event*`. What the spike found:

- **SDL_GPU cannot present on KMS with Ubuntu's lavapipe**: SDL's kmsdrm Vulkan surface needs `VK_KHR_display`,
  and lavapipe offers only headless, xcb, xlib and wayland surfaces (QEMU 8.2 has no Venus either, so there is no
  Vulkan driver for virtio-gpu). **NVIDIA's Vulkan has it** (`VK_KHR_display`, `VK_EXT_acquire_drm_display`,
  `VK_EXT_direct_mode_display`, checked on this Spark), so on the Spark the default World (SDL_GPU) presents on KMS
  as it presents in a window.
- So the image got a second way to present the frames it draws itself: **`HostFramePresenter` copies the
  damaged rectangles of a SoftwareGPU's or NvComputeGPU's back buffer into the window's SDL surface**
  (`windowPresentAddress`, primitive 463, a sibling of `gpuUploadTextureAddress`: docs/ffi-fork.md, platform.md)
  where no SDL_GPU device can be made, or with `SAMALTAK_PRESENT=surface`. On kmsdrm SDL draws that surface with
  its GLES renderer over EGL/GBM (Mesa's llvmpipe under QEMU). The QEMU appliance runs `SAMALTAK_GPU=software`.
  Under QEMU a full 1920x1080 copy into the surface takes 0.5 ms; showing it 14.5-15 ms whatever the rectangle's
  size (SDL's emulation draws the whole frame; llvmpipe on 4 vCPUs). Hosted under Xvfb the surface path also beat
  SDL_GPU on lavapipe for a SoftwareGPU World's first frames (181 vs 438 ms average).
- **Input works without udevd**: SDL's udev code enumerates through libudev (sysfs) and, with no udev database,
  guesses each device's class from its capabilities: "QEMU Virtio Keyboard" and "QEMU Virtio Tablet" were found,
  and keys and clicks sent by QMP reached the Workspace (`typed.png` in the test). Hotplug needs udev's netlink
  events, which only udevd sends: a USB keyboard plugged in after boot is not seen. Running systemd's `udevd` from
  the root (2 MB with its rules) or teaching SDL's hint `SDL_EVDEV_DEVICES` from an mdev hook are the options.
- The World's window on kmsdrm is the screen: `--window-size` should be the display's mode (the test passes
  `1920x1080` on this variant; without it SDL set the 1440x900 mode the World asked for).

Boot to the World, measured by `make linux-appliance-test` (QMP screendumps every 0.1 s until the World is on the
screen): on the image's KMS screen **1.5-2.2 s** from QEMU's start under a load of 23-27 (an initramfs of 30 MB
instead of 89 MB to load and unpack; the kernel's uptime at the VM's start 0.28-0.49 s); with SDL's kmsdrm
**1.85-2.05 s** unloaded, of which about 0.7 s is AAVMF and loading the kernel and initramfs,
0.45 s the kernel and `rcS`, and 0.7-0.9 s the VM from its start to the World's first frame. From the VM's
exit to the power down 0.2 s (`samaltak-run` runs `rcK` and `poweroff -f` itself); the control request `Smalltalk
quit: 0` to QEMU's end about 3 s, most of it the VM's own quit.

## 3. The GPU on the Spark

System-NV (Phase A) needs only the RM: `nvidia.ko` with its GSP firmware, `/dev/nvidiactl` and `/dev/nvidia0`
(`rcS` makes them; nvidia.ko makes no devtmpfs nodes). `nvidia-modeset` and `nvidia-drm` (modeset=1) are for the
display; `nvidia-uvm` is CUDA's, not System-NV's (loaded anyway: cheap, and CUDA programs would need it). No NVIDIA
userspace library is involved: NvComputeGPU renders the World with the raster kernels through RM ioctls (docs/nv-gpu.md).

Two ways to get the World onto the Spark's screen:

| | SDL_GPU on NVIDIA's Vulkan (the default World, or `--gpu nv` presenting through it) | NvComputeGPU, presenting without NVIDIA userspace |
| --- | --- | --- |
| userspace | NVIDIA's Vulkan ICD, EGL and GBM: 116 MB, 39 MB compressed, proprietary (redistributable), version-locked to nvidia.ko | none beyond our VM and SDL |
| present | VK_KHR_display through SDL's kmsdrm: as in a window | the window surface (this change) needs a GLES driver on KMS (NVIDIA's EGL+GBM again); a KMS dumb-buffer presenter does not |
| shaders | the Renderer's GLSL via shaderc, as on any Linux | the raster kernels (cubins in the image) |
| works today | yes, on this Spark's userspace (untested on bare KMS: the Spark's display is the desktop's now) | rendering yes; presenting through `KmsDisplay` (section 2), proven on virtio-gpu, untested on nvidia-drm |

The KMS screen and evdev input in the image (section 2) are done: the appliance's World can be NvComputeGPU on the
GB10 with no NVIDIA userspace and no SDL, the same structure as the UEFI World (FirmwareDisplay + SoftwareGPU) with
Linux below it.

## 4. The spike

`make linux-appliance` builds the variants on this Spark (`LINUX_GPU=virtio`, the default, for QEMU with the image's
KMS screen; `mesa`, QEMU with SDL's kmsdrm; `nvidia`; `both`: mesa and nvidia)
in about 20 s once the packages are cached (the first build downloads 391 MB of .debs, most of it the kernel's
modules package, and builds SDL in 30 s). `make linux-appliance-test` (15 s) boots the QEMU variant with a data
volume made for it (ext4 with `samaltak.args`, a random control token and VNC password, 0600) and checks:

| check | result |
| --- | --- |
| the World on KMS (virtio-gpu, 1920x1080) | the image's KMS screen: 1.5-2.2 s after QEMU's start (load 23-27); SDL's kmsdrm (`mesa`): 1.85-2.1 s (4.8-5.5 s while other agents' gates loaded the machine) |
| the control service (`samaltak-ctl connect`, the token from the data volume) | `3 + 4` = 7; a screenshot |
| HTTPS from the guest (`HTTPClient get: 'https://example.com/'`, OpenSSL, DNS from DHCP) | 200 in 68-284 ms |
| the RFB server on 0.0.0.0:5900 (VNC authentication) | `RFB 003.008` |
| keyboard and tablet (QMP → virtio input → evdev → SDL → the World) | a click into the Workspace and `3 + 4` typed there |
| the World's Quit | VM exit 0, power off, QEMU ends |

x86-64 was not attempted: this build host has no x86-64 userspace to copy, and the VM would need a cross build;
nothing in the design is arm64-specific (Ubuntu's generic or nvidia kernel for amd64, OVMF).

## 5. Compared with the UEFI app

| | appliance | UEFI app |
| --- | --- | --- |
| boot | 1.9 s in QEMU to the World; on the Spark firmware POST dominates either way | 5.4 s in QEMU to `3 + 4` headless |
| size | ~110-160 MB (kernel + initramfs) | ~1 MB + the image |
| self-contained | no: Ubuntu's kernel, glibc, OpenSSL, SDL, Mesa or NVIDIA userspace | yes: one EFI binary, the image drives everything |
| drivers | all of Linux's: GB10 (with GSP), 10 GbE, Wi-Fi, ConnectX-7, NVMe, USB | ours (virtio, e1000e) and the firmware's (SNP, Block I/O, GOP, HID) |
| GPU | System-NV, NvComputeGPU, CUDA, Vulkan as hosted | #20, months of driver work |
| explorable to the metal | no: below the syscall line is Linux | yes: PCI, firmware tables, MMIO from the Debugger |
| licensing | the kernel is GPLv2, the VM a separate program over syscalls (fine); shipping the kernel means pointing at Ubuntu's source; NVIDIA's userspace is proprietary but redistributable, the open modules MIT/GPL | our code plus the firmware's |
| attack surface | Linux's (well patched, large), OpenSSL; only what we run listens: control (token), RFB (VNC auth) | our NetworkStack and TLS, young and small |
| updates | Ubuntu's kernel and modules rebuilt into a UKI, A/B slots | one EFI binary plus the image |
| debugging | a shell on tty2, dmesg, the VM's log, gdb | the console log, QEMU |

## 6. What changes for #20

Unnecessary on the appliance (nvidia.ko does them): step 3, booting GSP (WPR, FRTS, SEC2, the booter, the RISC-V
start); step 4, the RPC transport over the message queues and GSP's init RPCs; step 5's kernel-RM side (system memory
described to GSP, GMMU page tables for client VA spaces, BAR mappings); the fake GSP and the VFIO development loop
(docs/nv-gsp.md 10-14) as means to those ends; and the open questions about the firmware's handling of the GPU, SMMU
and ATS. Step 6's exit (Tests-NV pass, `fill` gives 7) holds on the appliance on its first boot, because Phase A is
what runs there.

Still useful: the transport seam (`NvTransport`, `NvIoctlTransport`) and the fakes, as tests of System-NV without a
GPU; the probe (step 1) as a UEFI diagnostic; docs/nv-gsp.md as the record of how GB10 boots, should Phase B come
back. Phase B only makes sense if the product is the UEFI app owning the GPU; it is a driver's worth of work with
nvidia.ko and nova-core as references and GB10 support in neither fully public.

## 7. The Spark plan (first boot)

1. `make linux-appliance LINUX_GPU=nvidia` (and a UKI of it for the stick); a data volume with `samaltak.args`
   (control and RFB on every address, a token and VNC password of our own).
2. Boot it once without touching Ubuntu: copy to the ESP's `\EFI\samaltak-linux\`, a `Boot####` entry with
   the command line, `BootNext` (as `tools/reboot-into-samaltak`); the way back is a power cycle (BootOrder still
   Ubuntu) or the World's reboot (exit 3 with BootNext cleared).
3. Check, on the console and over the control service: `nvidia.ko` loads and GSP boots (`dmesg`), `/dev/nvidia0`
   exists, r8127 gets a lease, the World on the screen through NVIDIA's Vulkan, keyboard and mouse (USB HID), then
   `--gpu nv`, and Tests-NV and NvComputeGPUTest over the control service.
4. Then without NVIDIA's userspace: the image's KMS screen on nvidia-drm and evdev (section 2), `--gpu nv`; a squashfs
   or UKI layout, A/B slots, SNTP.

## 8. The UEFI work: keep it for

QEMU and machines without a usable Linux, the firmware World (PCI, ACPI, the memory map, live), a system whose every
layer is Smalltalk, and the tests that run the image without an operating system. mbedTLS (tls-mbedtls) and the
other library work there still pay off. What stops is adding hardware drivers to it: the Spark's GPU, its 10 GbE
and Wi-Fi are the appliance's.
