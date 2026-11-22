#!/bin/sh
# The image's Smalltalk tests, headless; fails unless they ran (at least one), all passed and none was skipped.
# usage: tests/st_suite.sh IMAGE [VM option...] [-- test names [image option...]]
#   e.g. tests/st_suite.sh build/samaltak.image --eden 1 -- Tests-Kernel
#
# Shards: the test classes (the VM's --test-list) are split over SAMALTAK_TEST_JOBS VM processes (default
# min(nproc / 2, 8); 1 runs one VM, as before), balanced by each class's time in the last run with the same VM options
# (the timings file SAMALTAK_TEST_TIMES_DIR/<key>, default the image's directory's test-times/; classes without a time
# count by their number of tests). Each shard has its own TMPDIR and log; the output is the shards' logs one after
# another and one summary line "N run, N passed, N failed, N errors in T ms" (T: the slowest shard) like a single
# VM's; a failure, error, crash or skipped test in any shard fails the suite.
# Slots: every VM this script starts (a shard or the single VM) first takes one of SAMALTAK_TEST_SLOTS lock files in
# SAMALTAK_TEST_SLOT_DIR (default nproc / 2, in /tmp/samaltak-test-slots-<uid>, with flock(1)), so that concurrent
# suites (gate stages, several agents' gates) together run at most that many test VMs; the rest wait for a slot.
# Displays: VMs sharing one X display disturb each other (a clipboard request answered after its requestor's window
# went is a BadWindow that ends the VM), so with SAMALTAK_TEST_XVFB=1 each VM gets an Xvfb of its own; the default
# (auto) does that for shards when DISPLAY is set; 0: always DISPLAY.
set -u
cd "$(dirname "$0")/.."
IMAGE=$1
shift
VMOPTS=
while [ $# -gt 0 ] && [ "$1" != "--" ]; do VMOPTS="$VMOPTS $1"; shift; done
[ $# -gt 0 ] && shift

NPROC=$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)
JOBS=$(( NPROC / 2 )); [ "$JOBS" -gt 8 ] && JOBS=8
JOBS=${SAMALTAK_TEST_JOBS:-$JOBS}
case $JOBS in ''|*[!0-9]*) JOBS=1 ;; esac
[ "$JOBS" -lt 1 ] && JOBS=1
SLOTS=${SAMALTAK_TEST_SLOTS:-$(( NPROC / 2 ))}
case $SLOTS in ''|*[!0-9]*) SLOTS=1 ;; esac
[ "$SLOTS" -lt 1 ] && SLOTS=1
SLOT_DIR=${SAMALTAK_TEST_SLOT_DIR:-/tmp/samaltak-test-slots-$(id -u)}
XVFB=${SAMALTAK_TEST_XVFB:-auto}
OWN_X=0
[ "$XVFB" = 1 ] && OWN_X=1
WORK=$(mktemp -d "${TMPDIR:-/tmp}/st_suite.XXXXXX") || exit 1
PIDS=
trap '[ -n "${SAMALTAK_TEST_KEEP:-}" ] && echo "st_suite: kept $WORK" || rm -rf "$WORK"' EXIT
trap '[ -n "$PIDS" ] && kill $PIDS 2>/dev/null; exit 143' INT TERM HUP

# with_slot COMMAND...: run COMMAND holding one of the machine's test slots (a lock on a slot file, which the
# subshell holds; exit 75 when it is taken: then the next one, and after all of them again a second later; COMMAND
# runs with the lock's descriptor closed, so that nothing it leaves behind keeps the slot). Without flock(1) or a
# writable slot directory, COMMAND just runs.
with_slot() {
  if ! command -v flock >/dev/null 2>&1 || ! mkdir -p "$SLOT_DIR" 2>/dev/null || ! [ -w "$SLOT_DIR" ]; then
    "$@"; return
  fi
  while :; do
    i=1
    while [ $i -le "$SLOTS" ]; do
      ( flock -n 9 || exit 75; "$@" 9>&- ) 9>>"$SLOT_DIR/slot$i"
      s=$?
      [ $s = 75 ] || return $s
      i=$((i + 1))
    done
    sleep 1
  done
}

