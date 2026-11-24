#!/bin/sh
# The image's Smalltalk tests, headless; fails unless they ran (at least one), all passed and none was skipped.
# usage: tests/st_suite.sh IMAGE [VM option...] [-- test names [image option...]]
#   e.g. tests/st_suite.sh build/samaltak.image --eden 1 -- Tests-Kernel
#
# Shards: the test classes (the VM's --test-list) are split over SAMALTAK_TEST_JOBS VM processes (default
# min(nproc / 2, 8); 1 runs one VM, as before), balanced by each class's time in the last run with the same VM options
# (the timings file SAMALTAK_TEST_TIMES_DIR/<key>, default the image's directory's test-times/, else the machine's
# ~/.cache/samaltak/test-times/<key>, which every run updates too; classes without a time count by their number of
# tests). Each shard has its own TMPDIR and log; the output is the shards' logs one after
# another and one summary line "N run, N passed, N failed, N errors in T ms" (T: the slowest shard) like a single
# VM's; a failure, error, crash or skipped test in any shard fails the suite.
# Slots: every VM this script starts (a shard or the single VM) first takes one of the machine's SAMALTAK_TEST_SLOTS
# test slots (tests/lib/slots.sh: default 4/5 of the CPUs, at most one per 3 GB available), so that concurrent suites (gate
# stages, several agents' gates) together run at most that many test VMs; the rest wait for a slot.
# Timeline: with SAMALTAK_TIMELINE (tests/timeline.sh), each VM's run and its wait for a slot are events.
# Displays: VMs sharing one X display disturb each other (a clipboard request answered after its requestor's window
# went is a BadWindow that ends the VM), so with SAMALTAK_TEST_XVFB=1 each VM gets an Xvfb of its own; the default
# (auto) does that for shards when DISPLAY is set; 0: always DISPLAY. Shards render with 2 lavapipe threads each
# (LP_NUM_THREADS, unless set).
# Hangs: a test that outlives its time limit is ended by its runner, and in-image by TestResult's watchdog, which prints
# every Process's stack and quits the VM when the runner cannot run; a VM that hangs below Smalltalk (blocked in a
# primitive) is ended after SAMALTAK_TEST_VM_TIMEOUT seconds (default 1800; 0: never), with its threads' backtraces
# when gdb may attach, and fails its shard.
# Reruns: a shard (or the single VM) that fails, crashes or ends early runs once more (tests/lib/rerun.sh,
# SAMALTAK_TEST_RERUN; 0: no rerun), after the others, at once with the other failed ones: if it passes, the suite
# passes and its first run's failure lines are printed as "flake: <line>" (tests/stages.sh lists them, tests/flakes.sh
# records them); if it fails again, the suite fails with "st_suite: ... failed again on its rerun".
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
. tests/lib/slots.sh
. tests/lib/rerun.sh
XVFB=${SAMALTAK_TEST_XVFB:-auto}
VM_TIMEOUT=${SAMALTAK_TEST_VM_TIMEOUT:-1800}
case $VM_TIMEOUT in ''|*[!0-9]*) VM_TIMEOUT=1800 ;; esac
OWN_X=0
[ "$XVFB" = 1 ] && OWN_X=1
WORK=$(mktemp -d "${TMPDIR:-/tmp}/st_suite.XXXXXX") || exit 1
PIDS=
trap '[ -n "${SAMALTAK_TEST_KEEP:-}" ] && echo "st_suite: kept $WORK" || rm -rf "$WORK"' EXIT
trap '[ -n "$PIDS" ] && kill $PIDS 2>/dev/null; exit 143' INT TERM HUP

# timed COMMAND...: COMMAND, its run an event of the timeline (SLOT_LABEL its text).
timed() {
  tt=$(tl_now)
  "$@"
  ts=$?
  tl_add "$tt" "$(tl_now)" $ts st_suite "${SLOT_LABEL:-}"
  return $ts
}

