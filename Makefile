# Samaltak: VM, seed image (the Smalltalk ImageBuilder, run in boot/seed.image), full image (stage 2), tests.
# OUT selects the build directory, so concurrent builds do not collide: make image OUT=build/me
OUT ?= build
# SAMALTAK_TIMELINE=FILE: each recipe line's start, end, exit status and target go into FILE (tests/timed-sh), and
# st_suite's VMs and slot waits too; tests/timeline.sh reports it (tests/stages.sh: OUT/stages/timeline).
ifneq ($(SAMALTAK_TIMELINE),)
SHELL = $(CURDIR)/tests/timed-sh $@
endif

VM := vm/build/samaltak
# The C compiles' jobs (the VM's, the UEFI application's): one per CPU, unless make already runs jobs at once (-j).
NPROC := $(shell nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)
BUILD_JOBS = $(if $(findstring jobserver,$(MAKEFLAGS)),,-j$(NPROC))
# What the test targets build first: image (always rebuilt), or fresh-image (only when src/, boot/ or the VM are newer:
# tests/stages.sh builds once, then runs stages at once).
TEST_IMAGE ?= image

all: vm seed image runtime

vm:
	$(MAKE) -C vm $(BUILD_JOBS)

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
	$(MAKE) -C vm $(BUILD_JOBS)

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
	tests/rerun.sh bound-ffi-site tests/vm/bound_ffi_site_test.sh $(OUT)/samaltak.image $(VM)
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
	$(MAKE) test-ffi-headless
	$(MAKE) test-ffi-no-platform
	$(MAKE) test-jit
	$(MAKE) test-tools
	$(MAKE) test-uefi
	@echo "make test: all passed"
PLATFORM_CHECK = @[ -f vm/build/.variant-platform ] || { echo "make test: FAILED: the VM was built without the platform layer (SDL3), UI tests would not run"; exit 1; }
# test-core's parts run at once (make -j -O: TEST_CORE_JOBS, all of them by default; 1: one after another), the main
# suite first, each part's output shown when it ends; every part's VMs hold the machine's test slots (tests/st_suite.sh,
# tests/with-slot).
# Every part runs to its end (-k).
TEST_CORE_PARTS := suite vm gen layering fresh-seed ffi cli-quit resume-rng verify-gc heap weather agents wodify pi-functions
TEST_CORE_JOBS ?= $(words $(TEST_CORE_PARTS))
# make -j N -O, but one at a time on make 3.81 (macOS's), which has no -O
TEST_PARTS_SYNC = $(if $(filter 3.%,$(MAKE_VERSION)),-j1,-j$(1) -O --no-print-directory)
# A part that fails runs once more (tests/rerun.sh, SAMALTAK_TEST_RERUN; a suite reruns its failed shards itself): one
# that passes then is a flake, listed as "flake: <line>". The runtime image comes first, for the three parts using it.
RERUN_PART = +@tests/rerun.sh $(1)-part-$* $(MAKE) --no-print-directory $(1)-part-$*
test-core-rerun-%:
	$(call RERUN_PART,test-core)
test-tools-rerun-%:
	$(call RERUN_PART,test-tools)
test-uefi-rerun-%:
	$(call RERUN_PART,test-uefi)
test-core: $(TEST_IMAGE)
	$(PLATFORM_CHECK)
	@$(MAKE) --no-print-directory fresh-runtime
	$(MAKE) -k $(call TEST_PARTS_SYNC,$(TEST_CORE_JOBS)) $(addprefix test-core-rerun-,$(TEST_CORE_PARTS))
test-core-part-suite:
	tests/st_suite.sh $(OUT)/samaltak.image
test-core-part-vm: vm
	tests/with-slot vm/tests/run.sh
test-core-part-gen:
	tests/with-slot tests/vm/gen_test.sh $(OUT)/samaltak.image
test-core-part-pi-functions:
	tests/tools/pi_functions_test.sh
test-core-part-fresh-seed:
	tests/with-slot tests/boot/fresh_seed_test.sh $(VM)
test-core-part-ffi:
	tests/with-slot tests/vm/runtime_native_grants_test.sh $(OUT)/samaltak.image $(VM)
	tests/with-slot tests/vm/wrapped_ffi_specialization_test.sh $(OUT)/samaltak.image $(VM)
	tests/with-slot tests/vm/ffi_external_notification_test.sh $(OUT)/samaltak.image $(VM)
	tests/with-slot tests/vm/ffi_arity_test.sh $(OUT)/samaltak.image $(VM)
test-core-part-layering:
	tests/with-slot tests/boot/layering_test.sh
test-core-part-cli-quit:
	tests/with-slot tests/boot/cli_quit_test.sh $(OUT)/samaltak.image
test-core-part-resume-rng:
	tests/with-slot tests/boot/resume_rng_test.sh $(OUT)/samaltak.image
test-core-part-verify-gc:
	SAMALTAK_VERIFY_GC=1 tests/st_suite.sh $(OUT)/samaltak.image --eden 1 -- Tests-Kernel Tests-Compiler
test-core-part-heap:
	tests/st_suite.sh $(OUT)/samaltak.image --max-heap 128 -- LowSpaceTest StackOverflowTest
test-core-part-weather: fresh-runtime
	tests/st_suite.sh $(OUT)/runtime.image -- Weather --load apps/Weather
test-core-part-agents: fresh-runtime
	tests/st_suite.sh $(OUT)/runtime.image -- Agents --load apps/Agents
test-core-part-wodify: fresh-runtime
	tests/st_suite.sh $(OUT)/runtime.image -- Wodify --load apps/Wodify
# Native-entry and semantic smoke, not the performance gate (shared CI CPUs are noisy).
test-ffi-bigint-owned: $(TEST_IMAGE)
	tests/vm/bigint_owned_ffi_test.sh "$(OUT)/samaltak.image" "$(VM)" "$(OUT)/ffi-bigint-owned-logs"

