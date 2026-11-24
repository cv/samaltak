#!/usr/bin/env python3
"""Test process exec probe protection without letting exec replace the driver."""
import argparse
import os
from pathlib import Path
import struct
import subprocess
import tempfile


def argv_record(*argv):
    parts = [os.fsencode(arg) for arg in argv]
    return struct.pack("<I", len(parts)) + b"".join(
        struct.pack("<I", len(part)) + part for part in parts
    )


def slice_expr(record):
    return "{#[" + " ".join(map(str, record)) + "]. 1. " + str(len(record)) + "}"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("vm", type=Path)
    parser.add_argument("--mode", choices=("none", "baseline", "opt"))
    args = parser.parse_args()
    env = os.environ.copy()
    for name in ("DISPLAY", "WAYLAND_DISPLAY", "SAMALTAK_NATIVE_GRANTS"):
        env.pop(name, None)
    env.update(SDL_VIDEODRIVER="ffi_probe_no_video", SDL_VIDEO_DRIVER="ffi_probe_no_video",
               SAMALTAK_FFI_NATIVE_TRACE="1")

    replacement = "ffi exec replacement reached"
    valid = slice_expr(argv_record("/bin/echo", replacement))
    # Prefix all cases with a freshly prepared, real executable target.
    setup = f"""
    | bind record fixed array must sqrt |
    must := [:test :message | test ifFalse: [Error signal: message]].
    bind := FFI bind: #(call platform platform_process_exec (bytesWithLength) i32).
    record := {valid}.
    fixed := (FFIBinding >> #tryInvoke1:) primitiveNumber.
    array := (FFIBinding >> #tryInvoke:) primitiveNumber.
    """
    probes = """
    must value: (bind prepare == true) value: 'real exec binding did not prepare'.
    must value: ((thisContext tryPrimitive: fixed receiver: bind args: {record}) == #primitiveFailed)
        value: 'fixed call probe was not vetoed'.
    must value: ((thisContext tryPrimitive: array receiver: bind args: {{record}}) == #primitiveFailed)
        value: 'array call probe was not vetoed'.
    must value: ((Simulator new runSimulated: [bind tryInvoke1: record]) == false)
        value: 'simulating an exec send entered native code'.
    sqrt := FFI bind: #(call libm sqrt (f64) f64).
    must value: ((thisContext tryPrimitive: fixed receiver: sqrt args: #(9.0)) = 3.0)
        value: 'an unrelated prepared FFI probe stopped working'.

    Compiler compile: 'execProbeOld: argv
        <primitive: 518>
        ^#oldPrimitiveFallback' in: FFIBinding.
    must value: ((thisContext tryPrimitive: 518 receiver: bind args: {record}) == #primitiveFailed)
        value: 'stale primitive probe did not fail'.
    must value: ((Context executeMethod: (FFIBinding >> #execProbeOld:) receiver: bind arguments: {record})
        == #oldPrimitiveFallback) value: 'stale method context could not run its fallback'.
    300 timesRepeat: [
        must value: ((bind execProbeOld: record) == #oldPrimitiveFallback)
            value: 'ordinary send to stale primitive did not use fallback'].
    true
    """

    def run(mode, body, expected_status, expected_line, exec_entries, position_entries=0):
        completed = subprocess.run(
            [str(args.vm.resolve()), "--jit", mode, "--jit-opt", "8",
             str(args.image.resolve()), "--headless", "--eval", setup + body],
            env=env, capture_output=True, stdin=subprocess.DEVNULL, start_new_session=True,
            text=True, errors="replace", timeout=60, check=False,
        )
        trace = completed.stderr.splitlines()
        entries = (trace.count("ffi-native-entry 1542"), trace.count("ffi-native-entry 1529"))
        if (completed.returncode != expected_status
                or expected_line not in completed.stdout.splitlines()
                or entries != (exec_entries, position_entries)):
            raise SystemExit(
                f"ffi_exec_probe_test: {mode}: expected status {expected_status} "
                f"and {expected_line!r}; got {completed.returncode}. "
                f"Native entries exec/position: expected {(exec_entries, position_entries)}, "
                f"got {entries}\n"
                f"{completed.stdout}{completed.stderr}"
            )

    # A path under a private empty directory guarantees ordinary exec returns 0.
    with tempfile.TemporaryDirectory(prefix="samaltak-exec-probe-") as tmp:
        missing = slice_expr(argv_record(str(Path(tmp) / "missing")))
        malformed = slice_expr(argv_record("/bin/echo", "malformed exec reached") + b"\x00")
        ordinary = f"""
        [ | invalid position |
        invalid := {missing}.
        position := FFI bind: #(call platform platform_files_position (i64) nonNegativeI64).
        must value: ((bind tryInvoke1: invalid) == 0) value: 'missing exec did not return zero'.
        must value: ((bind tryInvoke: {{invalid}}) == 0) value: 'array missing exec did not return zero'.
        must value: ((bind tryInvoke1: {malformed}) == 0) value: 'trailing bytes were accepted'.
        "Heat the same native-zero path without scanning the fd table each time."
        invalid := {{#[0 0 0 0]. 1. 4}}.
        300 timesRepeat: [
            must value: ((bind tryInvoke1: invalid) == 0) value: 'native zero changed'.
            must value: ((bind tryInvoke1: nil) == false) value: 'wrapper rejection changed'.
            must value: ((bind tryInvoke: {{invalid}}) == 0) value: 'array native zero changed'.
            must value: ((position tryInvoke1: -1) isNil) value: 'native nil changed'].
        bind tryInvoke1: record.
        Error signal: 'explicit exec did not replace this child VM'] value
        """
        for mode in (args.mode,) if args.mode else ("none", "baseline", "opt"):
            run(mode, probes, 0, "true", 0)
            run(mode, ordinary, 0, replacement, 604, 300)
            print(f"ffi_exec_probe_test: {mode}: passed")


if __name__ == "__main__":
    main()
