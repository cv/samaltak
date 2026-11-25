#!/bin/sh
# perf on one AWFY benchmark's laps only (Linux, sudo perf): docs/jit.md, Where the time goes.
#   perf-awfy.sh [options] stat|record|spe Bench [iterations [inner]]
# The VM files the benchmark in, then waits for a start gun; perf attaches to that VM process alone, counts or samples
# the laps, and stops when they end. stat: counters (cycles, instructions, branches, mispredicts, L1I/iTLB, frontend and
# backend stalls, L1D/L2D refills) into OUT/MODE-Bench.stat. record: cycles, retired mispredicts, L1I refills, frontend
# stalls sampled into OUT/MODE-Bench.data, symbolized by the perf map (SAMALTAK_PERF_MAP=jitdump; perf inject --jit for
# perf annotate). spe: Arm's Statistical Profiling Extension, every PERIOD-th operation with its exact pc, into
# OUT/MODE-Bench.spe.data, then perf_mix.py: where the operations are and what kind (class checks, frame traffic, ...).
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
VM=$ROOT/vm/build/samaltak IMAGE=$ROOT/build/samaltak.image MODE=opt CPU= OUT=/tmp/perf-awfy PERIOD=4096 FREQ=10000 INIT= RECARGS=
usage() {
    cat <<EOF
usage: $0 [--vm PATH] [--image PATH] [--jit MODE] [--cpu N] [-o DIR] [--period N] [--freq N] stat|record|spe Bench [n [inner]]
  --cpu N    the logical CPU to pin the VM to (default: the last of the fastest cores)
  -o DIR     output directory (default /tmp/perf-awfy)
  --record-args A record: more perf record options, e.g. '-g'
  --init EXPR Smalltalk to evaluate before the laps, e.g. 'Profiler default stop'
  --period N spe: sample every Nth operation (default 4096); --freq N record: samples a second per event (default 10000)
EOF
    exit 2
}
while [ $# -gt 0 ]; do
    case $1 in
    --vm) VM=$2; shift ;; --image) IMAGE=$2; shift ;; --jit) MODE=$2; shift ;; --cpu) CPU=$2; shift ;;
    -o) OUT=$2; shift ;; --init) INIT=$2; shift ;; --record-args) RECARGS=$2; shift ;; --period) PERIOD=$2; shift ;; --freq) FREQ=$2; shift ;;
    -*) usage ;; *) break ;;
    esac
    shift
done
[ $# -ge 2 ] || usage
WHAT=$1 B=$2 N=${3:-100}
IN=${4:-$(sh "$ROOT/vm/tests/bench/awfy.sh" --inner "$B")}
if [ -z "$CPU" ]; then
    CPU=$(grep -H . /sys/devices/system/cpu/cpu[0-9]*/cpufreq/cpuinfo_max_freq | awk -F: '
        { n = split($1, p, "/"); c = substr(p[n - 2], 4) + 0; f = $2 + 0; if (f > m || (f == m && c > best)) { if (f > m) best = -1; m = f; if (c > best) best = c } }
        END { print best }')
fi
# The core PMU of that CPU (big.LITTLE machines have one per core type); generic events elsewhere.
P=
for d in /sys/bus/event_source/devices/armv8_pmuv3_*; do
    [ -r "$d/cpus" ] || continue
    if awk -v c="$CPU" -F, '{ for (i = 1; i <= NF; i++) { n = split($i, r, "-"); if (c >= r[1] && c <= r[n]) ok = 1 } } END { exit !ok }' "$d/cpus"; then P=${d##*/}; fi
done
if [ -n "$P" ]; then
    STAT="$P/cpu_cycles/,$P/inst_retired/,$P/br_retired/,$P/br_mis_pred_retired/,$P/l1i_cache/,$P/l1i_cache_refill/,$P/l1i_tlb_refill/,$P/itlb_walk/,$P/stall_frontend/,$P/stall_backend/,$P/stall_backend_mem/,$P/l1d_cache_refill/,$P/l2d_cache_refill/,$P/dtlb_walk/,$P/br_return_retired/"
    REC="$P/cpu_cycles/,$P/br_mis_pred_retired/,$P/l1i_cache_refill/,$P/stall_frontend/"
else
    STAT=cycles,instructions,branches,branch-misses,L1-icache-load-misses,iTLB-load-misses,L1-dcache-load-misses
    REC=cycles,branch-misses,L1-icache-load-misses
fi
mkdir -p "$OUT"
case $B in Micro*) F=Micro ;; Adv*) F=Adverse ;; *) F=$(sh "$ROOT/vm/tests/bench/awfy.sh" --file-of "$B") ;; esac
G=$OUT/go-$MODE-$B
rm -f "$G" "$G.ready" "$G.done" "$G.quit" "$OUT/perfpid"
D=$ROOT/vm/tests/bench/awfy
E="[#('Samaltak' 'Harness' 'Core' '$F') do: [:n | Compiler fileIn: '$D/', n, '.st']. (FileStream forceNewFileNamed: '$G.ready') close. [File exists: '$G'] whileFalse: [(Delay forMilliseconds: 2) wait]. ${INIT:+$INIT. }(Smalltalk at: #Harness) new run: #('$B' '$N' '$IN'). (FileStream forceNewFileNamed: '$G.done') close. [File exists: '$G.quit'] whileFalse: [(Delay forMilliseconds: 2) wait]. ''] on: Error do: [:e | 'ERROR ', e class name, ': ', e messageText]"
SAMALTAK_PERF_MAP=jitdump taskset -c "$CPU" "$VM" --jit "$MODE" "$IMAGE" --headless --eval "$E" > "$OUT/$MODE-$B.out" 2>&1 &
PID=$!
while [ ! -e "$G.ready" ]; do kill -0 $PID 2>/dev/null || { cat "$OUT/$MODE-$B.out" >&2; exit 1; }; sleep 0.05; done
case $WHAT in
stat) PERF="perf stat -x, -o $OUT/$MODE-$B.stat -e $STAT" ;;
record) PERF="perf record -q -k mono -F $FREQ $RECARGS -o $OUT/$MODE-$B.data -e $REC" ;;
spe) PERF="perf record -q -k mono -c $PERIOD -o $OUT/$MODE-$B.spe.data -e arm_spe_0/ts_enable=1,pa_enable=0/" ;;
*) kill $PID; usage ;;
esac
# perf as root, attached to the VM only; its pid in a file to stop it after the laps
sudo -n sh -c "echo \$\$ > $OUT/perfpid; exec $PERF -p $PID" &
sleep 0.5; touch "$G"
while [ ! -e "$G.done" ]; do kill -0 $PID 2>/dev/null || break; sleep 0.02; done
sudo -n kill -INT "$(cat "$OUT/perfpid")"; sleep 0.5; touch "$G.quit"
wait
cp "/tmp/perf-$PID.map" "$OUT/$MODE-$B.map" 2>/dev/null
rm -f "$G" "$G.ready" "$G.done" "$G.quit" "$OUT/perfpid"
echo "# $WHAT $MODE $B n=$N inner=$IN cpu=$CPU pid=$PID" > "$OUT/$MODE-$B.pid"
case $WHAT in
stat) cat "$OUT/$MODE-$B.stat" ;;
record) sudo -n perf report -i "$OUT/$MODE-$B.data" --stdio --sort sym 2>/dev/null | grep -v '^#' | grep -v '^$' | head -40 ;;
spe) python3 "$ROOT/vm/tests/bench/perf_mix.py" "$OUT/$MODE-$B.spe.data" $PID ;;
esac