FFI_HEADLESS_LOGS ?= $(OUT)/ffi-headless-logs
FFI_NO_PLATFORM_LOGS ?= $(OUT)/ffi-no-platform-logs
FFI_NO_PLATFORM_VM := vm/build/ffi-no-platform/samaltak
FFI_NO_VIDEO = env -u DISPLAY -u WAYLAND_DISPLAY -u XAUTHORITY -u SAMALTAK_NATIVE_GRANTS SDL_VIDEO_DRIVER=ffi_no_video SDL_VIDEODRIVER=ffi_no_video

test-ffi-headless: $(TEST_IMAGE) test-ffi-bigint-owned
	$(PLATFORM_CHECK)
	mkdir -p "$(FFI_HEADLESS_LOGS)"
	python3 tests/vm/ffi_cutover.py check "$(OUT)/samaltak.image" "$(VM)" --backend sdl --logs "$(FFI_HEADLESS_LOGS)"
	tests/vm/ffi_migration_manifest_test.sh $(OUT)/samaltak.image $(VM)
	tests/vm/ffi_migration_gate_test.sh $(OUT)/samaltak.image $(VM) sdl release
	tests/vm/ffi_migration_owned_test.sh $(OUT)/samaltak.image $(VM) sdl release
	tests/vm/file_ffi_snapshot_test.sh $(OUT)/samaltak.image $(VM)
	tests/vm/core_getenv_large_test.sh $(OUT)/samaltak.image $(VM)
	python3 tests/vm/core_ffi_test.py $(OUT)/samaltak.image $(VM) --trace --logs "$(FFI_HEADLESS_LOGS)/core"
	tests/vm/window_ffi_test.sh $(OUT)/samaltak.image $(VM) --logs "$(FFI_HEADLESS_LOGS)"
	@set -eu; for mode in none baseline opt; do \
		flags=; [ "$$mode" != opt ] || flags='--jit-flags eager'; \
		log="$(FFI_HEADLESS_LOGS)/file-$$mode.log"; \
		$(FFI_NO_VIDEO) SAMALTAK_FFI_NATIVE_TRACE=1 tests/st_suite.sh "$(OUT)/samaltak.image" \
			--jit "$$mode" --jit-threshold 0 $$flags -- FileFFITest ApprovedFFIRegistryTest FFISeededSiteTest >"$$log" 2>&1 \
			|| { cat "$$log"; exit 1; }; \
		python3 tests/vm/socket_ffi_test.py $(VM) $(OUT)/samaltak.image --jit "$$mode" --trace --logs "$(FFI_HEADLESS_LOGS)"; \
	done
	python3 tests/vm/process_ffi_test.py "$(OUT)/samaltak.image" "$(VM)" --logs "$(FFI_HEADLESS_LOGS)"
	python3 tests/vm/ffi_exec_probe_test.py "$(OUT)/samaltak.image" "$(VM)"
	python3 tests/vm/ffi_cutover.py coverage --profile hosted-headless \
		--none "$(FFI_HEADLESS_LOGS)/core/none.stderr" "$(FFI_HEADLESS_LOGS)/file-none.log" "$(FFI_HEADLESS_LOGS)/window-none.stderr" "$(FFI_HEADLESS_LOGS)/socket-none.stderr" "$(OUT)/ffi-bigint-owned-logs/production-none.err" "$(FFI_HEADLESS_LOGS)/process-none.stderr" "$(FFI_HEADLESS_LOGS)/exec-none.stderr" \
		--baseline "$(FFI_HEADLESS_LOGS)/core/baseline.stderr" "$(FFI_HEADLESS_LOGS)/file-baseline.log" "$(FFI_HEADLESS_LOGS)/window-baseline.stderr" "$(FFI_HEADLESS_LOGS)/socket-baseline.stderr" "$(OUT)/ffi-bigint-owned-logs/production-baseline.err" "$(FFI_HEADLESS_LOGS)/process-baseline.stderr" "$(FFI_HEADLESS_LOGS)/exec-baseline.stderr" \
		--opt "$(FFI_HEADLESS_LOGS)/core/opt.stderr" "$(FFI_HEADLESS_LOGS)/file-opt.log" "$(FFI_HEADLESS_LOGS)/window-opt.stderr" "$(FFI_HEADLESS_LOGS)/socket-opt.stderr" "$(OUT)/ffi-bigint-owned-logs/production-opt.err" "$(FFI_HEADLESS_LOGS)/process-opt.stderr" "$(FFI_HEADLESS_LOGS)/exec-opt.stderr"
	@logs=$$(mktemp -d "$(FFI_HEADLESS_LOGS)/paired.XXXXXXXX"); \
		python3 vm/tests/bench/ffi-paired.py --vm $(VM) --image $(OUT)/samaltak.image --logs "$$logs" --proof-only

test-ffi-no-platform: $(TEST_IMAGE)
	$(MAKE) -C vm BUILD=build/ffi-no-platform NO_PLATFORM=1
	mkdir -p "$(FFI_NO_PLATFORM_LOGS)"
	python3 tests/vm/ffi_cutover.py check "$(OUT)/samaltak.image" "$(FFI_NO_PLATFORM_VM)" --backend no-platform --logs "$(FFI_NO_PLATFORM_LOGS)"
	tests/vm/ffi_migration_gate_test.sh $(OUT)/samaltak.image $(FFI_NO_PLATFORM_VM) no-platform release
	python3 tests/vm/core_ffi_test.py $(OUT)/samaltak.image $(FFI_NO_PLATFORM_VM) --trace --logs "$(FFI_NO_PLATFORM_LOGS)/core"
	tests/vm/bigint_owned_ffi_test.sh "$(OUT)/samaltak.image" "$(FFI_NO_PLATFORM_VM)" "$(FFI_NO_PLATFORM_LOGS)"
	python3 tests/vm/ffi_cutover.py coverage --profile no-platform \
		--none "$(FFI_NO_PLATFORM_LOGS)/core/none.stderr" "$(FFI_NO_PLATFORM_LOGS)/production-none.err" \
		--baseline "$(FFI_NO_PLATFORM_LOGS)/core/baseline.stderr" "$(FFI_NO_PLATFORM_LOGS)/production-baseline.err" \
		--opt "$(FFI_NO_PLATFORM_LOGS)/core/opt.stderr" "$(FFI_NO_PLATFORM_LOGS)/production-opt.err"

