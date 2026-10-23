#!/bin/sh
# Interpreter performance suite: vm/tests/bench/run.sh [IMAGE] [runs]. Prints the best of `runs` runs per line.
ROOT=$(cd "$(dirname "$0")/../.." && cd .. && pwd)
IMG=${1:-$ROOT/build/samaltak.image}
RUNS=${2:-3}
for i in $(seq "$RUNS"); do
    "$ROOT/vm/build/samaltak" "$IMG" --headless --eval "$(cat "$ROOT/vm/tests/bench/bench.st")" 2>&1 | tr -d "'" | tr '\r' '\n'
done | awk '{key = $1; v = -1; for (i = 2; i <= NF; i++) if ($i ~ /^[0-9]+$/) { v = $i + 0; break }
           if (v < 0) next; g = ($0 ~ /glyphs/)
           if (!(key in best) || (g ? v > best[key] : v < best[key])) best[key] = v; isg[key] = g}
     END {for (k in best) print k, best[k], (isg[k] ? "glyphs/s" : "ms")}' | sort
