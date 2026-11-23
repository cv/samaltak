#!/bin/sh
# Build a seed image from a source tree with the Smalltalk ImageBuilder, run in the checked-in seed image.
# usage: [BOOT_IMAGE=seed] [PACKAGES=list] boot/build-image.sh SRC_DIR OUT_IMAGE [VM]   (PACKAGES: only the packages it names, e.g. src/runtime.txt)
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC=$1
OUT=$2
VM=${3:-"$ROOT/vm/build/samaltak"}
cd "$ROOT"
case "$SRC" in -*) SRC=./$SRC ;; esac
case "$OUT" in -*) OUT=./$OUT ;; esac
PKGS=${PACKAGES:-}
case "$PKGS" in -*) PKGS=./$PKGS ;; esac
mkdir -p "$(dirname "$OUT")"
exec "$VM" "${BOOT_IMAGE:-boot/seed.image}" --headless --eval "$(cat boot/build-image.st)" "$SRC" "$OUT" "$PKGS"
