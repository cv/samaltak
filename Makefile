# Samaltak: VM, seed image (Python bootstrapper), full image (stage 2 in Smalltalk), tests.
# OUT selects the build directory, so concurrent builds do not collide: make image OUT=build/me
OUT ?= build

PYTHON ?= python3
VM := vm/build/samaltak

all: vm seed image

vm:
	$(MAKE) -C vm

seed:
	@mkdir -p $(OUT)
	$(PYTHON) boot/bootstrap.py src $(OUT)/seed.image

image: vm seed
	$(VM) $(OUT)/seed.image --headless --stage2 $(OUT)/samaltak.image

test-vm: vm
	vm/tests/run.sh

# Everything; any failure, skipped test or headless-only VM fails it. The UI scripts use a hidden window.
test: image test-vm
	@[ -f vm/build/.variant-platform ] || { echo "make test: FAILED: the VM was built without the platform layer (SDL3), UI tests would not run"; exit 1; }
	tests/boot/layering_test.sh
	tests/st_suite.sh $(OUT)/samaltak.image
	SAMALTAK_VERIFY_GC=1 tests/st_suite.sh $(OUT)/samaltak.image --eden 1 -- Tests-Kernel Tests-Compiler
	$(MAKE) -C vm/platform test st-test
	tests/remote/cli_test.sh $(OUT)/samaltak.image
	tests/tools/desktop_test.sh $(OUT)/samaltak.image
	@echo "make test: all passed"

# The narrated walkthrough on the real system, from a copy of the image named nuuk.image like the prototype's (a visible window; needs ffmpeg, agent-browser for the captions and
# ELEVENLABS_API_KEY in .env unless the clips in $(VIDEO)/narration are cached).
VIDEO ?= .context/video-real
video: vm image
	cp $(OUT)/samaltak.image $(OUT)/nuuk.image
	node tools/narrate.mjs $(VIDEO)
	WALKTHROUGH_IMAGE=$(OUT)/nuuk.image node tools/walkthrough.mjs $(VIDEO)
	python3 tools/compose-video.py $(VIDEO)
	cp $(VIDEO)/walkthrough.mp4 docs/media/walkthrough.mp4

clean:
	$(MAKE) -C vm clean
	rm -rf build

.PHONY: all vm seed image test-vm test video clean
