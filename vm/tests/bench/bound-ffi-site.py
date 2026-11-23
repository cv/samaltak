#!/usr/bin/env python3
"""Paired, same-binary opt / opt -ffi-site headless PTY and scalar ablation."""
import argparse
import csv
import hashlib
import os
from pathlib import Path
import platform
import random
import statistics
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SELECTORS = tuple(
    prefix + op + ":" for op in ("Foreground", "Resize")
    for prefix in ("direct", "raw", "control", "wrapped")
) + ("matchedScalar:", "abruptScalar:")
TREATMENTS = ((1, 2, 3, 4), (5, 6, 7, 8), (9, 10))
WILLIAMS = ((0, 1, 3, 2), (1, 2, 0, 3), (2, 3, 1, 0), (3, 0, 2, 1))


def schedule(args, pair):
    rng = random.Random(args.seed + pair)
    for phase, rounds, sizes in (("warmup", 4, (8000, 8000)),
                                 ("discard", 2, args.sizes),
                                 ("steady", args.rounds, args.sizes)):
        for r in range(rounds):
            groups = [(g, n) for g in range(3) for n in sizes]
            rng.shuffle(groups)
            for g, size in groups:
                choices = TREATMENTS[g]
                order = (WILLIAMS[(r + g + pair + (size == sizes[1])) % 4]
                         if len(choices) == 4 else ((0, 1) if (r + pair) % 2 else (1, 0)))
                gid = 2 * g + 1 + (size == sizes[1] and sizes[0] != sizes[1])
                yield phase, r + 1, gid, size, tuple(choices[i] for i in order)


def execute(vm, image, tmp, plan, mode, env, log):
    literal = "#(" + " ".join(f"#('{phase}' {r} {g} {n} #({' '.join(map(str, ids))}))"
                              for phase, r, g, n, ids in plan) + ")"
    expr = ("[BoundFFISiteBench new run: " + literal + " selectors: #(" +
            " ".join(SELECTORS) + ")] on: Error do: [:e | Smalltalk vm stderrWrite: " +
            "e messageText, (String with: Character lf). Smalltalk quit: 1]")
    cmd = [vm, "--jit", "opt"]
    if mode == "off":
        cmd += ["--jit-flags", "-ffi-site"]
    cmd += [image, "--headless", "--load", HERE / "bound-ffi-site.st", "--eval", expr]
    p = subprocess.run(cmd, cwd=tmp, env=env, text=True, capture_output=True, timeout=240)
    if log is not None:
        log.with_suffix(".stdout").write_text(p.stdout)
        log.with_suffix(".stderr").write_text(p.stderr)
    if p.returncode or "true" not in p.stdout.splitlines():
        raise RuntimeError(f"{mode}: code={p.returncode}\n{p.stderr}\n{p.stdout[-4000:]}")
    actual = [line.split(",")[1:] for line in p.stdout.splitlines() if line.startswith("ffi-site-bench,")]
    expected = [(phase, r, g, n, SELECTORS[i - 1]) for phase, r, g, n, ids in plan for i in ids]
    if len(actual) != len(expected):
        raise RuntimeError(f"{mode}: got {len(actual)} rows, expected {len(expected)}")
    stats = [line for line in p.stdout.splitlines() if line.startswith("ffi-site-stats,")]
    if len(stats) != 1:
        raise RuntimeError(f"{mode}: bad opt compilation stats: {stats}")
    before, after = map(int, stats[0].split(",")[1:])
    if before <= 0 or after < before:
        raise RuntimeError(f"{mode}: no optimizing compiler? {stats[0]}")
    print(f"{mode}: {stats[0]}", file=sys.stderr)
    rows = []
    for (phase, r, g, n, name, us, allocated), want in zip(actual, expected):
        if (phase, int(r), int(g), int(n), name) != want or int(us) <= 0 or int(allocated) < 0:
            raise RuntimeError(f"{mode}: invalid sample {(phase, r, g, n, name, us, allocated)}")
        rows.append((*want, int(us), int(allocated)))
    return rows, p.stderr


def med(values):
    return statistics.median(values)


