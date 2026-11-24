#!/usr/bin/env python3
"""Prove canonical FFI entry, or compare the same API on two matched VM/image pairs."""
import argparse
from collections import Counter
import csv
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import random
import re
import statistics
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
MODES = ("none", "baseline", "opt")
STATS = ("wall_us", "cpu_us", "allocated_bytes", "scavenges", "full_gcs",
         "gc_us", "baseline_compiles", "opt_compiles", "deopts")
TRACE = re.compile(rb"^ffi-native-entry (\d+)$", re.MULTILINE)
FILE_SIZES = (1, 4096, 1048576)


def cases(display=False):
    if display:
        yield "window-size", 402, "window", "windowSize"
        yield "window-pixel-size", 403, "window", "windowPixelSize"
        yield "window-title", 405, "window", "windowTitle"
        yield "window-set-size", 421, "window", "windowSetSize"
        yield "gpu-pass", (444, 445), "gpu", "gpuPass"
        return
    for operation, key in (("position", 505), ("size", 504)):
        for size in FILE_SIZES:
            label = f"file-{operation}-{size}"
            yield label, key, "files", (
                f"file: 'payload-{size}' operation: #{operation} label: '{label}' "
                f"size: {size} position: {size // 2}")
    for operation, key in (("read", 502), ("write", 503)):
        for width in (64, 4096):
            label = f"file-{operation}-{width}"
            yield label, key, "file-io", f"fileIO: #{operation} width: {width} label: '{label}'"
    for variant, method in (("mixed", "Mixed"), ("sign", "Sign"), ("256b", "256b"), ("8192b", "8192b")):
        yield f"bigint-27-{variant}", 27, "bigint", f"bigInteger{method}"
    for variant, method in (("cancel", "SmallResult"), ("mixed", "Mixed"), ("256b", "256b"), ("8192b", "8192b")):
        yield f"bigint-20-{variant}", 20, "bigint-owned", f"bigIntegerAdd{method}"
    yield "socket-local-port", 547, "socket", "socketLocalPort"
    yield "socket-accept-pending", 542, "socket", "socketAcceptPending"
    for size in (64, 4096):
        label = f"socket-send-{size}"
        yield label, 544, "socket", f"socketSendSize: {size} label: '{label}'"
    yield "pty-read-pending", 561, "socket", "ptyReadPending"
    yield "float-fraction", 52, "scalars", "fractionPart"
    yield "core-utc-us", 152, "core", "coreUtcMicroseconds"
    yield "core-thread-cpu-us", 153, "core", "coreThreadCpuMicroseconds"
    yield "core-float-print-string", 61, "core", "coreFloatPrintString"
    yield "core-getenv", 1172, "core", "coreGetenv"
    for stream, key in (("stdout", 1169), ("stderr", 1170)):
        for size in (8, 256, 4096):
            label = f"{stream}-{size}"
            yield label, key, "scalars", f"stream: #{stream} size: {size} label: '{label}'"


