#!/usr/bin/env python3
"""Cutover acceptance: live registry/stale headers, and per-tier typed-entry coverage."""

import argparse
from collections import Counter
import os
from pathlib import Path
import re
import subprocess
import sys


HERE = Path(__file__).resolve().parent
TIERS = ("none", "baseline", "opt")
TRACE = re.compile(rb"^ffi-native-entry ([0-9]+)\r?$", re.MULTILINE)
CORE = set(range(20, 32)) | {52, 61, 152, 153, 169, 170, 172}
HEADLESS = CORE | set(range(500, 517)) | set(range(540, 556)) | {
    412, 413, 415, 417, 418, 518, 560, 561, 562, 564, 565,
}


def read_slots():
    slots = {}
    for line in (HERE / "ffi_cutover_slots.tsv").read_text().splitlines():
        if line.startswith("#"):
            continue
        number, name, witnesses = line.split()
        number = int(number)
        if number in slots:
            raise ValueError(f"duplicate retired slot {number}")
        slots[number] = (name, tuple(map(int, witnesses.split(","))))
    if (len(slots) != 102 or len({name for name, _ in slots.values()}) != 102
            or len({entry for _, entries in slots.values() for entry in entries}) != 103):
        raise ValueError("expected 102 distinct retired slots and 103 typed lanes")
    return slots


def command_for(vm, image, tier, expression):
    jit = ["--jit", tier]
    if tier != "none":
        jit += ["--jit-threshold", "0"]
    if tier == "opt":
        jit += ["--jit-flags", "eager"]
    # VM options belong before IMAGE, even in the no-platform launcher.
    return [vm, *jit, image, "--headless", "--eval", expression]


def probe_expression(slots, tier, backend):
    source = (HERE / "ffi_cutover_registry.st").read_text().replace("'", "''")
    rows = " ".join(f"({n} '{name}')" for n, (name, _) in slots.items())
    platform = "true" if backend == "sdl" else "false"
    return (f"[Compiler fileInString: '{source}'. "
            f"(Smalltalk at: #FFICutoverProbe) new check: #({rows}) mode: #{tier} platform: {platform}] "
            "on: Error do: [:e | Smalltalk vm stderrWrite: e messageText, "
            "(String with: Character lf). Smalltalk quit: 1]")


def check(args, slots):
    env = {key: val for key, val in os.environ.items() if key not in {
        "DISPLAY", "WAYLAND_DISPLAY", "XAUTHORITY", "SAMALTAK_NATIVE_GRANTS",
        "SAMALTAK_FFI_TRIAL", "SAMALTAK_FFI_NATIVE_TRACE",
    }}
    env.update(LC_ALL="C", SDL_VIDEO_DRIVER="ffi_no_video",
               SDL_VIDEODRIVER="ffi_no_video", SAMALTAK_VERIFY_GC="1")
    vm, image = (p.resolve(strict=True) for p in (args.vm, args.image))
    args.logs.mkdir(parents=True, exist_ok=True)
    for tier in args.mode or TIERS:
        result = subprocess.run(command_for(vm, image, tier,
                                probe_expression(slots, tier, args.backend)),
                                env=env, capture_output=True, timeout=120)
        stem = args.logs / f"registry-{args.backend}-{tier}"
        stem.with_suffix(".stdout").write_bytes(result.stdout)
        stem.with_suffix(".stderr").write_bytes(result.stderr)
        if result.returncode or b"#ffiCutoverRegistryOK" not in result.stdout.splitlines():
            raise ValueError(f"{args.backend}/{tier}: registry probe failed "
                             f"(exit {result.returncode}); see {stem}.stdout and {stem}.stderr")
        print(f"{args.backend}/{tier}: {len(slots)} retired slots, names and stale headers checked")


def coverage(args, slots):
    expected = {
        "all": set(slots), "hosted-headless": HEADLESS,
        "display": set(slots) - HEADLESS, "no-platform": CORE,
    }[args.profile]
    identity = {(tier, p.resolve(strict=True)) for tier in TIERS for p in getattr(args, tier)}
    if len({p for _, p in identity}) != sum(len(getattr(args, tier)) for tier in TIERS):
        raise ValueError("do not reuse a witness log within or across tiers")
    complete = True
    for tier in TIERS:
        counts = Counter(int(m) for p in getattr(args, tier) for m in TRACE.findall(p.read_bytes()))
        missing = [(n, e) for n in sorted(expected) for e in slots[n][1] if not counts[e]]
        if missing:
            complete = False
            print(f"{args.profile}/{tier} missing slot:typed-entry "
                  + " ".join(f"{n}:{e}" for n, e in missing), file=sys.stderr)
        else:
            print(f"{args.profile}/{tier}: all {len(expected)} operations witnessed")
    if not complete:
        raise ValueError("incomplete typed coverage; fixture success and live registry are separate gates")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    probe = sub.add_parser("check", help="check live VM, compiler and numeric method dispatch")
    probe.add_argument("image", type=Path)
    probe.add_argument("vm", type=Path)
    probe.add_argument("--backend", choices=("sdl", "no-platform"), required=True)
    probe.add_argument("--logs", type=Path, required=True)
    probe.add_argument("--mode", choices=TIERS, action="append")
    proof = sub.add_parser("coverage", help="check raw stderr logs from successful semantic fixtures")
    proof.add_argument("--profile", choices=("all", "hosted-headless", "display", "no-platform"),
                       required=True)
    for tier in TIERS:
        proof.add_argument(f"--{tier}", type=Path, nargs="+", required=True)
    args = parser.parse_args()
    try:
        slots = read_slots()
        (check if args.action == "check" else coverage)(args, slots)
    except (ValueError, OSError, subprocess.TimeoutExpired) as exc:
        parser.exit(1, f"ffi_cutover: {exc}\n")


if __name__ == "__main__":
    main()
