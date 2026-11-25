#!/bin/sh
# The nine interactions of docs/graphics-damage.md (RenderScenarios, Tests-Tools-Agent) on each GPU, under a private
# Xvfb at 1920x1080: a line per scenario of what rendering a presented frame costs (docs/nv-gpu.md, Small frames).
#   tests/nv/frames.sh [OUT] [devices...]     devices: cuda software (default both); OUT default build
# NV_FRAMES_NSYS=1 also profiles the libcuda run with nsys (kernel times per scenario: tests/nv/frames_nsys.py).
set -e
OUT=${1:-build}
[ $# -gt 0 ] && shift
DEVICES=${*:-cuda software}
DISPLAY_NUM=${NV_FRAMES_DISPLAY:-93}
mkdir -p "$OUT/nv"
Xvfb ":$DISPLAY_NUM" -screen 0 1920x1080x24 -nolisten tcp >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT INT TERM
sleep 1
for d in $DEVICES; do
	case $d in
	cuda) env="SAMALTAK_GPU=nv SAMALTAK_NV_COMPUTE=cuda" ;;
	software) env="SAMALTAK_GPU=software" ;;
	*) echo "frames.sh: unknown device $d" >&2; exit 2 ;;
	esac
	run="vm/build/samaltak $OUT/samaltak.image --headless --eval"
	if [ "$d" = cuda ] && [ -n "$NV_FRAMES_NSYS" ]; then
		run="${NSYS:-/usr/local/cuda/bin/nsys} profile -t cuda --force-overwrite true -o $OUT/nv/frames-cuda vm/build/samaltak $OUT/samaltak.image --headless --eval"
	fi
	env DISPLAY=":$DISPLAY_NUM" $env $run 'RenderScenarios new run' | tee "$OUT/nv/frames-$d.txt"
done
