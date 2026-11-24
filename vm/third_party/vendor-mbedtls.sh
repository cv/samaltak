#!/bin/sh
# Vendor mbedTLS into vm/third_party/mbedtls from its pinned release tarball (vm/third_party/README.md): download it
# (or take MBEDTLS_TARBALL), check its SHA-256, and replace include/, library/ and LICENSE with the release's, unchanged.
# Rerun after changing the pin; the result must equal what is committed (git diff shows nothing for the same pin).
set -eu
VERSION=3.6.8
SHA256=bc54b818e87f49c0b3281dd85d24adaede0e63b4e822e3fbd49c005a38b9595b
URL=https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-$VERSION/mbedtls-$VERSION.tar.bz2
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
tarball=${MBEDTLS_TARBALL:-}
if [ -z "$tarball" ]; then
  tarball=$tmp/mbedtls-$VERSION.tar.bz2
  curl -fsSL -o "$tarball" "$URL"
fi
actual=$( (sha256sum "$tarball" 2>/dev/null || shasum -a 256 "$tarball") | cut -d' ' -f1)
[ "$actual" = "$SHA256" ] || { echo "vendor-mbedtls: $tarball: SHA-256 $actual, expected $SHA256" >&2; exit 1; }
tar -xjf "$tarball" -C "$tmp"
src=$tmp/mbedtls-$VERSION
dst=$here/mbedtls
rm -rf "$dst"
mkdir -p "$dst"
cp -R "$src/include" "$src/library" "$src/LICENSE" "$dst/"
# the build files of mbedTLS's own build are not used
rm -f "$dst/include/CMakeLists.txt" "$dst/library/CMakeLists.txt" "$dst/library/Makefile" "$dst/library/.gitignore"
echo "vendored mbedTLS $VERSION into $dst"
