#!/usr/bin/env python3
"""Attribute legacy PTY facade overhead in one headless VM per JIT mode (Linux)."""
import argparse
import csv
import hashlib
import os
from pathlib import Path
import re
import statistics
import subprocess
import sys

HISTORY = "3ceae5316bd3cc180b594e989a0752c85df4782c"  # d124cd9^
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
BINDING_FILE = HERE / "pty-facade-binding.st"
VARIANTS = ("control", "direct", "prebound_reused", "prebound_fresh",
            "lookup", "on_do", "original", "forced_fallback")
OPS = ("foreground", "resize")


def method(source, header):
    pattern = rf"^{re.escape(header)}\n.*?(?=^!)"
    return re.search(pattern, source, re.MULTILINE | re.DOTALL).group().rstrip()


def st_string(s):
    return "'" + s.replace("'", "''") + "'"


def compile_st(source, cls):
    return f"Compiler compile: {st_string(source)} in: {cls} class"


def build_benchmark(candidate_file, candidate_selectors):
    source = HERE.joinpath("pty-facade-reference.st").read_text()
    call = method(source, "call: descriptor with: arguments ifUnavailable: fallback")
    lookup = method(source, "bindingFor: descriptor")
    setup = [
        compile_st(call, "PTYBenchBinding"),
        compile_st(lookup.replace("FFI bind:", "self bind:"), "PTYBenchBinding"),
        compile_st("benchLookup: descriptor with: arguments ifUnavailable: fallback\n"
                   "\t^(self bindingFor: descriptor) invoke: arguments", "PTYBenchBinding"),
        compile_st("benchInvoke: binding with: arguments ifUnavailable: fallback\n"
                   "\t^binding invoke: arguments", "PTYBenchBinding"),
    ]
    declarations, prepare, checks, selections = [], [], [], []
    for op, title, more, args, primitive, control in (
        ("foreground", "Foreground", "", "{aHandle}", "ptyForeground", "aHandle"),
        ("resize", "Resize", " rows: rows columns: columns", "{aHandle. rows. columns}", "ptyResize", "self"),
    ):
        orig_header = f"prim{title}: aHandle{more}"
        legacy_header = f"legacy{title}: aHandle{more}"
        orig = method(source, orig_header).replace("PlatformFFI", "PTYBenchBinding")
        selector_suffix = ":" if op == "foreground" else ":rows:columns:"
        direct_selector = "legacy" + title + selector_suffix
        call_args = "h rows: 24 columns: 80" if more else "h"
        setup.append(f"((PseudoTerminal class includesSelector: #{direct_selector}) "
                     f"and: [(PseudoTerminal class compiledMethodAt: #{direct_selector}) "
                     f"primitiveName = '{primitive}']) "
                     f"ifFalse: [self error: 'expected #{direct_selector} to be the {primitive} primitive']")
        descriptor = re.search(r"#\(call 'platform' .*?\) i32\)", orig).group()
        fallback = re.search(r"ifUnavailable: (\[.*?\])", orig).group(1)
        # Also used by the preflight; this is deliberately a native argument rejection.
        bad_args = args.replace("aHandle", "#invalidPtyHandle")
        binding_name = f"PTYBench{title}Binding"
        args_name = f"PTYBench{title}Arguments"
        declarations.extend([f"Smalltalk at: #{name} put: nil" for name in (binding_name, args_name)])
        prepare.extend([
            f"Smalltalk at: #{binding_name} put: (PTYBenchBinding bind: {descriptor})",
            f"Smalltalk at: #{args_name} put: {args.replace('aHandle', 'h').replace('rows', '24').replace('columns', '80')}",
        ])
        variants = (
            ("benchControl", orig.split("\n")[0] + f"\n\t^{control}"),
            ("legacy", None),
            ("benchPreboundReused", orig.replace("call: " + descriptor, "benchInvoke: " + binding_name)
             .replace(args, args_name).replace(fallback, "nil")),
            ("benchPreboundFresh", orig.replace("call: " + descriptor, "benchInvoke: " + binding_name)
             .replace(fallback, "nil")),
            ("benchLookup", orig.replace("call: " + descriptor, "benchLookup: " + descriptor)
             .replace(fallback, "nil")),
            ("benchOnDo", orig.replace(fallback, "nil")),
            ("benchOriginal", orig),
            ("benchForcedFallback", orig.replace(args, bad_args)),
        )
        selectors = []
        for prefix, body in variants:
            selectors.append(prefix + title + selector_suffix)
            if body is not None:
                variant = body.replace(orig_header, f"{prefix}{title}: aHandle{more}", 1)
                setup.append(compile_st(variant, "PseudoTerminal"))
                if descriptor in variant:
                    # Different methods may hold different descriptor literal identities.
                    # Prewarm every key, never a cache miss during a timed batch.
                    prepare.append(f"PTYBenchBinding bindingFor: ((PseudoTerminal class "
                                   f"compiledMethodAt: #{selectors[-1]}) literals detect: "
                                   "[:lit | lit class == Array and: [lit notEmpty and: [lit first == #call]]])")
        successful_calls = [f"PseudoTerminal benchOriginal{title}: {call_args}"]
        if candidate_selectors:
            candidate = candidate_selectors[len(selections)]
            selectors.append(candidate)
            successful_calls.append(f"PseudoTerminal {candidate.split(':')[0]}: {call_args}")
        selections.append(selectors)
        trap = compile_st(f"{legacy_header}\n self error: 'unexpected {op} fallback'", "PseudoTerminal")
        checks.extend([
            f"[| direct | direct := PseudoTerminal class compiledMethodAt: #{direct_selector}. "
            f"[{trap}. {'. '.join(successful_calls)}] ensure: ["
            f"PseudoTerminal class addSelector: #{direct_selector} withMethod: direct]] value",
            f"(PTYBenchBinding call: {descriptor} with: {bad_args.replace('rows', '24').replace('columns', '80')} "
            f"ifUnavailable: [#rejected]) == #rejected ifFalse: [self error: 'expected FFI {op} rejection']",
        ])
    if candidate_file is not None:
        setup.append(f"Compiler fileIn: {st_string(str(candidate_file))}")
    if candidate_selectors:
        for candidate in candidate_selectors:
            setup.append(f"(PseudoTerminal class includesSelector: #{candidate}) "
                         f"ifFalse: [self error: 'missing candidate selector {candidate}']")
    # Turn resize's keyword selector into the leading keyword for the timed call's source.
    selectors = "#(" + " ".join("(" + " ".join(st_string(s.split(":")[0] + ":") for s in pair) + ")"
                                for pair in zip(*selections)) + ")"
    return ".\n".join(declarations + setup), selectors, ".\n".join(prepare), ".\n".join(checks)


