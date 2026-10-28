#!/bin/sh
# Are We Fast Yet plus Samaltak workloads, one VM process per benchmark. See docs/benchmarks.md.
# Prints CSV lines benchmark,iteration,microseconds, then '#' lines: VM statistics delta per benchmark and a summary.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
DIR=$ROOT/vm/tests/bench/awfy

AWFY="Bounce CD DeltaBlue Havlak Json List Mandelbrot NBody Permute Queens Richards Sieve Storage Towers"
MICRO="MicroFib MicroLoop MicroFloats MicroSends MicroBlocks MicroDict MicroStrings MicroAlloc MicroFactorial"
WORKLOADS="Recompile TextRendering"
REALWORLD="BinaryTrees Fasta KNucleotide ReverseComplement SpectralNorm Pidigits Strings Dictionaries OrderedCollections Sorting Enumeration PrintParse Exceptions Megamorphic DeepRecursion Perform"

usage() {
    cat <<EOF
usage: $0 [options] [benchmark[:inner] ...]
  --vm PATH         VM binary (default vm/build/samaltak; with --pharo \$PHARO_VM)
  --image PATH      image (default build/samaltak.image; with --pharo \$PHARO_IMAGE)
  --vm-args ARGS    extra VM arguments, e.g. '--jit baseline'
  --pharo           run on Pharo 12 (all but the Samaltak workloads)
  --suite NAME      awfy (default), micro, workloads, realworld or all (all but realworld)
  -n N              iterations per benchmark (default 30)
  -i N              inner iterations for every benchmark (default: per benchmark, see inner())
  -o FILE           also write CSV and '#' lines to FILE
  --summary FILE... only summarize result files (one invocation each; steady = median over files)
EOF
    exit 2
}

# Inner iterations: a steady-state iteration takes 20-200 ms on the interpreter, except where
# upstream verifies only one non-trivial size (CD 100 of 2..1000, Havlak 1, Mandelbrot 500, NBody 250000).
inner() {
    case $1 in
    Bounce) echo 400 ;; CD) echo 100 ;; DeltaBlue) echo 8000 ;; Havlak) echo 1 ;; Json) echo 7 ;;
    List) echo 300 ;; Mandelbrot) echo 500 ;; NBody) echo 250000 ;; Permute) echo 300 ;;
    Queens) echo 400 ;; Richards) echo 7 ;; Sieve) echo 700 ;; Storage) echo 300 ;; Towers) echo 100 ;;
    Recompile) echo 3 ;; TextRendering) echo 200 ;;
    *) echo 1 ;;
    esac
}

file_of() {
    case $1 in
    Micro*) echo Micro ;;
    Recompile|TextRendering) echo Workloads ;;
    *) case " $REALWORLD " in *" $1 "*) echo RealWorld ;; *) echo "$1" ;; esac ;;
    esac
}

summarize() {
    # stdin: CSV and '#' lines, a line '#file N' before each invocation's lines
    awk -F, '
    /^#file / { f = $0; sub(/^#file /, "", f); next }
    /^[A-Za-z0-9]+,[0-9]+,-?[0-9]+$/ {
        b = $1; if (!(b in seen)) { seen[b] = 1; order[++nb] = b }
        k = b SUBSEP f; n[k]++; t[k, n[k]] = $3; tot[k] += $3; if (!(k in files)) { files[k] = 1; fl[b] = fl[b] " " f }
    }
    function median(a, m,   i, j, x) {
        for (i = 2; i <= m; i++) { x = a[i]; for (j = i - 1; j >= 1 && a[j] > x; j--) a[j + 1] = a[j]; a[j + 1] = x }
        return m % 2 ? a[(m + 1) / 2] : (a[m / 2] + a[m / 2 + 1]) / 2
    }
    END {
        printf "# %-18s %6s %10s %10s %10s\n", "benchmark", "runs", "first_ms", "steady_ms", "total_ms"
        for (i = 1; i <= nb; i++) {
            b = order[i]; nr = split(substr(fl[b], 2), fs, " ")
            for (r = 1; r <= nr; r++) {
                k = b SUBSEP fs[r]; m = n[k]; h = int(m / 2); c = 0
                delete s; for (j = h + 1; j <= m; j++) s[++c] = t[k, j]
                st[r] = median(s, c); fi[r] = t[k, 1]; to[r] = tot[k]
            }
            printf "# %-18s %6d %10.1f %10.1f %10.1f\n", b, nr, median(fi, nr) / 1000, median(st, nr) / 1000, median(to, nr) / 1000
        }
    }'
}

