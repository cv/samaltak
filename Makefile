# Samaltak: VM, seed image (the Smalltalk ImageBuilder, run in boot/seed.image), full image (stage 2), tests.
# OUT selects the build directory, so concurrent builds do not collide: make image OUT=build/me
OUT ?= build

VM := vm/build/samaltak
# What the test targets build first: image (always rebuilt), or fresh-image (only when src/, boot/ or the VM are newer:
# tests/stages.sh builds once, then runs stages at once).
TEST_IMAGE ?= image

all: vm seed image runtime

vm:
	$(MAKE) -C vm

seed: vm
	boot/build-image.sh src $(OUT)/seed.image

# The commit the image's sources are at (SourceFiler baseCommit, for updates from GitHub: docs/github.md), and whether
# src/ had uncommitted changes.
BASE_COMMIT = $(shell git rev-parse HEAD 2>/dev/null)
BASE_DIRTY = $(shell git status --porcelain -- src 2>/dev/null | head -1)
BASE_ARGS = $(if $(BASE_COMMIT),--base-commit $(BASE_COMMIT)) $(if $(BASE_DIRTY),--base-dirty)

image: vm seed
	$(VM) $(OUT)/seed.image --headless --stage2 $(OUT)/samaltak.image $(BASE_ARGS)

# The runtime image applications run on (bin/samaltak run, docs/apps.md): the packages of src/runtime.txt, lean on fonts.
runtime: vm
	PACKAGES=src/runtime.txt boot/build-image.sh src $(OUT)/runtime-seed.image
	$(VM) $(OUT)/runtime-seed.image --headless --stage2 $(OUT)/runtime.image --runtime

fresh-runtime: vm
	@[ -f $(OUT)/runtime.image ] && [ -z "$$(find src boot $(VM) -newer $(OUT)/runtime.image | head -1)" ] || $(MAKE) runtime

# The image, rebuilt only if src/, boot/ or the VM are newer, so an image saved from the World menu stays.
fresh-image: vm
	@[ -f $(OUT)/samaltak.image ] && [ -z "$$(find src boot $(VM) -newer $(OUT)/samaltak.image | head -1)" ] || $(MAKE) image

# Start the system.
run: fresh-image
	$(VM) $(OUT)/samaltak.image

test-vm: vm
	vm/tests/run.sh

# After changing the VM's Lowtalk sources (src/VM-Core, src/VM-Platform): translate them into vm/gen (checked in).
translate: image
	$(VM) $(OUT)/samaltak.image --headless --eval "[VMTranslator generateVM. 'ok'] on: Error do: [:e | e messageText]"
	$(MAKE) -C vm

# The image's tests under each JIT, every method compiled on its first activation (under opt also optimized after
# one more, and again with deoptimization stress); Tests-Kernel also with a code cache small enough to be flushed
# again and again (x86-64's code is a third bigger than arm64's: in 1 MB it thrashes so hard that the slowest tests
# time out, 2 MB still flushes hundreds of times).
STRESS_CACHE_MB := $(if $(filter x86_64 amd64,$(shell uname -m)),2,1)
test-jit: $(TEST_IMAGE)
	$(MAKE) test-jit-none
	$(MAKE) test-jit-baseline
	$(MAKE) test-jit-opt
	$(MAKE) test-jit-deopt
	$(MAKE) test-jit-cache
test-jit-none: $(TEST_IMAGE)
	tests/st_suite.sh $(OUT)/samaltak.image --jit none
test-jit-baseline: $(TEST_IMAGE)
	tests/st_suite.sh $(OUT)/samaltak.image --jit baseline --jit-threshold 0
test-jit-opt: $(TEST_IMAGE)
	tests/st_suite.sh $(OUT)/samaltak.image --jit opt --jit-threshold 0 --jit-flags eager
test-jit-deopt: $(TEST_IMAGE)
	tests/st_suite.sh $(OUT)/samaltak.image --jit opt --jit-threshold 0 --jit-flags eager,deopt
test-jit-cache: $(TEST_IMAGE)
	tests/st_suite.sh $(OUT)/samaltak.image --jit opt --jit-threshold 0 --jit-cache $(STRESS_CACHE_MB) --jit-flags eager,notes -- Tests-Kernel

# Everything, in stages (CI runs them as separate jobs); any failure, skipped test or headless-only VM fails it. The UI
# scripts use a hidden window. tests/stages.sh builds once and runs stages at once (the gate); tests/st_suite.sh shards
# each Smalltalk suite over SAMALTAK_TEST_JOBS VMs (default min(nproc / 2, 8); 1: one VM). TEST_IMAGE: what the test
# targets build first (TEST_IMAGE, at the top).
test: test-core
	$(MAKE) test-jit
	$(MAKE) test-tools
	$(MAKE) test-uefi
	@echo "make test: all passed"
PLATFORM_CHECK = @[ -f vm/build/.variant-platform ] || { echo "make test: FAILED: the VM was built without the platform layer (SDL3), UI tests would not run"; exit 1; }
test-core: $(TEST_IMAGE) test-vm
	$(PLATFORM_CHECK)
	tests/vm/gen_test.sh $(OUT)/samaltak.image
	tests/boot/layering_test.sh
	tests/boot/cli_quit_test.sh $(OUT)/samaltak.image
	tests/st_suite.sh $(OUT)/samaltak.image
	SAMALTAK_VERIFY_GC=1 tests/st_suite.sh $(OUT)/samaltak.image --eden 1 -- Tests-Kernel Tests-Compiler
	tests/st_suite.sh $(OUT)/samaltak.image --max-heap 128 -- LowSpaceTest StackOverflowTest
	$(MAKE) fresh-runtime
	tests/st_suite.sh $(OUT)/runtime.image -- Weather --load apps/Weather
# System-NV on a real NVIDIA GPU (hosted Linux, /dev/nvidiactl; the GB10): not part of make test, which runs where
# there is none. Fails, saying so, without a GPU. NvGpuMeasure reports launch latency and copy bandwidth. Then the
# raster kernels (gpu/nv, docs/nv-kernels.md) on the GPU against PlatformRaster (tests/nv/run.sh: needs the driver,
# not nvcc).
test-nv: $(TEST_IMAGE)
	tests/st_suite.sh $(OUT)/samaltak.image -- NvGpuTest NvComputeGPUTest
	tests/nv/run.sh $(OUT)
test-tools: $(TEST_IMAGE)
	$(PLATFORM_CHECK)
	$(MAKE) -C vm/platform test st-test
	tests/remote/cli_test.sh $(OUT)/samaltak.image
	tests/remote/auth_test.sh $(OUT)/samaltak.image
	tests/remote/recording_test.sh $(OUT)/samaltak.image
	tests/tools/desktop_test.sh $(OUT)/samaltak.image
	tests/tools/snapshot_test.sh $(OUT)/samaltak.image
	tests/tools/reboot_test.sh $(OUT)/samaltak.image
	tests/tools/quit_signal_test.sh $(OUT)/samaltak.image

