#!/usr/bin/env python3
"""Aggregate gate runner — the one command that defines "done".

Groups:
  docs  verify_md_links, verify_doc_budgets, verify_note_format,
        verify_skills, gen_deepsuite_tokens --check,
        gen_launcher_icons --check                        (seconds, no Flutter)
  code  flutter analyze, flutter test, check_dart_imports
  all   docs + code (default; what CI runs)

Usage:
  python3 scripts/verify_all.py [--list] [docs|code|all]

Select the narrowest group that covers your change (docs/testing.md
"Select evidence by surface"); run `all` before closing a task.
Exit code 0 = every gate green, 1 = at least one gate failed.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
FLUTTER_ROOT = REPO / "flutter"
REFERENCE_PIN = REPO / "reference" / "deepseek-harness"
FLUTTER_BIN = Path.home() / "tools" / "flutter-3.47.1" / "bin"


def ensure_flutter_on_path() -> None:
    if shutil.which("flutter") is None and FLUTTER_BIN.is_dir():
        os.environ["PATH"] = f"{FLUTTER_BIN}:{os.environ.get('PATH', '')}"


GATES: list[dict] = [
    {
        "name": "md-links",
        "groups": ["docs"],
        "cmd": [sys.executable, "scripts/verify_md_links.py"],
        "cwd": REPO,
    },
    {
        "name": "doc-budgets",
        "groups": ["docs"],
        "cmd": [sys.executable, "scripts/verify_doc_budgets.py"],
        "cwd": REPO,
    },
    {
        "name": "note-format",
        "groups": ["docs"],
        "cmd": [sys.executable, "scripts/verify_note_format.py"],
        "cwd": REPO,
    },
    {
        "name": "skills",
        "groups": ["docs"],
        "cmd": [sys.executable, "scripts/verify_skills.py"],
        "cwd": REPO,
    },
    {
        "name": "design-token-drift",
        "groups": ["docs"],
        "cmd": [sys.executable, "scripts/gen_deepsuite_tokens.py", "--check"],
        "cwd": REPO,
        "requires": ("reference submodule", REFERENCE_PIN / ".git"),
    },
    {
        "name": "launcher-icon-drift",
        "groups": ["docs"],
        "cmd": [sys.executable, "scripts/gen_launcher_icons.py", "--check"],
        "cwd": REPO,
        "requires": ("reference submodule", REFERENCE_PIN / ".git"),
    },
    {
        "name": "flutter-analyze",
        "groups": ["code"],
        "cmd": ["flutter", "analyze"],
        "cwd": FLUTTER_ROOT,
        "timeout": 600,
    },
    {
        "name": "flutter-test",
        "groups": ["code"],
        "cmd": [
            "flutter",
            "test",
            "app/test",
            "packages/domain/test",
            "packages/network/test",
            "packages/harness_adapter/test",
        ],
        "cwd": FLUTTER_ROOT,
        "timeout": 1800,
    },
    {
        "name": "dart-imports",
        "groups": ["code"],
        "cmd": [sys.executable, "scripts/check_dart_imports.py"],
        "cwd": REPO,
    },
]


def run_group(group: str) -> int:
    ensure_flutter_on_path()
    selected = [g for g in GATES if group in g["groups"] or group == "all"]
    failures: list[str] = []
    for gate in selected:
        print(f"\n=== gate: {gate['name']} " + "=" * max(0, 50 - len(gate["name"])))
        requirement = gate.get("requires")
        if requirement and not Path(requirement[1]).exists():
            print(
                f"FAIL {gate['name']}: {requirement[0]} missing at {requirement[1]}\n"
                "      fix: git submodule update --init reference/deepseek-harness"
            )
            failures.append(gate["name"])
            continue
        started = time.monotonic()
        try:
            result = subprocess.run(
                gate["cmd"],
                cwd=gate["cwd"],
                timeout=gate.get("timeout", 900),
                check=False,
            )
        except FileNotFoundError as error:
            print(f"FAIL {gate['name']}: cannot execute {gate['cmd'][0]} ({error})")
            failures.append(gate["name"])
            continue
        except subprocess.TimeoutExpired:
            print(f"FAIL {gate['name']}: timed out after {gate.get('timeout', 900)}s")
            failures.append(gate["name"])
            continue
        elapsed = time.monotonic() - started
        status = "ok" if result.returncode == 0 else f"FAIL (exit {result.returncode})"
        print(f"--- {gate['name']}: {status} in {elapsed:.1f}s")
        if result.returncode != 0:
            failures.append(gate["name"])

    print("\n" + "=" * 64)
    if failures:
        print(f"AGGREGATE: {len(failures)} gate(s) failed: {', '.join(failures)}")
        print("Fix the first failure's output above; re-run this script.")
        return 1
    print(f"AGGREGATE: all {len(selected)} gates green ({group})")
    return 0


def main() -> int:
    args = sys.argv[1:]
    if "--list" in args:
        for gate in GATES:
            print(f"{gate['name']:<20} groups={','.join(gate['groups'])}")
        return 0
    group = "all"
    for arg in args:
        if arg in ("docs", "code", "all"):
            group = arg
        else:
            print(f"unknown argument: {arg} (expected docs|code|all|--list)")
            return 2
    return run_group(group)


if __name__ == "__main__":
    sys.exit(main())