# vm ARGS...: the VM, ended after VM_TIMEOUT seconds (its backtraces first, if gdb may attach): its exit status.
vm() {
  vm/build/samaltak "$@" &
  v=$!
  if [ "$VM_TIMEOUT" -gt 0 ]; then
    ( n=0
      while kill -0 $v 2>/dev/null; do
        sleep 5; n=$((n + 5))
        [ $n -ge "$VM_TIMEOUT" ] || continue
        echo "st_suite: the VM (pid $v) still runs after $VM_TIMEOUT s (SAMALTAK_TEST_VM_TIMEOUT): ended"
        if command -v gdb >/dev/null 2>&1; then
          bt=$(timeout 60 gdb -p $v -batch -nx -ex 'thread apply all bt 30' 2>&1)
          case $bt in
            *'Could not attach'*) echo "st_suite: (no backtraces: gdb may not attach here, /proc/sys/kernel/yama/ptrace_scope)" ;;
            *) echo "$bt" | grep -v '^\[New LWP' ;;
          esac
        fi
        kill -TERM $v 2>/dev/null; sleep 10; kill -KILL $v 2>/dev/null
        break
      done ) &
    w=$!
  fi
  wait $v
  s=$?
  [ "$VM_TIMEOUT" -gt 0 ] && { kill $w 2>/dev/null; wait $w 2>/dev/null; }
  return $s
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
      DISPLAY=:$(head -1 "$d"); export DISPLAY  # run_vm runs in a subshell of its own (with_slot)
      vm "$@"
    else
      echo "(st_suite: Xvfb did not start; on DISPLAY=${DISPLAY:-})"
      vm "$@"
    fi
    s=$?
    kill $x 2>/dev/null
    wait $x 2>/dev/null
    return $s
  fi
  vm "$@"
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
  SLOT_LABEL="$IMAGE$VMOPTS: $*"
  # shellcheck disable=SC2086
  with_slot timed run_vm $VMOPTS "$IMAGE" --headless --test "$@" >"$WORK/log" 2>&1
  code=$?
  if [ "$RERUN" = 1 ] && [ $code != 130 ] && [ $code != 143 ] && { [ $code != 0 ] || [ -z "$(summary_of "$WORK/log")" ]; }; then
    mv "$WORK/log" "$WORK/log.first"
    SLOT_LABEL="rerun: $SLOT_LABEL"
    # shellcheck disable=SC2086
    SLOT_PRIORITY=1
    # shellcheck disable=SC2086
    with_slot timed run_vm $VMOPTS "$IMAGE" --headless --test "$@" >"$WORK/log" 2>&1
    code2=$?
    echo "st_suite: the suite failed (exit $code), running it once more; its first run:"
    rerun_first "$WORK/log.first"
    cat "$WORK/log"
    s=$(summary_of "$WORK/log")
    if [ $code2 = 0 ] && [ -n "$s" ]; then
      rerun_flakes "$WORK/log.first" "$WORK/log" "st_suite $*"
      echo "st_suite: the suite failed (exit $code) and passed on its rerun (a flake)"
    else
      echo "st_suite: the suite failed again on its rerun (exit $code2)"
    fi
    verdict "$s" $code2
  fi
  cat "$WORK/log"
  verdict "$(summary_of "$WORK/log")" $code
}

[ "$JOBS" -le 1 ] && serial "$@"

# The classes the run would run (with the image options: --load can add some); too few to share: one VM.
vm/build/samaltak "$IMAGE" --headless --test-list --test "$@" 2>/dev/null | grep '^test-class ' >"$WORK/classes"
NCLASSES=$(wc -l <"$WORK/classes")
[ "$NCLASSES" -ge 2 ] || serial "$@"
[ "$XVFB" = auto ] && [ -n "${DISPLAY:-}" ] && OWN_X=1
# lavapipe (software Vulkan) renders with a thread per core by default: 2 per VM take as long and half the CPU
export LP_NUM_THREADS="${LP_NUM_THREADS:-2}"
[ "$JOBS" -gt "$NCLASSES" ] && JOBS=$NCLASSES

# The arguments after the names (image options such as --load) go to every shard.
n=0
for a in "$@"; do case $a in --*) break ;; esac; n=$((n + 1)); done
while [ $n -gt 0 ]; do shift; n=$((n - 1)); done

# Timings: one file per image and VM options (and the GC verifier), lines "<class> <ms>".
TIMES_DIR=${SAMALTAK_TEST_TIMES_DIR:-$(dirname "$IMAGE")/test-times}
KEY=$(printf '%s%s%s' "$(basename "$IMAGE" .image)" "$VMOPTS" "${SAMALTAK_VERIFY_GC:+ verify-gc}" | tr -c 'A-Za-z0-9.,=-' '_')
TIMES=$TIMES_DIR/$KEY
# a copy shared by every directory on the machine, for a fresh worktree's first run (a gate's)
SHARED_TIMES_DIR=${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}/samaltak/test-times
KNOWN=$TIMES; [ -f "$KNOWN" ] || KNOWN=$SHARED_TIMES_DIR/$KEY; [ -f "$KNOWN" ] || KNOWN=/dev/null

# Longest first, each class to the least loaded shard (weights: the recorded ms, else the number of tests times the
# recorded ms per test, else the number of tests).
awk -v times="$KNOWN" '
  BEGIN { while ((getline l < times) > 0) { split(l, f, " "); t[f[1]] = f[2] } }
  { name[NR] = $2; tests[NR] = $4; if ($2 in t) { ms += t[$2]; n += $4 } }
  END { per = (n > 0) ? ms / n : 1; for (i = 1; i <= NR; i++) print ((name[i] in t) ? t[name[i]] : tests[i] * per + 1), name[i], tests[i] }