# The Renderer's raster work as CUDA kernels for the NVIDIA GB10 (gpu/nv, docs/nv-kernels.md): rebuild the cubin with
# nvcc and regenerate src/System-Devices/NvRasterKernels.st. Not part of test or CI.
nv-kernels:
	tools/nv-kernels.py build

# The VM as a UEFI application for x86-64 or arm64 (UEFI_ARCH, this machine's by default), translated from the
# same Lowtalk with VM-UEFI in place of the C library (docs/uefi.md): $(UEFI)/esp is a boot volume with it
# (EFI/BOOT/BOOTX64.EFI or BOOTAA64.EFI) and samaltak.args (the command line, an argument a line), $(UEFI)/image.disk a
# disk with the image (UefiImageStore: two slots, snapshots go to the other), each rebuilt only if the image is newer,
# so a snapshot stays. uefi-run boots them in QEMU with its UEFI
# firmware, on this machine's CPU if it is UEFI_ARCH (KVM, or Hypervisor.framework on macOS), and fails unless the VM
# exits 0; UEFI_ARGS are its arguments after the image (disk:). uefi-ui boots the World in a QEMU window (USB keyboard,
# virtio tablet; the console on stdio). uefi-control boots it without a window, its control service (--control on
# 0.0.0.0 in the guest) forwarded from 127.0.0.1:UEFI_CONTROL_PORT, UEFI_CONTROL_ARGS after it (samaltak-ctl open --uefi);
# its token from the environment's UEFI_CONTROL_TOKEN, written into samaltak.args (mode 0600) and never on a command
# line, else one the image makes and shows on the console (docs/remote.md).
# The guest's network is QEMU's user network (NAT, DHCP, DNS) on a UEFI_NIC without its option ROM, which the image
# drives: e1000e on x86-64 (q35's default), virtio-net-pci on arm64 (virt's); a virtio-rng, so that the firmware offers EFI_RNG_PROTOCOL (SecureRandom's entropy). test-uefi runs the tests there that need no platform layer (no files, processes
# or ptys from Smalltalk), LowSpaceTest and StackOverflowTest in a 128 MB heap, opens the World on the firmware's screen and moves its pointer by remote input, drives the VM with
# samaltak-ctl and has it connect to itself through the host (10.0.2.2: QEMU's host), once to ping, once to move a megabyte
# each way, gets https://10.0.2.2 from tools/tls-test-server.sh with its test CA (docs/tls.md) (test-uefi-nic: on a virtio-net-pci too
# if UEFI_NIC is another, once to ping), snapshots and resumes, and restarts by the firmware's ResetSystem (Firmware restart, the World menu's Restart).
comma := ,
UEFI_HOST_ARCH := $(if $(filter x86_64 amd64,$(shell uname -m)),x86_64,arm64)
UEFI_ARCH ?= $(UEFI_HOST_ARCH)
UEFI := $(OUT)/uefi-$(UEFI_ARCH)
UEFI_ARGS ?= --headless --eval 'Smalltalk vmBanner'
# The VM's --max-heap and QEMU's RAM, in MB: uefi-run, uefi-boot and test-uefi boot with 256 in 2048 (UEFI_HEAP_MB,
# UEFI_RAM_MB if set); the World (uefi-ui, uefi-control) with UEFI_WORLD_HEAP_MB in UEFI_WORLD_RAM_MB, a quarter of
# it: the heap takes twice its limit (docs/uefi.md, Memory), the rest is for the firmware, the VM and the memory the
# image keeps outside the heap (textures, the back buffer, drivers' buffers).
UEFI_HEAP_MB ?=
UEFI_RAM_MB ?=
UEFI_WORLD_RAM_MB ?= 4096
UEFI_WORLD_HEAP_MB ?= $(shell expr $(UEFI_WORLD_RAM_MB) / 4)
UEFI_HEAP = $(or $(UEFI_HEAP_MB),256)
UEFI_MEM = $(or $(UEFI_RAM_MB),2048)
uefi-ui uefi-control: UEFI_HEAP = $(or $(UEFI_HEAP_MB),$(UEFI_WORLD_HEAP_MB))
uefi-ui uefi-control: UEFI_MEM = $(or $(UEFI_RAM_MB),$(UEFI_WORLD_RAM_MB))
UEFI_SCREEN ?= 1024x768
# UEFI_VNC=N: uefi-ui and uefi-control show the screen on a VNC server on 127.0.0.1:590N instead of a window (from another
# machine: ssh -L 590N:127.0.0.1:590N, then vnc://localhost:590N), its password the file UEFI_VNC_PASSWORD (at most 8 characters).
UEFI_VNC ?=
UEFI_VNC_PASSWORD ?= $(HOME)/.samaltak-vnc
UEFI_VNC_DISPLAY = -object secret,id=vncpw,file=$(UEFI_VNC_PASSWORD) -display vnc=127.0.0.1:$(UEFI_VNC),password-secret=vncpw
# UEFI_DISPLAY=N: uefi-ui and uefi-control show the screen through the image's own remote display server (RFB, --display
# on port 5900 in the guest) forwarded from 127.0.0.1:5900+N, and QEMU has no display (-display none; UEFI_DISPLAY wins
# over UEFI_VNC). Its VNC password: the file UEFI_DISPLAY_PASSWORD_FILE (at most 8 characters; e.g. ~/.samaltak-vnc, so a
# viewer's saved password works with both servers), copied to the ESP (0600) for --display-password-file, never on a
# command line, else one the image makes and shows at start (display: password ...). docs/remote.md, Remote display.
UEFI_DISPLAY ?=
UEFI_DISPLAY_PASSWORD_FILE ?=
UEFI_DISPLAY_PORT = $(shell expr 5900 + $(UEFI_DISPLAY))
UEFI_DISPLAY_FWD = $(if $(UEFI_DISPLAY),$(comma)hostfwd=tcp:127.0.0.1:$(UEFI_DISPLAY_PORT)-:5900)
UEFI_DISPLAY_ARGS = $(if $(UEFI_DISPLAY),--display --display-host 0.0.0.0 --display-port 5900 --display-vnc-auth)
# The remote display's password file on an ESP: the directory $1 gets the password in the file $2 (blanks and newlines
# dropped; 1 to 8 characters), mode 0600, and the samaltak.args $3 the option naming it; without $2 the file is removed.
DISPLAY_PASSWORD = rm -f $(1)/samaltak-display-password$(if $(2), && p="$$(tr -d ' \n' < $(2))" && [ -n "$$p" ] && [ $$(printf %s "$$p" | wc -c) -le 8 ] || { echo "$(2): not a VNC password of 1 to 8 characters" >&2; exit 1; }; (umask 077 && printf '%s\n' "$$p" > $(1)/samaltak-display-password) && printf '%s\n' --display-password-file /esp/samaltak-display-password >> $(3))
ifeq ($(shell uname -s),Darwin)
UEFI_WINDOW_DISPLAY := -display cocoa,zoom-to-fit=on
UEFI_WINDOW := osascript tools/qemu-window.applescript $(subst x, ,$(UEFI_SCREEN)) &
endif
# QEMU's display: uefi-ui's window, or none with UEFI_DISPLAY, or its VNC server with UEFI_VNC.
UEFI_QEMU_DISPLAY = $(if $(UEFI_DISPLAY),-display none,$(if $(UEFI_VNC),$(UEFI_VNC_DISPLAY),$(UEFI_WINDOW_DISPLAY)))
UEFI_DISK_MB ?= 512
UEFI_ACCEL := $(if $(filter $(UEFI_HOST_ARCH),$(UEFI_ARCH)),$(if $(wildcard /dev/kvm),-accel kvm -cpu host,$(if $(filter Darwin,$(shell uname -s)),-accel hvf -cpu host)))
ifeq ($(UEFI_ARCH),arm64)
UEFI_TARGET := aarch64
UEFI_BOOT := BOOTAA64.EFI
OVMF_CODE ?= $(firstword $(wildcard /usr/share/AAVMF/AAVMF_CODE.fd /opt/homebrew/share/qemu/edk2-aarch64-code.fd /usr/share/qemu/edk2-aarch64-code.fd))
OVMF_VARS ?= $(firstword $(wildcard /usr/share/AAVMF/AAVMF_VARS.fd /opt/homebrew/share/qemu/edk2-arm-vars.fd /usr/share/qemu/edk2-arm-vars.fd))
# UEFI_GPU: the display device. ramfb's firmware modes stop at 1024x768; virtio-gpu-pci's (VirtioGpuDxe) go to 1920x1080 and
# beyond, without a framebuffer: FirmwareScreen draws with Blt.
UEFI_GPU ?= ramfb
QEMU_UEFI_MACHINE := qemu-system-aarch64 -machine virt $(or $(UEFI_ACCEL),-cpu max) -device $(UEFI_GPU)
UEFI_NIC ?= virtio-net-pci
else
UEFI_TARGET := x86_64
UEFI_BOOT := BOOTX64.EFI
OVMF_CODE ?= $(firstword $(wildcard /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd /opt/homebrew/share/qemu/edk2-x86_64-code.fd /usr/share/qemu/edk2-x86_64-code.fd))
OVMF_VARS ?= $(firstword $(wildcard /usr/share/OVMF/OVMF_VARS_4M.fd /usr/share/OVMF/OVMF_VARS.fd /opt/homebrew/share/qemu/edk2-i386-vars.fd /usr/share/qemu/edk2-i386-vars.fd))
# UEFI_GPU: empty for q35's standard VGA (its firmware has modes up to 1920x1080 and more), or a device such as virtio-gpu-pci.
UEFI_GPU ?=
QEMU_UEFI_MACHINE := qemu-system-x86_64 -machine q35 $(UEFI_ACCEL) $(if $(UEFI_GPU),-vga none -device $(UEFI_GPU))
UEFI_NIC ?= e1000e
endif
UEFI_VGA = $(if $(filter x86_64,$(UEFI_ARCH)),$(if $(UEFI_GPU),,-vga std))
# UEFI_CPUS: QEMU's CPUs; the VM runs on the first and starts the others for its raster's bands and background compilation
# (docs/uefi.md, More than one CPU). 1: one CPU, as on firmware without MP services or PSCI.
UEFI_CPUS ?= 4
# UEFI_AFFINITY: the host CPUs QEMU runs on (tools/qemu-pin.sh; docs/uefi.md, Pinning): big, the cores of the highest
# maximum frequency where there is more than one kind (Linux; the DGX Spark's X925s, where an A725 is half as fast),
# each vCPU on one of its own and no more vCPUs than cores; a taskset list (5-9,15-19); empty or none, anywhere. The
# World (uefi-ui, uefi-control, so samaltak-ctl open --uefi) runs on big unless it is set; uefi-run, uefi-boot and the
# tests anywhere, as gates run at once.
UEFI_PIN = $(UEFI_AFFINITY)
uefi-ui uefi-control: UEFI_PIN = $(if $(filter undefined,$(origin UEFI_AFFINITY)),big,$(UEFI_AFFINITY))
QEMU_UEFI = $(QEMU_UEFI_MACHINE) -smp $(UEFI_CPUS) -m $(UEFI_MEM) -no-reboot \
	-nic user,model=$(UEFI_NIC)$(if $(UEFI_CONTROL_PORT),$(comma)hostfwd=tcp:127.0.0.1:$(UEFI_CONTROL_PORT)-:7341)$(UEFI_DISPLAY_FWD) -global $(UEFI_NIC).romfile= \
	-device virtio-rng-pci -drive if=pflash,format=raw,readonly=on,file=$(OVMF_CODE) -drive if=pflash,format=raw,file=$(UEFI)/vars.fd \
	-drive format=raw,file=fat:rw:$(UEFI)/esp -drive format=raw,file=$(UEFI)/image.disk \
	$(if $(filter %@usb-storage,$(UEFI_DISKS)),-device qemu-xhci$(comma)id=disks) $(foreach disk,$(UEFI_DISKS),$(call UEFI_DISK,$(disk)))
