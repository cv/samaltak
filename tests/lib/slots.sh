# The machine's test slots (sourced by tests/st_suite.sh and tests/with-slot): every test VM or QEMU first takes one
# of SAMALTAK_TEST_SLOTS lock files in SAMALTAK_TEST_SLOT_DIR (default /tmp/samaltak-test-slots-<uid>, with flock(1)),
# so that concurrent suites and boots (gate stages, several agents' gates) together run at most that many; the rest
# wait for a slot. The default: four fifths of the CPUs (16 of 20, 3 of 4: a test VM keeps about one busy), at most
# one per 3 GB of available memory, at least 1.
SLOT_NPROC=$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)
slot_default() {
  n=$(( SLOT_NPROC * 4 / 5 ))
  m=$(awk '/^MemAvailable:/ { print int($2 / 3145728) }' /proc/meminfo 2>/dev/null)
  case $m in ''|*[!0-9]*) ;; *) [ "$m" -lt "$n" ] && n=$m ;; esac
  [ "$n" -lt 1 ] && n=1
  echo $n
}
SLOTS=${SAMALTAK_TEST_SLOTS:-$(slot_default)}
case $SLOTS in ''|*[!0-9]*) SLOTS=1 ;; esac
[ "$SLOTS" -lt 1 ] && SLOTS=1
SLOT_DIR=${SAMALTAK_TEST_SLOT_DIR:-/tmp/samaltak-test-slots-$(id -u)}
. "$(dirname "$0")/lib/timeline.sh"

# with_slot COMMAND...: run COMMAND holding one of the machine's test slots (a lock on a slot file, which the
# subshell holds; exit 75 when it is taken: then the next one, and after all of them again a second later; COMMAND
# runs with the lock's descriptor closed, so that nothing it leaves behind keeps the slot). Without flock(1) or a
# writable slot directory, COMMAND just runs. A waiter looks for a free slot every SLOT_POLL seconds (default 1;
# tests/st_suite.sh's shard with the longest class 0.2: it gets the next free slot first). With SAMALTAK_TIMELINE, the
# wait for the slot is an event ("slot-wait", SLOT_LABEL).
with_slot() {
  if ! command -v flock >/dev/null 2>&1 || ! mkdir -p "$SLOT_DIR" 2>/dev/null || ! [ -w "$SLOT_DIR" ]; then
    "$@"; return
  fi
  slot_t0=$(tl_now)
  while :; do
    i=1
    while [ $i -le "$SLOTS" ]; do
      ( flock -n 9 || exit 75; tl_add "$slot_t0" "$(tl_now)" 0 slot-wait "slot $i: ${SLOT_LABEL:-$*}"; "$@" 9>&- ) 9>>"$SLOT_DIR/slot$i"
      s=$?
      [ $s = 75 ] || return $s
      i=$((i + 1))
    done
    sleep "${SLOT_POLL:-1}"
  done
}
