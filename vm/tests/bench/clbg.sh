#!/bin/sh
# Basic C versions of the Shootout (CLBG) programs the suites run (clbg/*.c, docs/benchmarks.md): built with
# cc -O2, each run for n iterations in one process. Prints what awfy.sh prints: name,iteration,microseconds (CPU
# time), then '# name 1 first_ms steady_ms total_ms' (steady: the median of the last half).
# usage: vm/tests/bench/clbg.sh [-n iterations] [-o file] [program ...]   (programs: binarytrees fasta ...)
set -u
DIR=$(cd "$(dirname "$0")" && pwd)/clbg
N=10 OUT=
while [ $# -gt 0 ]; do
    case $1 in
    -n) N=$2; shift ;;
    -o) OUT=$2; shift ;;
    -*) echo "usage: $0 [-n iterations] [-o file] [program ...]" >&2; exit 2 ;;
    *) break ;;
    esac
    shift
done
[ $# -eq 0 ] && set -- binarytrees fasta knucleotide revcomp spectralnorm pidigits mandelbrot nbody
BUILD=$(mktemp -d)
ALL=$(mktemp)
trap 'rm -rf "$BUILD" "$ALL"' EXIT
echo "# clbg $(date '+%Y-%m-%d %H:%M') cc=$(${CC:-cc} --version | head -1) flags=-O2 iterations=$N" | tee -a "$ALL"
for p in "$@"; do
    ${CC:-cc} -O2 -o "$BUILD/$p" "$DIR/$p.c" -lm -lgmp || exit 1
    "$BUILD/$p" "$N" | tee -a "$ALL" || { echo "# FAILED $p" | tee -a "$ALL"; continue; }
done
awk -F, '/^[A-Za-z]+,[0-9]+,[0-9]+$/ { n[$1]++; t[$1, n[$1]] = $3; if (!($1 in seen)) { seen[$1] = 1; order[++k] = $1 } }
    END { printf "# %-20s %5s %10s %10s %10s\n", "benchmark", "runs", "first_ms", "steady_ms", "total_ms";
          for (i = 1; i <= k; i++) { b = order[i]; m = n[b]; h = int(m / 2); c = 0; tot = 0;
              for (j = 1; j <= m; j++) tot += t[b, j];
              for (j = m - h + 1; j <= m; j++) v[++c] = t[b, j];
              for (x = 1; x <= c; x++) for (y = x + 1; y <= c; y++) if (v[y] < v[x]) { s = v[x]; v[x] = v[y]; v[y] = s }
              med = (c % 2) ? v[(c + 1) / 2] : (v[c / 2] + v[c / 2 + 1]) / 2;
              printf "# %-20s %5d %10.1f %10.1f %10.1f\n", b, 1, t[b, 1] / 1000, med / 1000, tot / 1000 } }' "$ALL" | tee -a "$ALL"
[ -n "$OUT" ] && cp "$ALL" "$OUT"
exit 0
