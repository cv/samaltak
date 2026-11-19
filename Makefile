# Samaltak: VM, seed image (the Smalltalk ImageBuilder, run in boot/seed.image), full image (stage 2), tests.
# OUT selects the build directory, so concurrent builds do not collide: make image OUT=build/me
OUT ?= build

VM := vm/build/samaltak

all: vm seed image

vm:
	$(MAKE) -C vm

seed: vm
	boot/build-image.sh src $(OUT)/seed.image

image: vm seed
	$(VM) $(OUT)/seed.image --headless --stage2 $(OUT)/samaltak.image

# Start the system. The image is rebuilt only if src/, boot/ or the VM are newer, so an image saved from the World menu stays.
run: vm
	@[ -f $(OUT)/samaltak.image ] && [ -z "$$(find src boot $(VM) -newer $(OUT)/samaltak.image | head -1)" ] || $(MAKE) image
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
test-jit: image
	$(MAKE) test-jit-none
	$(MAKE) test-jit-baseline
	$(MAKE) test-jit-opt
	$(MAKE) test-jit-deopt
	$(MAKE) test-jit-cache
test-jit-none: image
	tests/st_suite.sh $(OUT)/samaltak.image --jit none
test-jit-baseline: image
	tests/st_suite.sh $(OUT)/samaltak.image --jit baseline --jit-threshold 0
test-jit-opt: image
	tests/st_suite.sh $(OUT)/samaltak.image --jit opt --jit-threshold 0 --jit-flags eager
test-jit-deopt: image
	tests/st_suite.sh $(OUT)/samaltak.image --jit opt --jit-threshold 0 --jit-flags eager,deopt
test-jit-cache: image
	tests/st_suite.sh $(OUT)/samaltak.image --jit opt --jit-threshold 0 --jit-cache $(STRESS_CACHE_MB) --jit-flags eager,notes -- Tests-Kernel

# Everything, in stages (CI runs them as separate jobs); any failure, skipped test or headless-only VM fails it. The UI
# scripts use a hidden window.
test: test-core
	$(MAKE) test-jit
	$(MAKE) test-tools
	$(MAKE) test-uefi
	@echo "make test: all passed"
PLATFORM_CHECK = @[ -f vm/build/.variant-platform ] || { echo "make test: FAILED: the VM was built without the platform layer (SDL3), UI tests would not run"; exit 1; }
test-core: image test-vm
	$(PLATFORM_CHECK)
	tests/vm/gen_test.sh $(OUT)/samaltak.image
	tests/boot/layering_test.sh
	tests/st_suite.sh $(OUT)/samaltak.image
	SAMALTAK_VERIFY_GC=1 tests/st_suite.sh $(OUT)/samaltak.image --eden 1 -- Tests-Kernel Tests-Compiler
test-tools: image
	$(PLATFORM_CHECK)
	$(MAKE) -C vm/platform test st-test
	tests/remote/cli_test.sh $(OUT)/samaltak.image
	tests/remote/recording_test.sh $(OUT)/samaltak.image
	tests/tools/desktop_test.sh $(OUT)/samaltak.image
	tests/tools/snapshot_test.sh $(OUT)/samaltak.image
	tests/tools/reboot_test.sh $(OUT)/samaltak.image

# The headless VM as a UEFI application for x86-64, translated from the same Lowtalk with VM-UEFI in place of the C
# library (docs/uefi.md): $(UEFI)/esp is a boot volume with it (EFI/BOOT/BOOTX64.EFI), the image and samaltak.args (the
# command line, an argument a line). uefi-run boots it in QEMU with OVMF (KVM if there is /dev/kvm) and fails unless the
# VM exits 0; UEFI_ARGS are its arguments. test-uefi runs the tests there that need no platform layer (no files,
# processes or ptys from Smalltalk).
UEFI := $(OUT)/uefi
UEFI_ARGS ?= --headless --eval 'Smalltalk vmBanner'
UEFI_HEAP_MB ?= 256
OVMF_CODE ?= $(firstword $(wildcard /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd /opt/homebrew/share/qemu/edk2-x86_64-code.fd /usr/share/qemu/edk2-x86_64-code.fd))
OVMF_VARS ?= $(firstword $(wildcard /usr/share/OVMF/OVMF_VARS_4M.fd /usr/share/OVMF/OVMF_VARS.fd /opt/homebrew/share/qemu/edk2-i386-vars.fd /usr/share/qemu/edk2-i386-vars.fd))
QEMU_UEFI = qemu-system-x86_64 -machine q35 -m 2048 -nographic -net none -no-reboot $(if $(wildcard /dev/kvm),-accel kvm -cpu host) \
	-drive if=pflash,format=raw,readonly=on,file=$(OVMF_CODE) -drive if=pflash,format=raw,file=$(UEFI)/vars.fd \
	-drive format=raw,file=fat:rw:$(UEFI)/esp
uefi: image
	rm -rf $(UEFI)/gen
	mkdir -p $(UEFI)/esp/EFI/BOOT
	$(VM) $(OUT)/samaltak.image --headless --eval "[VMTranslator generateVMInto: '$(UEFI)/gen' os: #uefi arch: #x86_64. 'ok'] on: Error do: [:e | Transcript show: e messageText; cr. Smalltalk quit: 1]"
	$(MAKE) -f vm/uefi.mk GEN=$(UEFI)/gen OBJ=$(UEFI)/obj
	$(VM) $(OUT)/samaltak.image --headless --eval "UefiImageWriter new convert: '$(UEFI)/obj/samaltak.elf' to: '$(UEFI)/esp/EFI/BOOT/BOOTX64.EFI'"
	cp $(OUT)/samaltak.image $(UEFI)/esp/samaltak.image
uefi-run: uefi
	printf '%s\n' --max-heap $(UEFI_HEAP_MB) samaltak.image $(UEFI_ARGS) > $(UEFI)/esp/samaltak.args
	cp $(OVMF_VARS) $(UEFI)/vars.fd
	$(QEMU_UEFI) | tee $(UEFI)/console.log
	@grep -q 'samaltak: exit 0' $(UEFI)/console.log
UEFI_TESTS := CompilerTest ParserTest ScannerTest ClassTest CollectionTest ContextTest ExceptionTest FloatTest FractionTest \
	HashingTest ImmutabilityTest IntegerTest LazyContextTest MarriedContextTest MessageNotUnderstoodTest ObjectTest ProcessTest \
	StackOverflowTest StreamTest StringSearchTest StringTest SymbolTest SystemChangesTest SystemTest UnicodeTest WorkClockTest \
	Amd64DisassemblerTest Arm64DisassemblerTest ByteSearchTest
test-uefi:
	$(MAKE) uefi-run UEFI_ARGS='--headless --test $(UEFI_TESTS)'

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

.PHONY: all vm seed image run translate uefi uefi-run test-uefi test-vm test-jit test-jit-none test-jit-baseline test-jit-opt test-jit-deopt test-jit-cache test-core test-tools test video mindblown-video jit-video clean
