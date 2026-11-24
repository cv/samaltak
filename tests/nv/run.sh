#!/bin/sh
# make test-nv: the raster kernels (gpu/nv) on this machine's NVIDIA GPU, against PlatformRaster (tests/nv/README.md).
# Needs an NVIDIA GPU, its driver (libcuda) and cuda.h (CUDA_HOME, default /usr/local/cuda), not nvcc: the cubin is the
# one checked in as NvRasterKernels. Not part of make test or CI.
#   tests/nv/run.sh [OUT]     OUT: the build directory with samaltak.image (default build)
# NV_FUZZ (default 20000) random cases; NV_FRAMES (default 6) frames of the World recorded at 1920x1080.
set -e
OUT=${1:-build}
NV=$OUT/nv
CUDA=${CUDA_HOME:-/usr/local/cuda}
CC=${CC:-cc}
CXX=${CXX:-c++}
mkdir -p "$NV"
python3 tools/nv-kernels.py extract "$NV/raster.cubin"
# the C reference twice: without contraction (as the UEFI VM) and with gcc's default (as the hosted VM on Linux)
for m in off fma; do
	c=off; [ $m = fma ] && c=fast
	$CC -O2 -std=gnu11 -D_GNU_SOURCE -fsigned-char -Ivm/gen -Ivm/native -ffp-contract=$c \
		-Drasterize=ref_${m}_rasterize -Dblit_pixels=ref_${m}_blit_pixels -Dplatform_raster_copy=ref_${m}_copy -Dplatform_raster_fill=ref_${m}_fill -Dquad_bounds=ref_${m}_quad_bounds \
		-Dplatform_raster_forced_bands=ref_${m}_forced_bands \
		-c vm/gen/platform_raster.c -o "$NV/ref_$m.o"
done
# the raster's bands run one after the other here
$CC -O2 -std=gnu11 -D_GNU_SOURCE -Ivm/gen -Ivm/native -c vm/gen/no_cpu_workers.c -o "$NV/no_cpu_workers.o"
$CXX -O2 -std=c++17 -I"$CUDA/include" tests/nv/replay.cpp "$NV/ref_off.o" "$NV/ref_fma.o" "$NV/no_cpu_workers.o" -o "$NV/replay" -lcuda
"$NV/replay" fuzz "$NV/raster.cubin" "${NV_FUZZ:-20000}"
"$NV/replay" fuzzbatch "$NV/raster.cubin" "${NV_FUZZ:-20000}"
NV_RECORD="$NV/world.nvrec" NV_FRAMES="${NV_FRAMES:-6}" vm/build/samaltak "$OUT/samaltak.image" --headless --eval "$(cat tests/nv/record.st)"
"$NV/replay" replay "$NV/raster.cubin" "$NV/world.nvrec" 3
# the same frames through the image's NvComputeGPU (Graphics-NV: System-NV launching the kernels) and its SoftwareGPU
NV_RECORD="$NV/world.nvrec" vm/build/samaltak "$OUT/samaltak.image" --headless --eval "$(cat tests/nv/replay.st)"
# the World hosted on the NvComputeGPU (SAMALTAK_GPU=nv) under a private Xvfb, screenshot against the SoftwareGPU's
tests/nv/world_test.sh "$OUT"
echo "make test-nv: passed"
