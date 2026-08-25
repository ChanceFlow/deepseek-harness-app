#!/usr/bin/env python3
"""Unused-dependency gate for the Flutter workspace.

For every workspace member, flags a dependency declared in its pubspec
(`dependencies` or `dev_dependencies`) that no Dart file under that
member's `lib/` and `test/` refers to via a `package:` import/export.
This is the Dart-side answer to knip's dependency scan (knip itself is a
Node/TS tool and cannot read Dart): the cheap, high-value subset —
declared-but-unused packages — enforced in CI.

Semantics:
  - Per member package: pubspec deps vs package: URIs in that member's
    lib/ + test/.  A dep used only by another member still counts as
    unused for the member that declares it.
  - SDK deps (`sdk: flutter` and friends) are skipped.
  - Analysis-only dev deps (flutter_lints, custom_lint, ...) are
    allowlisted: they are consumed by analysis_options.yaml `include:`,
    never imported.
  - The workspace root pubspec (dsh_workspace) carries no deps; it is
    not scanned.

Exit code 0 = CLEAN, 1 = unused dependencies found.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

FLUTTER_ROOT = Path(__file__).resolve().parent.parent / "flutter"

# dev deps consumed by analysis_options.yaml includes, never imported
ANALYSIS_ONLY_DEPS = {"flutter_lints", "lints", "custom_lint", "very_good_analysis"}

_TOP_LEVEL_SECTION = re.compile(r"^([a-zA-Z0-9_]+):\s*(?:#.*)?$")
_ENTRY = re.compile(r"^  ([a-zA-Z0-9_]+):\s*(.*)$")
_SDK_VALUE = re.compile(r"^sdk:\s+(\S+)")


def parse_pubspec(pubspec: Path) -> dict[str, list[str]]:
    """Return {'dependencies': [...], 'dev_dependencies': [...]}."""
    result: dict[str, list[str]] = {"dependencies": [], "dev_dependencies": []}
    section: str | None = None
    for raw in pubspec.read_text(encoding="utf-8").splitlines():
        line = raw.rstrip()
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if not line.startswith(" "):
            top = _TOP_LEVEL_SECTION.match(line)
            if top and top.group(1) in result:
                section = top.group(1)
            else:
                section = None
            continue
        if section is None:
            continue
        if line.startswith("  ") and not line.startswith("    "):
            entry = _ENTRY.match(line)
            if entry is None:
                continue
            name, value = entry.group(1), entry.group(2)
            if _SDK_VALUE.match(value):
                continue  # sdk: flutter / flutter_test / ...
            result[section].append(name)
    return result


def used_packages(root: Path) -> set[str]:
    """All `package:` names referenced from .dart files under root."""
    used: set[str] = set()
    pattern = re.compile(r"""(?:import|export)\s+['"](?:package:([A-Za-z0-9_]+)/|package:([A-Za-z0-9_]+)\.dart)""")
    for dart in root.rglob("*.dart"):
        if any(part in {"build", ".dart_tool"} for part in dart.parts):
            continue
        text = dart.read_text(encoding="utf-8")
        for match in pattern.finditer(text):
            used.add(match.group(1) or match.group(2))
    return used


def check() -> int:
    root_pubspec = FLUTTER_ROOT / "pubspec.yaml"
    workspace_text = root_pubspec.read_text(encoding="utf-8")
    members = re.findall(r"^  - (\S+)$", workspace_text, flags=re.MULTILINE)

    failures: list[str] = []
    for member in sorted(members):
        pubspec = FLUTTER_ROOT / member / "pubspec.yaml"
        if not pubspec.exists():
            continue
        declared = parse_pubspec(pubspec)
        used = used_packages(FLUTTER_ROOT / member)
        for section in ("dependencies", "dev_dependencies"):
            for name in declared[section]:
                if name in used or name in ANALYSIS_ONLY_DEPS:
                    continue
                failures.append(f"{member}: {name} (declared in {section}, never used)")

    if not failures:
        print("UNUSED DEPS: CLEAN")
        return 0
    print("UNUSED DEPS: violations found")
    for failure in sorted(failures):
        print(f"  - {failure}")
    return 1


if __name__ == "__main__":
    sys.exit(check())