#!/bin/sh
# usage: tests/rerun.sh NAME COMMAND...: COMMAND (a test script, a make part of a stage), once more when it fails
# (tests/lib/rerun.sh: SAMALTAK_TEST_RERUN; not when what failed was itself rerun, a suite's shard, or was
# interrupted). Its output comes at its end. A failure that passes on its rerun is a flake ("flake: <line>", and
# "rerun: NAME passed on its rerun (a flake)"); a second failure is the exit status. Each run has at most
# SAMALTAK_TEST_PART_TIMEOUT seconds (default 1200; 0: no limit): a hung one fails (exit 124) instead of the stage.
. "$(dirname "$0")/lib/rerun.sh"
name=$1
shift
limit=${SAMALTAK_TEST_PART_TIMEOUT:-1200}
if [ "$limit" != 0 ] && command -v timeout >/dev/null; then set -- timeout -k 30 "$limit" "$@"; fi
[ "$RERUN" = 1 ] || exec "$@"
dir=$(mktemp -d "${TMPDIR:-/tmp}/rerun.XXXXXX") || exec "$@"
trap 'rm -rf "$dir"' EXIT
trap 'exit 143' INT TERM HUP
"$@" >"$dir/1" 2>&1
e=$?
if [ $e = 0 ] || [ $e = 130 ] || [ $e = 143 ] || grep -q -a -E 'again on its rerun' "$dir/1"; then
  cat "$dir/1"
  exit $e
fi
echo "rerun: $name failed (exit $e), running it once more; its first run:"
rerun_first "$dir/1"
"$@" >"$dir/2" 2>&1
e2=$?
cat "$dir/2"
if [ $e2 = 0 ]; then
  rerun_flakes "$dir/1" "$dir/2" "$name"
  echo "rerun: $name passed on its rerun (a flake)"
else
  echo "rerun: $name failed again on its rerun (exit $e2)"
fi
exit $e2
