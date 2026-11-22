#!/bin/sh
# Ext4 test fixtures (Tests-Storage, Ext4VolumeTest): a tree of files on the host and file system images of it made by
# e2fsprogs (mke2fs -d, no root needed), one per variant, into OUTDIR; rebuilt only when this script is newer than them.
#   OUTDIR/tree                 the files the images hold
#   OUTDIR/manifest.txt         what the host sees of each (find -printf): path type mode uid gid size links mtime target
#   OUTDIR/VARIANT.img          the images (VARIANTS below); OUTDIR/variants.txt lists them: name, block size, inode size, features
# After mke2fs, debugfs sets nanosecond and post-2038 times (times/), uninitialized extents (prealloc) and a uid and gid
# above 65535 (owner/high-uid); e2fsck -fyD indexes the big directories (htree); then the uninitialized extents' blocks are
# filled with 0xFF, which must still read as zeros. Exits 2 with a clear message if e2fsprogs is missing.
# usage: tests/storage/ext4_fixtures.sh OUTDIR
set -eu
OUT=$1
SCRIPT=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
PATH=$PATH:/sbin:/usr/sbin
export PATH
for tool in mke2fs debugfs e2fsck perl; do
    command -v $tool >/dev/null 2>&1 || {
        echo "ext4_fixtures: $tool not found: the ext4 tests need e2fsprogs (apt-get install e2fsprogs) and perl" >&2
        exit 2
    }
done
# Concurrent callers (test shards, gate stages at once) build them once: one at a time, under a lock beside OUTDIR.
if [ -z "${EXT4_FIXTURES_LOCKED:-}" ] && command -v flock >/dev/null 2>&1; then
    mkdir -p "$(dirname "$OUT")"
    EXT4_FIXTURES_LOCKED=1 exec flock "$OUT.lock" "$SCRIPT" "$@"
fi
if [ -f "$OUT/variants.txt" ] && [ "$OUT/variants.txt" -nt "$SCRIPT" ]; then exit 0; fi
rm -rf "$OUT"
mkdir -p "$OUT"
T=$OUT/tree
mkdir "$T"

# Small files, block boundaries, an empty file and directory, nested directories, a setuid file and a sticky directory.
printf 'Hello, ext4!\n' >"$T/hello.txt"
: >"$T/empty"
mkdir -p "$T/emptydir" "$T/dir/sub/deeper" "$T/dir/a" "$T/dir/b" "$T/dir/c" "$T/sticky"
printf 'deep\n' >"$T/dir/sub/deeper/file.txt"
chmod 1777 "$T/sticky"
printf '#!/bin/sh\n' >"$T/dir/suid"
chmod 4755 "$T/dir/suid"
chmod 640 "$T/dir/sub/deeper/file.txt"
mkdir "$T/sizes"
for n in 1 59 60 61 1023 1024 1025 2047 2048 2049 4095 4096 4097 12287 12288 12289 65535 65536 65537 \
        274431 274432 274433 1000000; do
    perl -e '$n = shift; print join("", map { chr(($_ * 7 + int($_ / 251)) % 256) } 0 .. $n - 1)' $n >"$T/sizes/$n"
done
head -c 16777216 /dev/urandom >"$T/large.bin"

# Sparse files: holes inside and at the end; 5 GiB with data past 4 GiB; many extents (an extent tree of depth 1 on
# 4 KiB blocks, 2 on 1 KiB); data and a hole for uninitialized extents (prealloc, 64 KiB).
perl -e '
    open F, ">", "$ARGV[0]/sparse" or die; binmode F;
    print F "start" x 1000; seek F, 1048576 + 123, 0; print F "middle" x 3000; truncate F, 3 * 1048576 + 77;
    open G, ">", "$ARGV[0]/huge" or die; binmode G;
    print G "head"; seek G, 4294967296 - 3, 0; print G "across 4 GiB"; seek G, 5 * 1073741824 - 9, 0; print G "the end!!";
    open H, ">", "$ARGV[0]/fragmented" or die; binmode H;
    for $i (0 .. 399) { seek H, $i * 8192, 0; print H sprintf("%-1024s", "island $i") }
    open P, ">", "$ARGV[0]/prealloc" or die; binmode P;
    print P "A" x 4096; seek P, 61440, 0; print P "Z" x 4096;
' "$T"

# Symbolic links: fast (in the inode) and slow (a block), relative, absolute, to a directory, dangling, loops.
LONG=a-directory-with-a-name-long-enough-that-a-link-to-it-is-slow
mkdir -p "$T/$LONG"
printf 'at the end of a slow link\n' >"$T/$LONG/target.txt"
mkdir "$T/links"
ln -s ../hello.txt "$T/links/fast"
ln -s "../$LONG/target.txt" "$T/links/slow"
ln -s /hello.txt "$T/links/absolute"
ln -s ../dir "$T/links/dirlink"
ln -s fast "$T/links/chain"
ln -s nowhere "$T/links/dangling"
ln -s loop2 "$T/links/loop1"
ln -s loop1 "$T/links/loop2"
ln -s self "$T/links/self"
ln -s ../links/dirlink/sub/../sub/deeper "$T/links/through"

# Hard links, in one directory and across two.
mkdir "$T/hard"
printf 'linked\n' >"$T/hard/one"
ln "$T/hard/one" "$T/hard/two"
ln "$T/hard/one" "$T/dir/three"

