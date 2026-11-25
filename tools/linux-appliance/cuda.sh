#!/bin/sh
# The CUDA root of the Linux appliance (docs/cuda.md, The World with the cu* libraries; docs/linux-appliance.md):
# NVIDIA's CUDA userspace and the cu* libraries in one read-only squashfs (zstd), samaltak-cuda-13.squashfs, which rcS
# mounts at /opt/cuda and samaltak-run names in SAMALTAK_CUDA_LIBS. Made from this build host's installed driver
# userspace, CUDA toolkit and cuOpt venv, the libraries the bindings are built and tested against:
#   - the driver's userspace, of nvidia.ko's version (the module the appliance ships: LINUX_KVER's
#     linux-modules-nvidia-580-open): libcuda, libnvidia-ptxjitcompiler, libnvidia-nvvm;
#   - the toolkit's, whose CUDA version must be the driver's major and no newer minor (NVRTC's PTX is then one the
#     driver's JIT takes): libcudart, libcublas, libcublasLt, libcurand, libnvrtc and its builtins, libnvJitLink,
#     libcusolver, libcufft, libcusparse;
#   - cuOpt's wheels (CUOPT_SITE): libcuopt_mathopt and what it loads (libcuopt_client, RMM, rapids_logger, cuDSS,
#     NCCL, their vendored OpenMP, TBB and c-ares), against the toolkit's cuBLAS and cuSPARSE: one copy of a soname.
# Layout: lib/ (each library under its file name, with links for the names it is loaded by: the one directory of
# SAMALTAK_CUDA_LIBS and LD_LIBRARY_PATH), LICENSES/ (the CUDA EULA, the driver's licence, each wheel's own), MANIFEST
# (versions, sha256 and origin of each file), README. What the libraries need of the system (glibc, libstdc++,
# libz, OpenSSL) is the appliance root's, checked against OUT/linux-appliance/root, which must be a variant with
# NVIDIA's modules (make linux-appliance LINUX_GPU=nvidia, which runs me after it). Reproducible:
# fixed owners and times (SOURCE_DATE_EPOCH, default 0), sorted, no xattrs; when the MANIFEST is the last build's,
# the squashfs is kept.
#
#   tools/linux-appliance/cuda.sh     (make linux-appliance-cuda)  ->  OUT/linux-appliance/samaltak-cuda-13.squashfs
#
# Environment: OUT (build), LINUX_KVER (7.0.0-1024-nvidia), LINUX_CACHE (where build.sh extracted the kernel's
# modules), CUDA_HOME (/usr/local/cuda-13.0), CUOPT_SITE (the cuOpt venv's site-packages; none: without cuOpt),
# LINUX_CUDA_ZSTD (zstd level, 15), LINUX_CUDA_JOBS (mksquashfs's threads, 8). Needs: mksquashfs (squashfs-tools 4.5
# or later), readelf, modinfo, python3, the nvidia variant's root and kernel modules (make linux-appliance
# LINUX_GPU=nvidia). No root.
set -eu
OUT=${OUT:-build}
W=$OUT/linux-appliance
KVER=${LINUX_KVER:-7.0.0-1024-nvidia}
CACHE=${LINUX_CACHE:-$HOME/.cache/samaltak/linux-appliance}
CUDA=${CUDA_HOME:-/usr/local/cuda-13.0}
SITE=${CUOPT_SITE:-$HOME/.local/share/samaltak-cuopt/venv/lib/python3.12/site-packages}
LEVEL=${LINUX_CUDA_ZSTD:-15}
JOBS=${LINUX_CUDA_JOBS:-8}
EPOCH=${SOURCE_DATE_EPOCH:-0}
TRIPLE=$(gcc -dumpmachine | sed 's/-unknown//')
LIB=/usr/lib/$TRIPLE
NAME=samaltak-cuda-13.squashfs
S=$W/cuda-root
L=$W/cuda.list
PATH=$PATH:/sbin:/usr/sbin
export LC_ALL=C
say() { echo "linux-appliance-cuda: $*"; }
die() { echo "linux-appliance-cuda: $*" >&2; exit 1; }
for t in mksquashfs readelf modinfo python3 sha256sum; do command -v $t > /dev/null || die "needs $t"; done
[ -f "$CUDA/version.json" ] || die "no CUDA toolkit at $CUDA (CUDA_HOME)"
mkdir -p "$W"
# The root the CUDA root goes with: the Spark's (a variant with NVIDIA's modules), not QEMU's.
variant=$(cat "$W/variant" 2>/dev/null || true)
case $variant in
nvidia | nvidia-vulkan | both) ;;
"") die "no appliance root in $W: make linux-appliance LINUX_GPU=nvidia OUT=$OUT (it makes the CUDA root too)" ;;
*) die "$W is the $variant variant (QEMU's), not the Spark's: make linux-appliance LINUX_GPU=nvidia (it makes the CUDA root too), in another OUT to keep this one" ;;
esac

