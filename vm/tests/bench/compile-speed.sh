#!/bin/sh
# Compile speed of Samaltak's two JITs and of Pharo 14's Cog, on the same corpus and in the AWFY first iterations
# (docs/benchmarks.md, Compile speed). Rounds are fresh VM processes, interleaved, each started on a quiet machine.
# usage: compile-speed.sh [corpus|awfy|all] [-n rounds] [-a awfy-rounds] [-o results-file]
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
DIR=$ROOT/vm/tests/bench
AW=$DIR/awfy
VM=${VM:-$ROOT/vm/build/samaltak}
IMAGE=${IMAGE:-$ROOT/build/samaltak.image}
if [ "$(uname -s)" = Darwin ]; then PHARO_LAUNCHER=$HOME/.cache/pharo14/vm/Pharo.app/Contents/MacOS/Pharo; else PHARO_LAUNCHER=$HOME/.cache/pharo14/vm/pharo; fi
PHARO_VM=${PHARO_VM:-$PHARO_LAUNCHER}
PHARO_IMAGE=${PHARO_IMAGE:-$HOME/.cache/pharo14/bench.image}
FILES="'Core' 'Bounce' 'CD' 'DeltaBlue' 'Havlak' 'Json' 'List' 'Mandelbrot' 'NBody' 'Permute' 'Queens' 'Richards' 'Sieve' 'Storage' 'Towers'"
WHAT=all ROUNDS=30 AWFY_ROUNDS=5 OUT=
case ${1:-} in corpus|awfy|all) WHAT=$1; shift ;; esac
while [ $# -gt 0 ]; do
    case $1 in
    -n) ROUNDS=$2; shift ;;
    -a) AWFY_ROUNDS=$2; shift ;;
    -o) OUT=$2; shift ;;
    *) echo "usage: $0 [corpus|awfy|all] [-n rounds] [-a awfy-rounds] [-o results-file]" >&2; exit 2 ;;
    esac
    shift
done

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
RAW=$WORK/raw AWRAW=$WORK/awfy
mkdir -p "$RAW" "$AWRAW"

# A Pharo work directory: filing in writes to the image's .changes and pharo-local.
PDIR=$WORK/pharo
mkdir -p "$PDIR"
cp "$PHARO_IMAGE" "$PDIR/bench.image"
[ -f "${PHARO_IMAGE%.image}.changes" ] && cp "${PHARO_IMAGE%.image}.changes" "$PDIR/bench.changes"
for s in "$(dirname "$PHARO_IMAGE")"/*.sources; do [ -f "$s" ] && cp "$s" "$PDIR/"; done
mkdir "$PDIR/awfy"
for f in "$AW"/*.st; do awk -f "$DIR/pharo14.awk" "$f" > "$PDIR/awfy/${f##*/}"; done

# Wait until the 1-minute load is at most 3 (give up after 30 minutes).
quiet() {
    t=0
    while :; do
        load=$(sysctl -n vm.loadavg | awk '{print $2}')
        [ "$(awk "BEGIN {print ($load <= 3)}")" = 1 ] && return 0
        [ $t -ge 1800 ] && { echo "machine not quiet (load $load)" >&2; exit 1; }
        sleep 5
        t=$((t + 5))
    done
}

samaltak_expr() {
    cat <<EOF
[ | d before |
  #('Samaltak' $FILES) do: [:n | Compiler fileIn: '$AW/', n, '.st'].
  Compiler fileIn: '$1/Probes.st'.
  Compiler fileIn: '$1/Samaltak.st'.
  d := Smalltalk at: #CompileSpeedDriver.
  before := d stats.
  d runAll.
  d reportStats: before.
  d reportTimes.
  d reportMethods.
  'done' ] on: Error do: [:e | 'ERROR ', e class name, ': ', e messageText]
EOF
}

pharo_expr() {
    cat <<EOF
[ | d before |
  #('Pharo' $FILES) do: [:n | ('$PDIR/awfy/', n, '.st') asFileReference fileIn].
  '$1/Probes.st' asFileReference fileIn.
  '$1/Pharo.st' asFileReference fileIn.
  d := Smalltalk at: #CompileSpeedDriver.
  before := d stats.
  d runAll.
  d reportStats: before.
  d collectCodeSizes.
  d reportTimes.
  d reportMethods.
  'done' ] on: Error do: [:e | 'ERROR ', e class name, ': ', e messageText]
EOF
}

# round CORPUSDIR CONFIG FILE: one round in a fresh process.
round() {
    quiet
    case $2 in
    baseline) "$VM" --jit baseline "$IMAGE" --headless --eval "$(samaltak_expr "$1")" ;;
    opt) "$VM" --jit opt --jit-flags eager "$IMAGE" --headless --eval "$(samaltak_expr "$1")" ;;
    cog) for f in Probes Pharo; do awk -f "$DIR/pharo14.awk" "$1/$f.st" > "$PDIR/$f.st"; done
        (cd "$PDIR" && "$PHARO_VM" --headless --codeSize=32M bench.image eval "$(pharo_expr "$PDIR")") ;;
    esac > "$3" 2>&1
    grep -q "done" "$3" && ! grep -q ERROR "$3" || { echo "FAILED round $2 ($3):" >&2; grep -v -E '^(probe|method|stat),' "$3" | head -20 >&2; exit 1; }
}

corpus() {
    python3 "$DIR/compile_speed.py" gen "$WORK/full" >&2
    # the methods without real blocks on either system: one round of the full corpus tells
    round "$WORK/full" baseline "$WORK/s0.out"
    round "$WORK/full" cog "$WORK/p0.out"
    python3 "$DIR/compile_speed.py" noblock "$WORK/s0.out" "$WORK/p0.out" > "$WORK/noblock.idx"
    python3 "$DIR/compile_speed.py" gen "$WORK/noblock" "$WORK/noblock.idx" >&2
    i=1
    while [ $i -le "$ROUNDS" ]; do
        for c in full noblock; do
            for cfg in baseline opt cog; do
                round "$WORK/$c" "$cfg" "$RAW/$c-$cfg-$i.out"
            done
        done
        i=$((i + 1))
    done
    python3 "$DIR/compile_speed.py" report "$RAW"
}

awfy() {
    i=1
    while [ $i -le "$AWFY_ROUNDS" ]; do
        quiet
        "$DIR/awfy.sh" -n 1 --vm-args '--jit baseline' -o "$AWRAW/baseline-$i.out" >/dev/null || exit 1
        quiet
        "$DIR/awfy.sh" -n 1 --vm-args '--jit opt' -o "$AWRAW/opt-$i.out" >/dev/null || exit 1
        quiet
        "$DIR/awfy.sh" --pharo -n 1 -o "$AWRAW/cog-$i.out" >/dev/null || exit 1
        i=$((i + 1))
    done
    python3 "$DIR/compile_speed.py" report-awfy "$AWRAW"/*.out
}

{
    echo "# compile-speed $(date '+%Y-%m-%d %H:%M') vm=$VM image=$IMAGE rounds=$ROUNDS awfy-rounds=$AWFY_ROUNDS"
    case $WHAT in corpus|all) corpus ;; esac
    case $WHAT in awfy|all) awfy ;; esac
} | if [ -n "$OUT" ]; then tee "$OUT"; else cat; fi
