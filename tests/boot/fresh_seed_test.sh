#!/bin/sh
# Requires a hosted VM with the File backend. All output is private to this run.
set -eu
cd "$(dirname "$0")/../.."
VM=${1:-"$PWD/vm/build/samaltak"}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
export SAMALTAK_BOOT_TEST_DIR="$TMP"

run() {
    if ! "$@" >"$TMP/run.out" 2>"$TMP/run.err"; then
        cat "$TMP/run.out" "$TMP/run.err" >&2
        exit 1
    fi
}

# A reproducible bootstrap profile can make itself in a second VM process.
seed="$TMP/new seed's image"
run env PACKAGES=boot/packages.txt boot/build-image.sh src "$seed" "$VM"
run env BOOT_IMAGE="$seed" PACKAGES=boot/packages.txt boot/build-image.sh src "$TMP/reminted.image" "$VM"
cmp "$seed" "$TMP/reminted.image"

# A new runtime seed must already have file, environment, console and bigint services.
run env BOOT_IMAGE="$seed" PACKAGES=src/runtime.txt boot/build-image.sh src "$TMP/runtime-seed.image" "$VM"
run "$VM" "$TMP/runtime-seed.image" --headless --eval "
    | dir path |
    dir := Smalltalk vm getenv: 'SAMALTAK_BOOT_TEST_DIR'.
    path := dir , '/Rebuilt.st'.
    (3618502788666131106986593281521497120414687020801267626233049500247285301249 + 3
        = 3618502788666131106986593281521497120414687020801267626233049500247285301252)
        ifFalse: [self error: 'stage 1 bigint failed'].
    File writeText: (File readText: 'tests/boot/seeded_binding.st') to: path.
    ((Directory fileNames: dir) includes: 'Rebuilt.st') ifFalse: [self error: 'stage 1 directory failed'].
    Smalltalk vm stdoutWrite: 'stage 1 stdout', (String with: Character lf).
    Smalltalk vm stderrWrite: 'stage 1 stderr', (String with: Character lf).
    true"
grep -Fx 'stage 1 stdout' "$TMP/run.out"
grep -Fx 'stage 1 stderr' "$TMP/run.err"
if "$VM" "$TMP/runtime-seed.image" --headless --eval "Error signal: 'bootstrap error witness'" >"$TMP/run.out" 2>"$TMP/run.err"; then
    echo 'fresh_seed_test: a stage-1 error exited successfully' >&2
    exit 1
fi
grep -F 'bootstrap error witness' "$TMP/run.err"

run "$VM" "$TMP/runtime-seed.image" --headless --stage2 "$TMP/runtime.image" --runtime
run env SAMALTAK_BOOT_TEST_VALUE=before "$VM" "$TMP/runtime.image" --headless --load "$TMP/Rebuilt.st" --eval "
    | site row |
    site := BootBindingFixture new seededSite.
    row := (BootBindingFixture compiledMethodAt: #seededSite) literals detect: [:each | each class == FFIBinding].
    (site == row and: [site isReadOnlyObject and: [(site instVarAt: 2) isNil]])
        ifFalse: [self error: 'file-in did not compile a cold binding literal'].
    (site tryInvoke1: 'SAMALTAK_BOOT_TEST_VALUE') = 'before'
        ifFalse: [self error: 'cold binding failed'].
    Smalltalk snapshot: ((Smalltalk vm getenv: 'SAMALTAK_BOOT_TEST_DIR') , '/rebound.image').
    'binding ', (site tryInvoke1: 'SAMALTAK_BOOT_TEST_VALUE')"
grep -Fx "'binding before'" "$TMP/run.out"
run env SAMALTAK_BOOT_TEST_VALUE=after "$VM" "$TMP/rebound.image" --headless
grep -Fx "'binding after'" "$TMP/run.out"
echo 'fresh_seed_test: passed'