# The versions: nvidia.ko's, the driver userspace's (the same, or libcuda refuses the module), the CUDA version the
# driver supports, the toolkit's.
ko=$(find "$CACHE/kernel-$KVER/lib/modules/$KVER" -name 'nvidia.ko*' 2>/dev/null | head -1)
[ -n "$ko" ] || die "no nvidia.ko for $KVER under $CACHE: make linux-appliance LINUX_GPU=nvidia first"
KOVER=$(modinfo -F version "$ko")
[ -n "$KOVER" ] || die "no version in $ko"
for l in libcuda.so.1 libnvidia-ptxjitcompiler.so.1 libnvidia-nvvm.so.4; do
	f=$(readlink -f "$LIB/$l" 2>/dev/null) && [ -f "$f" ] || die "no $LIB/$l: install the driver's userspace (libnvidia-compute-${KOVER%%.*}) of version $KOVER"
	[ "${f##*.so.}" = "$KOVER" ] || die "$LIB/$l is ${f##*.so.}, nvidia.ko ($KVER) is $KOVER: the driver's userspace must be the module's version"
done
DRVCUDA=$(python3 -c "import ctypes; v = ctypes.c_int(); ctypes.CDLL('$LIB/libcuda.so.1').cuDriverGetVersion(ctypes.byref(v)); print(v.value)")
TKVER=$(python3 -c "import json; print(json.load(open('$CUDA/version.json'))['cuda']['version'])")
TKMIN=$(python3 -c "import json; print(json.load(open('$CUDA/version.json')).get('nvidia_driver', {}).get('version', '0'))")
tk=$(echo "$TKVER" | awk -F. '{ print $1 * 1000 + $2 * 10 }')
[ $((tk / 1000)) = $((DRVCUDA / 1000)) ] && [ "$tk" -le "$DRVCUDA" ] \
	|| die "CUDA toolkit $TKVER ($CUDA) is not for driver $KOVER (CUDA $((DRVCUDA / 1000)).$((DRVCUDA % 1000 / 10))): the same major version, no newer minor"
[ "$(printf '%s\n%s\n' "$TKMIN" "$KOVER" | sort -V | head -1)" = "$TKMIN" ] || die "CUDA toolkit $TKVER wants driver $TKMIN or later, nvidia.ko is $KOVER"
drvpkg=$(dpkg -S "$(readlink -f "$LIB/libcuda.so.1")" | cut -d: -f1 | head -1)
drvdeb=$(dpkg-query -W -f '${Version}' "$drvpkg" 2>/dev/null || echo ?)
cuopt=""
if [ "$SITE" != none ]; then
	[ -f "$SITE/libcuopt_mathopt/lib64/libcuopt_mathopt.so" ] || die "no cuOpt at $SITE (CUOPT_SITE, or none)"
	cuopt=$(cd "$SITE" && ls -d libcuopt_mathopt_cu*.dist-info | head -1)
	cuopt=${cuopt%.dist-info}
	case $cuopt in *_cu$((DRVCUDA / 1000))-*) ;; *) die "cuOpt $cuopt is not for CUDA $((DRVCUDA / 1000))" ;; esac
fi