# Only these targets build a VM with test exports; use a separate object tree and binary.
# Calls of 7 to 16 arguments through the approved test exports as well as launcher grants.
test-ffi-arity: $(TEST_IMAGE)
	$(MAKE) -C vm BUILD=build/ffi-test-exports CPPFLAGS="$(CPPFLAGS) -DSAMALTAK_FFI_TEST_EXPORTS=1"
	tests/vm/ffi_arity_test.sh $(OUT)/samaltak.image $(VM) vm/build/ffi-test-exports/samaltak

test-ffi-gpu-paged: $(TEST_IMAGE)
	$(PLATFORM_CHECK)
	$(MAKE) -C vm BUILD=build/ffi-test-exports CPPFLAGS="$(CPPFLAGS) -DSAMALTAK_FFI_TEST_EXPORTS=1"
	@set -eu; unset DISPLAY WAYLAND_DISPLAY XAUTHORITY SAMALTAK_NATIVE_GRANTS; \
		export LC_ALL=C SDL_VIDEO_DRIVER=ffi_no_video SDL_VIDEODRIVER=ffi_no_video; \
		result=$$(SAMALTAK_FFI_TEST_EXPORTS=1 $(VM) "$(OUT)/samaltak.image" --headless \
			--eval "(PlatformFFI bind: #(call 'platform' 'platform_gpu_test_shader_pages' (writableBytesWithLength) i32)) isNil"); \
		test "$$result" = true || { echo "Release VM did not deny the paged shader fixture: $$result" >&2; exit 1; }; \
		for mode in none baseline opt; do \
			echo "Paged shader fixture: $$mode"; \
			result=$$(vm/build/ffi-test-exports/samaltak \
				--jit "$$mode" --jit-threshold 0 --jit-flags eager "$(OUT)/samaltak.image" --headless \
				--eval "$$(cat tests/vm/gpu_shader_paged_test.st)"); \
			test "$$result" = true || { printf '%s\n' "$$result" >&2; exit 1; }; \
		done

# Run only in display CI (real SDL window + software Vulkan through the test runner's X server).
FFI_DISPLAY_LOGS ?= $(OUT)/ffi-display-logs
test-ffi-display: $(TEST_IMAGE)
	@test "$$GITHUB_ACTIONS" = true && test -n "$$DISPLAY"
	mkdir -p "$(FFI_DISPLAY_LOGS)"
	tests/vm/window_ffi_test.sh $(OUT)/samaltak.image $(VM) --display-ci --logs "$(FFI_DISPLAY_LOGS)"
	@set -eu; for mode in none baseline opt; do \
		flags=; [ "$$mode" != opt ] || flags='--jit-flags eager'; \
		log="$(FFI_DISPLAY_LOGS)/gpu-$$mode.log"; \
		SAMALTAK_FFI_NATIVE_TRACE=1 tests/st_suite.sh "$(OUT)/samaltak.image" --jit "$$mode" --jit-threshold 0 \
			$$flags -- GPUFFIRegressionTest >"$$log" 2>&1 || { cat "$$log"; exit 1; }; \
	done
	python3 tests/vm/ffi_cutover.py coverage --profile display \
		--none "$(FFI_DISPLAY_LOGS)/gpu-none.log" "$(FFI_DISPLAY_LOGS)/window-none.stderr" \
		--baseline "$(FFI_DISPLAY_LOGS)/gpu-baseline.log" "$(FFI_DISPLAY_LOGS)/window-baseline.stderr" \
		--opt "$(FFI_DISPLAY_LOGS)/gpu-opt.log" "$(FFI_DISPLAY_LOGS)/window-opt.stderr"
	@logs=$$(mktemp -d "$(FFI_DISPLAY_LOGS)/paired.XXXXXXXX"); \
		python3 vm/tests/bench/ffi-paired.py --vm $(VM) --image $(OUT)/samaltak.image \
			--logs "$$logs" --display-ci --proof-only

# The NVIDIA GPU (the GB10) through NVIDIA's CUDA userspace (libcuda; docs/cuda.md): not part of make test, which runs
# where there is none. Fails, saying so, without a GPU. NvGpuMeasure reports launch latency and copy bandwidth. Then the
# raster kernels (gpu/nv, docs/nv-kernels.md) on the GPU against PlatformRaster (tests/nv/run.sh: needs the driver,
# not nvcc).
# cuOpt is no CUDA toolkit library: its wheel's lib64 (docs/cuda.md), where it is installed, adds CuOptGpuTest.
CUOPT_LIB ?= $(wildcard $(HOME)/.local/share/samaltak-cuopt/venv/lib/python3.12/site-packages/libcuopt_mathopt/lib64)
test-nv: $(TEST_IMAGE)
	SAMALTAK_CUDA_LIBS=$(CUOPT_LIB) tests/st_suite.sh $(OUT)/samaltak.image -- NvCudaComputeTest NvComputeGPUTest NvFragmentShaderTest CudaGpuTest CudaSolverGpuTest CudaFFTGpuTest CudaFusionGpuTest CudaShowcaseGpuTest GpuToolsGpuTest $(if $(CUOPT_LIB),CuOptGpuTest)
	tests/rerun.sh nv-kernels tests/nv/run.sh $(OUT)
