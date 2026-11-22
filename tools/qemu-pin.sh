#!/usr/bin/env bash
# tools/qemu-pin.sh AFFINITY QEMU-COMMAND...: run QEMU on the host CPUs AFFINITY names (the Makefile's UEFI_AFFINITY;
# docs/uefi.md, Pinning).
#   empty or none   as it is: anywhere
#   big             the logical CPUs of the highest cpuinfo_max_freq (the DGX Spark's Cortex-X925: 5-9, 15-19), on Linux
#                   with taskset and more than one kind of core; elsewhere as it is
#   a CPU list      such as 5-9,15-19 (taskset's): as it is (Linux)
# Pinned, QEMU runs under taskset -c LIST, with at most as many vCPUs as LIST has CPUs (its -smp cut down) and its
# threads named (-name ...,debug-threads=on), and each vCPU thread ("CPU n/KVM") is pinned to a CPU of the list of its
# own, the least busy ones first (sampled over 0.2 s as QEMU starts); the other threads (I/O, display) stay on the list.
# The script execs QEMU: its pid, exit status, stdin and signals are QEMU's.
set -eu
aff=${1-}
shift
[ "$aff" = none ] && aff=
[ -n "$aff" ] || exec "$@"
if [ "$(uname -s)" != Linux ] || ! command -v taskset >/dev/null; then
    [ "$aff" = big ] && exec "$@"
    echo "qemu-pin: a CPU list needs Linux's taskset" >&2
    exit 2
fi
if [ "$aff" = big ]; then
    # The CPUs of the highest maximum frequency, if not all have it.
    list=$(grep -H . /sys/devices/system/cpu/cpu[0-9]*/cpufreq/cpuinfo_max_freq 2>/dev/null | awk -F: '
        { n = split($1, p, "/"); c = substr(p[n - 2], 4) + 0; f[c] = $2 + 0; if ($2 + 0 > m) m = $2 + 0 }
        END { for (c in f) if (f[c] == m) big[c] = 1; else little = 1
              if (!little) exit
              for (c = 0; c < 4096; c++) if (c in big) s = s (s == "" ? "" : ",") c; print s }')
    [ -n "$list" ] || exec "$@"
else
    [[ $aff =~ ^[0-9]+(-[0-9]+)?(,[0-9]+(-[0-9]+)?)*$ ]] || { echo "qemu-pin: not a CPU list: $aff" >&2; exit 2; }
    list=$aff
fi
cpus=()
IFS=, read -ra parts <<< "$list"
for p in "${parts[@]}"; do
    if [[ $p == *-* ]]; then for ((c = ${p%-*}; c <= ${p#*-}; c++)); do cpus+=("$c"); done; else cpus+=("$p"); fi
done
max=${#cpus[@]}
# -smp N (or -smp cpus=N,...) cut to the CPUs pinned to; QEMU's default is one vCPU.
args=() prev='' vcpus=1
for a in "$@"; do
    if [ "$prev" = -smp ]; then
        n=${a#cpus=}; n=${n%%,*}
        if [[ $n =~ ^[0-9]+$ ]]; then
            if [ "$n" -gt "$max" ]; then
                echo "qemu-pin: $n vCPUs on $max host CPUs ($list): -smp $max" >&2
                if [[ $a == *,* ]]; then a=$max,${a#*,}; else a=$max; fi
                n=$max
            fi
            vcpus=$n
        fi
    fi
    args+=("$a")
    prev=$a
done
qemu=$$
(
    exec </dev/null >&2
    # The pinned CPUs by how busy they were over 0.2 s (/proc/stat's user, nice, system, irq, softirq, steal), least first.
    busy() { awk '/^cpu[0-9]/ { print substr($1, 4), $2 + $3 + $4 + $7 + $8 + $9 }' /proc/stat; }
    b0=$(busy); sleep 0.2; b1=$(busy)
    mapfile -t order < <(printf '%s\n' "$b0" | awk -v b1="$b1" -v want="${cpus[*]}" '
        BEGIN { n = split(b1, l, "\n"); for (i = 1; i <= n; i++) { split(l[i], f, " "); t[f[1]] = f[2] }
                split(want, w, " ") }
        { d[$1] = t[$1] - $2 }
        END { for (i = 1; i in w; i++) printf "%d %d %d\n", d[w[i]], i, w[i] }' | sort -n -k1,1 -k2,2 | awk '{ print $3 }')
    for ((i = 0; i < 300; i++)); do
        [ -d "/proc/$qemu" ] || exit 0
        found=()
        for t in /proc/"$qemu"/task/*; do
            name=$(cat "$t/comm" 2>/dev/null) || continue
            [[ $name =~ ^CPU\ ([0-9]+)/ ]] && found[BASH_REMATCH[1]]=${t##*/}
        done
        if [ ${#found[@]} -ge "$vcpus" ]; then
            msg=
            for v in "${!found[@]}"; do
                c=${order[v % max]}
                taskset -pc "$c" "${found[v]}" >/dev/null && msg="$msg vCPU $v on $c,"
            done
            echo "qemu-pin: QEMU on CPUs $list;${msg%,}"
            exit 0
        fi
        sleep 0.1
    done
    echo "qemu-pin: QEMU on CPUs $list; no vCPU threads named CPU n/... in 30 s: not pinned one by one"
) &
exec taskset -c "$list" "${args[@]}" -name samaltak,debug-threads=on
