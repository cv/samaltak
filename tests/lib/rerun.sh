# shellcheck shell=sh
# Reruns (sourced by tests/rerun.sh and tests/st_suite.sh): a test VM's shard, a suite or a test script that fails is
# run once more (SAMALTAK_TEST_RERUN=1, the default; 0: once only). A failure that passes on its rerun is a flake: the
# failure lines of the first run that the passing rerun does not print (tests that run failing tests on purpose print
# theirs every time) are printed as "flake: <line>", which tests/stages.sh lists and tests/flakes.sh records; the
# first run's output follows prefixed "rerun: 1| ". A second failure fails as before, the rerun's output printed as
# it is, with a line "... failed again on its rerun" (a wrapping rerun.sh does not run it a third time).
RERUN=${SAMALTAK_TEST_RERUN:-1}
case $RERUN in 0|1) ;; *) RERUN=1 ;; esac
# rerun_fail_lines LOG: its failure lines (those tests/flakes.sh records), without earlier runs' (prefixed)
rerun_fail_lines() {
  tr -d '\r' <"$1" | grep -a -v -E '^(rerun|flake): ' \
    | grep -a -E '^(FAIL|ERROR) |^st_suite: FAILED|^make(\[[0-9]+\])?: \*\*\*|^test-uefi[^:]*: |^[a-z_-]+: FAILED|FAIL(ED)? '
}
# rerun_flakes FIRST SECOND NAME: FIRST's failure lines that SECOND (which passed) has not, numbers aside, as
# "flake: <line>" (not make's and st_suite's generic lines); "flake: NAME failed: <its last line>" if there are none.
rerun_flakes() {
  rerun_fail_lines "$2" | sed -E 's/[0-9]+/N/g' | sort -u >"$1.seen"
  last=$(tr -d '\r' <"$1" | grep -a -v -E '^make(\[[0-9]+\])?: |^rerun: |^flake: ' | grep -a . | tail -n 1 | cut -c1-200)
  rerun_fail_lines "$1" | grep -a -v -E '^make(\[[0-9]+\])?: \*\*\*|^st_suite: FAILED [(]exit' | awk -v seen="$1.seen" -v name="$3" -v last="$last" '
    BEGIN { while ((getline l < seen) > 0) s[l] = 1 }
    { k = $0; gsub(/[0-9]+/, "N", k); if (!(k in s) && !(k in done)) { done[k] = 1; n++; print "flake: " $0 } }
    END { if (!n) print "flake: " name " failed: " last }'
  rm -f "$1.seen"
}
# rerun_first LOG: the first run's output, prefixed "rerun: 1| ": all of it up to 300 lines, else its failure lines
# and its last 200 lines
rerun_first() {
  if [ "$(wc -l <"$1")" -le 300 ]; then
    tr -d '\r' <"$1" | sed 's/^/rerun: 1| /'
  else
    rerun_fail_lines "$1" | sed 's/^/rerun: 1| /'
    echo "rerun: 1| ... (its last 200 lines)"
    tr -d '\r' <"$1" | tail -n 200 | sed 's/^/rerun: 1| /'
  fi
}
