#!/usr/bin/env python3
"""Compare two platform-capable Samaltak VMs without initializing video."""
import argparse
import csv
import os
from pathlib import Path
import shlex
import statistics
import subprocess
import sys
import tempfile

CASES = {
    **{name: ("first", "steady") for name in ("control", "scale", "ime", "foreground", "resize")},
    "close": ("first",),
    "dynamic": ("first_bind", "first_invoke", "invoke_reused", "invoke_fresh", "bind"),
}


def positive(text):
    n = int(text)
    if n < 1:
        raise argparse.ArgumentTypeError("must be positive")
    return n


def sample(vm, image, jit, case, tree, source, env, iterations, warmup):
    expr = f"({source}) value: #{case} value: {iterations} value: {warmup} value: #{tree}"
    cmd = [vm, "--jit", jit, "--eden", "16", image, "--headless", "--eval", expr]
    proc = subprocess.run(cmd, text=True, capture_output=True, env=env, timeout=120)
    rows = []
    for line in proc.stdout.splitlines():
        if line.startswith("ffi-bench,"):
            _, phase, n, us, size = line.split(",")
            rows.append((phase, int(n), int(us), int(size)))
    if proc.returncode or tuple(row[0] for row in rows) != CASES[case]:
        raise SystemExit(f"{cmd[:7]} {case} failed:\n{proc.stdout}{proc.stderr}")
    return rows


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("base_vm", type=Path)
    p.add_argument("base_image", type=Path)
    p.add_argument("branch_vm", type=Path)
    p.add_argument("branch_image", type=Path)
    p.add_argument("--jit", nargs="+", choices=("none", "baseline", "opt"), default=["none", "opt"])
    p.add_argument("--cases", nargs="+", choices=CASES, default=list(CASES))
    p.add_argument("--runs", type=positive, default=9)
    p.add_argument("--iterations", type=positive, default=200_000)
    p.add_argument("--warmup", type=positive, default=20_000)
    args = p.parse_args()
    artifacts = {
        "base": (args.base_vm.resolve(strict=True), args.base_image.resolve(strict=True)),
        "branch": (args.branch_vm.resolve(strict=True), args.branch_image.resolve(strict=True)),
    }
    if artifacts["base"] == artifacts["branch"]:
        p.error("provide independent base and branch VM/image pairs")
    source = Path(__file__).with_suffix(".st").read_text()
    env = os.environ.copy()
    for key in ("DISPLAY", "WAYLAND_DISPLAY", "SAMALTAK_NATIVE_GRANTS"):
        env.pop(key, None)
    # Fail closed even if a future change accidentally initializes SDL video.
    env["SDL_VIDEO_DRIVER"] = env["SDL_VIDEODRIVER"] = "ffibench_no_video"
    out = csv.writer(sys.stdout, lineterminator="\n")
    out.writerow(("jit", "case", "tree", "run", "phase", "calls", "us", "bytes"))
    values = {}
    with tempfile.TemporaryDirectory(prefix="descriptor-ffi-") as tmp:
        dynamic_env = env.copy()
        if "dynamic" in args.cases:
            lib = Path(tmp) / "bench.so"
            subprocess.run(
                [*shlex.split(os.environ.get("CC", "cc")), "-O2", "-fPIC", "-shared", "-x", "c", "-o", lib, "-"],
                input="#include <stdint.h>\nint32_t bench_add(int32_t a, int32_t b) {return a + b;}\n",
                text=True, check=True,
            )
            dynamic_env["SAMALTAK_NATIVE_GRANTS"] = f"ffibench|bench_add|i32(i32,i32)|{lib}"
        for jit in args.jit:
            for r in range(args.runs):
                for case in args.cases:
                    trees = ["branch"] if case == "dynamic" else ["base", "branch"]
                    if r % 2:
                        trees.reverse()
                    for tree in trees:
                        for phase, n, us, size in sample(
                            *artifacts[tree], jit, case, tree, source, dynamic_env if case == "dynamic" else env,
                            args.iterations, args.warmup,
                        ):
                            out.writerow((jit, case, tree, r + 1, phase, n, us, size))
                            values.setdefault((jit, case, phase, tree), []).append((us * 1000 / n, size / n))
                        sys.stdout.flush()
    for (jit, case, phase, tree), points in values.items():
        times, sizes = zip(*points)
        mem = f", {statistics.median(sizes):.1f} B/call" if sizes[0] >= 0 else ""
        print(f"{jit:8} {case:12} {phase:15} {tree:6} "
              f"{statistics.median(times):9.1f} ns/call [{min(times):.1f}, {max(times):.1f}]{mem}",
              file=sys.stderr)


if __name__ == "__main__":
    main()
