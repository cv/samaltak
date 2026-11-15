#!/bin/sh
# The Benchmarks Game's own Pharo programs (benchmarksgame/, docs/benchmarks.md) on Samaltak and Pharo, each run a
# fresh process, rounds interleaved, every run started on a quiet machine (1-minute load < 3). Samaltak files in
# benchmarksgame/Samaltak.st, then the program with `d` exponents written `e` and `StdioStream instance methodsFor:`
# as `StdioStream methodsFor:`; Pharo files in the program as pharo14.py writes it.
# Prints program,system,round,run_ms,process_ms,md5: run_ms is `BenchmarksGame do: N` inside the image (JIT and GC
# included), process_ms the whole process (start, image load, file-in, quit); md5 of the program's output. Then
# medians, Samaltak / Pharo, and whether the outputs are the same.
# usage: vm/tests/bench/benchmarksgame.sh [-n rounds] [-o file] [--small] [program ...]
#   --small: the sizes for checking output (seconds in all); VM, IMAGE, VMARGS: Samaltak; PHARO_VM, PHARO_IMAGE: Pharo
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
DIR=$ROOT/vm/tests/bench/benchmarksgame
N=3 OUT= SMALL=0
while [ $# -gt 0 ]; do
    case $1 in
    -n) N=$2; shift ;;
    -o) OUT=$2; shift ;;
    --small) SMALL=1 ;;
    -*) echo "usage: $0 [-n rounds] [-o file] [--small] [program ...]" >&2; exit 2 ;;
    *) break ;;
    esac
    shift
done
[ $# -eq 0 ] && set -- $(cd "$DIR" && ls *-pharo-*.st | sed 's/\.st$//')

# N per program: the reduced sizes (seconds to tens of seconds on Pharo), or --small's
size() {
    if [ $SMALL = 1 ]; then
        case $1 in binarytrees*) echo 10 ;; fannkuchredux*) echo 7 ;; fasta*) echo 1000 ;; mandelbrot*) echo 200 ;;
        nbody*) echo 1000 ;; pidigits*) echo 30 ;; spectralnorm*) echo 100 ;; *) echo 0 ;; esac
    else
        case $1 in binarytrees*) echo 18 ;; fannkuchredux*) echo 10 ;; fasta*) echo 2500000 ;; mandelbrot*) echo 4000 ;;
        nbody*) echo 5000000 ;; pidigits*) echo 10000 ;; spectralnorm*) echo 2000 ;; *) echo 0 ;; esac
    fi
}
input() { case $1 in knucleotide*|revcomp*) echo "$WORK/input.txt" ;; *) echo /dev/null ;; esac; }

VM=${VM:-$ROOT/vm/build/samaltak}
IMAGE=${IMAGE:-$ROOT/build/samaltak.image}
VMARGS=${VMARGS:-}
if [ "$(uname -s)" = Darwin ]; then PHARO_LAUNCHER=$HOME/.cache/pharo14/vm/Pharo.app/Contents/MacOS/Pharo; else PHARO_LAUNCHER=$HOME/.cache/pharo14/vm/pharo; fi
PHARO_VM=${PHARO_VM:-$PHARO_LAUNCHER}
PHARO_IMAGE=${PHARO_IMAGE:-$HOME/.cache/pharo14/bench.image}

WORK=$(mktemp -d)
ALL=$(mktemp)
trap 'rm -rf "$WORK" "$ALL"' EXIT
mkdir "$WORK/samaltak" "$WORK/pharo"
for f in "$DIR"/*-pharo-*.st; do
    b=${f##*/}
    sed -E -e 's/([0-9])d(-?[0-9])/\1e\2/g' -e 's/^!StdioStream instance methodsFor:/!StdioStream methodsFor:/' "$f" > "$WORK/samaltak/$b"
    python3 "$DIR/pharo14.py" "$f" "$WORK/pharo/$b" || exit 1
