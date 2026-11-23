#!/bin/sh
# A snapshot resumed twice must not answer the same random bytes twice: not from SecureRandom default when the
# resumed do-it asks, not in the session token ControlServer's startUp: makes (it used to come from the snapshot's
# key, the same in every run of the file: SecureRandom reseeded only at its own place in the startup list, after
# ControlServer). The run that wrote the snapshot must not share them either.
# usage: tests/boot/resume_rng_test.sh IMAGE
set -u
cd "$(dirname "$0")/../.."
IMAGE=$1
VM=vm/build/samaltak
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
# a free port on 127.0.0.1 for the control service of the resumed runs
port() { python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])'; }
# the random lines of one run, the token as its SHA-256 (the test never prints a token)
lines() { grep -E '^(rng|control: token) ' "$1" | sed 's/^control: token \([0-9a-f-]*\).*/token \1/' | while read -r k v; do
  [ "$k" = token ] && v=$(printf %s "$v" | sha256sum | cut -c1-16); echo "$k $v"; done; }

EXPR="| lf | lf := String with: Character lf. SecureRandom default nextBytes: 8. (Smalltalk snapshot: '$TMP/snap.image') ifTrue: [Smalltalk vm stderrWrite: 'rng resumed ', (SecureRandom default nextBytes: 16) hex, lf. Smalltalk quit: 0]. Smalltalk vm stderrWrite: 'rng saved ', (SecureRandom default nextBytes: 16) hex, lf. Smalltalk quit: 0"
timeout 120 "$VM" "$IMAGE" --headless --eval "$EXPR" </dev/null >"$TMP/saved" 2>&1
grep -q '^rng saved ' "$TMP/saved" && [ -s "$TMP/snap.image" ] && pass "snapshot written" || { fail "snapshot written"; cat "$TMP/saved"; exit 1; }

for i in 1 2; do
  env -u SAMALTAK_CONTROL_TOKEN timeout 120 "$VM" "$TMP/snap.image" --headless --control --control-port "$(port)" </dev/null >"$TMP/run$i" 2>&1
  lines "$TMP/run$i" >"$TMP/lines$i"
  if grep -q '^rng resumed ' "$TMP/lines$i" && grep -q '^token ' "$TMP/lines$i"; then pass "resume $i: random bytes and a made token"
  else fail "resume $i: no random bytes or token"; sed 's/token [0-9a-f-]*/token <redacted>/' "$TMP/run$i" | tail -10; fi
done

r1=$(grep '^rng ' "$TMP/lines1" | cut -d' ' -f3); r2=$(grep '^rng ' "$TMP/lines2" | cut -d' ' -f3); r0=$(grep '^rng saved ' "$TMP/saved" | cut -d' ' -f3)
t1=$(grep '^token ' "$TMP/lines1"); t2=$(grep '^token ' "$TMP/lines2")
[ -n "$r1" ] && [ "$r1" != "$r2" ] && [ "$r1" != "$r0" ] && [ "$r2" != "$r0" ] && pass "SecureRandom: each run its own bytes" || fail "SecureRandom replayed: saved $r0, resumed $r1 and $r2"
[ -n "$t1" ] && [ "$t1" != "$t2" ] && pass "the session token: each resume its own" || fail "the session token replayed across resumes ($t1 / $t2)"

[ $fails -eq 0 ] || { echo "resume_rng_test: $fails failed"; exit 1; }
echo "resume_rng_test: all passed"
