#!/usr/bin/env python3
"""Finite-timeout stdlib PTY runner. Never fakes a PTY.

Usage:
  python3 pty_driver.py --probe
  python3 pty_driver.py --timeout SEC --cwd DIR --out FILE
                       [--prompt-contains TEXT] [--answer TEXT ...] -- CMD [ARG ...]

--probe exits 0 if a real PTY can be opened, else 3.
SAIKIT_VERIFY_PTY=missing forces unavailable (exit 3). A pipe is never
substituted for a PTY.

The child is placed in its own process group. On timeout the group is
signaled (SIGTERM, then SIGKILL) and reaped. do_killpg is the mutation
hook for skip_killpg.
"""
from __future__ import annotations

import argparse
import json
import os
import select
import signal
import sys
import time
from typing import Any

# Mutation hook: skip_killpg flips this to False.
do_killpg = True


def pty_available() -> bool:
    if os.environ.get("SAIKIT_VERIFY_PTY") == "missing":
        return False
    try:
        master, slave = os.openpty()
        os.close(master)
        os.close(slave)
        return True
    except (OSError, AttributeError):
        return False


def child_env() -> dict[str, str]:
    home = os.environ.get("VERIFY_HOME") or os.environ.get("HOME") or "/tmp"
    tmp = os.environ.get("VERIFY_TMPDIR") or os.environ.get("TMPDIR") or "/tmp"
    path = os.environ.get("PATH", "/usr/bin:/bin:/usr/local/bin")
    env = {
        "HOME": home,
        "USERPROFILE": home,
        "PATH": path,
        "TMPDIR": tmp,
        "TMP": tmp,
        "TEMP": tmp,
        "LANG": os.environ.get("LANG", "C"),
        "TERM": "dumb",
        "TZ": os.environ.get("TZ", "UTC"),
    }
    for key in ("LC_ALL", "LC_CTYPE", "USER", "LOGNAME"):
        if os.environ.get(key):
            env[key] = os.environ[key]
    return env