# More disks for the image's files (docs/files.md): UEFI_DISKS, raw disk images FILE@DEVICE, DEVICE nvme, virtio-blk-pci
# or usb-storage, attached read-only. UEFI_EXT4_DISK is an ext4 file system of the fixture tests/uefi/ext4 (and a file
# numbers.txt of 50000 lines) labeled fixture on a whole disk, UEFI_EXT4_GPT_DISK the same unlabeled in a GPT partition
# named fixture-gpt from 1 MB; test-uefi reads them on NVMe and virtio.
UEFI_DISKS ?=
UEFI_DISK_FILE = $(word 1,$(subst @, ,$(1)))
UEFI_DISK_ID = $(basename $(notdir $(call UEFI_DISK_FILE,$(1))))
UEFI_DISK = -drive if=none,id=$(call UEFI_DISK_ID,$(1)),format=raw,readonly=on,file=$(call UEFI_DISK_FILE,$(1)) \
	-device $(word 2,$(subst @, ,$(1))),drive=$(call UEFI_DISK_ID,$(1))$(if $(filter %@nvme,$(1)),$(comma)serial=$(call UEFI_DISK_ID,$(1)))$(if $(filter %@usb-storage,$(1)),$(comma)bus=disks.0)
UEFI_EXT4_DISK := $(UEFI)/ext4.disk
UEFI_EXT4_GPT_DISK := $(UEFI)/ext4-gpt.disk
$(UEFI)/ext4-root: $(wildcard tests/uefi/ext4/* tests/uefi/ext4/*/* tests/uefi/ext4/*/*/*)
	rm -rf $@ && mkdir -p $(UEFI) && cp -a tests/uefi/ext4 $@ && seq 1 50000 > $@/numbers.txt