# test-tools's parts run at once too (TEST_TOOLS_JOBS, all by default; 1: one after another), the longest first, each
# holding a test slot and, with SAMALTAK_TEST_XVFB=1 (tests/stages.sh), on an Xvfb of its own (tests/with-display).
TEST_TOOLS_PARTS := rfb platform reboot desktop snapshot recording cli auth quit-signal
TEST_TOOLS_JOBS ?= $(words $(TEST_TOOLS_PARTS))
TOOLS_PART = tests/with-slot tests/with-display
test-tools: $(TEST_IMAGE)
	$(PLATFORM_CHECK)
	$(MAKE) -k $(call TEST_PARTS_SYNC,$(TEST_TOOLS_JOBS)) $(addprefix test-tools-rerun-,$(TEST_TOOLS_PARTS))
test-tools-part-platform:
	$(TOOLS_PART) $(MAKE) -C vm/platform test st-test
test-tools-part-cli:
	$(TOOLS_PART) tests/remote/cli_test.sh $(OUT)/samaltak.image
test-tools-part-auth:
	$(TOOLS_PART) tests/remote/auth_test.sh $(OUT)/samaltak.image
test-tools-part-recording:
	$(TOOLS_PART) tests/remote/recording_test.sh $(OUT)/samaltak.image
test-tools-part-rfb:
	SLOT_PRIORITY=1 $(TOOLS_PART) tests/remote/rfb_test.sh $(OUT)/samaltak.image
test-tools-part-desktop:
	$(TOOLS_PART) tests/tools/desktop_test.sh $(OUT)/samaltak.image
test-tools-part-snapshot:
	$(TOOLS_PART) tests/tools/snapshot_test.sh $(OUT)/samaltak.image
test-tools-part-reboot:
	$(TOOLS_PART) tests/tools/reboot_test.sh $(OUT)/samaltak.image
test-tools-part-quit-signal:
	$(TOOLS_PART) tests/tools/quit_signal_test.sh $(OUT)/samaltak.image
# The Renderer's raster work as CUDA kernels for the NVIDIA GB10 (gpu/nv, docs/nv-kernels.md): rebuild the cubin with
# nvcc and regenerate src/System-Devices/NvRasterKernels.st. Not part of test or CI.
nv-kernels:
	tools/nv-kernels.py build

# The image's shipped GLSL fragment shaders (ShaderViews': Claude's Robot) compiled for the GB10 by NVRTC
# (docs/nv-shaders.md): regenerate src/Graphics-NV/NvPrecompiledShaders.st, then build the image again. Needs NVRTC
# (the CUDA toolkit), not the GPU. Not part of test or CI; make test-nv fails while they are stale.
nv-shaders: $(OUT)/samaltak.image
	tools/nv-shaders.sh $(OUT)

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
# each way (test-uefi-nic: on a virtio-net-pci too
# if UEFI_NIC is another, once to ping), snapshots and resumes, and restarts by the firmware's ResetSystem (Firmware restart, the World menu's System › Restart).
comma := ,
UEFI_HOST_ARCH := $(if $(filter x86_64 amd64,$(shell uname -m)),x86_64,arm64)
UEFI_ARCH ?= $(UEFI_HOST_ARCH)
UEFI := $(OUT)/uefi-$(UEFI_ARCH)
UEFI_ARGS ?= --headless --eval 'Smalltalk vmBanner'
# UEFI_VM_ARGS: the VM's options, before the image (disk:), such as --jit baseline --jit-threshold 0; UEFI_ARGS after it
# are the image's, where a --jit is no option of the VM's.
UEFI_VM_ARGS ?=
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
# UEFI_VNC=N: uefi-ui and uefi-control show the screen on QEMU's VNC server on 127.0.0.1:590N instead of a window (from
# another machine: ssh -L 590N:127.0.0.1:590N, then vnc://localhost:590N), its password the file UEFI_VNC_PASSWORD (at most
# 8 characters). The fallback to UEFI_DISPLAY below, the image's own server (samaltak-ctl open --uefi --vnc N's default).
UEFI_VNC ?=
UEFI_VNC_PASSWORD ?= $(HOME)/.samaltak-vnc
UEFI_VNC_DISPLAY = -object secret,id=vncpw,file=$(UEFI_VNC_PASSWORD) -display vnc=127.0.0.1:$(UEFI_VNC),password-secret=vncpw
# UEFI_DISPLAY=N: uefi-ui and uefi-control show the screen through the image's own remote display server (RFB, --display
# on port 5900 in the guest) forwarded from 127.0.0.1:5900+N, and QEMU has no display (-display none; UEFI_DISPLAY wins
# over UEFI_VNC). Its VNC password: the file UEFI_DISPLAY_PASSWORD_FILE (at most 8 characters; by default ~/.samaltak-vnc
# where present, UEFI_VNC's, so a viewer's saved password works with both servers), written into samaltak.args
# (--display-password, mode 0600, as the control token: the image has no files on UEFI), never on a command line, else one the image makes and shows at start (display: password ...).
# docs/remote.md, Remote display.
UEFI_DISPLAY ?=
UEFI_DISPLAY_PASSWORD_FILE ?= $(wildcard $(HOME)/.samaltak-vnc)
UEFI_DISPLAY_PORT = $(shell expr 5900 + $(UEFI_DISPLAY))
UEFI_DISPLAY_FWD = $(if $(UEFI_DISPLAY),$(comma)hostfwd=tcp:127.0.0.1:$(UEFI_DISPLAY_PORT)-:5900)
UEFI_DISPLAY_ARGS = $(if $(UEFI_DISPLAY),--display --display-host 0.0.0.0 --display-port 5900 --display-vnc-auth)
# The remote display's password into a samaltak.args (mode 0600): the password in the file $1 (blanks and newlines
# dropped; 1 to 8 characters) appended to $2 as --display-password; nothing without $1.
DISPLAY_PASSWORD = $(if $(1),p="$$(tr -d ' \n' < $(1))" && [ -n "$$p" ] && [ $$(printf %s "$$p" | wc -c) -le 8 ] || { echo "$(1): not a VNC password of 1 to 8 characters" >&2; exit 1; }; printf '%s\n' --display-password "$$p" >> $(2))
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
# UEFI_AFFINITY: the host CPUs QEMU runs on (tools/qemu-pin.sh; docs/uefi.md, Pinning): big, the cores of the highest
# maximum frequency where there is more than one kind (Linux; the DGX Spark's X925s, where an A725 is half as fast),
# each vCPU on one of its own and no more vCPUs than cores; a taskset list (5-9,15-19); empty or none, anywhere. The
# World (uefi-ui, uefi-control, so samaltak-ctl open --uefi) runs on big unless it is set; uefi-run, uefi-boot and the
# tests anywhere, as gates run at once.
UEFI_PIN = $(UEFI_AFFINITY)
uefi-ui uefi-control: UEFI_PIN = $(if $(filter undefined,$(origin UEFI_AFFINITY)),big,$(UEFI_AFFINITY))
QEMU_UEFI = $(QEMU_UEFI_MACHINE) -m $(UEFI_MEM) -no-reboot \
	-nic user,model=$(UEFI_NIC)$(if $(UEFI_CONTROL_PORT),$(comma)hostfwd=tcp:127.0.0.1:$(UEFI_CONTROL_PORT)-:7341)$(UEFI_DISPLAY_FWD) -global $(UEFI_NIC).romfile= \
	-device virtio-rng-pci -drive if=pflash,format=raw,readonly=on,file=$(OVMF_CODE) -drive if=pflash,format=raw,file=$(UEFI_RUN)/vars.fd \
	-drive format=raw,file=fat:rw:$(UEFI_RUN)/esp -drive format=raw,file=$(UEFI_RUN)/image.disk
