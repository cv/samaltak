#!/bin/sh
# Test stages (make targets: test-core, test-jit-baseline, test-uefi, ...) at once: build once (make all), then each
# stage as a make process of its own with TEST_IMAGE=fresh-image (no second build), its log in OUT/stages/<stage>.log.
# Each log is printed as its stage ends, then "stage <stage>: passed in N s" or "stage <stage>: FAILED (exit N) in N s";
# at the end "stages: all passed in N s" or "stages: FAILED: <stages>" (exit 1). Every stage runs to its end, a failing
# one does not stop the others. The Smalltalk suites share the machine's test slots (tests/st_suite.sh), and each of
# their VMs gets an Xvfb of its own (SAMALTAK_TEST_XVFB=1) when DISPLAY is set, so that the stages' windows do not meet.
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
# shellcheck disable=SC2086
t=$(tl_now)
# shellcheck disable=SC2086
SAMALTAK_TIMELINE_PARENT=build make $VARS all || { echo "stages: FAILED: the build (make all)"; exit 1; }
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
      else
        echo "stage $s: FAILED (exit $e) in $secs s"
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
timeline
[ -z "$failed" ] || { echo "stages: FAILED:$failed (in $(( $(date +%s) - START )) s)"; exit 1; }
echo "stages: all passed in $(( $(date +%s) - START )) s"