' "$WORK/classes" | sort -k1,1 -g -r | awk -v jobs="$JOBS" '
  { best = 0; for (k = 1; k < jobs; k++) if (load[k] < load[best]) best = k; load[best] += $1; print best + 1, $2, $3 }
' >"$WORK/plan"

# start_shard K [rerun] IMAGE-OPTION...: shard K's VM in the background, its log, exit status (and trace) in WORK/K
start_shard() {
  k=$1; again=$2; shift 2
  mkdir -p "$WORK/$k/tmp"
  classes=$(cat "$WORK/$k/classes")
  # shard 1 has the longest class (the plan places the longest first): it is the suite's critical path; so is a rerun
  SLOT_PRIORITY=; [ $k = 1 ] || [ -n "$again" ] && SLOT_PRIORITY=1
  # shellcheck disable=SC2086
  ( export TMPDIR="$WORK/$k/tmp"; SLOT_LABEL="${again:+rerun: }shard $k/$JOBS $(basename "$IMAGE")$VMOPTS: $classes"
    # SAMALTAK_FFI_NATIVE_TRACE's lines (stderr, one per native entry: the summary's own writes are some) go after the
    # log, so they do not split its lines (make test-ffi-headless counts them)
    if [ -n "${SAMALTAK_FFI_NATIVE_TRACE:-}" ]; then
      with_slot timed run_vm $VMOPTS "$IMAGE" --headless --test-times --test $classes "$@" \
        >"$WORK/$k/log" 2>"$WORK/$k/trace"
    else
      with_slot timed run_vm $VMOPTS "$IMAGE" --headless --test-times --test $classes "$@" \
        >"$WORK/$k/log" 2>&1
    fi
    echo $? >"$WORK/$k/exit" ) &
  PIDS="$PIDS $!"
}
# shard_ok K: shard K passed: exit 0 and its own summary, of all its tests
shard_ok() {
  [ "$(cat "$WORK/$1/exit" 2>/dev/null || echo 1)" = 0 ] || return 1
  s=$(summary_of "$WORK/$1/log")
  [ -n "$s" ] && [ "$(echo "$s" | sed -n -E 's/^([0-9]+) run, .*/\1/p')" = "$(cat "$WORK/$1/tests")" ]
}

k=1
while [ $k -le "$JOBS" ]; do
  mkdir -p "$WORK/$k"
  awk -v k=$k '$1 == k { printf "%s ", $2 }' "$WORK/plan" >"$WORK/$k/classes"
  awk -v k=$k '$1 == k { n += $3 } END { print n + 0 }' "$WORK/plan" >"$WORK/$k/tests"
  start_shard $k "" "$@"
  k=$((k + 1))
done
wait
# the failed shards once more (not one that was interrupted)
if [ "$RERUN" = 1 ]; then
  PIDS=
  k=1
  while [ $k -le "$JOBS" ]; do
    e=$(cat "$WORK/$k/exit" 2>/dev/null || echo 1)
    if ! shard_ok $k && [ "$e" != 130 ] && [ "$e" != 143 ]; then
      mv "$WORK/$k" "$WORK/$k.first"
      mkdir -p "$WORK/$k"
      cp "$WORK/$k.first/classes" "$WORK/$k.first/tests" "$WORK/$k/"
      start_shard $k rerun "$@"
    fi
    k=$((k + 1))
  done
  wait
fi

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
  [ -f "$WORK/$k/trace" ] && cat "$WORK/$k/trace"
  if [ -d "$WORK/$k.first" ]; then
    e1=$(cat "$WORK/$k.first/exit" 2>/dev/null || echo 1)
    if shard_ok $k; then
      rerun_flakes "$WORK/$k.first/log" "$log" "shard $k of $JOBS"
      echo "st_suite: shard $k of $JOBS failed (exit $e1) and passed on its rerun (a flake): $(cat "$WORK/$k/classes")"
    else
      rerun_fail_lines "$WORK/$k.first/log" | sed 's/^/rerun: 1| /'
      echo "st_suite: shard $k of $JOBS failed again on its rerun (exit $e1, then $e): $(cat "$WORK/$k/classes")"
    fi
  fi
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
  mkdir -p "$SHARED_TIMES_DIR" 2>/dev/null && cp "$TIMES" "$SHARED_TIMES_DIR/$KEY.$$" 2>/dev/null && mv "$SHARED_TIMES_DIR/$KEY.$$" "$SHARED_TIMES_DIR/$KEY"
fi
summary="$run run, $passed passed, $failed failed, $errors errors"
[ "$skipped" -gt 0 ] && summary="$summary, $skipped skipped"
summary="$summary in $ms ms"
[ "$run" -gt 0 ] && echo "$summary"
[ -n "$missing" ] && { echo "$missing" | sed 1d; exit 1; }
[ "$run" -gt 0 ] || summary=
verdict "$summary" $code