uefi: fresh-image
	$(MAKE) $(UEFI)/esp/EFI/BOOT/$(UEFI_BOOT) $(UEFI)/image.disk
$(UEFI)/esp/EFI/BOOT/$(UEFI_BOOT): $(OUT)/samaltak.image vm/uefi.mk
	rm -rf $(UEFI)/gen
	mkdir -p $(UEFI)/esp/EFI/BOOT
	$(VM) $(OUT)/samaltak.image --headless --eval "[VMTranslator generateVMInto: '$(UEFI)/gen' os: #uefi arch: #$(UEFI_ARCH). 'ok'] on: Error do: [:e | Transcript show: e messageText; cr. Smalltalk quit: 1]"
	$(MAKE) $(BUILD_JOBS) -f vm/uefi.mk GEN=$(UEFI)/gen OBJ=$(UEFI)/obj UEFI_TARGET=$(UEFI_TARGET)
	$(VM) $(OUT)/samaltak.image --headless --eval "UefiImageWriter new convert: '$(UEFI)/obj/samaltak.elf' to: '$(UEFI)/esp/EFI/BOOT/$(UEFI_BOOT)'"
$(UEFI)/image.disk: $(OUT)/samaltak.image
	$(VM) $(OUT)/samaltak.image --headless --eval "UefiImageDisk new write: '$(OUT)/samaltak.image' to: '$(UEFI)/image.disk'"
	truncate -s $(UEFI_DISK_MB)M $(UEFI)/image.disk
# UEFI_RUN: the directory of a boot's state, its ESP (esp/: the EFI application and samaltak.args), image disk, firmware
# variables (vars.fd) and console.log: $(UEFI) by default; another (test-uefi's parts, so that they boot at once) gets
# copies of $(UEFI)'s EFI application and image disk the first time (a snapshot stays in it). UEFI_SLOT: a command QEMU
# runs under (test-uefi: tests/with-slot, a test slot each).
UEFI_RUN ?= $(UEFI)
UEFI_SLOT ?=
CP_SPARSE := $(if $(filter Darwin,$(shell uname -s)),-c,--sparse=always)
UEFI_RUN_DIR = $(if $(filter-out $(UEFI),$(UEFI_RUN)),mkdir -p $(UEFI_RUN)/esp/EFI/BOOT \
	&& { [ -f $(UEFI_RUN)/esp/EFI/BOOT/$(UEFI_BOOT) ] || cp $(UEFI)/esp/EFI/BOOT/$(UEFI_BOOT) $(UEFI_RUN)/esp/EFI/BOOT/; } \
	&& { [ -f $(UEFI_RUN)/image.disk ] || cp $(CP_SPARSE) $(UEFI)/image.disk $(UEFI_RUN)/image.disk; })
uefi-run: uefi
	$(MAKE) uefi-boot
uefi-boot:
	$(UEFI_RUN_DIR)
	printf '%s\n' --max-heap $(UEFI_HEAP) $(UEFI_VM_ARGS) disk: $(UEFI_ARGS) > $(UEFI_RUN)/esp/samaltak.args
	cp $(OVMF_VARS) $(UEFI_RUN)/vars.fd
	$(UEFI_SLOT) tools/qemu-pin.sh '$(UEFI_PIN)' $(QEMU_UEFI) -nographic | tee $(UEFI_RUN)/console.log
	@grep -q 'samaltak: exit 0' $(UEFI_RUN)/console.log
uefi-ui: uefi
	$(UEFI_RUN_DIR)
	rm -f $(UEFI_RUN)/esp/samaltak.args && umask 077 && printf '%s\n' --max-heap $(UEFI_HEAP) $(UEFI_VM_ARGS) disk: --window-size $(UEFI_SCREEN) $(UEFI_DISPLAY_ARGS) > $(UEFI_RUN)/esp/samaltak.args
	$(call DISPLAY_PASSWORD,$(if $(UEFI_DISPLAY),$(UEFI_DISPLAY_PASSWORD_FILE)),$(UEFI_RUN)/esp/samaltak.args)
	cp $(OVMF_VARS) $(UEFI_RUN)/vars.fd
	$(if $(UEFI_DISPLAY)$(UEFI_VNC),,$(UEFI_WINDOW)) tools/qemu-pin.sh '$(UEFI_PIN)' $(QEMU_UEFI) $(UEFI_QEMU_DISPLAY) $(UEFI_VGA) -device qemu-xhci -device usb-kbd -device virtio-tablet-pci -serial stdio
