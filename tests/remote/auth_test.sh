#!/bin/sh
# The control service's token (docs/remote.md): a request without it, or with another, is refused (code 4) and runs
# nothing; the session's token works, also through samaltak-ctl connect --token-file (as the image shows it, in groups);
# a wrong one makes no session; the token is in no process's command line (ps) and not in the session's log; the
# session file is the owner's alone.
# usage: tests/remote/auth_test.sh [image]          a headless session of its own (default: build/samaltak.image)
#        tests/remote/auth_test.sh --session name   an open session (test-uefi: the VM on UEFI)
set -u
cd "$(dirname "$0")/../.."
CTL=tools/samaltak-ctl
SESSIONS=${TMPDIR:-/tmp}/samaltak-ctl
TMP=$(mktemp -d)
own=
if [ "${1:-}" = --session ]; then S=$2; else S=auth-test-$$; own=1; IMAGE=${1:-build/samaltak.image}; fi
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
check() { # name expected actual
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1: expected [$2], got [$3]"; fi
}
contains() { # name haystack needle
  case "$2" in *"$3"*) pass "$1" ;; *) fail "$1: [$3] not in [$2]" ;; esac
}
gpid=
cleanup() {
  [ -n "$own" ] && $CTL --session "$S" close >/dev/null 2>&1
  [ -n "$gpid" ] && kill -KILL "$gpid" 2>/dev/null
  rm -f "$SESSIONS/$S-made.json"
  rm -f "$SESSIONS/$S-remote.json" "$SESSIONS/$S-bad.json"
  rm -rf "$TMP"
}
trap cleanup EXIT

if [ -n "$own" ]; then
  $CTL --session "$S" open --headless --image "$IMAGE" >"$TMP/open" 2>&1 || { cat "$TMP/open"; echo "FAIL open"; exit 1; }
fi
J=$SESSIONS/$S.json
field() { node -e 'const s = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")); process.stdout.write(String(s[process.argv[2]] ?? ""))' "$J" "$1"; }
T=$(field token)
P=$(field port)
check "the session has a token of 32 hex digits" "32" "$(printf %s "$T" | tr -cd 0-9a-f | wc -c | tr -d ' ')"
check "the session file is the owner's alone" "-rw-------" "$(ls -l "$J" | cut -c1-10)"
check "eval with the session's token" "7" "$($CTL --session "$S" eval '3 + 4')"

# A request straight to the port: prints the response line.
raw() { node -e '
  const s = require("net").createConnection({ host: "127.0.0.1", port: +process.argv[1] });
  let b = ""; s.setEncoding("utf8");
  s.on("connect", () => s.write(process.argv[2] + "\n"));
  s.on("data", d => { b += d; if (b.includes("\n")) { process.stdout.write(b.split("\n")[0]); s.end(); } });
  s.on("error", e => { process.stdout.write("error " + e.message); });
  setTimeout(() => { process.stdout.write("no answer"); process.exit(1); }, 20000).unref();' "$P" "$1"; }
out=$(raw '{"id": 11, "cmd": "eval", "source": "Smalltalk at: #AuthTestRan put: true"}')
contains "no token: refused" "$out" '"code":4'
contains "no token: says unauthorized" "$out" 'unauthorized'
contains "no token: answers the request's id" "$out" '"id":11'
out=$(raw '{"id": 12, "cmd": "eval", "source": "Smalltalk at: #AuthTestRan put: true", "auth": "0123456789abcdef0123456789abcdef"}')
contains "a wrong token: refused" "$out" '"code":4'
out=$(raw "{\"id\": 13, \"cmd\": \"eval\", \"source\": \"Smalltalk at: #AuthTestRan put: true\", \"auth\": \"$(printf %s "$T" | cut -c1-31)\"}")
contains "a token one short: refused" "$out" '"code":4'
check "nothing refused ran" "false" "$($CTL --session "$S" eval 'Smalltalk includesKey: #AuthTestRan')"

umask 077
printf '0123456789abcdef0123456789abcdef\n' >"$TMP/wrong"
out=$($CTL --session "$S-bad" connect --port "$P" --token-file "$TMP/wrong" 2>&1); code=$?
check "connect with a wrong token: exit 1" "1" "$code"
contains "connect with a wrong token: says unauthorized" "$out" "unauthorized"
[ -e "$SESSIONS/$S-bad.json" ] && fail "connect with a wrong token made a session" || pass "connect with a wrong token made no session"
out=$($CTL --session "$S-bad" connect --port "$P" --token-file "$TMP/none" 2>&1); code=$?
check "connect without a token file: exit 1" "1" "$code"

# As the image shows a token it made: groups of four.
printf '%s\n' "$T" | sed 's/..../&-/g; s/-$//' >"$TMP/right"
out=$($CTL --session "$S-remote" connect --port "$P" --token-file "$TMP/right" 2>&1); code=$?
check "connect with the token, grouped: exit 0" "0" "$code"
check "eval through the connected session" "42" "$($CTL --session "$S-remote" eval '6 * 7')"
check "the connected session's file is the owner's alone" "-rw-------" "$(ls -l "$SESSIONS/$S-remote.json" | cut -c1-10)"
$CTL --session "$S-remote" close >/dev/null; code=$?
check "close of a connected session: exit 0" "0" "$code"
check "close of a connected session leaves the image running" "9" "$($CTL --session "$S" eval '3 * 3')"

ps -eo args | T="$T" awk 'index($0, ENVIRON["T"]) { found = 1 } END { exit found }' \
  && pass "the token is in no command line (ps)" || fail "the token is on a command line (ps)"
L=$(field log)
if [ -n "$L" ] && [ -f "$L" ]; then
  grep -qF "$T" "$L" && fail "the token is in the session's log $L" || pass "the token is not in the session's log"
fi

if [ -n "$own" ]; then
  # Started with --control and no token (as on a bare-metal machine): the image makes one and shows it once, on stdout.
  vm/build/samaltak "$IMAGE" --headless --control --control-port 0 --control-port-file "$TMP/gport" >"$TMP/glog" 2>&1 </dev/null &
  gpid=$!
  i=0; until grep -q 'control: token' "$TMP/glog" 2>/dev/null && [ -s "$TMP/gport" ] || [ $i -ge 300 ]; do i=$((i + 1)); sleep 0.1; done
  shown=$(sed -n 's/^control: token \([0-9a-f-]*\) .*/\1/p' "$TMP/glog")
  check "a token the image made: shown in groups of four" "39" "$(printf %s "$shown" | wc -c | tr -d ' ')"
  printf '%s\n' "$shown" >"$TMP/shown"
  $CTL --session "$S-made" connect --port "$(cat "$TMP/gport")" --token-file "$TMP/shown" >/dev/null 2>&1
  check "connect with the token the image showed" "#made" "$($CTL --session "$S-made" eval '#made' 2>&1)"
  $CTL --session "$S-made" close --quit >/dev/null 2>&1
  wait "$gpid"; check "close --quit of a connected session quits the image" "0" "$?"
  gpid=
  # A token too short to be a secret: the service does not listen.
  printf 'abc\n' >"$TMP/short"
  out=$(timeout 60 vm/build/samaltak "$IMAGE" --headless --control --control-port 0 --control-token-file "$TMP/short" --eval 1 2>&1 </dev/null)
  contains "a short token: not listening" "$out" "control: the token has fewer than 16 characters: not listening"
fi

[ $fails -eq 0 ] && echo "auth_test: all passed" || echo "auth_test: $fails failed"
exit $fails
