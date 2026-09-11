#!/usr/bin/env python3
"""Gate: a release workflow signs an APK only after the suite CI runs.

A signed artifact cannot be withdrawn once a user has installed it, so the
release workflows run the test suite themselves instead of trusting that CI
passed on the same tree. That makes the package list a second copy of the
`flutter-test` gate's list, and a copy drifts in silence: `packages/asr` was
missing from both release workflows while CI and the aggregate ran it, so
every signed APK shipped asr code that no release build had tested.

This gate holds the copies equal. The source of truth is the `flutter-test`
gate in `scripts/verify_all.py`; every home in gates_manifest.json
(`release_suite.homes`) must run exactly that package set. Both directions
fail: a package the aggregate tests and a home skips, and a package a home
tests that the aggregate does not name.

Inside a home, commands are joined across `\\` line continuations, and a
`flutter test` that appears in a comment is ignored — only a command line
whose first token is `flutter test` counts.

Exit code 0 = every home runs the aggregate's set, 1 = violations found.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPO: Path = Path(__file__).resolve().parent.parent
MANIFEST: Path = REPO / "scripts" / "gates_manifest.json"

sys.path.insert(0, str(REPO / "scripts"))
import verify_all  # noqa: E402  — the flutter-test gate is the source of truth

_FLAG = re.compile(r"^-")
_TEST_COMMAND = re.compile(r"^flutter\s+test\b")


def _packages(argv: list[str]) -> list[str]:
    """The path arguments of a full `flutter test` argv, flags dropped.

    Accepts both a gate command (`["flutter", "test", ...]`, possibly with
    `--concurrency=` injected after the subcommand) and a workflow line that
    already starts at `flutter`.
    """
    rest = argv[argv.index("test") + 1 :] if "test" in argv else argv[1:]
    return [arg for arg in rest if not _FLAG.match(arg)]


def _join_continuations(text: str) -> list[str]:
    """Logical command lines: a trailing backslash joins the next line."""
    logical: list[str] = []
    pending: str | None = None
    for line in text.splitlines():
        stripped = line.strip()
        if pending is None:
            if not stripped or stripped.startswith("#"):
                continue
            pending = stripped
        else:
            pending = f"{pending} {stripped}"
        if pending.endswith("\\"):
            pending = pending[:-1].rstrip()
            continue
        logical.append(pending)
        pending = None
    if pending is not None:
        logical.append(pending)
    return logical


def _suites(text: str) -> list[list[str]]:
    """Every `flutter test` command line in a workflow, as argument lists."""
    found: list[list[str]] = []
    for line in _join_continuations(text):
        if _TEST_COMMAND.match(line):
            found.append(line.split())
    return found


def check() -> int:
    manifest: dict[str, object] = json.loads(MANIFEST.read_text(encoding="utf-8"))
    config: dict[str, object] = manifest["release_suite"]  # type: ignore[assignment]
    source_gate: str = str(config["source_gate"])
    homes: list[str] = list(config["homes"])  # type: ignore[arg-type]

    gate = next((g for g in verify_all.GATES if g["name"] == source_gate), None)
    if gate is None:
        print(f"RELEASE-SUITE GATE: no `{source_gate}` gate in scripts/verify_all.py")
        return 1
    expected: set[str] = set(_packages(list(gate["cmd"])))
    if not expected:
        print(f"RELEASE-SUITE GATE: the `{source_gate}` gate tests no packages")
        return 1

    violations: list[str] = []
    for home in homes:
        path: Path = REPO / home
        if not path.exists():
            violations.append(f"{home}: pinned file is missing — remove or fix the manifest entry")
            continue
        suites: list[list[str]] = _suites(path.read_text(encoding="utf-8"))
        if not suites:
            violations.append(f"{home}: runs no `flutter test` — remove or fix the manifest entry")
            continue
        found: set[str] = set()
        for suite in suites:
            found.update(_packages(suite))
        for missing in sorted(expected - found):
            violations.append(f"{home}: skips {missing}, which the `{source_gate}` gate tests")
        for extra in sorted(found - expected):
            violations.append(f"{home}: tests {extra}, which the `{source_gate}` gate does not name")

    if violations:
        print("RELEASE-SUITE GATE: the release suite and the aggregate disagree")
        for violation in violations:
            print(f"  {violation}")
        print(
            "fix: add the package to `flutter-test` in scripts/verify_all.py and to every\n"
            "     release workflow, or drop it from both — the signed APK is gated by the\n"
            "     same set the merge gate runs."
        )
        return 1

    print(
        f"RELEASE-SUITE GATE: {len(homes)} release workflow(s) run the `{source_gate}` set "
        f"({len(expected)} package test roots)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(check())