$(UEFI_EXT4_DISK): $(UEFI)/ext4-root
	rm -f $@ && truncate -s 16M $@ && PATH=$$PATH:/sbin:/usr/sbin && mkfs.ext4 -q -F -L fixture -d $< $@
$(UEFI_EXT4_GPT_DISK): $(UEFI)/ext4-root
	rm -f $@ $@.part && truncate -s 16M $@.part && PATH=$$PATH:/sbin:/usr/sbin && mkfs.ext4 -q -F -d $< $@.part && truncate -s 20M $@ \
		&& sgdisk -n 1:2048:+16M -c 1:fixture-gpt -t 1:8300 $@ >/dev/null && dd if=$@.part of=$@ bs=1M seek=1 conv=notrunc status=none && rm $@.part
uefi: fresh-image
	$(MAKE) $(UEFI)/esp/EFI/BOOT/$(UEFI_BOOT) $(UEFI)/image.disk
$(UEFI)/esp/EFI/BOOT/$(UEFI_BOOT): $(OUT)/samaltak.image vm/uefi.mk
	rm -rf $(UEFI)/gen
	mkdir -p $(UEFI)/esp/EFI/BOOT
	$(VM) $(OUT)/samaltak.image --headless --eval "[VMTranslator generateVMInto: '$(UEFI)/gen' os: #uefi arch: #$(UEFI_ARCH). 'ok'] on: Error do: [:e | Transcript show: e messageText; cr. Smalltalk quit: 1]"
	$(MAKE) -f vm/uefi.mk GEN=$(UEFI)/gen OBJ=$(UEFI)/obj UEFI_TARGET=$(UEFI_TARGET) UEFI_COMMIT="$$(git describe --always --dirty --abbrev=12 2>/dev/null)"
	$(VM) $(OUT)/samaltak.image --headless --eval "UefiImageWriter new convert: '$(UEFI)/obj/samaltak.elf' to: '$(UEFI)/esp/EFI/BOOT/$(UEFI_BOOT)'"
$(UEFI)/image.disk: $(OUT)/samaltak.image
	$(VM) $(OUT)/samaltak.image --headless --eval "UefiImageDisk new write: '$(OUT)/samaltak.image' to: '$(UEFI)/image.disk'"
	truncate -s $(UEFI_DISK_MB)M $(UEFI)/image.disk
uefi-run: uefi
	$(MAKE) uefi-boot
uefi-boot:
	printf '%s\n' --max-heap $(UEFI_HEAP) disk: $(UEFI_ARGS) > $(UEFI)/esp/samaltak.args
	cp $(OVMF_VARS) $(UEFI)/vars.fd
	tools/qemu-pin.sh '$(UEFI_PIN)' $(QEMU_UEFI) -nographic | tee $(UEFI)/console.log
	@grep -q 'samaltak: exit 0' $(UEFI)/console.log
uefi-ui: uefi
	rm -f $(UEFI)/esp/samaltak.args && umask 077 && printf '%s\n' --max-heap $(UEFI_HEAP) disk: --window-size $(UEFI_SCREEN) $(UEFI_DISPLAY_ARGS) > $(UEFI)/esp/samaltak.args
	$(call DISPLAY_PASSWORD,$(UEFI)/esp,$(if $(UEFI_DISPLAY),$(UEFI_DISPLAY_PASSWORD_FILE)),$(UEFI)/esp/samaltak.args)
	cp $(OVMF_VARS) $(UEFI)/vars.fd
	$(if $(UEFI_DISPLAY)$(UEFI_VNC),,$(UEFI_WINDOW)) tools/qemu-pin.sh '$(UEFI_PIN)' $(QEMU_UEFI) $(UEFI_QEMU_DISPLAY) $(UEFI_VGA) -device qemu-xhci -device usb-kbd -device virtio-tablet-pci -serial stdio
uefi-control: uefi
	rm -f $(UEFI)/esp/samaltak.args && umask 077 && printf '%s\n' --max-heap $(UEFI_HEAP) disk: --control --control-host 0.0.0.0 --control-port 7341 \
		$${UEFI_CONTROL_TOKEN:+--control-token "$$UEFI_CONTROL_TOKEN"} $(UEFI_DISPLAY_ARGS) $(UEFI_CONTROL_ARGS) > $(UEFI)/esp/samaltak.args
	$(call DISPLAY_PASSWORD,$(UEFI)/esp,$(if $(UEFI_DISPLAY),$(UEFI_DISPLAY_PASSWORD_FILE)),$(UEFI)/esp/samaltak.args)
	cp $(OVMF_VARS) $(UEFI)/vars.fd
	tools/qemu-pin.sh '$(UEFI_PIN)' $(QEMU_UEFI) $(if $(UEFI_DISPLAY)$(UEFI_VNC),$(UEFI_QEMU_DISPLAY),-display none) $(UEFI_VGA) -device qemu-xhci -device usb-kbd -device virtio-tablet-pci -serial stdio
UEFI_TESTS := CompilerTest ParserTest ScannerTest ClassTest CollectionTest ContextTest ExceptionTest FloatTest FractionTest \
	HashingTest ImmutabilityTest IntegerTest LazyContextTest MarriedContextTest MessageNotUnderstoodTest ObjectTest ProcessTest \
	StackOverflowTest StreamTest StringSearchTest StringTest SymbolTest SystemChangesTest SystemTest UnicodeTest WorkClockTest \
	Amd64DisassemblerTest Arm64DisassemblerTest ByteSearchTest \
	SHA256Test SHA384Test SHA512Test HMACTest HKDFTest ChaCha20Test Poly1305Test ChaCha20Poly1305Test AesTest AesGcmTest SecureRandomTest WycheproofAeadTest NativeCryptoTest \
	X25519Test RsaPublicKeyTest EcPublicKeyTest EcPrivateKeyTest HmacHkdfWycheproofTest Asn1DerTest X509CertificateTest TrustStoreTest CertificateValidatorTest \
	MountTableTest FirmwareVolumesTest GitHubClientTest SourceFilerGitHubTest SourceUpdateTest PosixDeviceTest ZLibTest PNGCodecTest AgentImageTest \
	SoftwareGPUTest SoftwareGPUBandsTest JitOptBackgroundTest FrameTapTest
