#!/bin/sh
# Amd64Assembler against arm64: random programs of the code generators' instructions (Tests-VM/AsmLoweringFuzz),
# built for x86-64 (run here) and for arm64 (run under qemu-aarch64), must leave the same registers and memory.
# usage: tools/lowering-check.sh IMAGE [seed [count [length]]]
# On x86-64 it needs aarch64-linux-gnu-gcc and qemu-aarch64; on arm64 X86_CC (a C compiler for static x86-64 programs,
# e.g. clang --target=x86_64-linux-gnu -fuse-ld=lld with a sysroot) and qemu-x86_64. X86_CC, X86_RUN, ARM64_CC and
# ARM64_RUN override either. Without X86_CC and x86_64-linux-gnu-gcc on PATH, arm64 uses tools/x86-toolchain.sh's (it
# downloads one without root: run it once).
set -u
cd "$(dirname "$0")/.."
IMAGE=$1
SEED=${2:-1}
COUNT=${3:-2000}
LEN=${4:-12}
VM=${VM:-vm/build/samaltak}
DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT
$VM "$IMAGE" --headless --eval "[(VMTranslator modules: {AsmLoweringFuzz. Arm64Assembler. Amd64Assembler. CodeCache. DarwinJitPlatform. LinuxJitPlatform} header: 'fuzz') writeTo: '$DIR'. 'ok'] on: Error do: [:e | e messageText]" >"$DIR/translate.out" 2>&1
grep -q "^'ok'$" "$DIR/translate.out" || { echo "lowering-check: translation failed"; cat "$DIR/translate.out"; exit 1; }
case $(uname -m) in
x86_64|amd64) X86_CC=${X86_CC:-cc}; X86_RUN=${X86_RUN:-}; ARM64_CC=${ARM64_CC:-aarch64-linux-gnu-gcc -static}; ARM64_RUN=${ARM64_RUN:-qemu-aarch64} ;;
*) if [ -z "${X86_CC:-}" ] && ! command -v x86_64-linux-gnu-gcc >/dev/null 2>&1; then
     T=$(tools/x86-toolchain.sh --path)
     [ -x "$T/bin/x86_64-linux-gnu-gcc" ] || { echo "lowering-check: no x86-64 cross compiler: run tools/x86-toolchain.sh (or set X86_CC, X86_RUN)"; exit 1; }
     eval "$(tools/x86-toolchain.sh --env)"
   fi
   X86_CC=${X86_CC:-x86_64-linux-gnu-gcc -static}; X86_RUN=${X86_RUN:-qemu-x86_64}; ARM64_CC=${ARM64_CC:-cc}; ARM64_RUN=${ARM64_RUN:-} ;;
esac
$X86_CC -std=gnu11 -O1 -w -fsigned-char -o "$DIR/x86" "$DIR"/*.c || exit 1
$ARM64_CC -std=gnu11 -O1 -w -fsigned-char -o "$DIR/arm64" "$DIR"/*.c || exit 1
$X86_RUN "$DIR/x86" "$SEED" "$COUNT" "$LEN" >"$DIR/x86.out" || { echo "lowering-check: x86 run failed ($?)"; tail -3 "$DIR/x86.out"; exit 1; }
$ARM64_RUN "$DIR/arm64" "$SEED" "$COUNT" "$LEN" >"$DIR/arm64.out" || { echo "lowering-check: arm64 run failed"; exit 1; }
# programs either side skipped do not count
awk 'NR==FNR { if ($2 == "skip") skip[$1] = 1; next } { if ($2 == "skip") skip[$1] = 1 } END { for (p in skip) print p }' "$DIR/x86.out" "$DIR/arm64.out" >"$DIR/skips"
grep -v -w -F -f "$DIR/skips" "$DIR/x86.out" | grep '^p' >"$DIR/x86.cmp"
grep -v -w -F -f "$DIR/skips" "$DIR/arm64.out" | grep '^p' >"$DIR/arm64.cmp"
n=$(wc -l <"$DIR/x86.cmp")
s=$(wc -l <"$DIR/skips")
if cmp -s "$DIR/x86.cmp" "$DIR/arm64.cmp"; then
  echo "lowering-check: $n programs the same on x86-64 and arm64 ($s skipped)"
else
  echo "lowering-check: FAILED: x86-64 and arm64 differ ($n programs, $s skipped):"
  diff "$DIR/arm64.cmp" "$DIR/x86.cmp" | head -${DIFFLINES:-10}
  [ -n "${KEEP:-}" ] && cp -r "$DIR" "$KEEP"
  exit 1
fi
