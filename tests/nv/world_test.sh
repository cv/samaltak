#!/bin/sh
# make test-nv, part 3: the World hosted on an NvComputeGPU (SAMALTAK_GPU=nv: Graphics-NV, the raster kernels on this
# machine's NVIDIA GPU, presenting through SDL_GPU) on a private Xvfb, against the same World on a SoftwareGPU
# (SAMALTAK_GPU=software), both on the recording clock: the screenshots must be equal but for the top bar's frame time,
# which shows each device's own. The readouts of the machine's speed and load (the Mandelbrot's time to render, the
# Process Browser's CPU column and load meters) are frozen first (Tools freezeReadouts), once the Mandelbrot is done.
#   tests/nv/world_test.sh [OUT]
set -e
OUT=${1:-build}
NV=$OUT/nv
CTL=tools/samaltak-ctl
mkdir -p "$NV"
D=
for n in $(seq 170 199); do
	if [ ! -e /tmp/.X11-unix/X$n ] && [ ! -e /tmp/.X$n-lock ]; then D=:$n; break; fi
done
[ -n "$D" ] || { echo "world_test: no free X display"; exit 1; }
Xvfb $D -screen 0 1920x1080x24 >/dev/null 2>&1 </dev/null &
XPID=$!
S=nvworld-$$
trap '$CTL --session $S close >/dev/null 2>&1 || true; kill $XPID 2>/dev/null || true' EXIT
sleep 1
for gpu in nv software; do
	DISPLAY=$D SAMALTAK_GPU=$gpu $CTL --session $S open --image "$OUT/samaltak.image" --window-size 1920x1080 --work-clock >/dev/null
	$CTL --session $S wait idle 20000 >/dev/null || true
	$CTL --session $S wait 4000 >/dev/null
	n=0
	while [ "$($CTL --session $S eval 'Tools freezeReadouts')" != false ]; do
		n=$((n + 1)); [ $n -lt 60 ] || { echo "world_test: the Mandelbrot did not finish rendering on $gpu"; exit 1; }
		$CTL --session $S wait 1000 >/dev/null
	done
	# every window drawn again at the end of its animations: a device that composes only on change (SoftwareGPU) may
	# otherwise still show a cross-fade's last step
	$CTL --session $S eval "World current windows do: [:w | w invalidate]. 0" >/dev/null
	$CTL --session $S wait idle 20000 >/dev/null || true
	$CTL --session $S wait 2000 >/dev/null
	$CTL --session $S eval "GPUPlatform device printString, ' ', World current compositor lastError printString" > "$NV/world-$gpu.txt"
	$CTL --session $S eval "(World current windows detect: [:w | w title = 'Process Browser'] ifNone: [nil]) ifNil: [''] ifNotNil: [:w | | b | b := w bounds. b left printString, ' ', b top printString, ' ', b right printString, ' ', b bottom printString]" >> "$NV/world-$gpu.txt"
	$CTL --session $S screenshot "$NV/world-$gpu.png" --scale 1 >/dev/null
	$CTL --session $S close >/dev/null
done
NV_DIR="$NV" vm/build/samaltak "$OUT/samaltak.image" --headless --eval "$(cat tests/nv/world_compare.st)"
