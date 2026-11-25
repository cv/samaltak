#!/bin/sh
# The CUDA root in QEMU, where there is no GPU (make linux-appliance-cuda-test, after make linux-appliance and
# linux-appliance-cuda): a disk laid out as install.sh leaves DGX OS's root (an ext4 file system with
# /var/lib/samaltak/data.img and samaltak-cuda-13.squashfs), booted with the command line install.sh gives the boot
# option (samaltak.data= and samaltak.cuda=UUID=...:/path). Checks: rcS mounts the squashfs at /opt/cuda and
# samaltak-run names it (SAMALTAK_CUDA_LIBS); every binding's library loads from it (how long each took: squashfs
# pages them in); with no device the libraries answer "no device" as CudaErrors, the Smalltalk side says CUDA is
# unavailable and the VM goes on (Cuda summary, CudaMatrix, cuBLAS, cuOpt); NVRTC compiles a kernel (no GPU needed);
# the World's time to the screen with the CUDA root; the quit powers off. Output in OUT/linux-appliance/cuda-test/.
set -eu
OUT=${OUT:-build}
W=$OUT/linux-appliance
T=$W/cuda-test
SQ=${LINUX_CUDA_SQUASHFS:-$W/samaltak-cuda-13.squashfs}
CP=${LINUX_CONTROL_PORT:-17343}
HERE=$(cd "$(dirname "$0")" && pwd)
QMP="python3 $HERE/qmp.py $T/qmp.sock"
CTL="$HERE/../samaltak-ctl --session linux-appliance-cuda-test"
UUID=5a3a1a7c-c0da-4c0d-a000-000000000013
PATH=$PATH:/sbin:/usr/sbin
now() { date +%s.%N; }
since() { echo "$(now) $1" | awk '{ printf "%.2f", $1 - $2 }'; }
fail() { echo "linux-appliance-cuda-test: FAILED: $*"; tr -d '\r' < "$T/console.log" | tail -20; exit 1; }
say() { echo "linux-appliance-cuda-test: $*"; }
[ -f "$W/vmlinuz" ] && [ -f "$SQ" ] || { echo "linux-appliance-cuda-test: no $W/vmlinuz or $SQ: make linux-appliance linux-appliance-cuda first" >&2; exit 1; }
rm -rf "$T" && mkdir -p "$T/data" "$T/host/var/lib/samaltak"
(umask 077
 head -c 24 /dev/urandom | base64 | tr -d '/+=\n' > "$T/control-token"
 cp "$T/control-token" "$T/data/control-token"
 printf '%s\n' --max-heap 2048 --control --control-host 0.0.0.0 --control-port 7341 --control-token-file /data/control-token > "$T/data/samaltak.args")
truncate -s 256M "$T/data.img" && mkfs.ext4 -q -F -L SAMALTAK-DATA -d "$T/data" "$T/data.img"
mv "$T/data.img" "$T/host/var/lib/samaltak/data.img"
ln "$SQ" "$T/host/var/lib/samaltak/samaltak-cuda-13.squashfs" 2>/dev/null || cp "$SQ" "$T/host/var/lib/samaltak/samaltak-cuda-13.squashfs"
# DGX OS's root, as far as the appliance sees it: another label, the files where install.sh puts them.
mb=$(( ($(wc -c < "$SQ") + 268435456) / 1048576 + 128 ))
truncate -s "${mb}M" "$T/host.img" && mkfs.ext4 -q -F -L test-root -U "$UUID" -d "$T/host" "$T/host.img"
rm -rf "$T/host"
P=/var/lib/samaltak

t0=$(now)
OUT=$OUT LINUX_QMP=$T/qmp.sock LINUX_DATA=$T/host.img LINUX_CONTROL_PORT=$CP \
	LINUX_CMDLINE="samaltak.data=UUID=$UUID:$P/data.img samaltak.cuda=UUID=$UUID:$P/samaltak-cuda-13.squashfs" \
	"$HERE/run.sh" > "$T/console.log" 2>&1 &
qemu=$!
trap 'kill $qemu 2>/dev/null || true' EXIT
i=0; while :; do
	sleep 0.1; i=$((i + 1)); [ $i -gt 300 ] && fail "no World on the screen in 30 s"
	kill -0 $qemu 2>/dev/null || fail "QEMU ended"
	[ -S "$T/qmp.sock" ] || continue
	$QMP screendump "$T/first.png" 2>/dev/null || continue
	[ "$(wc -c < "$T/first.png")" -gt 100000 ] && break