# The files: the roots and every library they need (readelf's NEEDED), looked up in the toolkit first, then cuOpt's
# wheels; what is in none of them is the system's (the appliance root's). L lists "name<TAB>source<TAB>origin".
dirs="$CUDA/lib64"
[ "$SITE" = none ] || for d in libcuopt_mathopt/lib64 libcuopt_client/lib64 librmm/lib64 rapids_logger/lib64 nvidia/cu13/lib nvidia/nccl/lib \
	libcuopt_mathopt_cu13.libs libcuopt_client.libs; do dirs="$dirs $SITE/$d"; done
find_lib() { for d in $dirs; do [ -e "$d/$1" ] && { echo "$d/$1"; return 0; }; done; return 1; }
origin() {
	case $1 in
	"$LIB"/*) echo "driver $drvpkg $drvdeb" ;;
	"$CUDA"/*) echo "toolkit CUDA $TKVER" ;;
	"$SITE"/*) r=${1#"$SITE"/}; di=$(grep -l "^$r," "$SITE"/*.dist-info/RECORD 2>/dev/null | head -1); di=${di%/RECORD}; di=${di##*/}; echo "wheel ${di%.dist-info}" ;;
	*) echo "?" ;;
	esac
}
: > "$L"; sys=""
todo="$LIB/libcuda.so.1 $LIB/libnvidia-ptxjitcompiler.so.1 $LIB/libnvidia-nvvm.so.4"
for n in libcudart.so.13 libcublas.so.13 libcublasLt.so.13 libcurand.so.10 libnvrtc.so.13 libnvrtc-builtins.so.$(echo "$TKVER" | cut -d. -f1-2) \
	libnvJitLink.so.13 libcusolver.so.12 libcufft.so.12 libcusparse.so.12; do
	p=$(find_lib "$n") || die "no $n in $CUDA/lib64"; todo="$todo $p"
done
[ "$SITE" = none ] || todo="$todo $SITE/libcuopt_mathopt/lib64/libcuopt_mathopt.so $SITE/libcuopt_mathopt/lib64/libcudss_mtlayer_cuopt.so"
while [ -n "$todo" ]; do
	next=""
	for p in $todo; do
		n=${p##*/}
		grep -q "^$n	" "$L" && continue
		real=$(readlink -f "$p")
		printf '%s\t%s\t%s\n' "$n" "$real" "$(origin "$real")" >> "$L"
		for d in $(readelf -d "$real" | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p'); do
			grep -q "^$d	" "$L" && continue
			if q=$(find_lib "$d"); then next="$next $q"
			elif [ -e "$LIB/$d" ] || [ -e "/usr/lib/$d" ]; then case " $sys " in *" $d "*) ;; *) sys="$sys $d" ;; esac
			else die "$d (needed by $n) is in none of: $dirs $LIB"; fi
		done
	done
	todo=$next
