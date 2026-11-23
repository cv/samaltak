#!/bin/sh
# usage: tests/build-cache.sh restore|save: the VM's build directory (vm/build: the VM, its objects, and test-tools's
# platform-vm and platform-test) from or into a cache that the machine's worktrees share, keyed by what it is built
# from: the tree of vm/ (git rev-parse HEAD:vm), the compilers', linker's and libraries' versions, OS and CPU, and
# CC, CFLAGS, NO_PGO and NO_PLATFORM. tests/stages.sh (the gate) restores before its build, into a worktree without a
# VM, and saves after the build and at its end; a gate of a tree whose vm/ was built before (a re-run, a rebase onto
# commits that left vm/ alone) skips the VM's compile and link. Nothing is cached or restored while vm/ has
# uncommitted changes. SAMALTAK_BUILD_CACHE: the directory (default ~/.cache/samaltak/build; empty or 0: no cache);
# SAMALTAK_BUILD_CACHE_MB: its size bound (default 2048), the least recently used entries go first. Entries are made
# under a temporary name and renamed, saving and pruning hold a lock (flock), so concurrent gates can share it.
set -u
cd "$(dirname "$0")/.."
C=${SAMALTAK_BUILD_CACHE-${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}/samaltak/build}
case $C in ''|0) exit 0 ;; esac
MB=${SAMALTAK_BUILD_CACHE_MB:-2048}
case $MB in ''|*[!0-9]*) MB=2048 ;; esac
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
if [ -n "$(git status --porcelain -- vm 2>/dev/null)" ]; then echo "build-cache: vm/ has uncommitted changes: no cache"; exit 0; fi
hash() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; elif command -v shasum >/dev/null 2>&1; then shasum -a 256; else cksum; fi | cut -c1-24; }
key=$( { git rev-parse HEAD:vm; uname -sm
  for c in clang cc gcc ld.lld; do command -v $c >/dev/null 2>&1 && $c --version 2>/dev/null | head -1; done
  for p in sdl3 shaderc openssl; do pkg-config --modversion $p 2>/dev/null || echo "no $p"; done
  echo "${CC:-}|${CFLAGS:-}|${NO_PGO:-}|${NO_PLATFORM:-}"; } | hash)
E=$C/vm-$key
locked() { mkdir -p "$C" && if command -v flock >/dev/null 2>&1; then flock "$C/lock" "$@"; else "$@"; fi; }
case ${1:-} in
restore)
  [ -e vm/build/samaltak ] && exit 0
  if [ ! -d "$E" ]; then echo "build-cache: no VM built from this vm/ yet ($key)"; exit 0; fi
  rm -rf vm/build && mkdir -p vm/build && cp -R "$E/." vm/build/ || { rm -rf vm/build; echo "build-cache: restore failed"; exit 0; }
  touch "$E"
  # for make: everything newer than the checkout's sources, the programs newer than their objects
  find vm/build -type f ! -name samaltak ! -name gpu_test -exec touch {} +
  find vm/build -type f \( -name samaltak -o -name gpu_test \) -exec touch {} +
  echo "build-cache: the VM from the cache ($key)" ;;
save)
  [ -x vm/build/samaltak ] || exit 0
  # shellcheck disable=SC2016
  locked sh -c '
    E=$1; C=$2; MB=$3
    if [ -d "$E" ] && { [ ! -x vm/build/platform-vm/samaltak ] || [ -d "$E/platform-vm" ]; } \
        && { [ ! -x vm/build/platform-test/gpu_test ] || [ -d "$E/platform-test" ]; }; then touch "$E"; exit 0; fi
    rm -rf "$E.tmp" && cp -R vm/build "$E.tmp" && rm -rf "$E" && mv "$E.tmp" "$E" || { rm -rf "$E.tmp"; exit 0; }
    total=0
    for d in $(ls -dt "$C"/vm-* 2>/dev/null); do
      total=$((total + $(du -sk "$d" | cut -f1)))
      [ "$d" != "$E" ] && [ $total -gt $((MB * 1024)) ] && rm -rf "$d"
    done
    exit 0' sh "$E" "$C" "$MB"
  echo "build-cache: saved the VM ($key)" ;;
*) echo "usage: tests/build-cache.sh restore|save"; exit 2 ;;
esac