uefi-control: uefi
	$(UEFI_RUN_DIR)
	rm -f $(UEFI_RUN)/esp/samaltak.args && umask 077 && printf '%s\n' --max-heap $(UEFI_HEAP) $(UEFI_VM_ARGS) disk: --control --control-host 0.0.0.0 --control-port 7341 \
		$${UEFI_CONTROL_TOKEN:+--control-token "$$UEFI_CONTROL_TOKEN"} $(UEFI_DISPLAY_ARGS) $(UEFI_CONTROL_ARGS) > $(UEFI_RUN)/esp/samaltak.args
	$(call DISPLAY_PASSWORD,$(if $(UEFI_DISPLAY),$(UEFI_DISPLAY_PASSWORD_FILE)),$(UEFI_RUN)/esp/samaltak.args)
	cp $(OVMF_VARS) $(UEFI_RUN)/vars.fd
	$(UEFI_SLOT) tools/qemu-pin.sh '$(UEFI_PIN)' $(QEMU_UEFI) $(if $(UEFI_DISPLAY)$(UEFI_VNC),$(UEFI_QEMU_DISPLAY),-display none) $(UEFI_VGA) -device qemu-xhci -device usb-kbd -device virtio-tablet-pci -serial stdio
UEFI_TESTS := CompilerTest ParserTest ScannerTest ClassTest CollectionTest ContextTest ExceptionTest FloatTest FractionTest \
	HashingTest ImmutabilityTest IntegerTest LazyContextTest MarriedContextTest MessageNotUnderstoodTest ObjectTest ProcessTest \
	StackOverflowTest StreamTest StringSearchTest StringTest SymbolTest SystemChangesTest SystemTest UnicodeTest WorkClockTest \
	Amd64DisassemblerTest Arm64DisassemblerTest ByteSearchTest FFIBindingTest \
	GitHubClientTest SourceFilerGitHubTest SourceUpdateTest PosixDeviceTest ZLibTest PNGCodecTest AgentImageTest \
	SoftwareGPUTest FrameTapTest PixelPackTest
