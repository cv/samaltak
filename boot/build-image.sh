#!/bin/sh
# Build a seed image from a source tree with the Smalltalk ImageBuilder, run in the checked-in seed image.
# usage: [PACKAGES=list] boot/build-image.sh SRC_DIR OUT_IMAGE [VM]   (PACKAGES: only the packages it names, e.g. src/runtime.txt)
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC=$1
OUT=$2
VM=${3:-"$ROOT/vm/build/samaltak"}
mkdir -p "$(dirname "$OUT")"
cd "$ROOT" && exec "$VM" boot/seed.image --headless --eval "$(sed -e "s|@SRC@|$SRC|; s|@OUT@|$OUT|; s|@PACKAGES@|${PACKAGES:-}|" boot/build-image.st)"
