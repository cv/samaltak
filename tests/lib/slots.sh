# The machine's test slots (sourced by tests/st_suite.sh and tests/with-slot): every test VM or QEMU first takes one
# of SAMALTAK_TEST_SLOTS lock files in SAMALTAK_TEST_SLOT_DIR (default /tmp/samaltak-test-slots-<uid>, with flock(1)),
# so that concurrent suites and boots (gate stages, several agents' gates) together run at most that many; the rest
# wait for a slot. The default: three quarters of the CPUs (15 of 20, 3 of 4: a test VM keeps about one busy, its
# renderer and compiler threads some more), at most one per 3 GB of available memory, at least 1.
SLOT_NPROC=$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)
slot_default() {
  n=$(( SLOT_NPROC * 3 / 4 ))
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
# writable slot directory, COMMAND just runs. A waiter looks for a free slot every second; one on a gate's critical path
# (SLOT_PRIORITY=1: tests/st_suite.sh's shard with the longest class, the RFB scenarios) every 0.2 s, and may also take
# one of SAMALTAK_TEST_SLOTS_RESERVED more slots (default a fifth of the slots, at least 1) that only such waiters use,
# so that the longest work starts first. With SAMALTAK_TIMELINE, the wait for the slot is an event ("slot-wait",
# SLOT_LABEL).
RESERVED=${SAMALTAK_TEST_SLOTS_RESERVED:-$(( SLOTS / 5 ))}
case $RESERVED in ''|*[!0-9]*) RESERVED=1 ;; esac
[ "$RESERVED" -lt 1 ] && [ -z "${SAMALTAK_TEST_SLOTS_RESERVED:-}" ] && RESERVED=1
with_slot() {
  if ! command -v flock >/dev/null 2>&1 || ! mkdir -p "$SLOT_DIR" 2>/dev/null || ! [ -w "$SLOT_DIR" ]; then
    "$@"; return
  fi
  slot_t0=$(tl_now)
  slot_last=$SLOTS; slot_poll=1
  [ "${SLOT_PRIORITY:-}" = 1 ] && { slot_last=$(( SLOTS + RESERVED )); slot_poll=0.2; }
  while :; do
    i=1
    while [ $i -le "$slot_last" ]; do
      ( flock -n 9 || exit 75; tl_add "$slot_t0" "$(tl_now)" 0 slot-wait "slot $i: ${SLOT_LABEL:-$*}"; "$@" 9>&- ) 9>>"$SLOT_DIR/slot$i"
      s=$?
      [ $s = 75 ] || return $s
      i=$((i + 1))
    done
    sleep $slot_poll
  done
}
