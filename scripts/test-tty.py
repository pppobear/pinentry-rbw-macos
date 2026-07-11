#!/usr/bin/env python3
"""Black-box TTY regression tests for the pinentry executable."""

import os
import pty
import select
import signal
import subprocess
import sys
import termios
import time


def reset_job_control_signal() -> None:
    # Non-interactive parents may ignore SIGTSTP; make the child use the
    # normal disposition so the helper's restore-before-forward path is tested.
    signal.signal(signal.SIGTSTP, signal.SIG_DFL)


def read_until(descriptor: int, needle: bytes, timeout: float = 5) -> bytes:
    data = b""
    deadline = time.monotonic() + timeout
    while needle not in data and time.monotonic() < deadline:
        ready, _, _ = select.select([descriptor], [], [], 0.1)
        if ready:
            chunk = os.read(descriptor, 4096)
            if not chunk:
                break
            data += chunk
    if needle not in data:
        raise AssertionError(f"missing {needle!r} in {data!r}")
    return data


class Session:
    def __init__(self, binary: str, timeout: str = "0") -> None:
        self.master, self.slave = pty.openpty()
        environment = os.environ.copy()
        environment["SSH_CONNECTION"] = "integration-test"
        self.process = subprocess.Popen(
            [
                binary,
                "--timeout",
                timeout,
                "--ttyname",
                os.ttyname(self.slave),
                "--no-global-grab",
            ],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=environment,
            preexec_fn=reset_job_control_signal,
        )
        assert self.process.stdin is not None
        assert self.process.stdout is not None
        greeting = self.process.stdout.readline()
        if greeting != b"OK Pleased to meet you\n":
            raise AssertionError(f"unexpected greeting: {greeting!r}")
        self.process.stdin.write(b"SETPROMPT API key client__id\nGETPIN\n")
        self.process.stdin.flush()
        self.prompt_output = read_until(self.master, b"API key client__id")
        self.assert_echo(False)

    def assert_echo(self, expected: bool) -> None:
        enabled = bool(termios.tcgetattr(self.slave)[3] & termios.ECHO)
        if enabled != expected:
            raise AssertionError(f"terminal echo is {enabled}, expected {expected}")

    def read_protocol(self, needle: bytes, timeout: float = 5) -> bytes:
        assert self.process.stdout is not None
        return read_until(self.process.stdout.fileno(), needle, timeout)

    def finish(self) -> None:
        assert self.process.stdin is not None
        self.process.stdin.write(b"BYE\n")
        self.process.stdin.flush()
        self.process.wait(timeout=5)
        if self.process.returncode != 0:
            raise AssertionError(f"pinentry exited with {self.process.returncode}")
        os.close(self.master)
        os.close(self.slave)


def test_success(binary: str) -> None:
    session = Session(binary)
    secret = b"  CID-123 \t  "
    os.write(session.master, secret + b"\n")
    session.read_protocol(b"D " + secret + b"\nOK\n")
    session.assert_echo(True)
    terminal_output = session.prompt_output
    ready, _, _ = select.select([session.master], [], [], 0.2)
    if ready:
        terminal_output += os.read(session.master, 4096)
    if secret in terminal_output:
        raise AssertionError("secret was echoed to the terminal")
    session.finish()


def test_cancel(binary: str) -> None:
    session = Session(binary)
    os.write(session.master, b"\x04")
    session.read_protocol(b"ERR 83886179 operation cancelled")
    session.assert_echo(True)
    session.finish()


def test_timeout(binary: str) -> None:
    session = Session(binary, timeout="1")
    session.read_protocol(b"ERR 83886179 operation timed out", timeout=4)
    session.assert_echo(True)
    session.finish()


def test_stop_signal(binary: str) -> None:
    session = Session(binary)
    os.kill(session.process.pid, signal.SIGTSTP)
    stopped = False
    protocol_output = b""
    deadline = time.monotonic() + 5
    assert session.process.stdout is not None
    while time.monotonic() < deadline:
        child, status = os.waitpid(session.process.pid, os.WUNTRACED | os.WNOHANG)
        if child and os.WIFSTOPPED(status):
            if os.WSTOPSIG(status) != signal.SIGTSTP:
                raise AssertionError(f"child stopped on an unexpected signal: {status}")
            stopped = True
            break
        ready, _, _ = select.select([session.process.stdout.fileno()], [], [], 0.1)
        if ready:
            protocol_output += os.read(session.process.stdout.fileno(), 4096)
            if b"ERR 83886179 operation cancelled" in protocol_output:
                break
    session.assert_echo(True)
    if stopped:
        os.kill(session.process.pid, signal.SIGCONT)
        session.read_protocol(b"ERR 83886179 operation cancelled")
    elif b"ERR 83886179 operation cancelled" not in protocol_output:
        raise AssertionError("SIGTSTP was neither forwarded nor returned as cancellation")
    session.finish()


def test_terminating_signal(binary: str) -> None:
    session = Session(binary)
    os.kill(session.process.pid, signal.SIGTERM)
    session.process.wait(timeout=5)
    if session.process.returncode != -signal.SIGTERM:
        raise AssertionError(f"unexpected SIGTERM return code: {session.process.returncode}")
    session.assert_echo(True)
    os.close(session.master)
    os.close(session.slave)


def test_signal_during_input_cleanup(binary: str) -> None:
    for _ in range(10):
        session = Session(binary)
        os.write(session.master, b"x\n")
        os.kill(session.process.pid, signal.SIGTERM)
        session.process.wait(timeout=5)
        if session.process.returncode != -signal.SIGTERM:
            raise AssertionError(f"SIGTERM was swallowed during cleanup: {session.process.returncode}")
        session.assert_echo(True)
        os.close(session.master)
        os.close(session.slave)


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} /path/to/pinentry-rbw-macos")
    binary = os.path.abspath(sys.argv[1])
    for test in (
        test_success,
        test_cancel,
        test_timeout,
        test_stop_signal,
        test_terminating_signal,
        test_signal_during_input_cleanup,
    ):
        test(binary)
    print("tty integration tests: ok")


if __name__ == "__main__":
    main()
