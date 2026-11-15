#!/usr/bin/env python3
"""Summarize extremem.sh result files: one row per configuration, over its files (invocations).

usage: extremem_summary.py [--warmup MINUTES] LABEL=FILE[,FILE...] ...
Table 1, medians over the files: time of the simulated minutes after the warmup (s), latency percentiles of customer
preparations and decisions (ms), the process's CPU time (user + sys, s) and peak RSS (MB).
Table 2, the GC pauses of the measured minutes (Samaltak and Pharo: GC time across an event; Java: the collectors'
safepoints and ZGC's allocation stalls): per invocation (median) their number and sum, then the percentiles and the
maximum of all files' pauses together, and how many a run had per range of duration (mean over the files).
"""
import re
import statistics
import sys

BUCKETS = [(0, 0.5), (0.5, 1), (1, 2), (2, 5), (5, 10), (10, 20), (20, 50), (50, 100), (100, None)]


def parse(path, warmup):
    laps, lat, info = {}, {}, {'pauses': None}
    for line in open(path):
        line = line.strip()
        m = re.match(r'^Extremem,(\d+),(\d+)$', line)
        if m:
            laps[int(m.group(1))] = int(m.group(2))
        elif line.startswith('# latency '):
            f = line.split()
            if len(f) > 3:
                lat[f[2]] = [int(x) for x in f[3:]]  # count mean p50 p90 p99 p99.9 p99.99 max
        elif line.startswith('# pauses us:'):
            info['pauses'] = [int(x) / 1000 for x in line[len('# pauses us:'):].split()]
        elif line.startswith('# process '):
            info.update({k: float(v) for k, v in re.findall(r'(\w+)=([\d.]+)', line)})
        elif line.startswith('# tally'):
            info['tally'] = line
        elif 'ERROR' in line:
            sys.exit(f'{path}: {line}')
    if info['pauses'] is None:
        sys.exit(f'{path}: no pauses')
    info['measured_s'] = sum(v for k, v in laps.items() if k > warmup) / 1e6
    info['lat'] = lat
    return info


def percentile(sorted_values, p):
    if not sorted_values:
        return 0
    return sorted_values[max(1, -(-len(sorted_values) * p // 1000)) - 1]


def main():
    args = sys.argv[1:]
    warmup = 15
    if args[:1] == ['--warmup']:
        warmup = int(args[1])
        args = args[2:]
    configs = []
    tallies = set()
    for arg in args:
        label, files = arg.split('=', 1)
        runs = [parse(f, warmup) for f in files.split(',')]
        tallies.update(r['tally'] for r in runs)
        configs.append((label, runs))

    print('| configuration | measured s | prep p50 | prep p99 | prep p99.9 | prep max | decision p50 | decision p99 | decision p99.9 | decision max | CPU s | peak RSS MB |')
    print('|' + '---|' * 12)
    for label, runs in configs:
        med = lambda f: statistics.median(f(r) for r in runs)
        ms = lambda kind, i: med(lambda r: r['lat'][kind][i]) / 1000
        cells = [f"{med(lambda r: r['measured_s']):.1f}"]
        for kind in ('preparation', 'decision'):
            cells += [f'{ms(kind, i):.2f}' if i <= 4 else f'{ms(kind, i):.1f}' for i in (2, 4, 5, 7)]
        cells += [f"{med(lambda r: r['user_s'] + r['sys_s']):.1f}", f"{med(lambda r: r['maxrss_kb']) / 1024:.0f}"]
        print(f'| {label} | ' + ' | '.join(cells) + ' |')

    print()
    names = [f'<{hi}' if lo == 0 else (f'≥{lo}' if hi is None else f'{lo}–{hi}') for lo, hi in BUCKETS]
    print('| configuration | pauses | sum ms | % of time | p50 ms | p90 ms | p99 ms | p99.9 ms | max ms | ' + ' | '.join(names) + ' |')
    print('|' + '---|' * (9 + len(BUCKETS)))
    for label, runs in configs:
        pooled = sorted(p for r in runs for p in r['pauses'])
        count = statistics.median(len(r['pauses']) for r in runs)
        total = statistics.median(sum(r['pauses']) for r in runs)
        share = statistics.median(sum(r['pauses']) / 10 / r['measured_s'] for r in runs)
        cells = [f'{count:.0f}', f'{total:.0f}', f'{share:.1f}']
        cells += [f'{percentile(pooled, p):.2f}' for p in (500, 900, 990, 999)] + [f'{pooled[-1] if pooled else 0:.1f}']
        for lo, hi in BUCKETS:
            n = sum(1 for p in pooled if p >= lo and (hi is None or p < hi)) / len(runs)
            cells.append(f'{n:.0f}' if n >= 1 or n == 0 else f'{n:.1f}')
        print(f'| {label} | ' + ' | '.join(cells) + ' |')

    if len(tallies) != 1:
        sys.exit('tallies differ:\n' + '\n'.join(sorted(tallies)))


main()