VM= IMAGE= VMARGS= PHARO=0 SUITE=awfy N=30 INNER= OUT= SUMMARY=0
while [ $# -gt 0 ]; do
    case $1 in
    --vm) VM=$2; shift ;;
    --image) IMAGE=$2; shift ;;
    --vm-args) VMARGS=$2; shift ;;
    --pharo) PHARO=1 ;;
    --suite) SUITE=$2; shift ;;
    -n) N=$2; shift ;;
    -i) INNER=$2; shift ;;
    -o) OUT=$2; shift ;;
    --summary) SUMMARY=1 ;;
    -h|--help) usage ;;
    -*) usage ;;
    *) break ;;
    esac
    shift
done

if [ $SUMMARY = 1 ]; then
    [ $# -gt 0 ] || usage
    i=0
    for f in "$@"; do i=$((i + 1)); echo "#file $i"; cat "$f"; done | summarize
    exit 0
fi

if [ $# -eq 0 ]; then
    case $SUITE in
    awfy) set -- $AWFY ;;
    micro) set -- $MICRO ;;
    workloads) set -- $WORKLOADS ;;
    realworld) set -- $REALWORLD ;;
    all) set -- $AWFY $MICRO $WORKLOADS ;;
    *) usage ;;
    esac
fi

if [ $PHARO = 1 ]; then
    VM=${VM:-${PHARO_VM:-/tmp/pharo-dl/vm/Pharo.app/Contents/MacOS/Pharo}}
    IMAGE=${IMAGE:-${PHARO_IMAGE:-/tmp/pharo-dl/bench.image}}
    # Filing in writes to the image's .changes and pharo-local: work on a copy.
    WORK=$(mktemp -d)
    SRCIMAGE=$IMAGE src=$(dirname "$IMAGE")
    cp "$IMAGE" "$WORK/awfy.image"
    [ -f "${IMAGE%.image}.changes" ] && cp "${IMAGE%.image}.changes" "$WORK/awfy.changes"
    for s in "$src"/*.sources; do [ -f "$s" ] && cp "$s" "$WORK/"; done
    IMAGE=$WORK/awfy.image
else
    VM=${VM:-$ROOT/vm/build/samaltak}
    IMAGE=${IMAGE:-$ROOT/build/samaltak.image}
fi

LOG=$(mktemp)
ALL=$(mktemp)
trap 'rm -rf "$LOG" "$ALL" ${WORK:+"$WORK"}' EXIT
status=0
echo "# awfy $(date '+%Y-%m-%d %H:%M') vm=$VM image=${SRCIMAGE:-$IMAGE} vm-args='$VMARGS' iterations=$N" | tee -a "$ALL"
for spec in "$@"; do
    b=${spec%%:*}
    if [ "$b" != "$spec" ]; then in=${spec#*:}; else in=${INNER:-$(inner "$b")}; fi
    if [ $PHARO = 1 ] && [ "$(file_of "$b")" = Workloads ]; then
        echo "# skipped $b (Samaltak only)" | tee -a "$ALL"
        continue
    fi
    echo "# run $b inner=$in" | tee -a "$ALL"
    files="'Harness' 'Core' '$(file_of "$b")'"
    run="(Smalltalk at: #Harness) new run: #('$b' '$N' '$in')"
    if [ $PHARO = 1 ]; then
        expr="[#('Pharo' $files) do: [:n | ('$DIR/', n, '.st') asFileReference fileIn]. $run. ''] on: Error do: [:e | 'ERROR ', e class name, ': ', e messageText]"
        (cd "$WORK" && "$VM" --headless $VMARGS "$IMAGE" eval "$expr") 2>&1
    else
        expr="[#('Samaltak' $files) do: [:n | Compiler fileIn: '$DIR/', n, '.st']. $run. ''] on: Error do: [:e | 'ERROR ', e class name, ': ', e messageText]"
        "$VM" $VMARGS "$IMAGE" --headless --eval "$expr" 2>&1
    fi | tee "$LOG" | tr -u '\r' '\n' | grep --line-buffered -E '^[A-Za-z0-9]+,[0-9]+,-?[0-9]+$|^# ' | tee -a "$ALL"
    if grep -q "ERROR" "$LOG" || ! grep -q "^$b,$N," "$LOG"; then
        echo "# FAILED $b" | tee -a "$ALL"
        grep -v -E '^[A-Za-z0-9]+,[0-9]+,-?[0-9]+$|^# ' "$LOG" | head -20 >&2
        status=1
    fi
done
{ echo "#file 1"; cat "$ALL"; } | summarize | tee -a "$ALL"
[ -n "$OUT" ] && cp "$ALL" "$OUT"
exit $status