done
# Filing in writes to the image's .changes: work on a copy.
cp "$PHARO_IMAGE" "$WORK/pharo/run.image"
[ -f "${PHARO_IMAGE%.image}.changes" ] && cp "${PHARO_IMAGE%.image}.changes" "$WORK/pharo/run.changes"
for s in "$(dirname "$PHARO_IMAGE")"/*.sources; do [ -f "$s" ] && cp "$s" "$WORK/pharo/"; done

now() { perl -MTime::HiRes=time -e 'printf "%d\n", time * 1000'; }
quiet() {
    while :; do
        load=$( (sysctl -n vm.loadavg 2>/dev/null || cat /proc/loadavg) | tr -d '{}' | awk '{print $1}')
        [ "$(awk "BEGIN {print ($load < 3)}")" = 1 ] && return 0
        sleep 10
    done
}
# run SYSTEM PROGRAM N INPUT: output in $WORK/out, stderr in $WORK/err ("ms <n>" there)
run() {
    case $1 in
    samaltak) "$VM" $VMARGS "$IMAGE" --headless --eval "| t | [Compiler fileIn: '$DIR/Samaltak.st'. Compiler fileIn: '$WORK/samaltak/$2.st'. t := Time millisecondsToRun: [(Smalltalk at: #BenchmarksGame) do: $3. (Smalltalk at: #Stdio) stdout flush]. Smalltalk vm stderrWrite: 'ms ', t printString, (String with: Character lf)] on: Error do: [:e | Smalltalk vm stderrWrite: 'ERROR ', e messageText printString, (String with: Character lf)]. Smalltalk quit: 0" ;;
    pharo) (cd "$WORK/pharo" && "$PHARO_VM" --headless run.image eval "| t | '$WORK/pharo/$2.st' asFileReference fileIn. t := Time millisecondsToRun: [(Smalltalk at: #BenchmarksGame) do: $3. Stdio stdout flush]. Stdio stderr nextPutAll: 'ms ', t printString; lf; flush. Smalltalk snapshot: false andQuit: true") ;;
    esac < "$4" > "$WORK/out" 2> "$WORK/err"
}

echo "# benchmarksgame $(date '+%Y-%m-%d %H:%M') vm=$VM vm-args='$VMARGS' pharo=$PHARO_VM rounds=$N small=$SMALL" | tee -a "$ALL"
# knucleotide and revcomp read fasta's output
if [ $SMALL = 1 ]; then fn=25000; else fn=2500000; fi
run samaltak fasta-pharo-2 $fn /dev/null && cp "$WORK/out" "$WORK/input.txt"
r=1 first=pharo second=samaltak
while [ $r -le "$N" ]; do
    for p in "$@"; do
        for s in $first $second; do
            quiet
            t0=$(now); run $s "$p" "$(size "$p")" "$(input "$p")"; t1=$(now)
            ms=$(awk '/^ms /{print $2}' "$WORK/err" | tail -1)
            if [ -z "$ms" ]; then
                echo "# FAILED $p $s: $(grep -v '^ms ' "$WORK/err" | head -3 | tr '\n' ' ')" | tee -a "$ALL"
            else
                echo "$p,$s,$r,$ms,$((t1 - t0)),$( (md5 -q "$WORK/out" 2>/dev/null || md5sum "$WORK/out") | cut -c1-32)" | tee -a "$ALL"
            fi
        done
        t=$first first=$second second=$t
    done
    r=$((r + 1))
done
awk -F, '/^[a-z0-9-]+,(pharo|samaltak),/ {
        k = $1 SUBSEP $2; n[k]++; run[k, n[k]] = $4; proc[k, n[k]] = $5; if (!((k, $6) in seen)) { seen[k, $6] = 1; md[k]++; h[k] = $6 }
        if (!($1 in p)) { p[$1] = 1; order[++np] = $1 } }
    function med(a, k, m,   i, j, x, v) { for (i = 1; i <= m; i++) v[i] = a[k, i]
        for (i = 2; i <= m; i++) { x = v[i]; for (j = i - 1; j >= 1 && v[j] > x; j--) v[j + 1] = v[j]; v[j + 1] = x }
        return m % 2 ? v[(m + 1) / 2] : (v[m / 2] + v[m / 2 + 1]) / 2 }
    END {
        printf "# %-22s %10s %10s %10s %10s %7s %7s %5s\n", "program", "pharo_run", "pharo_proc", "sam_run", "sam_proc", "run", "proc", "same"
        for (i = 1; i <= np; i++) { b = order[i]; kp = b SUBSEP "pharo"; ks = b SUBSEP "samaltak"
            if (!n[kp] || !n[ks]) continue
            pr = med(run, kp, n[kp]); pp = med(proc, kp, n[kp]); sr = med(run, ks, n[ks]); sp = med(proc, ks, n[ks])
            same = (md[kp] == 1 && md[ks] == 1 && h[kp] == h[ks]) ? "yes" : "NO"
            if (pr > 0 && sr > 0) { lr += log(sr / pr); lp += log(sp / pp); c++ }
            printf "# %-22s %10.0f %10.0f %10.0f %10.0f %7.2f %7.2f %5s\n", b, pr, pp, sr, sp, (pr > 0 ? sr / pr : 0), sp / pp, same }
        if (c) printf "# %-22s %43s %7.2f %7.2f\n", "geometric mean", "", exp(lr / c), exp(lp / c) }' "$ALL" | tee -a "$ALL"
[ -n "$OUT" ] && cp "$ALL" "$OUT"
grep -q '^# FAILED' "$ALL" && exit 1
exit 0
