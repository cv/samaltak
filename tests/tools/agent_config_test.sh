#!/bin/sh
# samaltak-ctl agent-config: the agent's API key reaches the image from a key command or the environment, nothing
# prints it, the image's answers and printStrings leave it out, and a snapshot does not contain it. Works on a copy of
# the image in a scratch dir, headless.
# usage: tests/tools/agent_config_test.sh [image]   (default: build/samaltak.image)
set -u
cd "$(dirname "$0")/../.."
IMAGE=${1:-build/samaltak.image}
CTL=tools/samaltak-ctl
export SAMALTAK_SESSION=agent-config-test-$$
unset SAMALTAK_AGENT_KEY ANTHROPIC_API_KEY
SCRATCH=$(mktemp -d)
LOG=${TMPDIR:-/tmp}/samaltak-ctl/$SAMALTAK_SESSION.log
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
check() { # name expected actual
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1: expected [$2], got [$3]"; fi
}
contains() { # name haystack needle
  case "$2" in *"$3"*) pass "$1" ;; *) fail "$1: [$3] not in [$2]" ;; esac
}
lacks() { # name haystack secret (the secret is never shown)
  case "$2" in *"$3"*) fail "$1: the key is there" ;; *) pass "$1" ;; esac
}
newkey() { echo "sk-test-$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"; }
cleanup() { $CTL close >/dev/null 2>&1; rm -rf "$SCRATCH"; }
trap cleanup EXIT

cp "$IMAGE" "$SCRATCH/test.image"
$CTL open --headless --image "$SCRATCH/test.image" >/dev/null 2>&1 || { echo "FAIL open"; exit 1; }

out=$($CTL agent-config 2>&1)
contains "no key at first" "$out" '"hasKey":false'
contains "Anthropic's API by default" "$out" '"baseUrl":"https://api.anthropic.com"'

# the key from a program's stdout
KEY=$(newkey)
(umask 077; echo "$KEY" > "$SCRATCH/key")
out=$($CTL agent-config --model claude-test --thinking high --max-tokens 2000 --key-command "cat '$SCRATCH/key'" 2>&1)
contains "configured" "$out" '"model":"claude-test"'
contains "the image has the key" "$out" '"hasKey":true'
lacks "the answer leaves the key out" "$out" "$KEY"
check "the key arrived whole" "${#KEY}" "$($CTL eval 'ApiKeyAccount default apiKey size')"
lacks "the account's printString leaves the key out" "$($CTL eval 'ApiKeyAccount default printString')" "$KEY"
check "conversations talk to an AnthropicProvider" true "$($CTL eval 'AgentConversation new provider isKindOf: AnthropicProvider')"

# the key from the environment; a setting alone keeps the rest
KEY2=$(newkey)
out=$(ANTHROPIC_API_KEY=$KEY2 $CTL agent-config --thinking off 2>&1)
contains "thinking off" "$out" '"thinking":null'
contains "the model stays" "$out" '"model":"claude-test"'
lacks "the answer leaves the second key out" "$out" "$KEY2"
check "the key from ANTHROPIC_API_KEY" "'$(echo "$KEY2" | tail -c 9)'" "$($CTL eval 'ApiKeyAccount default apiKey last: 8')"
KEY3=$(newkey)
out=$(SAMALTAK_AGENT_KEY=$KEY3 ANTHROPIC_API_KEY=$KEY2 $CTL agent-config --max-tokens 4000 2>&1)
check "SAMALTAK_AGENT_KEY comes first" "'$(echo "$KEY3" | tail -c 9)'" "$($CTL eval 'ApiKeyAccount default apiKey last: 8')"

# refusals: a failing key command sends nothing, a bad setting changes nothing
out=$($CTL agent-config --model other --key-command false 2>&1); code=$?
check "a failing key command fails" 1 "$code"
contains "and says so" "$out" 'the key command failed'
out=$($CTL agent-config --thinking lots --key-env NO_SUCH_KEY_VARIABLE 2>&1)
contains "an unset --key-env fails" "$out" 'NO_SUCH_KEY_VARIABLE is not set'
out=$(SAMALTAK_AGENT_KEY=$KEY $CTL agent-config --thinking lots 2>&1); code=$?
check "a bad setting fails" 1 "$code"
contains "with the image's reason" "$out" 'Thinking must be'
lacks "the error leaves the key out" "$out" "$KEY"
check "the model unchanged" "'claude-test'" "$($CTL eval 'ApiKeyAccount default model')"
check "the key unchanged" "'$(echo "$KEY3" | tail -c 9)'" "$($CTL eval 'ApiKeyAccount default apiKey last: 8')"

# a snapshot forgets the key first, and its file does not hold any key sent
check "snapshot written" false "$($CTL eval "Smalltalk snapshot: '$SCRATCH/saved.image'")"
check "the key is gone after the snapshot" false "$($CTL eval 'ApiKeyAccount default isSignedIn')"
check "the configuration stays" true "$($CTL eval 'ApiKeyAccount default isConfigured')"
for k in "$KEY" "$KEY2" "$KEY3"; do
  if grep -q -a -F "$k" "$SCRATCH/saved.image"; then fail "a key is in the snapshot"; else pass "no key in the snapshot"; fi
done
if [ -f "$LOG" ] && grep -q -a -F -e "$KEY" -e "$KEY2" -e "$KEY3" "$LOG"; then fail "a key is in the VM's log"; else pass "no key in the VM's log"; fi

out=$($CTL agent-config --clear 2>&1)
contains "clear forgets the model" "$out" '"model":null'
check "conversations are back on Codex" true "$($CTL eval 'AgentConversation new provider isKindOf: CodexProvider')"

if [ $fails -eq 0 ]; then echo "all passed"; else echo "$fails failed"; fi
exit $fails
