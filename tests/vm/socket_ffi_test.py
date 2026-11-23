#!/usr/bin/env python3
"""Exercise the real hosted socket/TLS/PTY facades without a display or external network."""

import argparse
import concurrent.futures
import os
from pathlib import Path
import re
import socket
import ssl
import subprocess
import tempfile
import time


KEYS = set(range(540, 556)) | {561, 562, 564, 565}


def peer(listener, cert, key, resume):
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(cert, key)
    raw, _ = listener.accept()
    with raw:
        raw.settimeout(15)
        with context.wrap_socket(raw, server_side=True) as conn:
            # Don't drain until the client has observed WANT_WRITE and moved its buffer.
            deadline = time.monotonic() + 15
            while not resume.exists():
                if time.monotonic() >= deadline:
                    raise TimeoutError("VM did not observe pending TLS send")
                time.sleep(0.005)
            remaining = 4 * 1024 * 1024
            while remaining:
                data = conn.recv(min(65536, remaining))
                if not data or data != b"A" * len(data):
                    raise AssertionError("TLS payload mismatch")
                remaining -= len(data)
            conn.sendall(b"K")
            try:
                conn.unwrap().close()  # Sends authenticated close_notify before waiting.
            except (ssl.SSLEOFError, ConnectionResetError):
                # Samaltak closes its socket without sending its own close_notify.
                pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("vm", type=Path)
    parser.add_argument("image", type=Path)
    parser.add_argument("--jit", choices=("none", "baseline", "opt"), default="none")
    route = parser.add_mutually_exclusive_group()
    route.add_argument("--legacy", action="store_true", help="run the same workload on legacy primitives")
    route.add_argument("--fallback", action="store_true", help="run candidate facades on an older hosted VM")
    parser.add_argument("--trace", action="store_true", help="require one native entry per audit ID")
    parser.add_argument("--logs", type=Path, help="retain raw VM stdout and stderr in this directory")
    args = parser.parse_args()
    if args.logs:
        args.logs.mkdir(parents=True, exist_ok=True)
    if args.trace and (args.legacy or args.fallback):
        parser.error("--trace requires candidate mode")
    fixture = Path(__file__).with_name("socket_ffi.st").read_text()
    if args.legacy:
        fixture = fixture.replace("ffiCandidatePlatform", "platform").replace("ffiCandidatePrim", "prim")
    with tempfile.TemporaryDirectory(prefix="samaltak-socket-ffi-") as directory:
        root = Path(directory)
        cert, key, resume, source = (root / name for name in ("cert.pem", "key.pem", "resume", "socket_ffi.st"))
        source.write_text(fixture)
        subprocess.run(
            ["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-batch",
             "-keyout", key, "-out", cert, "-days", "1", "-subj", "/CN=localhost",
             "-addext", "subjectAltName=DNS:localhost"],
            check=True, capture_output=True,
        )
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
            listener.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 64 * 1024)
            listener.bind(("127.0.0.1", 0))
            listener.listen(1)
            listener.settimeout(15)
            env = {k: v for k, v in os.environ.items() if k not in {
                "DISPLAY", "WAYLAND_DISPLAY", "SAMALTAK_NATIVE_GRANTS",
            }} | {
                "SDL_VIDEODRIVER": "socket_ffi_no_video",
                "SDL_VIDEO_DRIVER": "socket_ffi_no_video",
                "SSL_CERT_FILE": str(cert),
                "SAMALTAK_SOCKET_TEST_PORT": str(listener.getsockname()[1]),
                "SAMALTAK_SOCKET_TEST_RESUME": str(resume),
                "SAMALTAK_SOCKET_TEST_LEGACY": "1" if args.legacy or args.fallback else "0",
                "SAMALTAK_FFI_NATIVE_TRACE": "1" if args.trace else "0",
            }
            availability = ("(PlatformFFI bind: #(call 'platform' 'platform_sockets_local_port' (i64) i32)) "
                            "isNil ifFalse: [self error: 'Fallback test requires an older hosted VM']. "
                            if args.fallback else "")
            code = ("[" + availability + "SocketFFISmoke run] on: Error do: [:e | "
                    "Smalltalk vm stderrWrite: e messageText, (String with: Character lf). "
                    "Smalltalk quit: 1]")
            with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
                server = pool.submit(peer, listener, cert, key, resume)
                result = subprocess.run(
                    [args.vm.resolve(), args.image.resolve(), "--headless", "--jit", args.jit,
                     "--load", source, "--eval", code],
                    text=True, capture_output=True, env=env, timeout=45,
                )
                if args.logs:
                    arm = ("legacy" if args.legacy else "fallback" if args.fallback
                           else "trace" if args.trace else "candidate")
                    stem = f"{arm}-{args.jit}"
                    (args.logs / f"{stem}.stdout").write_text(result.stdout)
                    (args.logs / f"{stem}.stderr").write_text(result.stderr)
                if result.returncode or "socket-ffi-ok" not in result.stdout:
                    raise SystemExit(f"VM returned {result.returncode}:\n{result.stdout}\n{result.stderr}")
                server.result(timeout=20)
            if args.trace:
                seen = {int(value) - 1024 for value in re.findall(r"ffi-native-entry (\d+)", result.stderr)}
                if KEYS - seen:
                    raise SystemExit(f"missing native entry proof for IDs {sorted(KEYS - seen)}\n{result.stderr}")
                print(f"native entry seen for all {len(KEYS)} IDs")
            arm = "legacy" if args.legacy else "fallback" if args.fallback else "candidate"
            print(f"socket-ffi-ok: {args.jit} {arm}")


if __name__ == "__main__":
    main()