def median_interval(values, alpha):
    """Conservative, distribution-free two-sided sign/order-statistic CI."""
    ordered = sorted(values)
    n = len(ordered)
    cumulative = 0
    lower, upper = 0.0, math.inf  # ratios: no finite bound at this n
    for rank in range(n // 2):
        cumulative += math.comb(n, rank)
        if 2 * cumulative > alpha * (2 ** n):
            break
        lower, upper = ordered[rank], ordered[n - rank - 1]
    return lower, upper


def digest(path):
    with path.open("rb") as file:
        return hashlib.sha256(file.read()).hexdigest()


def stream_fixture(label):
    stream, _, count = label.partition("-")
    if stream in ("stdout", "stderr"):
        return stream, (("é" * (int(count) - 1) + "\n").encode())
    return None, None


def run(args, work, case, mode, arm, session=None, pair=None):
    proof = session is None
    vm, image = (args.vm, args.image) if arm else (args.old_vm, args.old_image)
    label, key, suite, selector = case
    n = args.proof_calls if proof else args.calls
    warmup = args.warmup
    stream, payload = stream_fixture(label)
    if not proof and payload:
        # Keep each stream arm's regular-file sink bounded without skipping marshalling.
        limit = (2 * 1024 * 1024) // len(payload)
        n, warmup = min(n, limit), min(warmup, limit)
    suffix = f"proof-{arm}" if proof else f"run-{session:02}-{pair:02}-{arm}"
    log = args.logs / f"{label}-{mode}-{suffix}"
    env = {k: v for k, v in os.environ.items() if k not in {
        "SAMALTAK_NATIVE_GRANTS", "SAMALTAK_VERIFY_GC",
        "SAMALTAK_OPT_TRACE", "SAMALTAK_FFI_SITE_TRACE",
        "SAMALTAK_FFI_BOX_FULL_GC", "SAMALTAK_FFI_NATIVE_TRACE"}}
    env.update(LC_ALL="C", SAMALTAK_PARITY_VALUE="parity value")
    if not args.display_ci:
        for variable in ("DISPLAY", "WAYLAND_DISPLAY", "XAUTHORITY"):
            env.pop(variable, None)
        env.update(SDL_VIDEO_DRIVER="ffi_no_video", SDL_VIDEODRIVER="ffi_no_video")
    if proof:
        env["SAMALTAK_FFI_NATIVE_TRACE"] = "1"
    pair_or_nil = "nil" if proof else str(pair)
    expr = (f"[FFIPairedBench count: {n} warmup: {warmup} pair: {pair_or_nil} arm: {arm}. "
            f"FFIPairedBench {selector}. Smalltalk vm stdoutWrite: "
            "((String with: Character lf), 'ffi-paired-ok', (String with: Character lf))] "
            "on: Error do: [:e | Smalltalk vm stderrWrite: e messageText, "
            "(String with: Character lf). Smalltalk quit: 1]")
    command = [vm, "--jit", mode, "--jit-threshold", "0", "--eden", str(args.eden)]
    if mode == "opt":
        command += ["--jit-opt", "256"]
    command += [image, "--headless", "--load", HERE / "ffi-paired.st",
                "--load", HERE / f"ffi-paired-{suite}.st", "--eval", expr]
    paths = {channel: work / "stream-capture" if stream == channel else log.with_suffix("." + channel)
             for channel in ("stdout", "stderr")}
    with paths["stdout"].open("wb") as out, paths["stderr"].open("wb") as err:
        result = subprocess.run(command, cwd=work, env=env, stdout=out, stderr=err, timeout=180)
    if stream:
        count = 0
        with paths[stream].open("rb") as out, log.with_suffix("." + stream).open("wb") as log_file:
            for line in out:
                if line == payload:
                    count += 1
                else:
                    log_file.write(line)
            log_file.write(f"ffi-stream-capture {count} lines x {len(payload)} bytes\n".encode())
        expected = n if proof else warmup + n
        if count != expected:
            raise RuntimeError(f"{log}: captured {count} matching stream writes, expected {expected}")
    stdout = log.with_suffix(".stdout").read_bytes()
    stderr = log.with_suffix(".stderr").read_bytes()
    if result.returncode or stdout.splitlines().count(b"ffi-paired-ok") != 1:
        raise RuntimeError(f"{log}: workload failed ({result.returncode}): {stderr[-800:]!r}")
    if proof:
        # Setup, cleanup and the evaluator can also use migrated calls. Count
        # only the timed operation(s) between the two stderr delimiters.
        marked = re.search(rb"^ffi-pair-begin\n(.*?)^ffi-pair-end$", stderr, re.M | re.S)
        if not marked:
            raise RuntimeError(f"{log}: missing trace delimiters")
        trace = Counter(map(int, TRACE.findall(marked[1])))
        keys = key if isinstance(key, tuple) else (key,)
        typed = arm == 1 or args.old_route == "typed"
        want = {1024 + item: n if typed else 0 for item in keys}
        if typed and stream == "stderr":
            want[2194] += 1  # the end delimiter is itself a canonical stderr write
        actual = {item: trace[item] for item in want}
        if actual != want:
            raise RuntimeError(f"{log}: native entry counts {actual}, expected {want}")
        return None
    trace = TRACE.findall(stderr)
    if trace:
        raise RuntimeError(f"{log}: tracing contaminated timing")
    rows = []
    for line in stdout.splitlines():
        if not line.startswith(b"ffi-pair "):
            continue
        _, name, *fields = line.decode("ascii").split()
        pair, measure_arm, count, *stats = map(int, fields)
        if name != label or count != n or len(stats) != len(STATS) or min(stats) < 0:
            raise RuntimeError(f"{log}: invalid row {line!r}")
        if min(stats[:2]) <= 0:
            raise RuntimeError(f"{log}: timer resolution; increase --calls")
        rows.append((pair, measure_arm, count, *stats))
    if [row[:2] for row in rows] != [(pair, arm)]:
        raise RuntimeError(f"{log}: expected one matching timing row")
    return rows[0]


def summarize(samples, selected):
    comparisons = len(selected) * len(MODES)
    alpha = 0.05 / comparisons
    for case, *_ in selected:
        for mode in MODES:
            pairs = samples[(case, mode)]
            per_session = {}
            by_order = {0: [], 1: []}
            for session, first, a, b in pairs:
                r = b[1] / a[1]
                # Each elapsed microsecond reading is the difference of two
                # quantized timestamps. Bound the ratio rather than counting
                # indistinguishable equal ticks as proof of no slowdown.
                lower = (b[1] - 1) / (a[1] + 1)
                upper = (b[1] + 1) / (a[1] - 1) if a[1] > 1 else math.inf
                per_session.setdefault(session, []).append((r, lower, upper))
                by_order[first].append(r)
            mids, lows, highs = (
                [statistics.median(rs[i] for rs in triples) for triples in per_session.values()]
                for i in range(3)
            )
            lo, _ = median_interval(lows, alpha)
            _, hi = median_interval(highs, alpha)
            status = ("at-par" if hi <= 1.0 else "slower" if lo > 1.0 else "inconclusive")
            print(f"{case:23} {mode:8} wall new/old={statistics.median(mids):.4f} "
                  f"simultaneous 95% [{lo:.4f}, {hi:.4f}] {status}; "
                  f"AB/BA medians={statistics.median(by_order[0]):.4f}/{statistics.median(by_order[1]):.4f}; "
                  f"CPU new/old={statistics.median(b[2]/a[2] for _, _, a, b in pairs):.4f}; "
                  f"old/new B/call={statistics.median(a[3]/a[0] for _, _, a, _ in pairs):.2f}/"
                  f"{statistics.median(b[3]/b[0] for _, _, _, b in pairs):.2f}; "
                  f"old/new GC us/arm={statistics.median(a[6] for _, _, a, _ in pairs):.0f}/"
                  f"{statistics.median(b[6] for _, _, _, b in pairs):.0f}")
            yield status


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    for option in ("vm", "image", "logs"):
        ap.add_argument(f"--{option}", type=Path, required=True)
    ap.add_argument("--old-vm", type=Path, help="previous revision's executable")
    ap.add_argument("--old-image", type=Path, help="image built by that previous executable/revision")
    ap.add_argument("--old-route", choices=("dedicated", "typed"), default="dedicated",
                    help="expected entry route in the previous pair (default: dedicated)")
    ap.add_argument("--case", choices=[case[0] for case in (*cases(), *cases(display=True))], action="append")
    ap.add_argument("--display-ci", action="store_true", help="display suites, GitHub Actions X11 only")
    ap.add_argument("--sessions", type=int, default=15, help="independent blocks of AB/BA pairs per case/mode")
    ap.add_argument("--pairs", type=int, default=6, help="even count, half each AB/BA order")
    ap.add_argument("--calls", type=int, default=12000)
    ap.add_argument("--warmup", type=int, default=12000)
    ap.add_argument("--proof-calls", type=int, default=1024)
    ap.add_argument("--eden", type=int, default=16, help="MB in VM eden")
    ap.add_argument("--seed", type=int, default=9808)
    ap.add_argument("--cpu", type=int, help="pin to an isolated CPU (Linux)")
    phase = ap.add_mutually_exclusive_group()
    phase.add_argument("--proof-only", action="store_true")
    phase.add_argument("--require-at-par", action="store_true", help="fail on slower or inconclusive")
    args = ap.parse_args()
    if (min(args.sessions, args.calls, args.warmup, args.proof_calls, args.eden) <= 0
            or args.pairs < 2 or args.pairs % 2):
        ap.error("positive sample counts/eden and an even number of pairs are required")
    args.vm, args.image = (p.resolve(strict=True) for p in (args.vm, args.image))
    if bool(args.old_vm) != bool(args.old_image) or (not args.proof_only and not args.old_vm):
        ap.error("timing requires a matched previous --old-vm/--old-image pair")
    if args.old_vm:
        args.old_vm, args.old_image = (p.resolve(strict=True) for p in (args.old_vm, args.old_image))
        if args.old_vm.samefile(args.vm) or args.old_image.samefile(args.image):
            ap.error("build separate executable and image artifacts for each revision")
    args.logs = args.logs.resolve()
    args.logs.mkdir(parents=True, exist_ok=True)
    if any(args.logs.iterdir()):
        ap.error("--logs must be empty; refusing to overwrite evidence")
    if args.cpu is not None:
        if not hasattr(os, "sched_getaffinity") or args.cpu not in os.sched_getaffinity(0):
            ap.error("CPU unavailable")
        os.sched_setaffinity(0, {args.cpu})

    if args.display_ci and (os.getenv("GITHUB_ACTIONS") != "true" or not os.getenv("DISPLAY")
                            or os.getenv("SDL_VIDEODRIVER") != "x11"):
        ap.error("--display-ci requires the GitHub Actions X11 display job")
    available = list(cases(display=args.display_ci))
    if args.case and not set(args.case).issubset({case[0] for case in available}):
        ap.error("--case does not belong to the selected headless/display suite")
    selected = [case for case in available if not args.case or case[0] in args.case]
    files = [args.vm, args.image, Path(__file__), HERE / "ffi-paired.st"]
    if args.old_vm:
        files += [args.old_vm, args.old_image]
    files += [HERE / f"ffi-paired-{suite}.st" for suite in sorted({c[2] for c in selected})]
    (args.logs / "plan.json").write_text(json.dumps({
        **{k: str(v) if isinstance(v, Path) else v for k, v in vars(args).items()},
        "host": platform.uname()._asdict(), "modes": MODES,
        "sha256": {str(p): digest(p) for p in files}, "cases": selected,
    }, indent=2) + "\n")

    samples = {}
    strata = [(case, mode) for case in selected for mode in MODES]
    rng = random.Random(args.seed)
    with tempfile.TemporaryDirectory(prefix="ffi-paired-") as tmp:
        work = Path(tmp)
        for size in FILE_SIZES:
            (work / f"payload-{size}").write_bytes(bytes(size))
        for case, mode in strata:
            if args.old_vm:
                run(args, work, case, mode, 0)
            run(args, work, case, mode, 1)
        print(f"Native entry checks passed: {len(strata)} cases/modes, exact canonical counts.")
        if args.proof_only:
            return 0
        with (args.logs / "pairs.csv").open("w", newline="") as f:
            csv_out = csv.writer(f)
            csv_out.writerow(("case", "mode", "session", "pair", "first_arm", "arm", "calls", *STATS))
            for rep in range(1, args.sessions + 1):
                rng.shuffle(strata)
                for case, mode in strata:
                    schedule = [0, 1] * (args.pairs // 2)
                    rng.shuffle(schedule)
                    for pair, first in enumerate(schedule, 1):
                        rows = [run(args, work, case, mode, arm, rep, pair)
                                for arm in (first, 1 - first)]
                        a, b = (row[2:] for row in sorted(rows))
                        samples.setdefault((case[0], mode), []).append((rep, first, a, b))
                        for _, arm, count, *stats in rows:
                            csv_out.writerow((case[0], mode, rep, pair, first, arm, count, *stats))
    with (args.logs / "ratios.csv").open("w", newline="") as f:
        out = csv.writer(f)
        out.writerow(("case", "mode", "session", "pair", "first_arm", "wall_new/old",
                      "cpu_new/old"))
        for (label, mode), pairs in sorted(samples.items()):
            for index, (session, first, a, b) in enumerate(pairs):
                out.writerow((label, mode, session, index % args.pairs + 1, first,
                              b[1] / a[1], b[2] / a[2]))
    statuses = list(summarize(samples, selected))
    return 1 if args.require_at_par and any(status != "at-par" for status in statuses) else 0


if __name__ == "__main__":
    raise SystemExit(main())