# run_vm ARGS...: the VM, on an X display of its own when OWN_X is 1 and there is Xvfb (one it starts and ends;
# -displayfd picks a free display), else on DISPLAY.
run_vm() {
  if [ "$OWN_X" = 1 ] && command -v Xvfb >/dev/null 2>&1; then
    d=$(mktemp "$WORK/display.XXXXXX")
    Xvfb -displayfd 3 -nolisten tcp -screen 0 1280x1024x24 3>"$d" >/dev/null 2>&1 &
    x=$!
    n=0
    while [ ! -s "$d" ] && [ $n -lt 100 ] && kill -0 $x 2>/dev/null; do sleep 0.1; n=$((n + 1)); done
    if [ -s "$d" ]; then
      DISPLAY=:$(head -1 "$d") vm/build/samaltak "$@"
    else
      echo "(st_suite: Xvfb did not start; on DISPLAY=${DISPLAY:-})"
      vm/build/samaltak "$@"
    fi
    s=$?
    kill $x 2>/dev/null
    wait $x 2>/dev/null
    return $s
  fi
  vm/build/samaltak "$@"
}

# summary_of LOG: the VM's own summary (the last; tests that run tests print summaries too)
summary_of() { grep -E '^[0-9]+ run, ' "$1" | tail -1; }

verdict() { # SUMMARY EXIT
  case "$1" in
    '') echo "st_suite: FAILED: no test summary (exit $2)"; exit 1 ;;
    '0 run'*) echo "st_suite: FAILED: no tests ran"; exit 1 ;;
    *skipped*) echo "st_suite: FAILED: tests were skipped: $1"; exit 1 ;;
  esac
  [ "$2" -eq 0 ] || { echo "st_suite: FAILED (exit $2): $1"; exit 1; }
  exit 0
}

serial() {
  # shellcheck disable=SC2086
  with_slot run_vm $VMOPTS "$IMAGE" --headless --test "$@" >"$WORK/log" 2>&1
  code=$?
  cat "$WORK/log"
  verdict "$(summary_of "$WORK/log")" $code
}

[ "$JOBS" -le 1 ] && serial "$@"

# The classes the run would run (with the image options: --load can add some); too few to share: one VM.
vm/build/samaltak "$IMAGE" --headless --test-list --test "$@" 2>/dev/null | grep '^test-class ' >"$WORK/classes"
NCLASSES=$(wc -l <"$WORK/classes")
[ "$NCLASSES" -ge 2 ] || serial "$@"
[ "$XVFB" = auto ] && [ -n "${DISPLAY:-}" ] && OWN_X=1
[ "$JOBS" -gt "$NCLASSES" ] && JOBS=$NCLASSES

# The arguments after the names (image options such as --load) go to every shard.
n=0
for a in "$@"; do case $a in --*) break ;; esac; n=$((n + 1)); done
while [ $n -gt 0 ]; do shift; n=$((n - 1)); done

# Timings: one file per image and VM options (and the GC verifier), lines "<class> <ms>".
TIMES_DIR=${SAMALTAK_TEST_TIMES_DIR:-$(dirname "$IMAGE")/test-times}
KEY=$(printf '%s%s%s' "$(basename "$IMAGE" .image)" "$VMOPTS" "${SAMALTAK_VERIFY_GC:+ verify-gc}" | tr -c 'A-Za-z0-9.,=-' '_')
TIMES=$TIMES_DIR/$KEY
KNOWN=$TIMES; [ -f "$KNOWN" ] || KNOWN=/dev/null

# Longest first, each class to the least loaded shard (weights: the recorded ms, else the number of tests times the
# recorded ms per test, else the number of tests).
awk -v times="$KNOWN" '
  BEGIN { while ((getline l < times) > 0) { split(l, f, " "); t[f[1]] = f[2] } }
  { name[NR] = $2; tests[NR] = $4; if ($2 in t) { ms += t[$2]; n += $4 } }
  END { per = (n > 0) ? ms / n : 1; for (i = 1; i <= NR; i++) print ((name[i] in t) ? t[name[i]] : tests[i] * per + 1), name[i], tests[i] }