def write_out(path: str | None, payload: dict[str, Any]) -> None:
    text = json.dumps(payload, ensure_ascii=False)
    if path:
        parent = os.path.dirname(path)
        if parent:
            os.makedirs(parent, exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(text + "\n")
    sys.stdout.write(text + "\n")


def reap(pid: int, seconds: float) -> int | None:
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        try:
            wpid, status = os.waitpid(pid, os.WNOHANG)
        except ChildProcessError:
            return 0
        if wpid == pid:
            return status
        time.sleep(0.05)
    return None


def decode_status(status: int | None) -> int:
    if status is None:
        return 124
    if os.WIFEXITED(status):
        return int(os.WEXITSTATUS(status))
    if os.WIFSIGNALED(status):
        return 128 + int(os.WTERMSIG(status))
    return 124


def kill_group(pid: int, sig: int) -> None:
    try:
        os.killpg(pid, sig)
    except (ProcessLookupError, PermissionError, OSError):
        try:
            os.kill(pid, sig)
        except (ProcessLookupError, PermissionError, OSError):
            pass


def answer_ready(transcript: str, sent: int, prompt_contains: str) -> bool:
    """True when the next --answer can be written.

    Default: wait for the setup-style ``N/5`` marker (19.8).
    ``--prompt-contains`` waits for that substring instead (CI offer, etc.).
    """
    if prompt_contains:
        start = 0
        idx = -1
        for _ in range(sent + 1):
            idx = transcript.find(prompt_contains, start)
            if idx < 0:
                return False
            start = idx + len(prompt_contains)
        tail = transcript[idx:]
        return "]: " in tail or ": " in tail or tail.rstrip().endswith(":")
    marker = f"{sent + 1}/5"
    if marker not in transcript:
        return False
    tail = transcript.split(marker, 1)[-1]
    return "]: " in tail or ":" in tail


def run(
    cmd: list[str],
    cwd: str,
    timeout: float,
    answers: list[str],
    prompt_contains: str = "",
) -> dict[str, Any]:
    if not pty_available():
        return {
            "pty": False,
            "exit": 3,
            "timed_out": False,
            "killed": False,
            "reaped": False,
            "transcript": "",
            "reason": "PTY ausente",
        }

    master, slave = os.openpty()
    pid = os.fork()
    if pid == 0:
        os.close(master)
        os.setsid()
        os.dup2(slave, 0)
        os.dup2(slave, 1)
        os.dup2(slave, 2)
        if slave > 2:
            os.close(slave)
        try:
            os.chdir(cwd)
        except OSError:
            os._exit(2)
        try:
            os.execvpe(cmd[0], cmd, child_env())
        except OSError:
            os._exit(127)

    os.close(slave)
    transcript = ""
    sent = 0
    timed_out = False
    killed = False
    reaped = False
    status: int | None = None
    deadline = time.monotonic() + timeout
    try:
        os.set_blocking(master, False)
        while True:
            remain = deadline - time.monotonic()
            if remain <= 0:
                timed_out = True
                break
            try:
                ready, _, _ = select.select([master], [], [], min(remain, 0.2))
            except InterruptedError:
                ready = []
            if ready:
                try:
                    chunk = os.read(master, 4096)
                except OSError:
                    chunk = b""
                if not chunk:
                    break
                transcript += chunk.decode("utf-8", "replace")
                while sent < len(answers):
                    if not answer_ready(transcript, sent, prompt_contains):
                        break
                    try:
                        os.write(master, (answers[sent] + "\n").encode("utf-8"))
                    except OSError:
                        sent = len(answers)
                        break
                    sent += 1
            try:
                wpid, status = os.waitpid(pid, os.WNOHANG)
            except ChildProcessError:
                wpid, status = pid, 0
            if wpid == pid:
                reaped = True
                # Drain leftover output.
                drain_end = time.monotonic() + 0.3
                while time.monotonic() < drain_end:
                    try:
                        more = os.read(master, 4096)
                    except OSError:
                        break
                    if not more:
                        break
                    transcript += more.decode("utf-8", "replace")
                break

        if not reaped:
            if timed_out and do_killpg:
                kill_group(pid, signal.SIGTERM)
                status = reap(pid, 1.0)
                if status is None:
                    kill_group(pid, signal.SIGKILL)
                    status = reap(pid, 1.0)
                killed = True
                reaped = status is not None
            elif timed_out:
                killed = False
                reaped = False
    finally:
        # Always reap leftovers so a mutant does not leak a live child.
        try:
            wpid, st = os.waitpid(pid, os.WNOHANG)
            if wpid == pid and not reaped:
                status = st
        except (ChildProcessError, OSError):
            pass
        if not reaped:
            kill_group(pid, signal.SIGKILL)
            leftover = reap(pid, 1.0)
            if leftover is not None and status is None:
                status = leftover
        try:
            os.close(master)
        except OSError:
            pass

    return {
        "pty": True,
        "exit": decode_status(status) if reaped or timed_out else 3,
        "timed_out": timed_out,
        "killed": killed,
        "reaped": reaped,
        "transcript": transcript,
        "reason": "timeout" if timed_out else "",
        "answers_sent": sent,
    }


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--probe", action="store_true")
    ap.add_argument("--timeout", type=float, default=8.0)
    ap.add_argument("--cwd", default=".")
    ap.add_argument("--out", default="")
    ap.add_argument("--answer", action="append", default=[])
    ap.add_argument(
        "--prompt-contains",
        default="",
        help="Wait for this substring before each --answer (default: N/5)",
    )
    ap.add_argument("cmd", nargs=argparse.REMAINDER)
    args = ap.parse_args(argv)

    if args.probe:
        return 0 if pty_available() else 3

    cmd = list(args.cmd)
    if cmd and cmd[0] == "--":
        cmd = cmd[1:]
    if not cmd:
        write_out(args.out or None, {"pty": False, "exit": 2, "reason": "falta comando"})
        return 2

    payload = run(cmd, args.cwd, args.timeout, list(args.answer), args.prompt_contains)
    write_out(args.out or None, payload)
    if not payload.get("pty"):
        return 3
    return 0


if __name__ == "__main__":
    sys.exit(main())