done
say "World on the screen $(since "$t0") s after QEMU started"
c=$(tr -d '\r' < "$T/console.log")
echo "$c" | grep -q "data on /host$P/data.img" || fail "the data volume is not $P/data.img on the root"
echo "$c" | grep -q "cuda on /host$P/samaltak-cuda-13.squashfs" || fail "no CUDA root mounted"
say "$(echo "$c" | grep -o 'samaltak-linux: data on [^ ]* at [0-9.]* s'); $(echo "$c" | grep -o 'samaltak-linux: cuda on .* at [0-9.]* s'); $(echo "$c" | grep -o 'vm start at [0-9.]* s')"

i=0; until $CTL connect --host 127.0.0.1 --port "$CP" --token-file "$T/control-token" > /dev/null 2>&1; do
	sleep 0.5; i=$((i + 1)); [ $i -gt 60 ] && fail "control service not reachable on 127.0.0.1:$CP"; done
ev() { $CTL eval "$1" 2>&1 || fail "eval $1: $?"; }
r=$(ev "{Smalltalk vm getenv: 'SAMALTAK_CUDA_LIBS'. Smalltalk vm getenv: 'LD_LIBRARY_PATH'}")
say "environment: $r"
case $r in *"'/opt/cuda/lib'"*) ;; *) fail "SAMALTAK_CUDA_LIBS is not /opt/cuda/lib: $r" ;; esac
# Each binding's library, loaded from the squashfs (the first touch reads it from the disk).
r=$(ev "(CudaLibraryAPI allSubclasses asSortedCollection: [:a :b | a name <= b name]) asArray collect: [:c | | t ok | t := Time millisecondClockValue. ok := c isAvailable. {c name. ok. Time millisecondClockValue - t}]")
say "libraries {class. loaded. ms}: $r"
case $r in *false*) fail "a library did not load: $r" ;; esac
# No device: CudaErrors with the libraries' own words, nothing that takes the VM down.
r=$(ev "{[CudaRuntimeAPI cudaGetDeviceCount] on: CudaError do: [:e | e messageText]. [CudaDriverAPI cuInit: 0. 'cuInit: ok'] on: CudaError do: [:e | e messageText]}")
say "no device: $r"
case $r in *cudaGetDeviceCount:*) ;; *) fail "cudaGetDeviceCount did not fail as a CudaError: $r" ;; esac
r=$(ev "{Cuda isAvailable. Cuda summary}")
say "Cuda: $r"
case $r in "#(false 'no CUDA here: cudaGetDeviceCount: "*) ;; *) fail "Cuda says it is available: $r" ;; esac
r=$(ev "{[CublasAPI cublasCreate. 'a handle'] on: CudaError do: [:e | e class name , ': ' , e messageText]. [(CudaMatrix rows: 2 cols: 2 values: #(1 2 3 4)) asRows] on: CudaError do: [:e | e class name , ': ' , e messageText]. [CuOpt maximize: #(3 5) subjectTo: #(#(1 0) #(0 2) #(3 2)) atMost: #(4 12 18)] on: Error do: [:e | e class name , ': ' , e messageText]}")
say "cuBLAS, CudaMatrix, cuOpt without a device: $r"
r=$(ev "| t c | t := Time millisecondClockValue. c := NvRtc compile: 'extern \"C\" __global__ void k(float *a) { a[threadIdx.x] *= 2.0f; }' options: #('-arch=sm_121'). {NvRtc version. c first size. Time millisecondClockValue - t}")
say "NVRTC {version. cubin bytes. ms}: $r"
case $r in "#(13"??" "[1-9]*) ;; *) fail "NVRTC did not compile from the CUDA root: $r" ;; esac
r=$(ev "GPUPlatform device class name")
say "the World's GPU without a device: $r"
case $r in *SoftwareGPU*) ;; *) fail "the World is not on a SoftwareGPU without a device: $r" ;; esac
r=$(ev '3 + 4') && [ "$r" = 7 ] || fail "the VM after the CUDA calls: $r"
say "the VM goes on: 3 + 4 = 7"
$CTL screenshot "$T/screenshot.png" > /dev/null 2>&1 || true

tq=$(now)
$CTL eval 'Smalltalk quit: 0' > /dev/null 2>&1 || true
i=0; while kill -0 $qemu 2>/dev/null; do sleep 0.1; i=$((i + 1)); [ $i -gt 200 ] && fail "no power off 20 s after quit"; done
say "powered off $(since "$tq") s after the quit"
grep -q 'vm exit 0' "$T/console.log" || fail "no 'vm exit 0' on the console"
$CTL close > /dev/null 2>&1 || true
rm -f "$T/host.img"
say passed
