#!/usr/bin/env python3
"""Core FFI semantic smoke, run on hosted and NO_PLATFORM images, without SDL."""
import argparse
import os
from pathlib import Path
import re
import subprocess


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("image", type=Path)
    ap.add_argument("vm", type=Path)
    ap.add_argument("--mode", choices=("none", "baseline", "opt"), action="append")
    ap.add_argument("--trace", action="store_true", help="assert per-export entry counts")
    ap.add_argument("--logs", type=Path)
    args = ap.parse_args()
    env = os.environb.copy()
    for key in (b"DISPLAY", b"WAYLAND_DISPLAY", b"SAMALTAK_NATIVE_GRANTS",
                b"SAMALTAK_FFI_NATIVE_TRACE", b"SAMALTAK_CORE_ABSENT"):
        env.pop(key, None)
    env.update({b"LC_ALL": b"C", b"SAMALTAK_CORE_PRESENT": b"text",
                b"SAMALTAK_CORE_EMPTY": b"",
                b"SAMALTAK_CORE_RAW_KEY_\xff": b"A\xed\xa0\x80\xc3\xa9"})
    if args.trace:
        env[b"SAMALTAK_FFI_NATIVE_TRACE"] = b"1"
    fixture = Path(__file__).with_name("core_ffi.st").read_text().replace("'", "''")
    expression = (
        f"[Compiler fileInString: '{fixture}'. Compiler evaluate: 'CoreFFISmoke run'] "
        "on: Error do: [:e | Smalltalk vm stderrWrite: e messageText, (String with: Character lf). "
        "Smalltalk quit: 1]"
    )
    text = b"O\x00\xc3\xa9\xff\xe2\x82\xac\xef\xbf\xbd"
    # 1024 + ID, count includes direct typed slice probes and excludes rejected calls.
    expected = {52: 11, 61: 24, 152: 1, 153: 1, 169: 2, 170: 2, 172: 4}
    for mode in args.mode or ("none", "baseline", "opt"):
        jit = ["--jit", mode]
        if mode != "none":
            jit += ["--jit-threshold", "0"]
        if mode == "opt":
            jit += ["--jit-flags", "eager"]
        command = [args.vm.resolve(strict=True), *jit, args.image.resolve(strict=True),
                   "--headless", "--eval", expression]
        result = subprocess.run(command, capture_output=True, env=env, timeout=60)
        if args.logs:
            args.logs.mkdir(parents=True, exist_ok=True)
            (args.logs / f"{mode}.stdout").write_bytes(result.stdout)
            (args.logs / f"{mode}.stderr").write_bytes(result.stderr)
        if (result.returncode or not result.stdout.endswith(text + b"true\n")
                or result.stdout.count(text) != 1
                or result.stderr.count(b"E\x00\xff") != 1
                or result.stderr.count(text) != 1):
            raise RuntimeError(f"{mode}: {result.returncode}, stdout={result.stdout!r}, stderr={result.stderr!r}")
        if args.trace:
            trace = [int(token) for token in re.findall(rb"ffi-native-entry (\d+)", result.stderr)]
            counts = {key: trace.count(key + 1024) for key in expected}
            if counts != expected:
                raise RuntimeError(f"{mode}: expected {expected}, got {counts}")
        print(f"core FFI smoke ({mode}): passed")


if __name__ == "__main__":
    main()
