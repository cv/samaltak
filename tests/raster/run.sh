#!/bin/sh
# The raster primitives' C on recorded World frames (tests/raster/replay.c): records the first frames of the World at
# 1920x1080 once (tests/nv/record.st, about 150 MB), replays them on vm/gen/platform_raster.c compiled with CC and
# CFLAGS, compares every pass end and frame with the recorded pixels and prints the time of a 1920x1080 frame's raster
# work. Exits 1 if any pixel differs (the C must match what the VM that recorded produced: record again after changing
# its arithmetic). No GPU needed.
#   tests/raster/run.sh [OUT [PASSES]]   OUT: the build directory with samaltak.image (default build)
#   CC=clang CFLAGS='-O2 -ffp-contract=off' tests/raster/run.sh    as the UEFI VM compiles it
#   RASTER_BANDS=4 tests/raster/run.sh    the work split into bands as for 4 CPUs (UEFI), run one after the other
set -e
OUT=${1:-build}
PASSES=${2:-7}
CC=${CC:-cc}
CFLAGS=${CFLAGS:--O2}
mkdir -p "$OUT/raster"
REC=$OUT/raster/world.nvrec
if [ ! -f "$REC" ] || [ "$OUT/samaltak.image" -nt "$REC" ]; then
	NV_RECORD="$REC" NV_FRAMES="${NV_FRAMES:-6}" vm/build/samaltak "$OUT/samaltak.image" --headless --eval "$(cat tests/nv/record.st)"
fi
$CC $CFLAGS -std=gnu11 -D_GNU_SOURCE -fsigned-char -Ivm/gen -Ivm/native -o "$OUT/raster/replay" tests/raster/replay.c vm/gen/platform_raster.c -lm
"$OUT/raster/replay" "$REC" "$PASSES"
