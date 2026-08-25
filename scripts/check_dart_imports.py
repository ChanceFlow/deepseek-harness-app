#!/usr/bin/env python3
"""Dart import gate for the Flutter workspace.

Holds the anti-corruption boundary: one direction of dependency, and dsh
wire types stay behind the adapter.

Rules:
  - domain           imports nothing outside dart:* (pure Dart, zero Flutter)
  - network          may not import domain / harness_adapter / app / flutter
  - harness_adapter  may import domain + network, never app / flutter
  - dev              may import flutter; never domain / network /
                     harness_adapter / app — debug tooling observes, and a
                     product type reaching it would ship in the app's graph
  - app              may import domain; only app/lib/di/** (assembly wiring)
                     may import harness_adapter

Exit code 0 = CLEAN, 1 = violations found.
"""

from __future__ import annotations

import sys
from collections.abc import Iterator
from pathlib import Path

FLUTTER_ROOT = Path(__file__).resolve().parent.parent / "flutter"

# package -> set of forbidden import prefixes
FORBIDDEN: dict[str, set[str]] = {
    "domain": {"package:flutter/", "package:harness_adapter/", "package:network/", "package:app/", "package:asr/"},
    "network": {"package:flutter/", "package:harness_adapter/", "package:domain/", "package:app/", "package:asr/"},
    "harness_adapter": {"package:flutter/", "package:app/", "package:asr/"},
    "dev": {"package:harness_adapter/", "package:network/", "package:domain/", "package:app/", "package:asr/"},
    "asr": {"package:flutter/", "package:harness_adapter/", "package:domain/", "package:app/"},
}


def check() -> int:
    violations: list[str] = []

    # domain / network / harness_adapter lib + test sources
    for pkg, forbidden in FORBIDDEN.items():
        base = FLUTTER_ROOT / "packages" / pkg
        for dart_file in sorted(base.rglob("*.dart")):
            if not _in_source(dart_file):
                continue
            for line, text in _imports(dart_file):
                for prefix in forbidden:
                    if prefix in text:
                        violations.append(
                            f"{dart_file.relative_to(FLUTTER_ROOT)}:{line}: "
                            f"{pkg} must not import {prefix} ({text.strip()})"
                        )

    # app: harness_adapter/network allowed only under lib/di/
    app_base = FLUTTER_ROOT / "app"
    for dart_file in sorted(app_base.rglob("*.dart")):
        if not _in_source(dart_file):
            continue
        is_wiring = _is_di(dart_file)
        for line, text in _imports(dart_file):
            if is_wiring:
                continue
            for prefix in ("package:harness_adapter/", "package:network/"):
                if prefix in text:
                    violations.append(
                        f"{dart_file.relative_to(FLUTTER_ROOT)}:{line}: "
                        f"app may import {prefix} only in lib/di/** ({text.strip()})"
                    )

    if violations:
        print("IMPORT GATE: violations found:")
        for violation in violations:
            print(f"  {violation}")
        return 1
    print("IMPORT GATE: CLEAN")
    return 0


def _in_source(path: Path) -> bool:
    parts = path.parts
    return "lib" in parts or "test" in parts


def _is_di(path: Path) -> bool:
    return "lib" in path.parts and "di" in path.parts


def _imports(path: Path) -> Iterator[tuple[int, str]]:
    with path.open(encoding="utf-8") as handle:
        for number, line in enumerate(handle, start=1):
            stripped = line.strip()
            if stripped.startswith("import ") or stripped.startswith("export "):
                yield number, stripped


if __name__ == "__main__":
    sys.exit(check())