UEFI_WORLD := | w t | w := UIWindows startUp. RemoteInputDevice default inject: {1. nil. 123. 45. 0. 0. nil. w displayWindow windowId}. t := Time millisecondClockValue. [w dispatcher pointer = (123 @ 45) or: [Time millisecondClockValue - t > 20000]] whileFalse: [(Delay forMilliseconds: 50) wait]. Smalltalk vm stderrWrite: 'world ', w extent printString, ' ', Renderer default device isSoftware printString, ' ', w dispatcher pointer rounded printString, (String with: Character lf)
UEFI_NET := | s buf n | s := RemoteSocket connectTo: '10.0.2.2' port: $$P timeout: 20000. s sendAll: '{\"cmd\": \"ping\", \"auth\": \"', ControlServer current token, '\"}', (String with: Character lf). buf := ByteArray new: 200. n := s receiveInto: buf timeout: 20000. s close. (buf copyFrom: 1 to: n) asString
UEFI_NET_BULK := | src req s buf n chunk out t ms resp ok more | src := String new: 1000000. 1 to: src size do: [:i | src at: i put: (Character value: 97 + (i * 7 rem: 26))]. req := '{\"cmd\": \"eval\", \"auth\": \"', ControlServer current token, '\", \"source\": \"''', src, ''' reverse\"}', (String with: Character lf). t := Time millisecondClockValue. s := RemoteSocket connectTo: '10.0.2.2' port: $$P timeout: 20000. s sendAll: req. out := WriteStream on: (String new: 1100000). buf := ByteArray new: 65536. more := true. [more] whileTrue: [n := s receiveInto: buf timeout: 60000. chunk := (buf copyFrom: 1 to: n) asString. out nextPutAll: chunk. more := n > 0 and: [(chunk includes: Character lf) not]]. ms := Time millisecondClockValue - t. s close. resp := out contents. ok := (resp includesSubstring: '\"ok\":true') and: [resp includesSubstring: src reverse]. 'bulk ', ok printString, ' ', (req size + resp size) printString, ' bytes in ', ms printString, ' ms'
UEFI_NET_DRIVER := 'driver ', NetworkStack active interface class name
UEFI_DRIVER = $(if $(filter e1000e,$(1)),E1000eInterface,VirtioNetInterface)
UEFI_RESET := Smalltalk vm stderrWrite: 'menu ', ((((ToolsMenu worldMenuAt: nil) itemLabeled: 'System') submenu) selectableItems collect: [:i | i label]) asArray printString, (String with: Character lf). Firmware restart
UEFI_SNAPSHOT := Smalltalk at: 'UefiMark' asSymbol put: 42. (Smalltalk snapshot: Smalltalk vm imagePath) ifTrue: ['resumed ', (Smalltalk at: 'UefiMark' asSymbol) printString, ' ', (SecureRandom default nextBytes: 16) hex] ifFalse: ['saved']
# test-uefi's parts boot at once (make -j UEFI_TEST_JOBS, default nproc / 2; 1: one after another), each QEMU holding
# one of the machine's test slots (tests/with-slot), each part in a boot directory of its own, $(UEFI)/run-<part>
# (UEFI_RUN), its output shown when it ends (make -O); the snapshot's three boots one after another in theirs. Every
# part runs to its end (-k), and the boot directories stay for a look when one fails.
UEFI_TEST_JOBS ?= $(shell n=$$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2); echo $$(( n > 1 ? n / 2 : 1 )))
UEFI_TEST_PARTS = tests cutover lowspace reset world world-gpu rfb net $(if $(filter-out virtio-net-pci,$(UEFI_NIC)),nic) snapshot \
	$(if $(filter arm64,$(UEFI_ARCH)),x86-jit)
# make 3.81 (macOS's) has no -O: there the parts run one after another
UEFI_TEST_SYNC = $(call TEST_PARTS_SYNC,$(UEFI_TEST_JOBS))
UEFI_PART_RUN = $(UEFI)/run-$(patsubst test-uefi-part-%,%,$@)
UEFI_PART_BOOT = uefi-boot UEFI_RUN=$(UEFI_PART_RUN) UEFI_SLOT=tests/with-slot
UEFI_PART_LOG = $(UEFI_PART_RUN)/console.log
# what starts a samaltak-ctl session (make uefi-control) for a part: its boot directory, and none of this make's flags
# (its -O would hold the session's console back until QEMU ends). Its slot is taken before the session picks its
# ports (rfb), or not at all (the short network sessions): a QEMU waiting for a slot would leave time for another
# session to take the port it was given.
UEFI_PART_ENV = MAKEFLAGS= UEFI_RUN=$(UEFI_PART_RUN) UEFI_AFFINITY=$(UEFI_AFFINITY) OUT=$(OUT)
test-uefi:
	rm -rf $(UEFI)/image.disk $(UEFI)/run-*
	$(MAKE) uefi
	$(MAKE) -k $(UEFI_TEST_SYNC) $(addprefix test-uefi-rerun-,$(UEFI_TEST_PARTS))
	rm -rf $(UEFI)/image.disk $(UEFI)/run-*
test-uefi-part-cutover:
	$(MAKE) $(UEFI_PART_BOOT) UEFI_ARGS="--headless --eval \"$$(tr '\n' ' ' < tests/boot/uefi_cutover.st)\""
	grep -Fq 'UEFI cutover OK' $(UEFI_PART_LOG)
	grep -Fq 'UEFI-stdout-π' $(UEFI_PART_LOG)
	grep -Fq 'UEFI-stderr-é' $(UEFI_PART_LOG)
test-uefi-part-tests:
	$(MAKE) $(UEFI_PART_BOOT) UEFI_ARGS='--headless --test $(UEFI_TESTS)'
test-uefi-part-lowspace:
	$(MAKE) $(UEFI_PART_BOOT) UEFI_HEAP_MB=128 UEFI_ARGS='--headless --test LowSpaceTest StackOverflowTest'
test-uefi-part-reset:
	-$(MAKE) $(UEFI_PART_BOOT) UEFI_ARGS="--headless --eval \"$(UEFI_RESET)\""
	grep -q "^samaltak: reset cold" $(UEFI_PART_LOG) && grep -q "'Restart' 'Warm restart' 'Power off'" $(UEFI_PART_LOG)
test-uefi-part-world:
	$(MAKE) $(UEFI_PART_BOOT) UEFI_ARGS="--eval \"$(UEFI_WORLD)\""
	grep -qE "^world [0-9]+@[0-9]+ true 123@45" $(UEFI_PART_LOG)
test-uefi-part-world-gpu:
	$(MAKE) $(UEFI_PART_BOOT) UEFI_GPU=virtio-gpu-pci UEFI_ARGS="--window-size 1920x1080 --eval \"$(UEFI_WORLD)\""
	grep -qE "^world 1920@1080 true 123@45" $(UEFI_PART_LOG)
test-uefi-part-rfb:
	SLOT_PRIORITY=1 $(UEFI_PART_ENV) tests/with-slot tests/remote/rfb_test.sh --uefi
test-uefi-part-net:
	$(UEFI_PART_ENV) tools/samaltak-ctl --session uefi-test open --uefi --headless
	P=$$(sed -n 's/.*"port": \([0-9]*\).*/\1/p' $${TMPDIR:-/tmp}/samaltak-ctl/uefi-test.json); N=$(UEFI_PART_RUN)/net.log; \
	tools/samaltak-ctl --session uefi-test eval "$(UEFI_NET_DRIVER)" > $$N; ok=$$?; \
	[ $$ok = 0 ] && { tests/remote/auth_test.sh --session uefi-test >> $$N; ok=$$?; }; \
	[ $$ok = 0 ] && { tools/samaltak-ctl --session uefi-test eval "$(UEFI_NET)" >> $$N; ok=$$?; }; \
	[ $$ok = 0 ] && { tools/samaltak-ctl --session uefi-test eval "$(UEFI_NET_BULK)" >> $$N; ok=$$?; }; \
	tools/samaltak-ctl --session uefi-test close; cat $$N; [ $$ok = 0 ] && grep -q pong $$N && grep -q "'bulk true" $$N \
		&& grep -q "'driver $(call UEFI_DRIVER,$(UEFI_NIC))'" $$N
test-uefi-part-nic:
	$(MAKE) test-uefi-nic UEFI_NIC=virtio-net-pci UEFI_RUN=$(UEFI_PART_RUN)
# x86-64 where test-uefi boots arm64: nothing else boots the x86-64 VM there, so its JIT's two tiers run tests under QEMU's
# emulation (TCG), every method compiled at its first activation; without x86-64 firmware (OVMF) it says it skipped.
UEFI_X86_TESTS := IntegerTest FloatTest StringTest CollectionTest
UEFI_X86_RUN = $(OUT)/uefi-x86_64/run-x86-jit
UEFI_X86_BOOT = uefi-boot UEFI_ARCH=x86_64 UEFI_RUN=$(UEFI_X86_RUN) UEFI_SLOT=tests/with-slot UEFI_ARGS='--headless --test $(UEFI_X86_TESTS)'
test-uefi-part-x86-jit:
	@if [ -z "$$($(MAKE) -s --no-print-directory uefi-firmware UEFI_ARCH=x86_64)" ]; then echo 'test-uefi: no x86-64 firmware (OVMF): the x86-64 boot skipped'; exit 0; fi; \
	rm -rf $(UEFI_X86_RUN) && $(MAKE) uefi UEFI_ARCH=x86_64 \
	&& $(MAKE) $(UEFI_X86_BOOT) UEFI_VM_ARGS='--jit baseline --jit-threshold 0' \
	&& $(MAKE) $(UEFI_X86_BOOT) UEFI_VM_ARGS='--jit opt --jit-threshold 0 --jit-flags eager'
uefi-firmware:
	@echo $(OVMF_CODE)
test-uefi-part-snapshot:
	$(MAKE) $(UEFI_PART_BOOT) UEFI_ARGS="--headless --eval \"$(UEFI_SNAPSHOT)\""
	grep -q "'saved'" $(UEFI_PART_LOG)
	$(MAKE) $(UEFI_PART_BOOT) UEFI_ARGS=--headless
	grep -o "'resumed 42 [0-9A-F]*'" $(UEFI_PART_LOG) > $(UEFI_PART_RUN)/resumed.txt && [ -s $(UEFI_PART_RUN)/resumed.txt ]
	$(MAKE) $(UEFI_PART_BOOT) UEFI_ARGS=--headless
	grep -o "'resumed 42 [0-9A-F]*'" $(UEFI_PART_LOG) | { read -r again; [ -n "$$again" ] && [ "$$again" != "$$(cat $(UEFI_PART_RUN)/resumed.txt)" ]; } \
		|| { echo 'test-uefi: a snapshot resumed twice answered the same SecureRandom bytes'; exit 1; }
test-uefi-nic:
	MAKEFLAGS= UEFI_RUN=$(UEFI_RUN) UEFI_SLOT=$(UEFI_SLOT) UEFI_NIC=$(UEFI_NIC) UEFI_AFFINITY=$(UEFI_AFFINITY) OUT=$(OUT) tools/samaltak-ctl --session uefi-test-nic open --uefi --headless
	P=$$(sed -n 's/.*"port": \([0-9]*\).*/\1/p' $${TMPDIR:-/tmp}/samaltak-ctl/uefi-test-nic.json); \
	tools/samaltak-ctl --session uefi-test-nic eval "$(UEFI_NET_DRIVER)" > $(UEFI_RUN)/net.log; ok=$$?; \
	[ $$ok = 0 ] && { tools/samaltak-ctl --session uefi-test-nic eval "$(UEFI_NET)" >> $(UEFI_RUN)/net.log; ok=$$?; }; \
	tools/samaltak-ctl --session uefi-test-nic close; cat $(UEFI_RUN)/net.log; [ $$ok = 0 ] && grep -q pong $(UEFI_RUN)/net.log \
		&& grep -q "'driver $(call UEFI_DRIVER,$(UEFI_NIC))'" $(UEFI_RUN)/net.log

# The Linux appliance (docs/linux-appliance.md): Ubuntu's NVIDIA kernel booted by its EFI stub with an initramfs of
# busybox (PID 1), the hosted VM and image, SDL3 for KMS/DRM, into OUT/linux-appliance; LINUX_GPU=virtio (QEMU, the
# default: the image's KMS screen), mesa (QEMU, SDL's kmsdrm) or nvidia (the DGX Spark: the open kernel modules, GSP
# firmware, and the CUDA root below: the World on libcuda; nvidia-vulkan adds NVIDIA's Vulkan). linux-appliance-run boots
# it in QEMU (arm64, KVM), linux-appliance-test end to end: the World on KMS, control, HTTPS, RFB, input, power off.
linux-appliance: fresh-image
	OUT=$(OUT) tools/linux-appliance/build.sh
linux-appliance-run:
	OUT=$(OUT) tools/linux-appliance/run.sh
linux-appliance-test: linux-appliance
	OUT=$(OUT) tools/linux-appliance/test.sh
# The appliance on a USB stick: a UKI (systemd's stub, kernel, initramfs, command line) and a GPT image with an ESP
# (removable media boot, install.sh for the NVMe) and the data volume; its test boots it in QEMU from a USB stick.
linux-appliance-usb: linux-appliance
	OUT=$(OUT) tools/linux-appliance/usb.sh
linux-appliance-usb-test: linux-appliance-usb
	OUT=$(OUT) tools/linux-appliance/usb-test.sh
# The CUDA root (docs/cuda.md): NVIDIA's driver userspace of nvidia.ko's version, the toolkit's cu* libraries and
# cuOpt in OUT/linux-appliance/samaltak-cuda-13.squashfs, which rcS mounts at /opt/cuda and linux-appliance-usb puts
# on the stick. make linux-appliance LINUX_GPU=nvidia makes it after the root (LINUX_CUDA=none: without);
# linux-appliance-cuda makes it again for the nvidia root there. linux-appliance-cuda-test boots the nvidia variant
# in QEMU (no GPU: the libraries load and say so, the World is in software); linux-appliance-cuda-check runs its root
# with the CUDA root on this machine's GPU (chroot in a mount namespace: sudo).
linux-appliance-cuda:
	OUT=$(OUT) tools/linux-appliance/cuda.sh
linux-appliance-cuda-test linux-appliance-cuda-check: export LINUX_GPU = nvidia
linux-appliance-cuda-test: linux-appliance
	OUT=$(OUT) tools/linux-appliance/cuda-test.sh
linux-appliance-cuda-check: linux-appliance
	OUT=$(OUT) tools/linux-appliance/cuda-check.sh


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
	rm -rf build vm/build/ffi-test-exports vm/build/ffi-no-platform

.PHONY: $(addprefix test-uefi-part-,$(UEFI_TEST_PARTS)) $(addprefix test-core-part-,$(TEST_CORE_PARTS)) $(addprefix test-tools-part-,$(TEST_TOOLS_PARTS)) all vm seed image fresh-image run translate uefi uefi-run uefi-boot uefi-ui uefi-control uefi-firmware test-uefi test-uefi-nic test-vm test-jit test-jit-none test-jit-baseline test-jit-opt test-jit-deopt test-jit-cache test-core test-tools test-nv nv-kernels nv-shaders test video mindblown-video jit-video clean

.PHONY: test-ffi-arity test-ffi-bigint-owned test-ffi-gpu-paged test-ffi-headless test-ffi-no-platform test-ffi-display
