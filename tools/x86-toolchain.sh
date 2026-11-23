#!/bin/sh
# An x86-64 cross toolchain and qemu-x86_64 for an arm64 Linux host (Debian/Ubuntu), without root: apt-get download of
# Ubuntu's cross gcc, binutils, glibc and qemu-user-static packages, unpacked (dpkg-deb -x) into a cache directory. For
# tools/lowering-check.sh on arm64, which uses it by itself once it is there.
#   tools/x86-toolchain.sh          set it up (if needed); print the X86_CC and X86_RUN it gives
#   tools/x86-toolchain.sh --env    the same as shell assignments: eval "$(tools/x86-toolchain.sh --env)"
#   tools/x86-toolchain.sh --path   only print the directory (no setup)
# The directory: SAMALTAK_X86_TOOLCHAIN, default ${XDG_CACHE_HOME:-~/.cache}/samaltak/x86-toolchain. Delete it to start
# over; a different package list (this script changed) sets it up again.
set -eu
DIR=${SAMALTAK_X86_TOOLCHAIN:-${XDG_CACHE_HOME:-$HOME/.cache}/samaltak/x86-toolchain}
[ "${1:-}" = --path ] && { echo "$DIR"; exit 0; }
GCCV=13
PKGS="gcc-$GCCV-x86-64-linux-gnu cpp-$GCCV-x86-64-linux-gnu gcc-$GCCV-x86-64-linux-gnu-base binutils-x86-64-linux-gnu
libgcc-$GCCV-dev-amd64-cross libc6-dev-amd64-cross libc6-amd64-cross linux-libc-dev-amd64-cross libgcc-s1-amd64-cross
libgomp1-amd64-cross libatomic1-amd64-cross qemu-user-static"
# the host libraries the compiler and binutils run with: downloaded too where they are not installed
HOSTLIBS="libsframe1 libjansson4 libisl23 libmpc3 libmpfr6 libgmp10 libzstd1 zlib1g binutils-common"
CC_WRAP=$DIR/bin/x86_64-linux-gnu-gcc
RUN=$DIR/root/usr/bin/qemu-x86_64-static
STAMP=$DIR/stamp
want=$(echo $PKGS | tr ' ' '\n' | sort | tr '\n' ' ')
if [ ! -x "$CC_WRAP" ] || [ ! -x "$RUN" ] || [ "$(cat "$STAMP" 2>/dev/null)" != "$want" ]; then
	case $(uname -s)/$(uname -m) in
	Linux/aarch64|Linux/arm64) ;;
	*) echo "x86-toolchain: for arm64 Linux hosts (here $(uname -s)/$(uname -m)); on x86-64 the native cc is the x86 side" >&2; exit 1 ;;
	esac
	command -v apt-get >/dev/null && command -v dpkg-deb >/dev/null || { echo "x86-toolchain: needs apt-get and dpkg-deb (Debian or Ubuntu)" >&2; exit 1; }
	extra=
	for p in $HOSTLIBS; do dpkg -s "$p" >/dev/null 2>&1 || extra="$extra $p"; done
	rm -rf "$DIR"
	mkdir -p "$DIR/debs" "$DIR/root" "$DIR/bin"
	echo "x86-toolchain: downloading into $DIR" >&2
	# shellcheck disable=SC2086
	(cd "$DIR/debs" && apt-get download $PKGS $extra >/dev/null) || {
		echo "x86-toolchain: apt-get download failed (apt's package lists may be stale or lack universe: ask for apt-get update)" >&2
		exit 1; }
	for f in "$DIR"/debs/*.deb; do dpkg-deb -x "$f" "$DIR/root"; done
	rm -rf "$DIR/debs"
	# the cross binutils' libbfd and libopcodes are in usr/lib/aarch64-linux-gnu, which the loader would look for in /
	cat >"$CC_WRAP" <<EOF
#!/bin/sh
LD_LIBRARY_PATH="$DIR/root/usr/lib/aarch64-linux-gnu\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}" exec "$DIR/root/usr/bin/x86_64-linux-gnu-gcc-$GCCV" "\$@"
EOF
	chmod +x "$CC_WRAP"
	# check: a static program that runs
	printf '#include <stdio.h>\nint main(void) { printf("%%d\\n", (int)sizeof(long double)); return 0; }\n' >"$DIR/check.c"
	"$CC_WRAP" -static -O1 -o "$DIR/check" "$DIR/check.c"
	[ "$("$RUN" "$DIR/check")" = 16 ] || { echo "x86-toolchain: the check program did not run under qemu-x86_64" >&2; exit 1; }
	rm -f "$DIR/check" "$DIR/check.c"
	echo "$want" >"$STAMP"
fi
if [ "${1:-}" = --env ]; then
	echo "X86_CC='$CC_WRAP -static'; X86_RUN='$RUN'; export X86_CC X86_RUN"
else
	echo "X86_CC=$CC_WRAP -static"
	echo "X86_RUN=$RUN"
fi
