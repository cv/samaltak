#!/bin/sh
# Standalone AAPCS64 oracle, no image/VM build. Needs Python 3, clang/lld and qemu-aarch64.
# Usage: QEMU_AARCH64=qemu-aarch64 tests/vm/wrapped_ffi_arm64_test.sh path/to/generated/ffi_stub_compiler.c
set -eu
if [ "$#" -ne 1 ]; then
    echo "usage: $0 path/to/generated/ffi_stub_compiler.c" >&2
    exit 2
fi
here=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
python3 - "$1" "$tmp/encoder.inc" <<'PY'
import re
import sys

with open(sys.argv[1]) as f:
    source = f.read()
with open(sys.argv[2], "w") as f:
    for name in ("arm64WrappedBranch", "arm64WrappedCall", "encodeWrappedArm64"):
        # Only the actual Lowtalk translation, with test doubles for VM helpers.
        defs = re.findall(r"^/\* FFIStubCompiler>>" + name + r":.*?^}\n", source, re.M | re.S)
        if len(defs) != 1:
            sys.exit(f"expected one translated definition of {name}")
        f.write(defs[0])
PY
"${CLANG:-clang}" --target=aarch64-linux-gnu -fuse-ld=lld -static -nostdlib \
    -std=c11 -Wall -Wextra -Werror -O2 -ffreestanding -fno-stack-protector \
    -I"$tmp" "$here/wrapped_ffi_arm64_oracle.c" -o "$tmp/oracle"
"${QEMU_AARCH64:-qemu-aarch64}" "$tmp/oracle"