UEFI_WORLD := | w t | w := UIWindows startUp. RemoteInputDevice default inject: {1. nil. 123. 45. 0. 0. nil. w displayWindow windowId}. t := Time millisecondClockValue. [w dispatcher pointer = (123 @ 45) or: [Time millisecondClockValue - t > 20000]] whileFalse: [(Delay forMilliseconds: 50) wait]. Smalltalk vm stderrWrite: 'world ', w extent printString, ' ', Renderer default device isSoftware printString, ' ', w dispatcher pointer rounded printString, (String with: Character lf)
UEFI_NET := | s buf n | s := RemoteSocket connectTo: '10.0.2.2' port: $$P timeout: 20000. s sendAll: '{\"cmd\": \"ping\", \"auth\": \"', ControlServer current token, '\"}', (String with: Character lf). buf := ByteArray new: 200. n := s receiveInto: buf timeout: 20000. s close. (buf copyFrom: 1 to: n) asString
UEFI_NET_BULK := | src req s buf n chunk out t ms resp ok more | src := String new: 1000000. 1 to: src size do: [:i | src at: i put: (Character value: 97 + (i * 7 rem: 26))]. req := '{\"cmd\": \"eval\", \"auth\": \"', ControlServer current token, '\", \"source\": \"''', src, ''' reverse\"}', (String with: Character lf). t := Time millisecondClockValue. s := RemoteSocket connectTo: '10.0.2.2' port: $$P timeout: 20000. s sendAll: req. out := WriteStream on: (String new: 1100000). buf := ByteArray new: 65536. more := true. [more] whileTrue: [n := s receiveInto: buf timeout: 60000. chunk := (buf copyFrom: 1 to: n) asString. out nextPutAll: chunk. more := n > 0 and: [(chunk includes: Character lf) not]]. ms := Time millisecondClockValue - t. s close. resp := out contents. ok := (resp includesSubstring: '\"ok\":true') and: [resp includesSubstring: src reverse]. 'bulk ', ok printString, ' ', (req size + resp size) printString, ' bytes in ', ms printString, ' ms'
UEFI_NET_DRIVER := 'driver ', NetworkStack active interface class name
UEFI_HTTPS := | s hs r | TLSSocket trustStore: (TrustStore new add: (ByteArray fromHex: '$$CA'); yourself). s := TLSSocket connectTo: '10.0.2.2' port: $$TP timeout: 20000. hs := s connection handshakeMilliseconds. s close. r := HTTPClient new get: 'https://10.0.2.2:$$TP/' headers: nil. TLSSocket trustStore: nil. 'https ', r status printString, ' ', s connection cipherSuite name, ' handshake ', hs printString, ' ms'
UEFI_DRIVER = $(if $(filter e1000e,$(1)),E1000eInterface,VirtioNetInterface)
UEFI_FILES := | f | f := [:x | Smalltalk vm stderrWrite: 'files ', x, (String with: Character lf)]. f value: 'mounts ', (FirmwareVolumes mounts collect: [:m | m key]) printString. f value: 'root ', (Directory entries: '/') printString. f value: 'mnt ', (Directory entries: '/mnt') printString. f value: 'hello ', (File readBytes: '/mnt/fixture/hello.txt') printString. f value: 'link ', (File readText: '/mnt/fixture-gpt/docs/hello-link') lines first. f value: 'numbers ', (File sizeOf: '/mnt/fixture-gpt/numbers.txt') printString, ' ', (FileStream readOnlyFileNamed: '/mnt/fixture/numbers.txt' do: [:s | s position: 288888. s upToEnd]) lines first. f value: 'write ', ([File writeText: 'x' to: '/mnt/fixture/x'. 'written'] on: FileError do: [:e | e messageText]). f value: 'store hidden ', (FirmwareBlockDevice all noneSatisfy: [:d | d isImageStore]) printString. f value: 'problems ', FirmwareVolumes problems size printString
UEFI_MP := 1 to: 300 do: [:i | Compiler evaluate: '3 + 4 * ', i printString]. Smalltalk vm stderrWrite: 'mp bg jobs ', Smalltalk vm statistics optBackgroundJobs printString, (String with: Character lf)
UEFI_RESET := Smalltalk vm stderrWrite: 'menu ', ((ToolsMenu worldMenuAt: nil) selectableItems collect: [:i | i label]) asArray printString, (String with: Character lf). Firmware restart
UEFI_SNAPSHOT := Smalltalk at: 'UefiMark' asSymbol put: 42. (Smalltalk snapshot: Smalltalk vm imagePath) ifTrue: ['resumed ', (Smalltalk at: 'UefiMark' asSymbol) printString] ifFalse: ['saved']
test-uefi:
	rm -f $(UEFI)/image.disk
	$(MAKE) uefi-run UEFI_ARGS='--headless --test $(UEFI_TESTS)'
	grep -q "^samaltak: $(UEFI_CPUS) CPUs" $(UEFI)/console.log
	$(MAKE) uefi-boot UEFI_HEAP_MB=128 UEFI_ARGS='--headless --test LowSpaceTest StackOverflowTest'
	$(MAKE) uefi-boot UEFI_ARGS="--headless --eval \"$(UEFI_MP)\""
	$(if $(filter-out 1,$(UEFI_CPUS)),grep -qE "^mp bg jobs [1-9]" $(UEFI)/console.log)
	$(MAKE) uefi-boot UEFI_CPUS=1 UEFI_ARGS='--headless --test SoftwareGPUTest SoftwareGPUBandsTest JitOptBackgroundTest'
	grep -q "^samaltak: 1 CPUs" $(UEFI)/console.log
	-$(MAKE) uefi-boot UEFI_ARGS="--headless --eval \"$(UEFI_RESET)\""
	grep -q "^samaltak: reset cold" $(UEFI)/console.log && grep -q "'Restart' 'Warm restart' 'Power off'" $(UEFI)/console.log
	$(MAKE) uefi-boot UEFI_ARGS="--eval \"$(UEFI_WORLD)\""
	grep -qE "^world [0-9]+@[0-9]+ true 123@45" $(UEFI)/console.log
	$(MAKE) uefi-boot UEFI_GPU=virtio-gpu-pci UEFI_ARGS="--window-size 1920x1080 --eval \"$(UEFI_WORLD)\""
	grep -qE "^world 1920@1080 true 123@45" $(UEFI)/console.log
	$(MAKE) $(UEFI_EXT4_DISK) $(UEFI_EXT4_GPT_DISK)
	$(MAKE) uefi-boot UEFI_DISKS="$(UEFI_EXT4_DISK)@nvme $(UEFI_EXT4_GPT_DISK)@virtio-blk-pci" UEFI_ARGS="--headless --eval \"$(UEFI_FILES)\""
	while read -r line; do grep -qF "$$line" $(UEFI)/console.log || { echo "test-uefi: files: no line: $$line"; exit 1; }; done < tests/uefi/files.expected
	$(MAKE) test-uefi-fat
	UEFI_AFFINITY=$(UEFI_AFFINITY) OUT=$(OUT) tools/samaltak-ctl --session uefi-test open --uefi --headless
	P=$$(sed -n 's/.*"port": \([0-9]*\).*/\1/p' $${TMPDIR:-/tmp}/samaltak-ctl/uefi-test.json); \
	TP=$$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])'); \
	tools/samaltak-ctl --session uefi-test eval "$(UEFI_NET_DRIVER)" > $(UEFI)/net.log; ok=$$?; \
	[ $$ok = 0 ] && { tests/remote/auth_test.sh --session uefi-test >> $(UEFI)/net.log; ok=$$?; }; \
	[ $$ok = 0 ] && { tools/samaltak-ctl --session uefi-test eval "$(UEFI_NET)" >> $(UEFI)/net.log; ok=$$?; }; \
	[ $$ok = 0 ] && { tools/samaltak-ctl --session uefi-test eval "$(UEFI_NET_BULK)" >> $(UEFI)/net.log; ok=$$?; }; \
	[ $$ok = 0 ] && { tools/tls-test-server.sh $(UEFI)/tls $$TP; ok=$$?; }; \
	[ $$ok = 0 ] && { CA=$$(cat $(UEFI)/tls/ca.hex); tools/samaltak-ctl --session uefi-test eval "$(UEFI_HTTPS)" >> $(UEFI)/net.log; ok=$$?; \
		kill $$(cat $(UEFI)/tls/pid); }; \
	tools/samaltak-ctl --session uefi-test close; cat $(UEFI)/net.log; [ $$ok = 0 ] && grep -q pong $(UEFI)/net.log && grep -q "'bulk true" $(UEFI)/net.log \
		&& grep -q "'driver $(call UEFI_DRIVER,$(UEFI_NIC))'" $(UEFI)/net.log && grep -q "'https 200 " $(UEFI)/net.log
	$(if $(filter-out virtio-net-pci,$(UEFI_NIC)),$(MAKE) test-uefi-nic UEFI_NIC=virtio-net-pci)
	$(MAKE) uefi-boot UEFI_ARGS="--headless --eval \"$(UEFI_SNAPSHOT)\""
	grep -q "'saved'" $(UEFI)/console.log
	$(MAKE) uefi-boot UEFI_ARGS=--headless
	grep -q "'resumed 42'" $(UEFI)/console.log
	rm $(UEFI)/image.disk
# test-uefi-fat: writable FAT volumes and crash reports (tests/uefi/fat.sh): the VM booted from a FAT32 EFI system
# partition image (QEMU's fat:rw: directory loses writes) with FAT disks to write, read-only and nearly full, what it
# wrote checked with mtools and fsck.fat; then a forced fatal error: its report on the ESP, the panel, a key, the reset.
UEFI_ESP_DRIVE := -drive format=raw,file=fat:rw:$(UEFI)/esp
test-uefi-fat: $(UEFI_EXT4_DISK)
	QEMU='$(subst $(UEFI_ESP_DRIVE),,$(QEMU_UEFI))' UEFI=$(UEFI) VARS=$(OVMF_VARS) BOOT=$(UEFI_BOOT) EXT4=$(UEFI_EXT4_DISK) sh tests/uefi/fat.sh
test-uefi-nic:
	UEFI_NIC=$(UEFI_NIC) UEFI_AFFINITY=$(UEFI_AFFINITY) OUT=$(OUT) tools/samaltak-ctl --session uefi-test open --uefi --headless
	P=$$(sed -n 's/.*"port": \([0-9]*\).*/\1/p' $${TMPDIR:-/tmp}/samaltak-ctl/uefi-test.json); \
	tools/samaltak-ctl --session uefi-test eval "$(UEFI_NET_DRIVER)" > $(UEFI)/net.log; ok=$$?; \
	[ $$ok = 0 ] && { tools/samaltak-ctl --session uefi-test eval "$(UEFI_NET)" >> $(UEFI)/net.log; ok=$$?; }; \
	tools/samaltak-ctl --session uefi-test close; cat $(UEFI)/net.log; [ $$ok = 0 ] && grep -q pong $(UEFI)/net.log \
		&& grep -q "'driver $(call UEFI_DRIVER,$(UEFI_NIC))'" $(UEFI)/net.log

# A boot disk for real hardware (docs/uefi.md, Real hardware): USB_IMAGE, one file to write onto a USB stick (dd) or to boot
# in QEMU, a GPT disk of three partitions: 1 the EFI system partition (FAT32 of USB_ESP_MB: EFI/BOOT/$(UEFI_BOOT) and
# samaltak.args), 2 the image store (UefiImageDisk: 1 MB and two slots of USB_SLOT_FACTOR times the image), 3 if USB_FILES
# (a directory, by default test-uefi's ext4 fixture) an ext4 volume of it, USB_FILES_MB, labelled USB_FILES_LABEL. Made
# without root: sgdisk on the file, mformat, mmd and mcopy (mtools), mkfs.ext4 -d, dd into the partitions' offsets.
# samaltak.args: --max-heap USB_HEAP_MB disk: USB_ARGS, the World by default (USB_SCREEN its --window-size, else the
# firmware's mode). USB_DIAG=1 first runs FirmwareDiagnostics (firmware, SMBIOS, ACPI and CPUs, memory map and protection,
# timer, RNG, GOP modes, PCI, disks, volumes, NICs, DHCP: on the console and in samaltak-diag.txt on the stick's ESP), then
# the World after a key or 30 s; USB_DIAG=key powers off after a key instead, USB_DIAG=quit at once. usb-run boots
# USB_IMAGE in QEMU as USB_DEVICE (usb-storage on xHCI, or nvme), its console on stdio (UEFI_VNC=N: its screen on VNC;
# UEFI_CONTROL_PORT=N: host 127.0.0.1:N forwarded to its port 7341, for USB_CONTROL; UEFI_DISPLAY=N: 127.0.0.1:5900+N
# forwarded to its port 5900, for USB_DISPLAY).
# test-usb-image makes one (usb-test.img) and boots that very file as a USB stick and as NVMe: the diagnostics (the
# store, the ext4 volume, DHCP, the file on the ESP), then a snapshot into the stick's store and its resume.
USB_IMAGE ?= $(UEFI)/usb.img
USB_HEAP_MB ?= 2048
USB_ESP_MB ?= 64
USB_SLOT_FACTOR ?= 3
USB_FILES ?= $(UEFI)/ext4-root
USB_FILES_MB ?= 32
USB_FILES_LABEL ?= usb-files
USB_SCREEN ?=
USB_DIAG ?=
USB_DIAG_RUN = $(if $(filter key,$(USB_DIAG)),runThenWaitForKey,$(if $(filter quit,$(USB_DIAG)),runThenQuit,runThenWorld))
USB_ARGS ?= $(if $(USB_SCREEN),--window-size $(USB_SCREEN)) $(if $(USB_DIAG),--eval 'FirmwareDiagnostics $(USB_DIAG_RUN)')
# USB_CONTROL=1: the control service on every address, port 7341, for samaltak-ctl connect from another machine
# (docs/remote.md); its token the contents of USB_CONTROL_TOKEN_FILE (e.g. openssl rand -hex 16 > F; written into
# samaltak.args, never on a command line, and the stick's file made 0600), else one the image makes at boot and shows
# on the screen.
USB_CONTROL ?=
USB_CONTROL_TOKEN_FILE ?=
USB_CONTROL_ARGS = $(if $(USB_CONTROL),--control --control-host 0.0.0.0 --control-port 7341)
# USB_DISPLAY=1: the image's remote display server (RFB) on every address, port 5900, for macOS Screen Sharing or TigerVNC
# from another machine (docs/remote.md, Remote display), with VNC authentication (never none): its password the contents
# of USB_DISPLAY_PASSWORD_FILE (at most 8 characters; copied to the stick's ESP, the stick's file made 0600), else one
# the image makes at boot and shows on the screen and console. VNC authentication is weak and the session unencrypted:
# a trusted network, or an SSH tunnel to a machine beside it.
USB_DISPLAY ?=
USB_DISPLAY_PASSWORD_FILE ?=
USB_DISPLAY_ARGS = $(if $(USB_DISPLAY),--display --display-host 0.0.0.0 --display-port 5900 --display-vnc-auth)
USB_DEVICE ?= usb-storage
USB_STORE_TYPE := 5aa3a57f-0f7e-4c2b-9b5e-53414d53544f
USB_PARTS = $(USB_IMAGE).parts
MTOOLS := MTOOLS_SKIP_CHECK=1
QEMU_USB = $(QEMU_UEFI_MACHINE) -m $(or $(UEFI_RAM_MB),$(USB_RAM_MB),2048) -no-reboot -nic user,model=$(UEFI_NIC)$(if $(UEFI_CONTROL_PORT),$(comma)hostfwd=tcp:127.0.0.1:$(UEFI_CONTROL_PORT)-:7341)$(UEFI_DISPLAY_FWD) -global $(UEFI_NIC).romfile= \
	-device virtio-rng-pci -drive if=pflash,format=raw,readonly=on,file=$(OVMF_CODE) -drive if=pflash,format=raw,file=$(UEFI)/usb-vars.fd \
	-device qemu-xhci -drive if=none,id=stick,format=raw,file=$(USB_IMAGE) \
	$(if $(filter nvme,$(USB_DEVICE)),-device nvme$(comma)serial=stick$(comma)drive=stick,-device usb-storage$(comma)drive=stick)
usb-image: uefi
	$(MAKE) usb-disk
usb-disk: $(filter $(UEFI)/ext4-root,$(USB_FILES))
	rm -rf $(USB_IMAGE) $(USB_PARTS) && mkdir -p $(USB_PARTS)
	umask 077 && printf '%s\n' --max-heap $(USB_HEAP_MB) disk: $(USB_CONTROL_ARGS) $(USB_DISPLAY_ARGS) $(USB_ARGS) > $(USB_PARTS)/samaltak.args
	$(if $(USB_CONTROL_TOKEN_FILE),printf '%s\n' --control-token "$$(tr -d ' \n' < $(USB_CONTROL_TOKEN_FILE))" >> $(USB_PARTS)/samaltak.args)
	$(call DISPLAY_PASSWORD,$(USB_PARTS),$(if $(USB_DISPLAY),$(USB_DISPLAY_PASSWORD_FILE)),$(USB_PARTS)/samaltak.args)
	$(if $(USB_DISPLAY),@echo "note: the remote display listens on every address with VNC authentication (weak, unencrypted): a trusted network or an SSH tunnel (docs/remote.md)")
	truncate -s $(USB_ESP_MB)M $(USB_PARTS)/esp && $(MTOOLS) mformat -i $(USB_PARTS)/esp -F -v SAMALTAK :: \
		&& $(MTOOLS) mmd -i $(USB_PARTS)/esp ::/EFI ::/EFI/BOOT && $(MTOOLS) mcopy -i $(USB_PARTS)/esp $(UEFI)/esp/EFI/BOOT/$(UEFI_BOOT) ::/EFI/BOOT/ \
		&& $(MTOOLS) mcopy -i $(USB_PARTS)/esp $(USB_PARTS)/samaltak.args ::/ \
		$(if $(USB_DISPLAY),$(if $(USB_DISPLAY_PASSWORD_FILE),&& $(MTOOLS) mcopy -i $(USB_PARTS)/esp $(USB_PARTS)/samaltak-display-password ::/))
	$(VM) $(OUT)/samaltak.image --headless --eval "UefiImageDisk new write: '$(OUT)/samaltak.image' to: '$(USB_PARTS)/store'"
	truncate -s $$(( 1 + 2 * $(USB_SLOT_FACTOR) * (($$(wc -c < $(OUT)/samaltak.image) + 1048575) / 1048576) ))M $(USB_PARTS)/store
	$(if $(USB_FILES),truncate -s $(USB_FILES_MB)M $(USB_PARTS)/files && PATH=$$PATH:/sbin:/usr/sbin && mkfs.ext4 -q -F -L $(USB_FILES_LABEL) -d $(USB_FILES) $(USB_PARTS)/files)
	E=$(USB_ESP_MB); S=$$(( $$(wc -c < $(USB_PARTS)/store) / 1048576 )); F=$(if $(USB_FILES),$(USB_FILES_MB),0); \
	truncate -s $$(( 2 + E + S + F ))M $(USB_IMAGE) \
		&& sgdisk -n 1:2048:+$${E}M -t 1:ef00 -c 1:EFI -n 2:$$(( (1 + E) * 2048 )):+$${S}M -t 2:$(USB_STORE_TYPE) -c 2:samaltak-image \
			$(if $(USB_FILES),-n 3:$$(( (1 + E + S) * 2048 )):+$${F}M -t 3:8300 -c 3:$(USB_FILES_LABEL)) $(USB_IMAGE) > /dev/null \
		&& dd if=$(USB_PARTS)/esp of=$(USB_IMAGE) bs=1M seek=1 conv=notrunc status=none \
		&& dd if=$(USB_PARTS)/store of=$(USB_IMAGE) bs=1M seek=$$(( 1 + E )) conv=notrunc status=none \
		$(if $(USB_FILES),&& dd if=$(USB_PARTS)/files of=$(USB_IMAGE) bs=1M seek=$$(( 1 + E + S )) conv=notrunc status=none)
	@echo "$(USB_IMAGE): $$(( $$(wc -c < $(USB_IMAGE)) / 1048576 )) MB, samaltak.args: $$(awk 'p { print "<token>"; p = 0; next } /^--control-token$$/ { p = 1 } { print }' $(USB_PARTS)/samaltak.args | tr '\n' ' ')"
	$(if $(USB_CONTROL_TOKEN_FILE)$(USB_DISPLAY_PASSWORD_FILE),chmod 600 $(USB_IMAGE))
	rm -rf $(USB_PARTS)
usb-run: USB_RAM_MB = $(shell expr $(USB_HEAP_MB) \* 4)
usb-run:
	cp $(OVMF_VARS) $(UEFI)/usb-vars.fd
	$(QEMU_USB) $(if $(UEFI_DISPLAY)$(UEFI_VNC),$(if $(UEFI_DISPLAY),-display none,$(UEFI_VNC_DISPLAY)) -device usb-kbd -device virtio-tablet-pci -serial stdio,-nographic) | tee $(UEFI)/usb-console.log
usb-boot:
	cp $(OVMF_VARS) $(UEFI)/usb-vars.fd
	$(QEMU_USB) -nographic | tee $(UEFI)/usb-console.log
	@grep -q 'samaltak: exit 0' $(UEFI)/usb-console.log
USB_TEST := $(UEFI)/usb-test.img
USB_TEST_ARGS = printf '%s\n' --max-heap 256 disk: $(1) > $(UEFI)/usb-test.args && $(MTOOLS) mcopy -o -i $(USB_TEST)@@1M $(UEFI)/usb-test.args ::/samaltak.args
USB_TEST_DIAG = for p in 'the image store' 'volumes: .*/mnt/usb-files' 'gop 1 modes: ' 'mp services: ' 'memory map [0-9]* descriptors' 'dhcp: 10\.0\.2\.15' '^diag done'; do \
		grep -q "$$p" $(UEFI)/usb-console.log || { echo "test-usb-image: $(1): no line $$p"; exit 1; }; done; \
	rm -f $(UEFI)/usb-diag.txt && $(MTOOLS) mcopy -i $(USB_TEST)@@1M ::/samaltak-diag.txt $(UEFI)/usb-diag.txt && grep -q '^diag done' $(UEFI)/usb-diag.txt \
		&& $(MTOOLS) mdel -i $(USB_TEST)@@1M ::/samaltak-diag.txt || { echo "test-usb-image: $(1): no samaltak-diag.txt on the ESP"; exit 1; }
test-usb-image: uefi
	$(MAKE) usb-disk USB_IMAGE=$(USB_TEST)
	$(call USB_TEST_ARGS,--headless --eval 'FirmwareDiagnostics runThenQuit')
	$(MAKE) usb-boot USB_IMAGE=$(USB_TEST) USB_DEVICE=usb-storage
	$(call USB_TEST_DIAG,usb-storage)
	$(MAKE) usb-boot USB_IMAGE=$(USB_TEST) USB_DEVICE=nvme
	$(call USB_TEST_DIAG,nvme)
	$(call USB_TEST_ARGS,--headless --eval "$(UEFI_SNAPSHOT)")
	$(MAKE) usb-boot USB_IMAGE=$(USB_TEST) USB_DEVICE=usb-storage
	grep -q "'saved'" $(UEFI)/usb-console.log
	$(call USB_TEST_ARGS,--headless)
	$(MAKE) usb-boot USB_IMAGE=$(USB_TEST) USB_DEVICE=usb-storage
	grep -q "'resumed 42'" $(UEFI)/usb-console.log
	rm $(USB_TEST)
# test-install: the installer (SamaltakInstaller, docs/uefi.md, Installing) under QEMU on an NVMe disk image like the
# DGX Spark's (an ESP with a fake Ubuntu, an ext4 root, free space) with a variable store of its own: install from a
# boot stick (usb-disk), check the GPT (sgdisk -v), the ESP (mtools) and the boot options (tests/uefi/efivars.py), boot
# Samaltak from the NVMe by BootNext with the stick removed, then Ubuntu (tests/uefi/install-test.sh).
INSTALL_USB := $(UEFI)/install-usb.img
test-install: uefi
	$(MAKE) usb-disk USB_IMAGE=$(INSTALL_USB) USB_FILES=
	UEFI=$(UEFI) UEFI_ARCH=$(UEFI_ARCH) UEFI_BOOT=$(UEFI_BOOT) OVMF_CODE=$(OVMF_CODE) OVMF_VARS=$(OVMF_VARS) \
		QEMU_UEFI_MACHINE='$(QEMU_UEFI_MACHINE)' USB_IMAGE=$(INSTALL_USB) tests/uefi/install-test.sh
	rm -rf $(INSTALL_USB) $(UEFI)/install-test


# The narrated walkthrough on the real system, from a copy of the image named nuuk.image like the prototype's (a visible window; needs ffmpeg, agent-browser for the captions and
# ELEVENLABS_API_KEY in .env unless the clips in $(VIDEO)/narration are cached).
VIDEO ?= .context/video-real
video: vm image
	cp $(OUT)/samaltak.image $(OUT)/nuuk.image
	node tools/narrate.mjs $(VIDEO)
	WALKTHROUGH_IMAGE=$(OUT)/nuuk.image node tools/walkthrough.mjs $(VIDEO)
	python3 tools/compose-video.py $(VIDEO)
	cp $(VIDEO)/walkthrough.mp4 docs/media/walkthrough.mp4

# The "mind blown" video (.context/mindblown.md): the same pipeline, steps in tools/mindblown/narration.json, voice
# Matilda, unperformed (no style exaggeration, lines spoken as one conversation). The snapshot beat saves the image and
# relaunches it, so it runs on its own copy of the image.
MINDBLOWN ?= .context/video-mindblown
MINDBLOWN_VOICE ?= XrExE9yKIg1WjnnlVkGX
MINDBLOWN_REQUEST ?= {"voice_settings": {"stability": 0.35, "similarity_boost": 0.7, "style": 0, "use_speaker_boost": true, "speed": 1.05}, "continuity": true}
mindblown-video: vm image
	cp $(OUT)/samaltak.image $(OUT)/nuuk.image
	ELEVENLABS_VOICE=$(MINDBLOWN_VOICE) ELEVENLABS_REQUEST='$(MINDBLOWN_REQUEST)' node tools/narrate.mjs $(MINDBLOWN) tools/mindblown/narration.json
	WALKTHROUGH_IMAGE=$(OUT)/nuuk.image node tools/mindblown/walkthrough-mindblown.mjs $(MINDBLOWN)
	python3 tools/compose-video.py $(MINDBLOWN) mindblown.mp4
	cp $(MINDBLOWN)/mindblown.mp4 docs/media/mindblown.mp4

# The JIT video: the same pipeline, steps in tools/jit/narration.json, the mind-blown voice. The race needs Pharo 12
# (vm/tests/bench/awfy.sh --pharo, /tmp/pharo-dl).
JIT_VIDEO ?= .context/video-jit
jit-video: vm image
	cp $(OUT)/samaltak.image $(OUT)/nuuk.image
	ELEVENLABS_VOICE=$(MINDBLOWN_VOICE) ELEVENLABS_REQUEST='$(MINDBLOWN_REQUEST)' node tools/narrate.mjs $(JIT_VIDEO) tools/jit/narration.json
	WALKTHROUGH_IMAGE=$(OUT)/nuuk.image node tools/jit/walkthrough-jit.mjs $(JIT_VIDEO)
	python3 tools/compose-video.py $(JIT_VIDEO) jit.mp4
	cp $(JIT_VIDEO)/jit.mp4 docs/media/jit.mp4

clean:
	$(MAKE) -C vm clean
	rm -rf build

.PHONY: all vm seed image fresh-image run translate uefi uefi-run uefi-boot uefi-ui uefi-control test-uefi test-uefi-fat test-uefi-nic usb-image usb-disk usb-run usb-boot test-usb-image test-install test-vm test-jit test-jit-none test-jit-baseline test-jit-opt test-jit-deopt test-jit-cache test-core test-tools test-nv nv-kernels test video mindblown-video jit-video clean
