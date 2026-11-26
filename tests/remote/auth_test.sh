#!/bin/sh
# Headless auth integration, against a disposable VM only.
# usage: tests/remote/auth_test.sh [image]  (default: build/samaltak.image)
#        tests/remote/auth_test.sh --session name  (disposable CLI-opened UEFI guest)
set -u
cd "$(dirname "$0")/../.." || exit 1
umask 077
# Never put credentials in this script's trace, even if called with sh -x.
set +x
TMP=$(mktemp -d) || exit 1
CTL=tools/samaltak-ctl
own=
if [ "${1:-}" = --session ]; then
  S=$2
else
  own=1
  S=auth-test
  IMAGE=${1:-build/samaltak.image}
  export TMPDIR="$TMP"
fi
SESSIONS=${TMPDIR:-/tmp}/samaltak-ctl
J=$SESSIONS/$S.json
fails=0
generated_pid=
fake_pid=
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
check() {
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1"; fi
}
absent() {
  if [ ! -e "$2" ]; then pass "$1"; else fail "$1"; fi
}
stop_child() {
  kill "$1" 2>/dev/null || :
  wait "$1" 2>/dev/null || :
}
cleanup() {
  [ -z "$own" ] || "$CTL" --session "$S" close >/dev/null 2>&1
  [ -z "$generated_pid" ] || stop_child "$generated_pid"
  [ -z "$fake_pid" ] || stop_child "$fake_pid"
  rm -f "$SESSIONS/$S-connected-$$.json"
  rm -rf "$TMP"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

if [ -n "$own" ]; then
  unset SAMALTAK_CONTROL_TOKEN SAMALTAK_CONTROL_PORT
  "$CTL" --session "$S" open --headless --image "$IMAGE" >"$TMP/open" 2>&1 || { fail "open"; exit 1; }
fi
field() {
  node -e '
    const s = JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"));
    process.stdout.write(String(s[process.argv[2]] ?? ""));
  ' "$J" "$1"
}
token=$(field token)
port=$(field port)
if ! printf '%s\n' "$token" | grep -Eq '^[0-9a-f]{32}$' ||
   ! printf '%s\n' "$port" | grep -Eq '^[1-9][0-9]*$'; then
  fail "the session has a 32-digit hex token and a port"
  exit 1
fi
pass "the session has a 32-digit hex token and a port"
mode() { ls -ld "$1" 2>/dev/null | cut -c1-10; }
check "the open session file is owner-only" "-rw-------" "$(mode "$J")"
if [ -n "$own" ]; then
  check "the launcher token file is owner-only" "-rw-------" "$(mode "$SESSIONS/$S.token")"
fi
eval_remote() { "$CTL" --session "$S" eval "$1" 2>/dev/null; }
check "authenticated eval" 7 "$(eval_remote '3 + 4')"

no_token_in() {
  printf '%s\n' "$token" | grep -aFq -f - "$2"
  check "$1" 1 "$?"
}
if [ -n "$own" ]; then
  # Ordinary authenticated eval and save: exercise a live save, then look for the literal
  # token in this one image file only. This is not a general snapshot secrecy guarantee.
  check "authenticated snapshot completes" "false" "$(eval_remote "Smalltalk snapshot: '$TMP/ordinary.image'")"
  no_token_in "no literal session token in the ordinary snapshot" "$TMP/ordinary.image"
  check "the live client still works after a snapshot" 8 "$(eval_remote '4 + 4')"
fi

# All five lines use the same socket: one accepted request must not authenticate later ones.
# The dummy wrong token differs in the first digit, so it can never be the real one.
case "$token" in
  0*) wrong=1${token#?} ;;
  *) wrong=0${token#?} ;;
esac
source='Smalltalk at: #AuthTestRan put: true'
raw() {
  node -e '
    const input = require("node:fs").readFileSync(0, "utf8");
    const socket = require("node:net").createConnection({host: "127.0.0.1", port: +process.argv[1]});
    const count = input.split("\n").length - 1;
    let response = "";
    socket.setEncoding("utf8");
    socket.setTimeout(20000, () => socket.destroy(new Error("response timeout")));
    socket.on("connect", () => socket.write(input));
    socket.on("data", chunk => {
      response += chunk;
      if (response.split("\n").length > count) {
        process.stdout.write(response);
        socket.destroy();
      }
    });
    socket.on("error", () => { process.exitCode = 1; });
  ' "$port"
}
{
  printf '{"id":11,"cmd":"ping","auth":"%s"}\n' "$token"
  printf '{"id":12,"cmd":"eval","source":"%s"}\n' "$source"
  printf '{"id":13,"cmd":"eval","source":"%s","auth":"%s"}\n' "$source" "$wrong"
  printf '{"id":14,"cmd":"eval","source":"%s","auth":"%s"}\n' "$source" "${wrong#?}"
  printf '{"id":15,"cmd":"ping","auth":"%s"}\n' "$token"
} | raw >"$TMP/responses"
node -e '
  const assert = require("node:assert/strict");
  try {
    const r = require("node:fs").readFileSync(0, "utf8").trimEnd().split("\n").map(line => JSON.parse(line));
    assert.deepEqual(r.map(x => x.id), [11, 12, 13, 14, 15]);
    for (const x of [r[0], r[4]]) assert(x.ok === true && x.pong === true && x.controlAuth === 1);
    for (const x of r.slice(1, 4)) assert(x.ok === false && x.code === 4 && typeof x.error === "string");
  } catch (_) { process.exitCode = 1; }
' <"$TMP/responses"
check "authenticated ping marker and per-request refusal on one socket" 0 "$?"
check "refused commands have no side effect" "false" "$(eval_remote 'Smalltalk includesKey: #AuthTestRan')"
no_token_in "no actual token in the raw responses" "$TMP/responses"

connected=$S-connected-$$
CJ=$SESSIONS/$connected.json
printf '%s\n' "$wrong" >"$TMP/wrong"
connect() { "$CTL" --session "$connected" connect --port "$1" --token-file "$2"; }
connect "$port" "$TMP/wrong" >"$TMP/connect" 2>&1
check "connect with the wrong token fails with code 4" 4 "$?"
absent "a wrong token creates no session file" "$CJ"
connect "$port" "$TMP/none" >"$TMP/connect" 2>&1
check "connect without a token file fails" 1 "$?"

# A fake legacy control service simply returns a pong, with no marker or a string marker.
# It listens on an ephemeral loopback port and never runs a command.
wait_for_file() {
  i=0
  while [ ! -s "$1" ] && kill -0 "$2" 2>/dev/null && [ "$i" -lt 200 ]; do
    sleep 0.1
    i=$((i + 1))
  done
  [ -s "$1" ]
}
for marker in missing string; do
  rm -f "$TMP/fake-port"
  node -e '
    const server = require("node:net").createServer(s => {
      s.on("error", () => {});
      s.setEncoding("utf8");
      let input = "";
      s.on("data", chunk => {
        input += chunk;
        if (!input.includes("\n")) return;
        const reply = {id: 1, ok: true, pong: true};
        if (process.argv[1] === "string") reply.controlAuth = "1";
        s.end(JSON.stringify(reply) + "\n");
      });
    });
    server.listen(0, "127.0.0.1", () => process.stdout.write(String(server.address().port)));
  ' "$marker" >"$TMP/fake-port" &
  fake_pid=$!
  if wait_for_file "$TMP/fake-port" "$fake_pid"; then
    connect "$(cat "$TMP/fake-port")" "$TMP/wrong" >"$TMP/connect" 2>&1
    check "connect refuses pong with a $marker auth marker" 1 "$?"
    absent "a $marker marker creates no session file" "$CJ"
  else
    fail "start fake service"
  fi
  stop_child "$fake_pid"
  fake_pid=
done

# Grouped, uppercase and with whitespace at the ends, via a private token file.
printf '  %s  \n' "$token" | tr 'a-f' 'A-F' | sed 's/[0-9A-F]\{8\}/&-/g; s/-  $/  /' >"$TMP/right"
connect "$port" "$TMP/right" >"$TMP/connect" 2>&1
check "connect accepts a grouped uppercase token from file" 0 "$?"
check "the connected session file is owner-only" "-rw-------" "$(mode "$CJ")"
check "eval through the connected session" 42 "$("$CTL" --session "$connected" eval '6 * 7' 2>/dev/null)"
"$CTL" --session "$connected" close >"$TMP/close" 2>&1
check "close of a connected session succeeds" 0 "$?"
absent "close removes the connected session file" "$CJ"
check "close of a connected session leaves the image running" 9 "$(eval_remote '3 * 3')"

if ps -ww -eo args >"$TMP/argv"; then
  no_token_in "no token in the live host process argument listing" "$TMP/argv"
else
  fail "read host process argument listing"
fi
log=$(field log)
no_token_in "no token in the CLI-started image log" "$log"

if [ -n "$own" ]; then
  # An unprovisioned VM generates a token, shows it once and accepts it.
  vm/build/samaltak "$IMAGE" --headless --control --control-host 127.0.0.1 --control-port 0 \
    --control-port-file "$TMP/generated-port" >"$TMP/generated-log" 2>&1 </dev/null &
  generated_pid=$!
  if wait_for_file "$TMP/generated-port" "$generated_pid" &&
     timeout 20 sh -c 'until grep -q "^control: token " "$1"; do sleep 0.1; done' sh "$TMP/generated-log"; then
    sed -n 's/^control: token //p' "$TMP/generated-log" >"$TMP/generated-token"
    check "generated token is announced once in four groups" 1 \
      "$(grep -Ecx '[0-9a-fA-F]{8}(-[0-9a-fA-F]{8}){3}' "$TMP/generated-token")"
    connect "$(cat "$TMP/generated-port")" "$TMP/generated-token" >"$TMP/connect" 2>&1
    check "connect accepts the generated token" 0 "$?"
    "$CTL" --session "$connected" close --quit >"$TMP/close" 2>&1
    check "close --quit requests VM shutdown" 0 "$?"
    absent "close --quit removes the connected session file" "$CJ"
    if timeout 20 sh -c 'while kill -0 "$1" 2>/dev/null; do sleep 0.1; done' sh "$generated_pid"; then
      wait "$generated_pid"
      check "close --quit shuts down the connected VM cleanly" 0 "$?"
      generated_pid=
    else
      fail "connected VM did not quit"
    fi
  else
    fail "unprovisioned VM did not start or announce a token"
  fi

  # Correct length but non-hex: invalid configuration must not enable the listener.
  printf 'zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz\n' >"$TMP/invalid"
  timeout 20 vm/build/samaltak "$IMAGE" --headless --control --control-host 127.0.0.1 --control-port 0 \
    --control-port-file "$TMP/invalid-port" --control-token-file "$TMP/invalid" --eval 1 \
    >"$TMP/invalid-log" 2>&1 </dev/null
  status=$?
  if [ "$status" != 124 ] && [ ! -e "$TMP/invalid-port" ] &&
     grep -Fq 'control: expected 32 hexadecimal control token digits' "$TMP/invalid-log" &&
     ! grep -Fq 'control: listening' "$TMP/invalid-log"; then
    pass "an invalid configured token does not start a listener"
  else
    fail "an invalid configured token did not fail closed"
  fi
fi

if [ "$fails" -eq 0 ]; then echo "auth_test: all passed"; else echo "auth_test: $fails failed"; exit 1; fi
