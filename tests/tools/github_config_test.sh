#!/bin/sh
# samaltak-ctl github-config: the GitHub token reaches the image from a token command or the environment, nothing
# prints it, a bad setting changes nothing, and a snapshot does not contain the token. Works on a copy of the image in a
# scratch dir, headless; GitHub itself is never contacted.
# usage: tests/tools/github_config_test.sh [image]   (default: build/samaltak.image)
set -u
cd "$(dirname "$0")/../.."
IMAGE=${1:-build/samaltak.image}
CTL=tools/samaltak-ctl
export SAMALTAK_SESSION=github-config-test-$$
unset SAMALTAK_GITHUB_TOKEN GITHUB_TOKEN
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
  case "$2" in *"$3"*) fail "$1: the token is there" ;; *) pass "$1" ;; esac
}
newtoken() { echo "ghp_test$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"; }
cleanup() { $CTL close >/dev/null 2>&1; rm -rf "$SCRATCH"; }
trap cleanup EXIT

cp "$IMAGE" "$SCRATCH/test.image"
$CTL open --headless --image "$SCRATCH/test.image" >/dev/null 2>&1 || { echo "FAIL open"; exit 1; }

out=$($CTL github-config 2>&1)
contains "no token at first" "$out" '"hasToken":false'

# the token from a program's stdout
TOKEN=$(newtoken)
(umask 077; echo "$TOKEN" > "$SCRATCH/token")
out=$($CTL github-config --repo owner/repo --token-command "cat '$SCRATCH/token'" 2>&1)
contains "configured" "$out" '"repository":"owner/repo"'
contains "pull requests go into main" "$out" '"baseBranch":"main"'
contains "branches under agent/" "$out" '"branchPrefix":"agent/"'
contains "the image has the token" "$out" '"hasToken":true'
lacks "the answer leaves the token out" "$out" "$TOKEN"
check "the token arrived whole" "${#TOKEN}" "$($CTL eval 'GitHubAccount default token size')"
lacks "the account's printString leaves the token out" "$($CTL eval 'GitHubAccount default printString')" "$TOKEN"

# the token from the environment
TOKEN2=$(newtoken)
out=$(GITHUB_TOKEN=$TOKEN2 $CTL github-config --repo owner/repo --base trunk --prefix bot/ 2>&1)
contains "another base branch" "$out" '"baseBranch":"trunk"'
lacks "the answer leaves the second token out" "$out" "$TOKEN2"
check "the token from GITHUB_TOKEN" "'$(echo "$TOKEN2" | tail -c 9)'" "$($CTL eval 'GitHubAccount default token last: 8')"
TOKEN3=$(newtoken)
out=$(SAMALTAK_GITHUB_TOKEN=$TOKEN3 GITHUB_TOKEN=$TOKEN2 $CTL github-config --repo owner/repo 2>&1)
check "SAMALTAK_GITHUB_TOKEN comes first" "'$(echo "$TOKEN3" | tail -c 9)'" "$($CTL eval 'GitHubAccount default token last: 8')"

# refusals: a failing token command sends nothing; a base branch under the prefix or a bad repository changes nothing
out=$($CTL github-config --repo owner/other --token-command false 2>&1); code=$?
check "a failing token command fails" 1 "$code"
contains "and says so" "$out" 'the token command failed'
out=$($CTL github-config --repo owner/repo --base bot/main --token-env NO_SUCH_TOKEN_VARIABLE 2>&1)
contains "an unset --token-env fails" "$out" 'NO_SUCH_TOKEN_VARIABLE is not set'
out=$(GITHUB_TOKEN=$TOKEN $CTL github-config --repo owner/repo --base bot/main 2>&1); code=$?
check "a base branch under the prefix fails" 1 "$code"
contains "with the image's reason" "$out" 'must not start with the branch prefix'
lacks "the error leaves the token out" "$out" "$TOKEN"
out=$(GITHUB_TOKEN=$TOKEN $CTL github-config --repo not-a-repository 2>&1)
contains "a bad repository fails" "$out" 'owner/name'
check "the base branch unchanged" "'trunk'" "$($CTL eval 'GitHubAccount default baseBranch')"
check "the token unchanged" "'$(echo "$TOKEN3" | tail -c 9)'" "$($CTL eval 'GitHubAccount default token last: 8')"

# a snapshot forgets the token first, and its file does not hold any token sent
check "snapshot written" false "$($CTL eval "Smalltalk snapshot: '$SCRATCH/saved.image'")"
check "the token is gone after the snapshot" false "$($CTL eval 'GitHubAccount default hasToken')"
check "the repository stays" "'owner/repo'" "$($CTL eval 'GitHubAccount default repository')"
for t in "$TOKEN" "$TOKEN2" "$TOKEN3"; do
  if grep -q -a -F "$t" "$SCRATCH/saved.image"; then fail "a token is in the snapshot"; else pass "no token in the snapshot"; fi
done
if [ -f "$LOG" ] && grep -q -a -F -e "$TOKEN" -e "$TOKEN2" -e "$TOKEN3" "$LOG"; then fail "a token is in the VM's log"; else pass "no token in the VM's log"; fi

out=$($CTL github-config --clear 2>&1)
contains "clear forgets the repository" "$out" '"repository":null'

if [ $fails -eq 0 ]; then echo "all passed"; else echo "$fails failed"; fi
exit $fails
