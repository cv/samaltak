#!/usr/bin/env python3
"""Display-free process semantics and exact typed-entry counts for all JIT tiers."""

import argparse
from collections import Counter
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

from ffi_cutover import TIERS, TRACE, command_for


ENTRIES = (1539, 1540, 1542, 1584)  # spawn, wait, exec, PTY spawn
MAIN_COUNTS = (5, 8, 0, 5)
EXEC_COUNTS = (0, 0, 3, 0)
ARG_TAIL = (b"two words", b"", b'$(";*|&<>\\)', b"\xff\xc3\xa9")
PARENT = b"process-parent"
EXEC_INPUT = b"exec-input $*\n"


def st_string(text):
    return "'" + text.replace("'", "''") + "'"


def st_bytes(data):
    return "#[" + " ".join(str(byte) for byte in data) + "]"


def report(mode, pid, cwd):
    return [
        f"{mode}-pid={pid}".encode("ascii"),
        b"cwd=" + os.fsencode(cwd).hex().encode("ascii"),
        b"parent=" + PARENT.hex().encode("ascii"),
        *(b"arg=" + arg.hex().encode("ascii")
          for arg in (b"process fixture", mode.encode("ascii"), *ARG_TAIL)),
    ]


def run(vm, image, tier, selector, *, label, work, env, logs, source, fd=None):
    expression = (
        f"[Compiler evaluate: {st_string(selector)}] on: Error do: [:e | "
        "Smalltalk vm stderrWrite: e messageText, (String with: Character lf). "
        "Smalltalk quit: 1]"
    )
    command = command_for(vm, image, tier, expression)[:-2]
    command += ["--load", source, "--eval", expression]
    # No shell, inherited terminal, or arbitrary environment; all candidate
    # programs live in this run's private PATH. Exec replaces only this child.
    with subprocess.Popen(command, cwd=work, env=env, start_new_session=True,
                          stdin=subprocess.PIPE if fd is not None else subprocess.DEVNULL,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          pass_fds=() if fd is None else (fd,)) as child:
        timed_out = False
        try:
            stdout, stderr = child.communicate(EXEC_INPUT if fd is not None else None, timeout=45)
        except subprocess.TimeoutExpired:
            child.kill()
            stdout, stderr = child.communicate()
            timed_out = True
    stem = logs / f"{label}-{tier}"
    stem.with_suffix(".stdout").write_bytes(stdout)
    stem.with_suffix(".stderr").write_bytes(stderr)
    location = f"{tier}/{label}: see {stem}.stdout and {stem}.stderr"
    if timed_out:
        raise RuntimeError(f"VM timed out ({location})")
    return child.pid, child.returncode, stdout.splitlines(), stderr, location


def check_counts(stderr, counts, location):
    trace = Counter(map(int, TRACE.findall(stderr)))
    got = tuple(trace[entry] for entry in ENTRIES)
    if got != counts:
        raise RuntimeError(f"native entry counts for {ENTRIES}: expected {counts}, got {got} ({location})")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("vm", type=Path)
    parser.add_argument("--mode", choices=TIERS, action="append")
    parser.add_argument("--logs", required=True, type=Path)
    args = parser.parse_args()
    vm, image = args.vm.resolve(strict=True), args.image.resolve(strict=True)
    args.logs.mkdir(parents=True, exist_ok=True)
    source = Path(__file__).with_name("process_ffi.st").resolve(strict=True)
    c_source = source.with_name("process_ffi_fixture.c")

    with tempfile.TemporaryDirectory(prefix="samaltak-process-ffi-") as temp:
        root = Path(temp).resolve()
        bin_dir, pty_bin = root / "host bin", root / "pty bin"
        bin_dir.mkdir()
        pty_bin.mkdir()
        binary = bin_dir / "process fixture"
        subprocess.run([os.environ.get("CC", "cc"), "-std=c99", "-Wall", "-Wextra", "-Werror",
                        "-o", binary, c_source], check=True, timeout=30)
        shutil.copy2(binary, pty_bin / "terminal fixture")
        env = {
            "PATH": str(bin_dir),
            "HOME": str(root),
            "LC_ALL": "C",
            "TERM": "ignored-parent-term",
            "SDL_VIDEO_DRIVER": "ffi_no_video",
            "SDL_VIDEODRIVER": "ffi_no_video",
            "SAMALTAK_FFI_NATIVE_TRACE": "1",
            "SAMALTAK_VERIFY_GC": "1",
            "PROCESS_FFI_PARENT": PARENT.decode("ascii"),
        }
        for tier in args.mode or TIERS:
            work = root / tier
            work.mkdir()
            pty_cwd = work / "cwd café"
            pty_cwd.mkdir()
            selector = (
                "ProcessFFISmoke spawnAndWait; "
                f"terminal: {st_string(str(pty_bin))} directory: {st_bytes(os.fsencode(pty_cwd))} "
                f"cwdHex: '{os.fsencode(pty_cwd).hex()}' inheritedCwdHex: '{os.fsencode(work).hex()}'. "
                "#processFFIOK"
            )
            _, code, lines, stderr, location = run(
                vm, image, tier, selector, label="process", work=work, env=env,
                logs=args.logs, source=source,
            )
            hold_pids = [m[1] for line in lines if (m := re.fullmatch(rb"vm-hold-pid=([1-9][0-9]*)", line))]
            if code or len(hold_pids) != 1:
                raise RuntimeError(f"process fixture returned {code}, expected one child PID ({location})")
            pid = int(hold_pids[0])
            expected = [*report("hold", pid, work), f"vm-hold-pid={pid}".encode("ascii"), b"#processFFIOK"]
            if Counter(lines) != Counter(expected):
                raise RuntimeError(f"spawn argv/cwd/env/PID mismatch ({location})")
            check_counts(stderr, MAIN_COUNTS, location)

            # Pass a descriptor allocated by the runner, not a guessed number.
            # The successful fixture must keep stdin/stdout/stderr and PID, but
            # report EBADF for this otherwise inherited descriptor.
            with (work / "release").open("rb") as marker:
                fd = marker.fileno()
                pid, code, lines, stderr, location = run(
                    vm, image, tier, "ProcessFFISmoke execInIsolatedVM", label="exec", work=work,
                    env={**env, "PROCESS_FFI_FD": str(fd)}, logs=args.logs, source=source, fd=fd,
                )
            expected = [b"vm-exec-ready", *report("exec", pid, work),
                        b"input=" + EXEC_INPUT.hex().encode("ascii")]
            if code != 43 or lines != expected or b"exec-stderr" not in stderr.splitlines():
                raise RuntimeError(f"exec replacement returned {code}, expected same PID and stdio ({location})")
            check_counts(stderr, EXEC_COUNTS, location)
            print(f"{tier}: process semantics and exact typed-entry counts passed")


if __name__ == "__main__":
    main()
