#!/usr/bin/env python3
"""Black-box locale and protocol-stability tests for the pinentry executable."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys
from typing import Optional


LOCALE_VARIABLES = ("PINENTRY_RBW_LOCALE", "LC_ALL", "LC_MESSAGES", "LANG")


def environment(**overrides: str) -> dict[str, str]:
    result = os.environ.copy()
    for key in LOCALE_VARIABLES:
        result.pop(key, None)
    result.update(overrides)
    return result


def run(
    binary: str,
    *arguments: str,
    stdin: Optional[str] = None,
    env: Optional[dict[str, str]] = None,
    expected_status: int = 0,
) -> subprocess.CompletedProcess[str]:
    completed = subprocess.run(
        [binary, *arguments],
        input=stdin,
        capture_output=True,
        check=False,
        encoding="utf-8",
        env=env,
        timeout=10,
    )
    if completed.returncode != expected_status:
        raise AssertionError(
            f"{arguments!r} exited {completed.returncode}, expected {expected_status}\n"
            f"stdout={completed.stdout!r}\nstderr={completed.stderr!r}"
        )
    return completed


def assert_contains(output: str, expected: str) -> None:
    if expected not in output:
        raise AssertionError(f"missing {expected!r} from {output!r}")


def test_help_locales(binary: str) -> None:
    english = run(binary, "--help", env=environment(PINENTRY_RBW_LOCALE="en-US"))
    chinese = run(binary, "--help", env=environment(PINENTRY_RBW_LOCALE="zh-Hans"))
    standard_locale = run(binary, "--help", env=environment(LC_MESSAGES="zh_CN.UTF-8"))
    explicit = run(binary, "--lc-messages", "zh_CN.UTF-8", "--help", env=environment())
    fallback = run(binary, "--help", env=environment(PINENTRY_RBW_LOCALE="fr-FR"))

    assert_contains(english.stdout, "Usage:")
    assert_contains(chinese.stdout, "用法：")
    assert_contains(standard_locale.stdout, "用法：")
    assert_contains(explicit.stdout, "用法：")
    assert_contains(fallback.stdout, "Usage:")
    for completed in (english, chinese, standard_locale, explicit, fallback):
        if completed.stderr:
            raise AssertionError(f"help wrote to stderr: {completed.stderr!r}")


def test_version_is_language_independent(binary: str) -> None:
    english = run(binary, "--version", env=environment(PINENTRY_RBW_LOCALE="en"))
    chinese = run(binary, "--version", env=environment(PINENTRY_RBW_LOCALE="zh-Hans"))
    if english.stdout != chinese.stdout or not english.stdout.strip():
        raise AssertionError(f"localized version output differs: {english.stdout!r} vs {chinese.stdout!r}")


def test_cli_errors_are_localized(binary: str) -> None:
    english = run(
        binary,
        "--unknown",
        env=environment(PINENTRY_RBW_LOCALE="en"),
        expected_status=2,
    )
    chinese = run(
        binary,
        "--unknown",
        env=environment(PINENTRY_RBW_LOCALE="zh-Hans"),
        expected_status=2,
    )
    assert_contains(english.stderr, "fatal: unsupported argument: --unknown")
    assert_contains(chinese.stderr, "fatal: 不支持的参数：--unknown")

    explicit = run(
        binary,
        "--lc-messages", "zh-Hans",
        "--timeout", "invalid",
        env=environment(PINENTRY_RBW_LOCALE="en"),
        expected_status=2,
    )
    assert_contains(explicit.stderr, "fatal: 无效的超时时间：invalid")


def test_protocol_is_language_independent(binary: str) -> None:
    transcript = "OPTION lc-messages={locale}\nGETINFO version\nCONFIRM\nBYE\n"
    outputs: list[str] = []
    for locale in ("en_US.UTF-8", "zh_CN.UTF-8"):
        completed = run(
            binary,
            stdin=transcript.format(locale=locale),
            env=environment(SSH_CONNECTION="test"),
        )
        outputs.append(completed.stdout)
        if completed.stderr:
            raise AssertionError(f"protocol wrote to stderr: {completed.stderr!r}")

    # CONFIRM cannot show a GUI in the synthetic SSH session. Its human-readable
    # detail may be localized, but the greeting, OPTION/GETINFO results, numeric
    # error code, and session terminator must stay language-independent.
    for output in outputs:
        lines = output.splitlines()
        if lines[0] != "OK Pleased to meet you":
            raise AssertionError(f"unexpected greeting: {lines!r}")
        if lines[1] != "OK" or not lines[2].startswith("D ") or lines[3] != "OK":
            raise AssertionError(f"unexpected OPTION/GETINFO response: {lines!r}")
        if not lines[4].startswith("ERR 83886081 ") or lines[5] != "OK":
            raise AssertionError(f"unexpected CONFIRM/BYE response: {lines!r}")
    assert_contains(outputs[0], "This is an SSH session; a confirmation dialog cannot be shown.")
    assert_contains(outputs[1], "当前是 SSH 会话，无法显示确认对话框。")


def test_help_and_completions_list_the_same_options(binary: str) -> None:
    expected = {
        "--store", "--store-stdin", "--clear", "--version", "--help",
        "--ttyname", "--timeout", "--display", "--no-global-grab", "--lc-messages",
    }
    help_output = run(binary, "--help", env=environment(PINENTRY_RBW_LOCALE="en")).stdout
    project_root = Path(__file__).resolve().parents[1]
    zsh_completion = (project_root / "completions" / "_pinentry-rbw-macos").read_text(encoding="utf-8")
    fish_completion = (project_root / "completions" / "pinentry-rbw-macos.fish").read_text(encoding="utf-8")

    for option in expected:
        assert_contains(help_output, option)
        assert_contains(zsh_completion, option)
        assert_contains(fish_completion, option.removeprefix("--"))


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} /path/to/pinentry-rbw-macos")
    binary = os.path.abspath(sys.argv[1])
    test_help_locales(binary)
    test_version_is_language_independent(binary)
    test_cli_errors_are_localized(binary)
    test_protocol_is_language_independent(binary)
    test_help_and_completions_list_the_same_options(binary)
    print("i18n integration tests: ok")


if __name__ == "__main__":
    main()
