#!/bin/sh
# make nv-shaders: the GLSL fragment shaders the image ships (every ShaderView's: Claude's Robot), compiled for the
# NVIDIA GB10 (sm_121) by NVRTC, through the image's own GLSL front end (Graphics-Shaders) and NvShaderCompiler, into
# src/Graphics-NV/NvPrecompiledShaders.st, so an NvComputeGPU runs them without a compiler (docs/nv-shaders.md). Needs
# NVRTC (the CUDA toolkit's libnvrtc; SAMALTAK_NVRTC names it), not the GPU. Run it again when a shipped shader or the
# front end changes, then build the image again; make test-nv fails while they are stale.
#   tools/nv-shaders.sh [OUT]     OUT: the build directory with samaltak.image (default build)
set -e
OUT=${1:-build}
DEST=src/Graphics-NV/NvPrecompiledShaders.st
vm/build/samaltak "$OUT/samaltak.image" --headless --eval "
	| s | s := NvShaderCompiler precompiledSource.
	File writeBytes: s asByteArray to: '$DEST.new'.
	NvShaderCompiler shippedSources size printString, ' shaders, ', s size printString, ' bytes'"
mv "$DEST.new" "$DEST"
echo "nv-shaders: wrote $DEST; build the image again (make image)"
