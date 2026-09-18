#!/usr/bin/env python3
"""Transparent stdio app-server bridge. Only plain user-message text is filtered."""

import concurrent.futures
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import threading
import time

ROOT = Path(__file__).resolve().parent
BACKEND = os.environ.get(
    "JEV_REAL_CODEX", str(ROOT / "JevCodex.app/Contents/Resources/codex-jev")
)
FILTER = os.environ.get("JEV_MESSAGE_FILTER", str(ROOT / "jev-message-filter"))
HOME = Path(os.environ.get("CODEX_HOME", str(Path.home() / ".codex")))
MAX_LINE = 64 * 1024 * 1024


def is_stdio_server(args):
    if "app-server" not in args:
        return False
    rest = args[args.index("app-server") + 1 :]
    if any(
        x in rest
        for x in ("daemon", "generate-ts", "generate-json-schema", "--help", "-h")
    ):
        return False
    for i, arg in enumerate(rest):
        if arg.startswith("--listen=") and arg != "--listen=stdio://":
            return False
        if arg == "--listen" and (i + 1 >= len(rest) or rest[i + 1] != "stdio://"):
            return False
    return True


def run(args):
    if not is_stdio_server(args):
        os.execv(BACKEND, [BACKEND, *args])
    child = subprocess.Popen(
        [BACKEND, *args], stdin=subprocess.PIPE, stdout=sys.stdout.buffer
    )
    lock = threading.RLock()
    helpers = set()
    jobs = {}
    pool = concurrent.futures.ThreadPoolExecutor(max_workers=4)
    stopping = threading.Event()

    def record(stats, method):
        # Metadata only: never log prompts, keys, or response bodies.
        try:
            directory = HOME / "jev-bridge"
            directory.mkdir(mode=0o700, parents=True, exist_ok=True)
            if directory.is_symlink():
                return
            path = directory / "activity.jsonl"
            entry = {"time": time.time(), "method": method, **stats}
            flags = (
                os.O_WRONLY | os.O_CREAT | os.O_APPEND | getattr(os, "O_NOFOLLOW", 0)
            )
            fd = os.open(path, flags, 0o600)
            with os.fdopen(fd, "ab") as log:
                log.write(json.dumps(entry).encode() + b"\n")
        except OSError:
            pass

    def forward(line):
        with lock:
            if not stopping.is_set() and child.poll() is None:
                child.stdin.write(line)
                child.stdin.flush()

    def handle(line, request, previous):
        if previous:
            try:
                previous.result()
            except Exception:
                pass
        if stopping.is_set():
            return
        method = request.get("method")
        if method in ("turn/start", "turn/steer"):
            stats = {
                "apiCalls": 0,
                "savedEstimate": 0,
                "status": "Filter unavailable; original forwarded.",
            }
            helper = None
            try:
                helper = subprocess.Popen(
                    [FILTER],
                    stdin=subprocess.PIPE,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.DEVNULL,
                )
                with lock:
                    helpers.add(helper)
                    if stopping.is_set():
                        helper.terminate()
                result, _ = helper.communicate(line, timeout=35)
                if helper.returncode == 0 and len(result) <= 2_000_000:
                    filtered = json.loads(result)
                    updated = filtered["request"]
                    # A filter must never change routing or the RPC identity.
                    if (
                        updated.get("id"),
                        updated.get("method"),
                        updated.get("params", {}).get("threadId"),
                    ) != (
                        request.get("id"),
                        method,
                        request.get("params", {}).get("threadId"),
                    ):
                        raise ValueError("routing changed")
                    line = json.dumps(updated, ensure_ascii=False).encode() + b"\n"
                    stats = filtered["stats"]
            except (
                OSError,
                ValueError,
                KeyError,
                TypeError,
                AttributeError,
                subprocess.TimeoutExpired,
            ):
                if helper and helper.poll() is None:
                    helper.kill()
                    helper.communicate()
            finally:
                with lock:
                    helpers.discard(helper)
            record(stats, method)
        forward(line)

    def stop(*_):
        stopping.set()
        if child.poll() is None:
            child.terminate()
        with lock:
            for helper in helpers:
                if helper.poll() is None:
                    helper.terminate()

    def watch_child():
        code = child.wait()
        stop()
        # Close the wrapper's inherited stdout too, so clients observe backend EOF promptly.
        os._exit(max(0, code) if code >= 0 else 128 - code)

    threading.Thread(target=watch_child, daemon=True).start()
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        while not stopping.is_set() and child.poll() is None:
            line = sys.stdin.buffer.readline(MAX_LINE + 1)
            if not line:
                break
            if len(line) > MAX_LINE:
                stop()
                break
            try:
                request = json.loads(line)
            except ValueError:
                forward(line)
                continue
            if not isinstance(request, dict):
                forward(line)
                continue
            # Responses to server-initiated approvals/questions must bypass compression queues.
            thread = (
                request.get("params", {}).get("threadId")
                if isinstance(request.get("params"), dict)
                else None
            )
            if isinstance(thread, str) and thread and "method" in request:
                previous = jobs.get(thread)
                jobs[thread] = pool.submit(handle, line, request, previous)
                jobs = {key: job for key, job in jobs.items() if not job.done()}
            else:
                forward(line)
    finally:
        pool.shutdown(wait=True, cancel_futures=True)
        if child.stdin and not child.stdin.closed:
            child.stdin.close()
        try:
            code = child.wait(timeout=5)
        except subprocess.TimeoutExpired:
            stop()
            code = child.wait(timeout=5)

    return code


if __name__ == "__main__":
    raise SystemExit(run(sys.argv[1:]))
