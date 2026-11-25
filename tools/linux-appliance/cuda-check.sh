#!/bin/sh
# The CUDA root on this machine's GPU (make linux-appliance-cuda-check, after make linux-appliance and
# linux-appliance-cuda): the appliance's root as the initramfs holds it (OUT/linux-appliance/root) with the squashfs
# mounted at /opt/cuda, in a private mount namespace, and the appliance's VM and image run in it by chroot, as the
# calling user, with this machine's nvidia.ko and /dev/nvidia* (bound in). Nothing else of the host is visible, so
# every library the VM loads comes from the root or the squashfs (the loader's list, LD_DEBUG, says which); then
# Cuda summary, CudaGpuTest and CuOptGpuTest, and CudaBenchmark report (a 4096 SGEMM's TFLOPS). The tests free what
# they allocate (the GPU is shared: a few hundred MB at most). Needs sudo for the namespace, the read-only loop mount
# and chroot; nothing outside the namespace changes, and its mounts and the loop device go with it.
#
# Environment: OUT (build), LINUX_CUDA_SQUASHFS (OUT/linux-appliance/samaltak-cuda-13.squashfs), LINUX_CHECK_TIMEOUT
# (300 s).
set -eu
OUT=${OUT:-build}
W=$OUT/linux-appliance
R=$(cd "$W/root" 2>/dev/null && pwd) || { echo "linux-appliance-cuda-check: no $W/root: make linux-appliance first" >&2; exit 1; }
SQ=$(readlink -f "${LINUX_CUDA_SQUASHFS:-$W/samaltak-cuda-13.squashfs}")
T=$(mkdir -p "$W/cuda-check" && cd "$W/cuda-check" && pwd)
say() { echo "linux-appliance-cuda-check: $*"; }
fail() { echo "linux-appliance-cuda-check: FAILED: $*"; exit 1; }
[ -f "$SQ" ] || fail "no $SQ: make linux-appliance-cuda first"
[ -d "$R/opt/cuda" ] || fail "$R has no /opt/cuda: make linux-appliance again"
sudo -n true 2>/dev/null || fail "needs sudo without a password (the mount namespace, the loop mount, chroot)"
drv=$(unsquashfs -cat "$SQ" MANIFEST | sed -n 's/^driver \([^ ]*\).*/\1/p')
ko=$(cat /sys/module/nvidia/version 2>/dev/null || echo none)
[ "$drv" = "$ko" ] || fail "the squashfs's driver userspace is $drv, this machine's nvidia.ko $ko: libcuda would refuse it"
say "root $R, $SQ (driver $drv = this nvidia.ko)"

EXPR="[String streamContents: [:s |
	s nextPutAll: 'env: '; print: {Smalltalk vm getenv: 'SAMALTAK_CUDA_LIBS'. Smalltalk vm getenv: 'LD_LIBRARY_PATH'}; cr.
	{CudaGpuTest. CuOptGpuTest} do: [:c | s nextPutAll: c name; nextPutAll: ': '; print: c run; cr].
	s nextPutAll: CudaBenchmark report]] on: Error do: [:e | 'ERROR ' , e class name , ': ' , e messageText printString]"
mkdir -p "$T/mnt"
rm -f "$T/out.txt" "$T/loader.txt"
t0=$(date +%s)
set +e
sudo -n unshare --mount --propagation private sh -eu -c '
	M=$1; R=$2; SQ=$3; U=$4; TMO=$5; EXPR=$6
	mount --bind "$R" "$M"; mount -o remount,bind,ro "$M"
	mount -t squashfs -o ro,loop "$SQ" "$M/opt/cuda"
	mount -t proc proc "$M/proc"; mount --rbind /sys "$M/sys"; mount --rbind /dev "$M/dev"
	for d in tmp run data; do mount -t tmpfs -o mode=1777 "$d" "$M/$d"; done
	exec timeout -k 5 "$TMO" chroot --userspec="$U" "$M" /usr/bin/env -i HOME=/data PATH=/usr/bin:/bin \
		SAMALTAK_CUDA_LIBS=/opt/cuda/lib LD_LIBRARY_PATH=/usr/local/lib:/opt/cuda/lib LD_DEBUG=files \
		/samaltak/samaltak /samaltak/samaltak.image --headless --eval "$EXPR" < /dev/null
' sh "$T/mnt" "$R" "$SQ" "$(id -u):$(id -g)" "${LINUX_CHECK_TIMEOUT:-300}" "$EXPR" > "$T/out.txt" 2> "$T/loader.txt"
s=$?
set -e
tr '\r' '\n' < "$T/out.txt" > "$T/report.txt"
[ $s = 0 ] || { tail -5 "$T/loader.txt"; fail "the VM in the chroot: exit $s"; }
# The loader's list: each object it initialized, by directory.
sed -n 's/.*calling init: \(\/.*\)/\1/p' "$T/loader.txt" | sort -u > "$T/loaded.txt"
say "loaded $(wc -l < "$T/loaded.txt") objects: $(sed 's|/[^/]*$||' "$T/loaded.txt" | sort | uniq -c | awk '{ printf "%s%s %d", (NR > 1 ? ", " : ""), $2, $1 }')"
say "from the CUDA root: $(grep '^/opt/cuda/' "$T/loaded.txt" | sed 's|.*/||' | tr '\n' ' ')"
grep -q '^/opt/cuda/lib/libcublasLt' "$T/loaded.txt" && grep -q '^/opt/cuda/lib/libcuda\.so' "$T/loaded.txt" || fail "cuBLASLt or libcuda not loaded from /opt/cuda"
sed 's/^/  /' "$T/report.txt"
grep -q 'ERROR' "$T/report.txt" && fail "an error in the image"
for c in CudaGpuTest CuOptGpuTest; do grep -q "^$c: a TestResult(\([0-9]*\) run, \1 passed" "$T/report.txt" || fail "$c did not pass"; done
grep -q 'TFLOPS' "$T/report.txt" || fail "no SGEMM"
say "passed in $(($(date +%s) - t0)) s"
