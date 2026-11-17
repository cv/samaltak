#!/bin/sh
# Extremem (extremem/Extremem.st, extremem/Extremem.java) on Samaltak, Pharo 14 or a JVM. See docs/benchmarks.md.
# Prints Extremem,minute,microseconds per simulated minute, then '#' lines: latencies, tally, GC statistics, process.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
BENCH=$ROOT/vm/tests/bench

usage() {
    cat <<EOF
usage: $0 [options] [name=value ...]
  --samaltak        run on Samaltak (default)
  --pharo           run on Pharo 14 (\$PHARO_VM, \$PHARO_IMAGE; default ~/.cache/pharo14)
  --java JAVA       run on the JVM of this java binary
  --vm PATH         Samaltak VM (default vm/build/samaltak)
  --image PATH      Samaltak image (default build/samaltak.image)
  --vm-args ARGS    extra VM arguments: Samaltak's, e.g. '--jit opt', Pharo's, or the JVM's, e.g. '-XX:+UseZGC -Xmx1g'
  --pharo-init EXPR Smalltalk Pharo evaluates after the file-ins, before the run
  -o FILE           also write the output to FILE
name=value overrides a parameter of XmConfig / Extremem.Config (times in microseconds), e.g. simulationMinutes=35.
EOF
    exit 2
}

SYSTEM=samaltak VM= IMAGE= VMARGS= JAVA= OUT= PHARO_INIT=
while [ $# -gt 0 ]; do
    case $1 in
    --samaltak) SYSTEM=samaltak ;;
    --pharo) SYSTEM=pharo ;;
    --java) SYSTEM=java JAVA=$2; shift ;;
    --vm) VM=$2; shift ;;
    --image) IMAGE=$2; shift ;;
    --vm-args) VMARGS=$2; shift ;;
    --pharo-init) PHARO_INIT=$2; shift ;;
    -o) OUT=$(cd "$(dirname "$2")" && pwd)/${2##*/}; shift ;;
    -h|--help|-*) usage ;;
    *) break ;;
    esac
    shift
done

ARGS=
for a in "$@"; do ARGS="$ARGS '$a'"; done
RUN="(Smalltalk at: #Extremem) new run: #($ARGS)"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
# wall time, CPU time and peak RSS of the whole process: every GC thread included
TIME="/usr/bin/time -f #_process_wall_s=%e_user_s=%U_sys_s=%S_maxrss_kb=%M -o $WORK/time"

case $SYSTEM in
samaltak)
    VM=${VM:-$ROOT/vm/build/samaltak}
    IMAGE=${IMAGE:-$ROOT/build/samaltak.image}
    DESC="vm=$VM image=$IMAGE"
    expr="[Compiler fileIn: '$BENCH/awfy/Samaltak.st'. Compiler fileIn: '$BENCH/extremem/XmSamaltak.st'. Compiler fileIn: '$BENCH/extremem/Extremem.st'. $RUN. ''] on: Error do: [:e | 'ERROR ', e class name, ': ', e messageText]"
    set -- $TIME "$VM" $VMARGS "$IMAGE" --headless --eval "$expr" ;;
pharo)
    if [ "$(uname -s)" = Darwin ]; then PHARO_LAUNCHER=$HOME/.cache/pharo14/vm/Pharo.app/Contents/MacOS/Pharo; else PHARO_LAUNCHER=$HOME/.cache/pharo14/vm/pharo; fi
    VM=${PHARO_VM:-$PHARO_LAUNCHER}
    IMAGE=${PHARO_IMAGE:-$HOME/.cache/pharo14/bench.image}
    DESC="vm=$VM image=$IMAGE"
    # Filing in writes to the image's .changes: work on a copy.
    cp "$IMAGE" "$WORK/xm.image"
    [ -f "${IMAGE%.image}.changes" ] && cp "${IMAGE%.image}.changes" "$WORK/xm.changes"
    for s in "$(dirname "$IMAGE")"/*.sources; do [ -f "$s" ] && cp "$s" "$WORK/"; done
    for f in "$BENCH/awfy/Pharo.st" "$BENCH/extremem/XmPharo.st" "$BENCH/extremem/Extremem.st"; do awk -f "$BENCH/pharo14.awk" "$f" > "$WORK/${f##*/}"; done
    expr="[#('Pharo' 'XmPharo' 'Extremem') do: [:n | ('$WORK/', n, '.st') asFileReference fileIn]. ${PHARO_INIT:+$PHARO_INIT. }$RUN. ''] on: Error do: [:e | 'ERROR ', e class name, ': ', e messageText]"
    cd "$WORK" || exit 1
    set -- $TIME "$VM" --headless $VMARGS "$WORK/xm.image" eval "$expr" ;;
java)
    DESC="java=$JAVA ($("$JAVA" -version 2>&1 | head -1))"
    "${JAVA%/java}/javac" -d "$WORK/classes" "$BENCH/extremem/Extremem.java" || exit 1
    # GC pauses: the collectors' safepoints (time to safepoint included) and ZGC's allocation stalls
    LOGS="-Xlog:safepoint:file=$WORK/safepoint.log:uptimemillis -Xlog:gc:file=$WORK/gc.log:uptimemillis"
    set -- $TIME "$JAVA" $VMARGS $LOGS -cp "$WORK/classes" Extremem "$@" ;;
esac

# Java: '# pauses us: ...' from the logs, within the measured minutes (the run prints their uptime)
java_pauses() {
    from=$(sed -n 's/^# measured from uptime_ms=//p' "$WORK/out") to=$(sed -n 's/^# measured until uptime_ms=//p' "$WORK/out")
    [ -n "$from" ] && [ -n "$to" ] || return
    { awk -F'[][]' '/Safepoint "(.*Collect.*|Z.*|Shenandoah.*|G1.*)"/ && match($0, /Total: [0-9]+ ns/) {
          print $2 + 0, int(substr($0, RSTART + 7, RLENGTH - 10) / 1000) }' "$WORK/safepoint.log"
      awk -F'[][]' 'match($0, /Allocation Stall \([^)]*\) [0-9.]+ms/) {
          s = substr($0, RSTART, RLENGTH); sub(/.* /, "", s); print $2 + 0, int(s * 1000) }' "$WORK/gc.log"
    } | sort -n | awk -v from="$from" -v to="$to" 'BEGIN { printf "# pauses us:" } $1 >= from && $1 <= to { printf " %d", $2 } END { print "" }'
}

{
    echo "# extremem $(date '+%Y-%m-%d %H:%M') system=$SYSTEM $DESC vm-args='$VMARGS'${PHARO_INIT:+ pharo-init='$PHARO_INIT'} params='$*'" | sed "s|params='.*|params='$ARGS'|"
    "$@" 2>&1 | tr '\r' '\n' | grep -E '^Extremem,|^# |ERROR' | tee "$WORK/out"
    [ $SYSTEM = java ] && java_pauses
    sed -n 's/^#_process_/# process /; s/_\([a-z]*_[a-z]*=\)/ \1/gp' "$WORK/time"
} | tee "${OUT:-/dev/null}"
