# Timeline events (sourced): tl_now, the time in epoch seconds with milliseconds; tl_add START END EXIT WHAT TEXT
# [ID] appends a line "START END EXIT STAGE ID PARENT<tab>WHAT<tab>TEXT" to SAMALTAK_TIMELINE, if set (one short
# write: lines of concurrent writers do not mix). STAGE: SAMALTAK_TIMELINE_STAGE; PARENT: SAMALTAK_TIMELINE_PARENT,
# the ID of the event this one is part of (tests/timed-sh sets it for what a recipe line runs). tests/timeline.sh
# reports the file.
tl_now() {
  t=$(date +%s%3N)
  case $t in *N) t=$(date +%s)000 ;; esac
  echo "${t%???}.${t#${t%???}}"
}
tl_add() {
  [ -n "${SAMALTAK_TIMELINE:-}" ] || return 0
  printf '%s %s %s %s %s %s\t%s\t%.200s\n' "$1" "$2" "$3" "${SAMALTAK_TIMELINE_STAGE:--}" "${6:--}" \
    "${SAMALTAK_TIMELINE_PARENT:--}" "$4" "$(printf '%s' "$5" | tr '\n\t' '  ')" >>"$SAMALTAK_TIMELINE"
}