# Unicode names.
mkdir "$T/unicode"
printf 'é\n' >"$T/unicode/héllo wörld.txt"
printf 'ja\n' >"$T/unicode/日本語のファイル"
printf 'smile\n' >"$T/unicode/emoji-😀"
mkdir "$T/unicode/Ελληνικά"

# A FIFO, and files whose times and owner debugfs sets (their manifest lines are not what the image holds).
mkdir "$T/special" "$T/times" "$T/owner"
mkfifo "$T/special/fifo"
printf 'nanoseconds\n' >"$T/times/nanos"
printf 'after 2106\n' >"$T/times/future"
printf 'owner\n' >"$T/owner/high-uid"

# A directory of 2000 entries (htree after e2fsck -D), names of every length up to 255 bytes; some files have data.
mkdir "$T/many"
perl -e '
    for $i (0 .. 1999) {
        $name = sprintf("entry-%04d", $i);
        $name .= "-" . ("x" x (($i * 37) % 245)) if $i % 3 == 0;
        open F, ">", "$ARGV[0]/many/$name" or die;
        print F "entry $i\n" if $i % 10 == 0;
        close F }
' "$T"
mkdir "$T/many-dirs"
for i in 0 1 2 3 4 5 6 7 8 9; do mkdir "$T/many-dirs/d$i"; done
touch -d '2001-02-03 04:05:06' "$T/hello.txt"

(cd "$T" && find . -mindepth 1 -printf '%P\t%y\t%m\t%U\t%G\t%s\t%n\t%T@\t%l\n' | LC_ALL=C sort) >"$OUT/manifest.txt"

# name, block size, inode size, size in MB, features (mke2fs -O none,...), more mke2fs options (: for spaces, - for none)
EXT4=has_journal,ext_attr,dir_index,filetype,extent,flex_bg,sparse_super,large_file,huge_file,dir_nlink,extra_isize
VARIANTS="
ext4-4k 4096 256 96 $EXT4,resize_inode,64bit,metadata_csum -
ext4-1k 1024 256 96 $EXT4,resize_inode,64bit,metadata_csum -
ext4-32bit 4096 256 96 $EXT4,resize_inode,uninit_bg -
ext4-small-inodes 4096 128 96 has_journal,ext_attr,dir_index,filetype,extent,flex_bg,sparse_super,large_file,huge_file,dir_nlink,64bit,metadata_csum -
ext4-inline 4096 256 96 $EXT4,64bit,metadata_csum,inline_data -
ext4-metabg 1024 256 96 $EXT4,sparse_super2,meta_bg,64bit,metadata_csum -g:1024
ext4-64k 65536 256 160 $EXT4,64bit,metadata_csum -
ext3-4k 4096 256 96 has_journal,ext_attr,resize_inode,dir_index,filetype,sparse_super,large_file -
ext2-1k 1024 128 96 ext_attr,resize_inode,dir_index,filetype,sparse_super,large_file -
ext2-2k-nofiletype 2048 128 96 sparse_super,large_file -
"
: >"$OUT/variants.tmp"
echo "$VARIANTS" | while read -r name bs isize mb features more; do
    [ -n "$name" ] || continue
    img=$OUT/$name.img
    extra=$(echo "$more" | tr ':' ' ' | sed 's/^-$//')
    # shellcheck disable=SC2086
    mke2fs -q -F -t ext4 -O "none,$features" -b "$bs" -I "$isize" -N 4096 $extra -L "fixture-$name" \
        -U 0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0 -E "root_owner=$(id -u):$(id -g)" -d "$T" "$img" "${mb}M" >"$OUT/$name.log" 2>&1 \
        || { cat "$OUT/$name.log" >&2; echo "ext4_fixtures: mke2fs failed for $name" >&2; exit 1; }
    cmds=$OUT/$name.debugfs
    : >"$cmds"
    if [ "$isize" -gt 128 ]; then
        printf 'sif /times/nanos mtime 0x6040db3f\nsif /times/nanos mtime_extra 0x1D6F3454\nsif /times/nanos crtime_extra 0x4\n' >>"$cmds"
        printf 'sif /times/future mtime 0x10\nsif /times/future mtime_extra 0x1\n' >>"$cmds"
    fi
    printf 'sif /owner/high-uid uid 100000\nsif /owner/high-uid gid 70000\n' >>"$cmds"
    # mke2fs 1.47.0 -d with inline_data drops a file's trailing hole from its size
    case $features in *inline_data*) printf 'sif /sparse size 3145805\n' >>"$cmds" ;; esac
    case $features in *extent*) printf 'fallocate /prealloc 0 %d\n' $((65536 / bs - 1)) >>"$cmds" ;; esac
    debugfs -w -f "$cmds" "$img" >>"$OUT/$name.log" 2>&1
    e2fsck -fyD "$img" >>"$OUT/$name.log" 2>&1 || [ $? -le 1 ] || { cat "$OUT/$name.log" >&2; exit 1; }
    debugfs -R 'ex /prealloc' "$img" 2>/dev/null | awk '/Uninit/ { print $8, $10 }' | while read -r from to; do
        perl -e 'print "\377" x shift' $(( (to - from + 1) * bs )) | dd of="$img" bs="$bs" seek="$from" conv=notrunc 2>/dev/null
    done
    e2fsck -fn "$img" >>"$OUT/$name.log" 2>&1 || { cat "$OUT/$name.log" >&2; echo "ext4_fixtures: $name is not clean" >&2; exit 1; }
    echo "$name $bs $isize $features" >>"$OUT/variants.tmp"
done
mv "$OUT/variants.tmp" "$OUT/variants.txt"