' "$WORK/classes" | sort -k1,1 -g -r | awk -v jobs="$JOBS" '
  { best = 0; for (k = 1; k < jobs; k++) if (load[k] < load[best]) best = k; load[best] += $1; print best + 1, $2, $3 }
' >"$WORK/plan"

k=1
while [ $k -le "$JOBS" ]; do
  mkdir -p "$WORK/$k/tmp"
  classes=$(awk -v k=$k '$1 == k { printf "%s ", $2 }' "$WORK/plan")
  echo "$classes" >"$WORK/$k/classes"
  awk -v k=$k '$1 == k { n += $3 } END { print n + 0 }' "$WORK/plan" >"$WORK/$k/tests"
  # shellcheck disable=SC2086
  ( export TMPDIR="$WORK/$k/tmp"; with_slot run_vm $VMOPTS "$IMAGE" --headless --test-times --test $classes "$@" \
      >"$WORK/$k/log" 2>&1
    echo $? >"$WORK/$k/exit" ) &
  PIDS="$PIDS $!"
  k=$((k + 1))
done
wait

# The logs in shard order without their summaries and class times, then the merged summary.
code=0; missing=; run=0; passed=0; failed=0; errors=0; skipped=0; ms=0
k=1
while [ $k -le "$JOBS" ]; do
  log=$WORK/$k/log
  e=$(cat "$WORK/$k/exit" 2>/dev/null || echo 1)
  s=$(summary_of "$log")
  want=$(cat "$WORK/$k/tests")
  got=$(echo "$s" | sed -n -E 's/^([0-9]+) run, .*/\1/p')
  last=0
  [ -n "$s" ] && [ "$got" = "$want" ] && last=$(grep -n -E '^[0-9]+ run, ' "$log" | tail -1 | cut -d: -f1)
  awk -v last="$last" 'NR != last && !/^test-time /' "$log"
  if [ -z "$s" ]; then
    missing="$missing
st_suite: FAILED: shard $k of $JOBS gave no test summary (exit $e): $(cat "$WORK/$k/classes")"
  elif [ "$got" != "$want" ]; then
    # a summary of tests that a test ran, not the shard's own: the VM ended before its last test
    missing="$missing
st_suite: FAILED: shard $k of $JOBS ended early (exit $e), its last summary counts $got of its $want tests: $(cat "$WORK/$k/classes")"
  else
    # shellcheck disable=SC2046
    set -- $(echo "$s" | sed -E 's/^([0-9]+) run, ([0-9]+) passed, ([0-9]+) failed, ([0-9]+) errors(, ([0-9]+) skipped)? in ([0-9]+) ms.*/\1 \2 \3 \4 x\6 \7/; s/ x / 0 /; s/ x([0-9])/ \1/')
    run=$((run + $1)); passed=$((passed + $2)); failed=$((failed + $3)); errors=$((errors + $4))
    skipped=$((skipped + $5)); [ "$6" -gt "$ms" ] && ms=$6
    # this run's class times replace the recorded ones
    grep '^test-time ' "$log" | awk '{ print $2, $3 }' >>"$WORK/newtimes"
  fi
  [ "$e" -ne 0 ] && code=$e
  k=$((k + 1))
done
if [ -s "$WORK/newtimes" ] && mkdir -p "$TIMES_DIR" 2>/dev/null; then
  { cat "$WORK/newtimes"; [ -f "$TIMES" ] && cat "$TIMES"; } | awk '!seen[$1]++' | sort >"$TIMES.$$" && mv "$TIMES.$$" "$TIMES"
fi
summary="$run run, $passed passed, $failed failed, $errors errors"
[ "$skipped" -gt 0 ] && summary="$summary, $skipped skipped"
summary="$summary in $ms ms"
[ "$run" -gt 0 ] && echo "$summary"
[ -n "$missing" ] && { echo "$missing" | sed 1d; exit 1; }
[ "$run" -gt 0 ] || summary=
verdict "$summary" $code