done
sys=$(echo $sys | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')
for d in $sys; do [ -e "$W/root$LIB/$d" ] || [ -e "$W/root/usr/lib/$d" ] || die "the appliance's root ($W/root, $variant) has no $d: make linux-appliance LINUX_GPU=$variant again (build.sh's list of libraries)"; done

# The MANIFEST: what it is made of, by content (no paths of this machine in it), and how it is compressed.
M=$W/cuda.MANIFEST
{
	echo "# $NAME: NVIDIA's CUDA userspace for the Samaltak Linux appliance, mounted at /opt/cuda (docs/cuda.md)"
	echo "driver $KOVER (CUDA $((DRVCUDA / 1000)).$((DRVCUDA % 1000 / 10)); $drvpkg $drvdeb; nvidia.ko of linux-modules-nvidia-${KOVER%%.*}-open-$KVER)"
	echo "toolkit CUDA $TKVER"
	[ -z "$cuopt" ] || echo "cuopt $cuopt"
	echo "needs from the root: $sys"
	echo "squashfs zstd -$LEVEL, 1 MiB blocks, time $EPOCH"
	echo "files:"
	sort "$L" | while IFS='	' read -r n src org; do
		b=${src##*/}
		echo "$(sha256sum "$src" | cut -d' ' -f1)  lib/$b  $org"
		[ "$n" = "$b" ] || echo "->  lib/$n  lib/$b"
	done | sort -k2,2 -u
} > "$M.new"
mv "$M.new" "$M"
if [ -f "$W/$NAME" ] && cmp -s "$M" "$W/$NAME.manifest"; then
	say "$W/$NAME is current ($(($(wc -c < "$W/$NAME") / 1048576)) MB)"
	exit 0
fi

# The tree: the files under their own names (mode 0644), the links, the licences, the MANIFEST and a README.
rm -rf "$S" && mkdir -p "$S/lib" "$S/LICENSES/cuda-toolkit" "$S/LICENSES/nvidia-driver"
sort "$L" | while IFS='	' read -r n src org; do
	b=${src##*/}
	[ -e "$S/lib/$b" ] || { cp --reflink=auto "$src" "$S/lib/$b" && chmod 0644 "$S/lib/$b"; }
	[ "$n" = "$b" ] || [ -e "$S/lib/$n" ] || ln -s "$b" "$S/lib/$n"
done
cp "$CUDA/EULA.txt" "$S/LICENSES/cuda-toolkit/EULA.txt"
cp "/usr/share/doc/$drvpkg/copyright" "$S/LICENSES/nvidia-driver/copyright"
for w in $(cut -f3 "$L" | sed -n 's/^wheel //p' | sort -u); do
	[ -d "$SITE/$w.dist-info/licenses" ] && mkdir -p "$S/LICENSES/$w" && cp -r "$SITE/$w.dist-info/licenses/." "$S/LICENSES/$w/"
done
cp "$M" "$S/MANIFEST"
cat > "$S/README" << EOF
$NAME: NVIDIA's CUDA userspace and libraries for the Samaltak Linux appliance (docs/cuda.md),
mounted read-only at /opt/cuda; the VM loads them from /opt/cuda/lib (SAMALTAK_CUDA_LIBS).

The files are NVIDIA's (and the RAPIDS projects'), unmodified, in object form, under their own licences:
  - the CUDA runtime, cuBLAS/cuBLASLt, cuRAND, NVRTC, nvJitLink, cuSOLVER, cuFFT, cuSPARSE: the CUDA Toolkit EULA's
    redistributable components (LICENSES/cuda-toolkit/EULA.txt, Attachment A);
  - libcuda and libnvidia-ptxjitcompiler (Attachment A's "NVIDIA CUDA Driver Libraries") and libnvidia-nvvm: the
    NVIDIA driver's userspace of nvidia.ko's version, under the NVIDIA Driver License Agreement
    (LICENSES/nvidia-driver/copyright);
  - cuOpt, RMM, rapids_logger (Apache-2.0), cuDSS (NVIDIA's cuDSS licence), NCCL (BSD-3-Clause): each wheel's
    licence files in LICENSES/<wheel>/.
MANIFEST lists every file with its sha256 and where it came from.
EOF
chmod -R u+rwX,go+rX,go-w "$S"

# The squashfs, reproducibly.
say "mksquashfs: $(du -sm "$S" | cut -f1) MB, zstd -$LEVEL, $JOBS threads"
t0=$(date +%s)
rm -f "$W/$NAME.new"
mksquashfs "$S" "$W/$NAME.new" -noappend -comp zstd -Xcompression-level "$LEVEL" -b 1M -all-root -no-xattrs \
	-all-time "$EPOCH" -mkfs-time "$EPOCH" -processors "$JOBS" -quiet -no-progress
mv "$W/$NAME.new" "$W/$NAME"
cp "$M" "$W/$NAME.manifest"
(cd "$W" && sha256sum "$NAME" > "$NAME.sha256")
rm -rf "$S"
say "$W/$NAME $(($(wc -c < "$W/$NAME") / 1048576)) MB in $(($(date +%s) - t0)) s ($(grep -c '^[0-9a-f]\{64\}' "$M") files; driver $KOVER, CUDA $TKVER${cuopt:+, $cuopt})"