def orders(size, rounds, varying=False):
    if varying:
        return [[(i, 2) for i in ((2, size) if r % 2 == 0 else (size, 2))]
                for r in range(5 + rounds)]
    # Williams design: each position and each ordered pair balanced per cycle.
    seq = [0] + [j if i % 2 == 0 else size - j
                 for i, j in enumerate((i + 1) // 2 for i in range(1, size))]
    cycle = [[(v + shift) % size for v in seq] for shift in range(size)]
    if size % 2:
        cycle += [row[::-1] for row in cycle]
    result = []
    for r in range(5 + rounds):
        row = cycle[(r - 5) % len(cycle)]
        result.append([(i + 1, 1 + (r + j + k) % 2) for j, i in enumerate(row) for k in range(2)])
    return result


def summarize(values, names, jit, rounds, varying):
    for op in (("resize",) if varying else OPS):
        direct = [values[(op, "direct", r)][0] for r in range(1, rounds + 1)]
        for variant in (("direct", "candidate") if varying else names):
            ts, bs = zip(*(values[(op, variant, r)] for r in range(1, rounds + 1)))
            ratios = [t / d for t, d in zip(ts, direct)]
            print(f"{jit:8} {op:10} {variant:16} {statistics.median(ts):8.1f} ns/call "
                  f"[{min(ts):.1f}, {max(ts):.1f}], {statistics.median(bs):6.2f} B/call; "
                  f"paired/direct {statistics.median(ratios):.3f}x "
                  f"[{min(ratios):.3f}, {max(ratios):.3f}]", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vm", type=Path, default=ROOT / "vm/build/samaltak")
    parser.add_argument("--image", type=Path, default=ROOT / "build/samaltak.image")
    parser.add_argument("--cpu", type=int, default=0, help="logical CPU (default: 0)")
    parser.add_argument("--jit", nargs="+", choices=("none", "baseline", "opt"), default=["none", "opt"])
    parser.add_argument("--rounds", type=int, help="steady rounds per mode (default: 16 or 18 with candidate)")
    parser.add_argument("--iterations", type=int, default=100_000, help="calls per batch")
    parser.add_argument("--warmup", type=int, default=40_000, help="warmup calls per variant/op (multiple of 4)")
    candidates = parser.add_mutually_exclusive_group()
    candidates.add_argument("--candidate", choices=("fresh", "memo"), help="use a bundled candidate")
    candidates.add_argument("--candidate-file", type=Path, help="load custom methods in memory")
    parser.add_argument("--candidate-selectors", nargs=2, metavar=("FOREGROUND", "RESIZE"),
                        help="class-side selectors on PseudoTerminal (default: benchCandidateForeground: "
                             "benchCandidateResize:rows:columns: with --candidate-file)")
    parser.add_argument("--vary-resize", action="store_true",
                        help="compare direct and candidate on alternating 24x80/25x81 on one PTY")
    args = parser.parse_args()
    selectors = args.candidate_selectors
    if args.candidate:
        args.candidate_file = HERE / "pty-facade-candidate.st"
        prefix = "bench" + args.candidate.capitalize()
        selectors = selectors or (prefix + "Foreground:", prefix + "Resize:rows:columns:")
    elif args.candidate_file:
        args.candidate_file = args.candidate_file.resolve(strict=True)
        selectors = selectors or ("benchCandidateForeground:", "benchCandidateResize:rows:columns:")
    if selectors and not (re.fullmatch(r"\w+:", selectors[0]) and
                          re.fullmatch(r"\w+:rows:columns:", selectors[1])):
        parser.error("expected selectors with : and :rows:columns: keywords")
    if args.vary_resize and (not selectors or args.iterations % 2 or args.warmup % 8):
        parser.error("vary-resize requires a candidate, even iterations and warmup divisible by 8")
    names = VARIANTS + (("candidate",) if selectors else ())
    rounds = args.rounds if args.rounds is not None else (18 if selectors else 16)
    if rounds < 1 or args.iterations < 1 or args.warmup < 4 or args.warmup % 4:
        parser.error("rounds and iterations must be positive; warmup must be a positive multiple of 4")
    allowed = os.sched_getaffinity(0)
    if args.cpu not in allowed:
        parser.error(f"CPU {args.cpu} is unavailable; choose --cpu from {sorted(allowed)} and coordinate its use")
    os.sched_setaffinity(0, {args.cpu})
    vm = args.vm.resolve(strict=True)
    image = args.image.resolve(strict=True)
    if not os.access(vm, os.X_OK) or not vm.is_file() or not image.is_file():
        parser.error("provide an executable platform VM and its image")
    print(f"CPU={args.cpu} historical={HISTORY} "
          f"iterations={args.iterations} warmup={args.warmup} rounds={rounds} vary_resize={args.vary_resize}", file=sys.stderr)
    for f in (vm, image, args.candidate_file):
        if f is not None:
            print(f"{hashlib.sha256(f.read_bytes()).hexdigest()}  {f}", file=sys.stderr)
    setup, sels, prepare, checks = build_benchmark(args.candidate_file, selectors)
    schedule = orders(len(names), rounds, args.vary_resize)
    schedule_st = "#(" + " ".join("(" + " ".join(f"({i} {op})" for i, op in row) + ")"
                                  for row in schedule) + ")"
    body = HERE.joinpath("pty-facade.st").read_text()
    expr = (f"[{setup}.\n({body}) valueWithArguments: "
            f"{{{args.iterations}. {args.warmup}. {schedule_st}. {sels}. [:h | {prepare}]. [:h | {checks}]. {str(args.vary_resize).lower()}}}] "
            "on: Error do: [:e | Smalltalk vm stderrWrite: e messageText, (String with: Character lf). "
            "Smalltalk quit: 1]")
    env = {k: v for k, v in os.environ.items()
           if k not in ("DISPLAY", "WAYLAND_DISPLAY", "SAMALTAK_NATIVE_GRANTS")}
    env["SDL_VIDEO_DRIVER"] = env["SDL_VIDEODRIVER"] = "ffibench_no_video"
    csv_out = csv.writer(sys.stdout, lineterminator="\n")
    csv_out.writerow(("jit", "phase", "round", "slot", "op", "variant", "calls", "us", "bytes"))
    for jit in args.jit:
        proc = subprocess.run([vm, "--jit", jit, "--eden", "16", image, "--headless",
                               "--load", BINDING_FILE, "--eval", expr],
                              text=True, capture_output=True, env=env, timeout=600)
        data = [line.split(",")[1:] for line in proc.stdout.splitlines() if line.startswith("pty-facade,")]
        if (proc.returncode or "pty-facade-ok" not in proc.stdout or
                len(data) != sum(map(len, schedule))):
            sys.exit(f"{jit} failed ({proc.returncode}, {len(data)} rows):\n{proc.stderr}\n{proc.stdout[-2000:]}")
        values = {}
        plan = [(r, slot, i, op) for r, order in enumerate(schedule, 1)
                for slot, (i, op) in enumerate(order, 1)]
        for (phase, *nums), expected in zip(data, plan):
            r, slot, i, op, count, us, size = map(int, nums)
            expected_phase = "warmup" if r <= 4 else ("discard" if r == 5 else "steady")
            if (r, slot, i, op) != expected or phase != expected_phase:
                sys.exit(f"{jit}: malformed data: {phase}, {nums}")
            name, op = names[i - 1], OPS[op - 1]
            trial = r - 5 if phase == "steady" else (r if phase == "warmup" else 1)
            csv_out.writerow((jit, phase, trial, slot, op, name, count, us, size))
            if phase == "steady":
                values[(op, name, trial)] = (us * 1000 / count, size / count)
        sys.stdout.flush()
        summarize(values, names, jit, rounds, args.vary_resize)


if __name__ == "__main__":
    main()
