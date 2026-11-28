#!/bin/sh
# The image's Smalltalk tests, headless; fails unless they ran (at least one), all passed and none was skipped.
# usage: tests/st_suite.sh IMAGE [VM option...] [-- test names]   e.g. tests/st_suite.sh build/samaltak.image --eden 1 -- Tests-Kernel
# SAMALTAK_TEST_TRACE=1 reports the last test started if no summary is printed.
set -u
cd "$(dirname "$0")/.."
IMAGE=$1
shift
VMOPTS=
while [ $# -gt 0 ] && [ "$1" != "--" ]; do VMOPTS="$VMOPTS $1"; shift; done
[ $# -gt 0 ] && shift
LOG=$(mktemp)
trap 'rm -f "$LOG"' EXIT
# shellcheck disable=SC2086
vm/build/samaltak $VMOPTS "$IMAGE" --headless --test "$@" >"$LOG" 2>&1
code=$?
summary=$(grep -E '^[0-9]+ run, ' "$LOG" | tail -1)
if [ "${SAMALTAK_TEST_TRACE:-}" = 1 ]; then
  sed '/^st_suite: starting /d' "$LOG"
  [ -n "$summary" ] || grep '^st_suite: starting ' "$LOG" | tail -1
else
  cat "$LOG"
fi
case "$summary" in
  '') echo "st_suite: FAILED: no test summary (exit $code)"; exit 1 ;;
  '0 run'*) echo "st_suite: FAILED: no tests ran"; exit 1 ;;
  *skipped*) echo "st_suite: FAILED: tests were skipped: $summary"; exit 1 ;;
esac
[ $code -eq 0 ] || { echo "st_suite: FAILED (exit $code): $summary"; exit 1; }
