#!/bin/sh
# The gates' failure ledger: every stage that tests/stages.sh runs is recorded (its tree, stage, result and failure
# lines) in SAMALTAK_LEDGER (default ~/.cache/samaltak/gate-ledger.tsv, shared by the machine's worktrees), and the
# report lists the failures by frequency: how often, in how many trees, and in how many of those trees the same stage
# also passed (a rerun of the same tree: a flake), and how often it passed on its automatic rerun (tests/lib/rerun.sh:
# recorded as result "flake" of a passed stage). Failure lines that passing stages print too (tests that run tests on
# purpose, an ignored make error) are left out.
# usage: tests/flakes.sh [report] [N]        the N most frequent failures (default 15)
#        tests/flakes.sh record TREE STAGE passed|failed LOG   (tests/stages.sh)
#        tests/flakes.sh known STAGE LOG     which of a failed stage's lines failed before, and how often (tests/stages.sh)
#        tests/flakes.sh import GATE-LOG...  earlier gates' logs (build/gate-runs/<id>.log, the tree from <id>.json)
set -u
TAB=$(printf '\t')
# lines every failed suite or stage prints, left out of the report
GENERIC='^make: [*][*][*]|^st_suite: FAILED [(]exit'
L=${SAMALTAK_LEDGER:-${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}/samaltak/gate-ledger.tsv}
mkdir -p "$(dirname "$L")" 2>/dev/null
# failure lines of a stage's log, without what changes from run to run (times, Makefile line numbers, pids)
lines() {
  tr -d '\r' | grep -a -v -E '^(rerun|flake): ' | grep -a -E '^(FAIL|ERROR) |^st_suite: FAILED|^make(\[[0-9]+\])?: \*\*\*|^test-uefi[^:]*: |^[a-z_-]+: FAILED|FAIL(ED)? ' \
    | norm
}
norm() { sed -E 's/Makefile:[0-9]+/Makefile/; s/make\[[0-9]+\]/make/; s/ in [0-9]+ ms//; s/[0-9]{4,}/N/g' | cut -c1-200 | sort -u; }
record() { # TIME TREE STAGE RESULT < log
  t=$1; tree=$2; stage=$3; res=$4
  log=$(tr -d '\r')
  out=$(printf '%s\t%s\t%s\t%s\t\n' "$t" "$tree" "$stage" "$res"
    printf '%s\n' "$log" | lines | while IFS= read -r l; do printf '%s\t%s\t%s\t%s\t%s\n' "$t" "$tree" "$stage" "$res" "$l"; done
    # the failures that passed on their rerun (tests/lib/rerun.sh)
    printf '%s\n' "$log" | grep -a '^flake: ' | sed 's/^flake: //' | norm | while IFS= read -r l; do printf '%s\t%s\t%s\tflake\t%s\n' "$t" "$tree" "$stage" "$l"; done)
  printf '%s\n' "$out" >>"$L"
}
case ${1:-report} in
record) [ $# -eq 5 ] || { echo "usage: tests/flakes.sh record TREE STAGE RESULT LOG"; exit 2; }
  record "$(date +%s)" "$2" "$3" "$4" <"$5" ;;
import) shift
  for f in "$@"; do
    j=${f%.log}.json; [ -f "$j" ] || continue
    tree=$(sed -n 's/.*"tree":"\([0-9a-f]*\)".*/\1/p' "$j"); t=$(sed -n 's/.*"started":\([0-9]*\).*/\1/p' "$j")
    grep -q "^$t$TAB$tree$TAB" "$L" 2>/dev/null && continue
    # the stages' logs, each between "=== stage S" and "stage S: passed|FAILED"
    awk -v d="${TMPDIR:-/tmp}/flakes.$$" 'BEGIN { system("mkdir -p " d) }
      /^=== stage / { s = $3; f = d "/" s; printf "" > f; next }
      s != "" && $0 ~ "^stage " s ": (passed|FAILED)" { print ($3 == "passed" ? "passed" : "failed") > (d "/" s ".result"); close(f); s = ""; next }
      s != "" { print > f }' "$f"
    for r in "${TMPDIR:-/tmp}/flakes.$$"/*.result; do
      [ -f "$r" ] || continue
      s=$(basename "$r" .result); record "$t" "$tree" "$s" "$(cat "$r")" <"${r%.result}"
    done
    rm -rf "${TMPDIR:-/tmp}/flakes.$$"
  done ;;
known) [ $# -eq 3 ] && [ -s "$L" ] || exit 0
  lines <"$3" | grep -v -E "$GENERIC" | while IFS= read -r l; do
    awk -F '\t' -v s="$2" -v l="$l" '$3 == s && $5 == "" && $4 == "passed" { p[$2] = 1 } $3 == s && $5 == l && ($4 == "failed" || $4 == "flake") { f++; t[$2] = 1 }
      $5 == l && $4 == "passed" { noise = 1 }
      END { for (k in t) { n++; if (k in p) b++ } if (f && !noise) printf "flakes: known: %s (failed %d times before, in %d trees, %d of which also passed)\n", l, f, n, b + 0 }' "$L"
  done ;;
report|[0-9]*) n=${2:-${1:-15}}; case $n in *[!0-9]*) n=15 ;; esac
  [ -s "$L" ] || { echo "flakes: no gates recorded in $L"; exit 0; }
  awk -F '\t' -v n="$n" -v now="$(date +%s)" -v generic="$GENERIC" '
    $5 == "" { runs++; if ($4 == "failed") fails++; res[$2 SUBSEP $3] = res[$2 SUBSEP $3] " " $4; next }
    $4 == "passed" { noise[$5] = 1; next }
    { key = $3 "\t" $5; c[key]++; if ($4 == "flake") rr[key]++; if (!((key, $2) in seen)) { seen[key, $2] = 1; trees[key]++; tl[key] = tl[key] " " $2 }
      if ($1 > last[key]) last[key] = $1 }
    END {
      printf "flakes: %d stage runs, %d failed (%s)\n", runs, fails, FILENAME
      m = 0
      for (k in c) {
        split(k, p, "\t"); if (p[2] in noise || p[2] ~ generic) continue
        split(substr(tl[k], 2), ts, " "); fl = 0
        for (i in ts) if (index(res[ts[i] SUBSEP p[1]], "passed")) fl++
        out[++m] = sprintf("%4d %3d %3d %3d  %s  %-17s %s", c[k], trees[k], fl, rr[k], sprintf("%5.1fh ago", (now - last[k]) / 3600), p[1], p[2])
      }
      printf "flakes: failures  trees  trees-that-also-passed  passed-on-rerun  last seen  stage  line\n"
      for (i = 1; i <= m; i++) print out[i] | "sort -k1,1nr -k3,3nr | head -" n
    }' "$L" ;;
*) sed -n '2,12p' "$0"; exit 2 ;;
esac
