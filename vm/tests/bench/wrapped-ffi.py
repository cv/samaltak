#!/usr/bin/env python3
"""Compare live PTY legacy primitives and deployed wrappers on one hosted VM."""
import argparse
import csv
import hashlib
import os
import platform
from pathlib import Path
import statistics
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
CASES = ("directForeground:", "wrappedForeground:", "priorForeground:",
         "directResize:", "wrappedResize:", "priorResize:",
         "directScalar:", "arrayScalar:", "priorScalar:")


def run(args, vm, image, jit, env, writer):
    expr = (f"WrappedFFIBench run: {args.iterations} warmup: {args.warmup} "
            f"rounds: {args.rounds}")
    cmd = [vm, "--jit", jit, image, "--headless", "--load", HERE / "wrapped-ffi.st", "--eval", expr]
    p = subprocess.run(cmd, env=env, timeout=900, text=True, capture_output=True)
    if p.returncode or "true" not in p.stdout.splitlines():
        sys.exit(f"{jit} failed ({p.returncode}):\n{p.stderr}\n{p.stdout[-4000:]}")
    data = [line.split(",")[1:] for line in p.stdout.splitlines() if line.startswith("wrapped-ffi,")]
    expected = []
    for r in range(1, 6 + args.rounds):
        phase = "warmup" if r <= 4 else "discard" if r == 5 else "steady"
        n = args.warmup // 4 if r <= 4 else args.iterations
        expected.extend((phase, r, variant, n) for variant in (CASES if r % 2 else CASES[::-1]))
    if len(data) != len(expected):
        sys.exit(f"{jit}: got {len(data)} rows, expected {len(expected)}")
    steady = {variant: [] for variant in CASES}
    for (phase, round_, variant, calls, usecs, allocated), plan in zip(data, expected):
        round_, calls, usecs, allocated = map(int, (round_, calls, usecs, allocated))
        if (phase, round_, variant, calls) != plan or usecs <= 0 or allocated < 0:
            sys.exit(f"{jit}: malformed benchmark row: {(phase, round_, variant, calls, usecs, allocated)}")
        writer.writerow((jit, phase, round_, variant, calls, usecs, allocated))
        if phase == "steady":
            steady[variant].append((usecs * 1000 / calls, allocated / calls))
    for start in range(0, len(CASES), 3):
        group = CASES[start:start + 3]
        reference = [t for t, _ in steady[group[0]]]
        for case in group:
            times, allocated = zip(*steady[case])
            ratio = statistics.median(t / d for t, d in zip(times, reference))
            print(f"{jit:8} {case:20} {statistics.median(times):8.1f} ns/call "
                  f"[{min(times):.1f}, {max(times):.1f}], {statistics.median(allocated):.2f} B/call; "
                  f"paired/direct {ratio:.3f}x", file=sys.stderr)
    sys.stdout.flush()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vm", type=Path, default=ROOT / "vm/build/samaltak")
    parser.add_argument("--image", type=Path, default=ROOT / "build/samaltak.image")
    parser.add_argument("--cpu", type=int, help="pin Linux process and PTY child to this logical CPU")
    parser.add_argument("--jit", nargs="+", choices=("none", "baseline", "opt"), default=["none", "opt"])
    parser.add_argument("--rounds", type=int, default=10)
    parser.add_argument("--iterations", type=int, default=50_000)
    parser.add_argument("--warmup", type=int, default=32_000)
    args = parser.parse_args()
    if args.rounds < 2 or args.iterations < 2 or args.iterations % 2 or args.warmup < 8 or args.warmup % 8 or args.iterations >= 1_000_000_000 or args.warmup >= 1_000_000_000:
        parser.error("need >=2 rounds, positive even iterations and warmup divisible by 8")
    if args.cpu is not None:
        if not hasattr(os, "sched_getaffinity") or args.cpu not in os.sched_getaffinity(0):
            parser.error("CPU is unavailable")
        os.sched_setaffinity(0, {args.cpu})
    vm = args.vm.resolve(strict=True)
    image = args.image.resolve(strict=True)
    print(f"{platform.machine()} {platform.system()} CPU={args.cpu} "
          f"iterations={args.iterations} warmup={args.warmup} rounds={args.rounds}", file=sys.stderr)
    for path in (vm, image):
        print(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path}", file=sys.stderr)
    env = {k: v for k, v in os.environ.items() if k not in
           ("DISPLAY", "WAYLAND_DISPLAY", "SAMALTAK_NATIVE_GRANTS", "SAMALTAK_VERIFY_GC")}
    env.update(LC_ALL="C", SDL_VIDEO_DRIVER="wrapped_ffi_no_video", SDL_VIDEODRIVER="wrapped_ffi_no_video")
    with tempfile.TemporaryDirectory(prefix="wrapped-ffi-bench-") as tmp:
        darwin = platform.system() == "Darwin"
        fixture = Path(tmp) / ("fixture.dylib" if darwin else "fixture.so")
        subprocess.run([os.environ.get("CC", "cc"), "-O2", "-dynamiclib" if darwin else "-shared",
                        "-fPIC", ROOT / "tests/vm/wrapped_ffi_fixture.c", "-o", fixture], check=True, env=env)
        env["SAMALTAK_NATIVE_GRANTS"] = (f"wrapped|wrapped_step|i32(i32)|{fixture}\n"
                                         f"wrapped|wrapped_calls|u32()|{fixture}")
        writer = csv.writer(sys.stdout, lineterminator="\n")
        writer.writerow(("jit", "phase", "round", "variant", "calls", "us", "bytes"))
        for jit in args.jit:
            run(args, vm, image, jit, env, writer)


if __name__ == "__main__":
    main()
