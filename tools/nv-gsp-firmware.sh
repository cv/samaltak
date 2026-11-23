#!/bin/sh
# Puts the firmware a GSP boot on the GB10 needs (docs/nv-gsp.md 1, NvGspFirmware fromDirectory:) into OUTDIR:
#   OUTDIR/gsp_ga10x.bin                 GSP-RM, as the driver loads it (from GSP_BIN, default the installed driver's)
#   OUTDIR/gb10b/fmc-{prod,debug}.{image,hash,sig,pkey}   the GSP-FMC archives
#   OUTDIR/gb10b/boot-{prod,debug}.{image,desc}          the GSP-RM boot loader and its RM_RISCV_UCODE_DESC
#   OUTDIR/SHA256SUMS
# The gb10b files are the byte arrays nvidia.ko is built with, cut from open-gpu-kernel-modules' generated bindata
# sources (MIT); gsp_ga10x.bin is NVIDIA's (the nvidia-firmware package: no modifications allowed), copied as it is.
# Nothing here ships them: put OUTDIR on a volume the UEFI image mounts (an ext4 or the ESP).
#   tools/nv-gsp-firmware.sh OUTDIR [open-gpu-kernel-modules checkout at 580.178.04]
set -eu
OUT=${1:?usage: tools/nv-gsp-firmware.sh OUTDIR [OGK]}
OGK=${2:-$HOME/src/github.com/NVIDIA/open-gpu-kernel-modules}
VERSION=580.178.04
GSP_BIN=${GSP_BIN:-/lib/firmware/nvidia/$VERSION/gsp_ga10x.bin}
tag=$(git -C "$OGK" describe --tags --exact-match 2>/dev/null || echo none)
[ "$tag" = "$VERSION" ] || { echo "nv-gsp-firmware: $OGK is at $tag, not $VERSION" >&2; exit 1; }
[ -f "$GSP_BIN" ] || { echo "nv-gsp-firmware: no $GSP_BIN (set GSP_BIN)" >&2; exit 1; }
mkdir -p "$OUT/gb10b"
cp "$GSP_BIN" "$OUT/gsp_ga10x.bin"
GEN="$OGK/src/nvidia/generated"
python3 - "$GEN" "$OUT/gb10b" <<'EOF'
import hashlib, re, sys, zlib
gen, out = sys.argv[1], sys.argv[2]
def arrays(path):
    """label -> bytes of each BINDATA array in a generated bindata source; compressed ones are raw deflate (bindataArchive: utilGzAllocate), inflated."""
    text = open(path).read()
    found = {}
    for m in re.finditer(r'// FUNCTION: \w+\("BINDATA_LABEL_(\w+)"\)(.*?)\{(.*?)\};', text, re.S):
        label, head, body = m.group(1), m.group(2), m.group(3)
        size = int(re.search(r'DATA SIZE \(bytes\): (\d+)', head).group(1))
        data = bytes(int(x, 16) for x in re.findall(r'0x([0-9a-fA-F]{2})', body))
        if 'COMPRESSION: YES' in head:
            packed = int(re.search(r'COMPRESSED SIZE \(bytes\): (\d+)', head).group(1))
            if len(data) != packed:
                sys.exit('nv-gsp-firmware: %s %s: %d compressed bytes, header says %d' % (path, label, len(data), packed))
            data = zlib.decompress(data, -15)
        if len(data) != size:
            sys.exit('nv-gsp-firmware: %s %s: %d bytes, header says %d' % (path, label, len(data), size))
        found[label] = data
    return found
wanted = {
    'kgspGetBinArchiveGspRmFmcGfwProdSigned_GB10B': {'UCODE_IMAGE': ('fmc-prod.image', 195912), 'UCODE_HASH': ('fmc-prod.hash', 48), 'UCODE_SIG': ('fmc-prod.sig', 384), 'UCODE_PKEY': ('fmc-prod.pkey', 384)},
    'kgspGetBinArchiveGspRmFmcGfwDebugSigned_GB10B': {'UCODE_IMAGE': ('fmc-debug.image', 195912), 'UCODE_HASH': ('fmc-debug.hash', 48), 'UCODE_SIG': ('fmc-debug.sig', 384), 'UCODE_PKEY': ('fmc-debug.pkey', 384)},
    'kgspGetBinArchiveGspRmBoot_GB10B': {'UCODE_IMAGE_PROD': ('boot-prod.image', 196608), 'UCODE_DESC_PROD': ('boot-prod.desc', 84), 'UCODE_IMAGE_DBG': ('boot-debug.image', 196608), 'UCODE_DESC_DBG': ('boot-debug.desc', 84)},
}
for archive, files in wanted.items():
    found = arrays('%s/g_bindata_%s.c' % (gen, archive))
    for label, (name, size) in files.items():
        data = found.get(label)
        if data is None or len(data) != size:
            sys.exit('nv-gsp-firmware: %s %s: %s' % (archive, label, 'missing' if data is None else '%d bytes, not %d' % (len(data), size)))
        open('%s/%s' % (out, name), 'wb').write(data)
for kind in ('prod', 'debug'):
    image = open('%s/fmc-%s.image' % (out, kind), 'rb').read()
    digest = open('%s/fmc-%s.hash' % (out, kind), 'rb').read()
    print('nv-gsp-firmware: fmc-%s hash %s SHA-384 of its image' % (kind, 'is the' if hashlib.sha384(image).digest() == digest else 'is not the'))
EOF
version=$(python3 - "$OUT/gsp_ga10x.bin" <<'EOF'
import struct, sys
b = open(sys.argv[1], 'rb').read()
shoff, = struct.unpack_from('<Q', b, 0x28); shnum, shstrndx = struct.unpack_from('<HH', b, 0x3C)
sh = lambda i: struct.unpack_from('<IIQQQQIIQQ', b, shoff + 64 * i)
names = sh(shstrndx)[4]
for i in range(shnum):
    n, t, f, a, off, size = sh(i)[:6]
    if b[names + n:].split(b'\0')[0] == b'.fwversion':
        print(b[off:off + size].split(b'\0')[0].decode())
EOF
)
[ "$version" = "$VERSION" ] || { echo "nv-gsp-firmware: gsp_ga10x.bin is version $version, not $VERSION" >&2; exit 1; }
(cd "$OUT" && sha256sum gsp_ga10x.bin gb10b/* > SHA256SUMS)
echo "nv-gsp-firmware: GSP-RM $version and the GB10B FMC and boot loader in $OUT"
