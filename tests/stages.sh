#!/bin/sh
# Test stages (make targets: test-core, test-jit-baseline, test-uefi, ...) at once: build once (make all), then each
# stage as a make process of its own with TEST_IMAGE=fresh-image (no second build), its log in OUT/stages/<stage>.log.
# Each log is printed as its stage ends, then "stage <stage>: passed in N s" or "stage <stage>: FAILED (exit N) in N s";
# at the end "stages: all passed in N s" or "stages: FAILED: <stages>" (exit 1). Every stage runs to its end, a failing
# one does not stop the others. The Smalltalk suites share the machine's test slots (tests/st_suite.sh), and each of
# their VMs gets an Xvfb of its own (SAMALTAK_TEST_XVFB=1) when DISPLAY is set, so that the stages' windows do not meet.
# Build cache: the VM (vm/build) comes from and goes into the machine's cache, keyed by vm/'s tree and the compilers
# (tests/build-cache.sh; SAMALTAK_BUILD_CACHE=0: none), so that a gate of an already built vm/ skips its compile.
# Flakes: each stage's result and failure lines go into the machine's ledger (tests/flakes.sh; report: tests/flakes.sh),
# and a failed stage's lines that failed in earlier gates are named first ("flakes: known: ...").
# Timeline: every recipe line, test VM and slot wait goes into OUT/stages/timeline (SAMALTAK_TIMELINE; set it empty
# for none), and the end shows each stage's span and the steps of the build and of the stage that ended last, the
# critical path (tests/timeline.sh; tests/timeline.sh OUT/stages/timeline all: every stage's).
# usage: tests/stages.sh [VAR=value...] stage...   e.g. tests/stages.sh test-core test-jit-opt test-uefi OUT=build/me
set -u
cd "$(dirname "$0")/.."
VARS=
STAGES=
for a in "$@"; do
  case $a in
    *=*) VARS="$VARS $a" ;;
    *) STAGES="$STAGES $a" ;;
  esac
done
[ -n "$STAGES" ] || { echo "usage: tests/stages.sh [VAR=value...] stage..."; exit 2; }
OUT=build
for a in $VARS; do case $a in OUT=*) OUT=${a#OUT=} ;; esac; done
LOGS=$OUT/stages
mkdir -p "$LOGS"
[ -n "${DISPLAY:-}" ] && export SAMALTAK_TEST_XVFB="${SAMALTAK_TEST_XVFB:-1}"
# lavapipe renders with a thread per core by default; 2 per VM take as long at half the CPU
export LP_NUM_THREADS="${LP_NUM_THREADS:-2}"
START=$(date +%s)
SAMALTAK_TIMELINE=${SAMALTAK_TIMELINE-$PWD/$LOGS/timeline}
export SAMALTAK_TIMELINE
[ -n "$SAMALTAK_TIMELINE" ] && : >"$SAMALTAK_TIMELINE"
. tests/lib/timeline.sh
timeline() { [ -n "$SAMALTAK_TIMELINE" ] && tests/timeline.sh "$SAMALTAK_TIMELINE"; }
PIDS=
trap '[ -n "$PIDS" ] && kill $PIDS 2>/dev/null; exit 143' INT TERM HUP

echo "stages: building (make all)"
t=$(tl_now)
# The VM from the machine's build cache when vm/ was built before (tests/build-cache.sh), the rest at once (-j -O).
tests/build-cache.sh restore
NPROC=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)
PAR="-j$NPROC -O"; case $(make --version 2>/dev/null | head -1) in *' 3.'*) PAR= ;; esac
# shellcheck disable=SC2086
SAMALTAK_TIMELINE_PARENT=build make $PAR $VARS all || { echo "stages: FAILED: the build (make all)"; exit 1; }
tests/build-cache.sh save
tl_add "$t" "$(tl_now)" 0 stages "make all" build

for s in $STAGES; do
  rm -f "$LOGS/$s.exit"
  # shellcheck disable=SC2086
  ( t=$(date +%s); t0=$(tl_now); export SAMALTAK_TIMELINE_STAGE=$s
    SAMALTAK_TIMELINE_PARENT=stage-$s make $VARS TEST_IMAGE=fresh-image "$s" >"$LOGS/$s.log" 2>&1; e=$?
    tl_add "$t0" "$(tl_now)" $e stages "make $s" "stage-$s"
    echo "$e $(( $(date +%s) - t ))" >"$LOGS/$s.exit.tmp"; mv "$LOGS/$s.exit.tmp" "$LOGS/$s.exit" ) &
  PIDS="$PIDS $!"
done
echo "stages: running$STAGES at once (logs in $LOGS)"

# the ledger of the gates' failures (tests/flakes.sh): this tree, -dirty with uncommitted changes
TREE=$(git rev-parse 'HEAD^{tree}' 2>/dev/null || echo unknown)
[ -n "$(git status --porcelain --untracked-files=no 2>/dev/null)" ] && TREE=$TREE-dirty
left=$STAGES
failed=
while [ -n "$left" ]; do
  next=
  for s in $left; do
    if [ -f "$LOGS/$s.exit" ]; then
      read -r e secs <"$LOGS/$s.exit"
      echo "=== stage $s ($LOGS/$s.log)"
      cat "$LOGS/$s.log"
      if [ "$e" = 0 ]; then
        echo "stage $s: passed in $secs s"
        tests/flakes.sh record "$TREE" "$s" passed "$LOGS/$s.log"
      else
        tests/flakes.sh known "$s" "$LOGS/$s.log"
        echo "stage $s: FAILED (exit $e) in $secs s"
        tests/flakes.sh record "$TREE" "$s" failed "$LOGS/$s.log"
        failed="$failed $s"
      fi
    else
      next="$next $s"
    fi
  done
  left=$next
  [ -n "$left" ] && sleep 2
done
wait
# what test-tools built besides (vm/build/platform-vm, platform-test) goes into the cache too
tests/build-cache.sh save >/dev/null
timeline
[ -z "$failed" ] || { echo "stages: FAILED:$failed (in $(( $(date +%s) - START )) s)"; exit 1; }
echo "stages: all passed in $(( $(date +%s) - START )) s"
