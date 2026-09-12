#!/usr/bin/env python3
"""Aggregate gate runner — CI's definition of "done".

Groups:
  docs  verify_md_links, verify_doc_budgets, verify_note_format,
        verify_skills, verify_env_names, verify_toolchain_pin,
        verify_i18n_arb, verify_theme_native, verify_wire_pin,
        verify_release_suite, gen_launcher_icons --check     (seconds, no Flutter)
  code  flutter analyze, dart format check, flutter test,
      check_dart_imports, verify_unused_deps
  all   docs + code (default)

Usage:
  python3 scripts/verify_all.py [--list] [docs|code|all]

.gitea/workflows/ci.yaml runs `docs` and `code` as two parallel jobs on every
push and pull request, and both gate a merge. Locally, reach for the narrowest
tool that would fail for your change (docs/testing.md "Select evidence by
surface") — `all` is for a structural change that touches every surface.
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
        "name": "env-names",
        "groups": ["docs"],
        "cmd": [sys.executable, "scripts/verify_env_names.py"],
        "cwd": REPO,
    },
    {
        "name": "toolchain-pin",
        "groups": ["docs"],
        "cmd": [sys.executable, "scripts/verify_toolchain_pin.py"],
        "cwd": REPO,
    },
    {
        "name": "ci-container-jobs",
        "groups": ["docs"],
        "cmd": [sys.executable, "scripts/verify_ci_container_jobs.py"],
        "cwd": REPO,
    },
    {
        "name": "i18n-arb",
        "groups": ["docs"],
        "cmd": [sys.executable, "scripts/verify_i18n_arb.py"],
        "cwd": REPO,
    },
    {
        "name": "theme-native",
        "groups": ["docs"],
        "cmd": [sys.executable, "scripts/verify_theme_native.py"],
        "cwd": REPO,
    },
    {
        "name": "launcher-icon-drift",
        "groups": ["docs"],
        "cmd": [sys.executable, "scripts/gen_launcher_icons.py", "--check"],
        "cwd": REPO,
        "requires": ("reference submodule", REFERENCE_PIN / ".git"),
    },
    {
        # Python-only and sub-second, but it is the process contract that a
        # re-pin cannot silently leave the client registry behind: it derives
        # the pinned tree's Typert Remote surface and compares it with
        # rpc_map.dart, so it belongs in the fast `docs` joint beside the other
        # pin gates, not in the Flutter-running `code` job.
        "name": "wire-pin",
        "groups": ["docs"],
        "cmd": [sys.executable, "scripts/verify_wire_pin.py"],
        "cwd": REPO,
        "requires": ("reference submodule", REFERENCE_PIN / ".git"),
    },
    {
        # The release workflows re-run the suite before signing, so their
        # package list is a second copy of `flutter-test` below. This gate
        # holds the two equal; a copy that drifts ships untested code inside
        # an artifact nobody can recall. `flutter-test` is the source of
        # truth, so this one reads it rather than repeating it.
        "name": "release-suite",
        "groups": ["docs"],
        "cmd": [sys.executable, "scripts/verify_release_suite.py"],
        "cwd": REPO,
    },
    {
        "name": "flutter-analyze",
        "groups": ["code"],
        # `--no-pub` because a gate may not reach the network on its own: bare
        # `flutter analyze` resolves the workspace itself when the package
        # config is missing or stale, which is how a job once sat on
        # "Resolving dependencies..." for 1h49m and another burned this whole
        # ceiling on it. Resolving is a named, bounded, retried step in every
        # workflow (and `scripts/flutter.sh pub get` locally); this gate runs
        # what that step produced, and fails fast when there is nothing to run.
        "cmd": ["flutter", "analyze", "--no-pub"],
        "cwd": FLUTTER_ROOT,
        # Same scale as flutter-test: in CI the analyzer starts cold (fresh
        # container, fresh analysis server, full pub-workspace resolution) on a
        # host that also runs APK builds and dev suites, and two green-everywhere
        # runs failed only on this ceiling.
        "timeout": 1800,
    },
    {
        "name": "dart-format",
        "groups": ["code"],
        "cmd": [
            "dart",
            "format",
            "--output=none",
            "--set-exit-if-changed",
            "app/lib",
            "app/test",
            "packages/domain/lib",
            "packages/domain/test",
            "packages/network/lib",
            "packages/network/test",
            "packages/harness_adapter/lib",
            "packages/harness_adapter/test",
            "packages/dev/lib",
            "packages/dev/test",
            "packages/asr/lib",
            "packages/asr/test",
        ],
        "cwd": FLUTTER_ROOT,
        "timeout": 300,
    },
    {
        "name": "flutter-test",
        "groups": ["code"],
        # `--no-pub` for the same reason as flutter-analyze above: a gate runs
        # what the workflow's named resolve step produced, and fails fast when
        # there is nothing to run instead of resolving over the network itself.
        "cmd": [
            "flutter",
            "test",
            "--no-pub",
            "app/test",
            "packages/domain/test",
            "packages/network/test",
            "packages/harness_adapter/test",
            "packages/dev/test",
            "packages/asr/test",
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
    {
        "name": "unused-deps",
        "groups": ["code"],
        "cmd": [sys.executable, "scripts/verify_unused_deps.py"],
        "cwd": REPO,
    },
]

# The forge CI runner shares its host: `flutter test` defaults to one
# flutter_tester per CPU, and on a loaded box that OOM-kills the suite
# (exit 137). DSH_TEST_CONCURRENCY caps the suite's parallelism where the
# CI job sets it; local runs leave it unset and keep the framework default.
_TEST_CONCURRENCY = os.environ.get("DSH_TEST_CONCURRENCY")
if _TEST_CONCURRENCY:
    for _gate in GATES:
        if _gate["name"] == "flutter-test":
            # The flag belongs to `flutter test` (after the subcommand):
            # before it is a global-option position and exits 64.
            _gate["cmd"] = [
                _gate["cmd"][0],
                _gate["cmd"][1],
                f"--concurrency={_TEST_CONCURRENCY}",
                *_gate["cmd"][2:],
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