def summarize(samples):
    f = sys.stderr
    print("steady medians (ns/call); delta is within matching pair, size and round", file=f)
    for size in sorted(set(k[2] for k in samples)):
        for selector in SELECTORS:
            pairs = [(v["off"][0], v["on"][0], v["on"][1])
                     for key, v in samples.items() if key[2:] == (size, selector)]
            off, on, alloc = zip(*pairs)
            pct = [(b - a) * 100 / a for a, b in zip(off, on)]
            delta = [b - a for a, b in zip(off, on)]
            print(f"{size:7} {selector:19} off={med(off):8.1f} on={med(on):8.1f} "
                  f"delta={med(delta):+7.1f} ({med(pct):+6.2f}%) "
                  f"[{min(delta):+.1f},{max(delta):+.1f}] on B/call={med(alloc):.3f}", file=f)
        for op in ("Foreground", "Resize", "Scalar"):
            reference = {"Foreground": "direct", "Resize": "direct", "Scalar": "matched"}[op]
            variants = ("raw", "wrapped") if op != "Scalar" else ("abrupt",)
            for variant in variants:
                for mode in ("on", "off") if op == "Scalar" else ("on",):
                    delta = [v[mode][0] - samples[key[:3] + (reference + op + ":",)][mode][0]
                             for key, v in samples.items() if key[2:] == (size, variant + op + ":")]
                    print(f"{size:7} {mode:3} {variant + op} vs {reference + op}: "
                          f"{med(delta):+.1f} ns/overall call", file=f)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--vm", type=Path, required=True)
    ap.add_argument("--image", type=Path, required=True)
    ap.add_argument("--cpu", type=int, help="pin both VM and PTY child (Linux)")
    ap.add_argument("--pairs", type=int, default=3)
    ap.add_argument("--rounds", type=int, default=8)
    ap.add_argument("--sizes", type=int, nargs=2, default=(25_000, 100_000))
    ap.add_argument("--seed", type=int, default=203)
    ap.add_argument("--logs", type=Path)
    ap.add_argument("--diagnostic", action="store_true",
                    help="only untimed, isolated trace proof for each raw/production PTY variant")
    args = ap.parse_args()
    if (args.pairs < 1 or args.rounds < 4 or args.rounds % 4 or
            len(set(args.sizes)) != 2 or any(n < 128 or n > 1_000_000_000 or n % 2 for n in args.sizes)):
        ap.error("need >=1 pair, rounds divisible by 4, two distinct even sizes (128..1e9)")
    vm, image = args.vm.resolve(strict=True), args.image.resolve(strict=True)
    log = args.logs.resolve() if args.logs else None
    if log:
        log.mkdir(parents=True, exist_ok=True)
    if args.cpu is not None:
        if not hasattr(os, "sched_getaffinity") or args.cpu not in os.sched_getaffinity(0):
            ap.error("CPU unavailable")
        os.sched_setaffinity(0, {args.cpu})
    print(f"{platform.machine()} {platform.system()} CPU={args.cpu} "
          f"sizes={args.sizes} rounds={args.rounds} pairs={args.pairs} seed={args.seed}", file=sys.stderr)
    for file in (vm, image, HERE / "bound-ffi-site.st", HERE / "bound-ffi-site.py"):
        print(f"{hashlib.sha256(file.read_bytes()).hexdigest()}  {file}", file=sys.stderr)
    env = {k: v for k, v in os.environ.items() if k not in
           ("DISPLAY", "WAYLAND_DISPLAY", "SAMALTAK_NATIVE_GRANTS", "SAMALTAK_VERIFY_GC",
            "SAMALTAK_FFI_SITE_TRACE", "SAMALTAK_FFI_BOX_FULL_GC", "SAMALTAK_OPT_TRACE")}
    env.update(LC_ALL="C", SDL_VIDEODRIVER="siteffi_no_video", SDL_VIDEO_DRIVER="siteffi_no_video")
    with tempfile.TemporaryDirectory(prefix="bound-ffi-bench-") as tmp:
        darwin = platform.system() == "Darwin"
        lib = Path(tmp) / ("fixture.dylib" if darwin else "fixture.so")
        subprocess.run([os.environ.get("CC", "cc"), "-O2", "-dynamiclib" if darwin else "-shared",
                        "-fPIC", ROOT / "tests/vm/wrapped_ffi_fixture.c", "-o", lib], check=True, env=env)
        env["SAMALTAK_NATIVE_GRANTS"] = "\n".join(
            f"wrapped|wrapped_{symbol}|{sig}|{lib}" for symbol, sig in
            (("step", "i32(i32)"), ("other", "i32(i32)"), ("calls", "u32()")))
        if args.diagnostic:
            baseline_misses = None
            print("variant,mode,hits,misses,positional_primitive")
            for i in (2, 4, 6, 8, 9, 10):
                phase = [("warmup", 1, 1, 24000, (i,)), ("steady", 1, 1, 100000, (i,))]
                name = SELECTORS[i - 1].rstrip(":")
                measured = {}
                for mode in ("on", "off"):
                    _, trace = execute(vm, image, tmp, phase, mode, {**env, "SAMALTAK_FFI_SITE_TRACE": "1"},
                                       log / f"{name}-{mode}" if log else None)
                    counters = [line for line in trace.splitlines() if line.startswith("ffi-site trace ")]
                    if len(counters) != 1:
                        raise RuntimeError(f"{name}/{mode}: expected trace counters: {trace}")
                    hits, misses, primitives = (int(item.split("=")[1]) for item in counters[0].split()[2:])
                    if (mode == "on" and hits < 90000) or (mode == "off" and (hits or misses)):
                        raise RuntimeError(f"{name}/{mode}: unexpected counters: {counters[0]}")
                    measured[mode] = hits, misses, primitives
                    print(f"{name},{mode},{hits},{misses},{primitives}")
                hits, misses, primitives = measured["on"]
                if hits + primitives != measured["off"][2]:
                    raise RuntimeError(f"{name}: direct and generic edges do not match the sole disabled-site path")
                if i == 9:
                    baseline_misses = misses
                elif i == 10 and not 1000 < misses - baseline_misses < 3000:
                    raise RuntimeError(f"{name}: expected an extra receiver miss roughly every 64 calls")
            return
        writer = csv.writer(sys.stdout, lineterminator="\n")
        writer.writerow(("pair", "mode", "phase", "round", "group", "calls", "variant", "us", "allocated_bytes"))
        samples = {}
        for pair in range(1, 1 + args.pairs):
            plan = list(schedule(args, pair))
            for mode in ("off", "on") if pair % 2 else ("on", "off"):
                rows, _ = execute(vm, image, tmp, plan, mode, env, log / f"pair-{pair}-{mode}" if log else None)
                for phase, r, g, n, name, us, bs in rows:
                    writer.writerow((pair, mode, phase, r, g, n, name, us, bs))
                    if phase == "steady":
                        samples.setdefault((pair, r, n, name), {})[mode] = (1000 * us / n, bs / n)
                sys.stdout.flush()
        summarize(samples)


if __name__ == "__main__":
    main()
