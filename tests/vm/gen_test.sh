#!/bin/sh
# vm/gen is what the Lowtalk sources translate to: translate them again with the image and compare.
# usage: tests/vm/gen_test.sh IMAGE
set -u
cd "$(dirname "$0")/../.."
IMAGE=$1
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
vm/build/samaltak "$IMAGE" --headless --eval "[(VMTranslator modules: VMModule vmModules header: 'samaltak') writeTo: '$TMP'. 'ok'] on: Error do: [:e | e messageText]" >"$TMP/out" 2>&1
if ! grep -q "^'ok'$" "$TMP/out"; then
  echo "gen_test: FAILED: translation failed"; cat "$TMP/out"; exit 1
fi
rm "$TMP/out"
if diff -r -q vm/gen "$TMP" >/dev/null; then
  echo "gen_test: vm/gen is current"
else
  echo "gen_test: FAILED: vm/gen differs from the translated sources (make translate):"
  diff -r -q vm/gen "$TMP" | head -20
  exit 1
fi
