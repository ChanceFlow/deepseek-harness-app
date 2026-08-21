#!/usr/bin/env python3
"""Gate: the ARB locales carry the same keys.

Every user-visible string is an ARB key in both locales (root AGENTS.md,
flutter/app/AGENTS.md). A key added to one file only compiles and ships: the
missing locale falls back to the other language at runtime, where nothing
fails. The locale files live in gates_manifest.json (`i18n.arb`); the first
is the reference for placeholder names.

Exit code 0 = the locales agree, 1 = violations found.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

REPO: Path = Path(__file__).resolve().parent.parent
MANIFEST: Path = REPO / "scripts" / "gates_manifest.json"


def message_keys(payload: dict[str, object]) -> set[str]:
    """Translatable keys: everything outside the @-prefixed metadata."""
    return {key for key in payload if not key.startswith("@")}


def placeholders(payload: dict[str, object], key: str) -> set[str]:
    """Placeholder names declared for one key's metadata."""
    meta: object = payload.get(f"@{key}")
    if not isinstance(meta, dict):
        return set()
    declared: object = meta.get("placeholders")
    if not isinstance(declared, dict):
        return set()
    return set(declared)


def check() -> int:
    manifest: dict[str, object] = json.loads(MANIFEST.read_text(encoding="utf-8"))
    config: dict[str, object] = manifest["i18n"]  # type: ignore[assignment]
    files: list[str] = list(config["arb"])  # type: ignore[arg-type]

    violations: list[str] = []
    payloads: dict[str, dict[str, object]] = {}
    for rel in files:
        path: Path = REPO / rel
        if not path.exists():
            violations.append(f"{rel}: ARB file is missing — remove or fix the manifest entry")
            continue
        payloads[rel] = json.loads(path.read_text(encoding="utf-8"))
    if violations:
        print("I18N-ARB GATE: violations found:")
        for violation in violations:
            print(f"  {violation}")
        return 1

    reference: str = files[0]
    reference_keys: set[str] = message_keys(payloads[reference])
    for rel in files[1:]:
        keys: set[str] = message_keys(payloads[rel])
        for key in sorted(reference_keys - keys):
            violations.append(f"{rel}: missing key '{key}' present in {reference}")
        for key in sorted(keys - reference_keys):
            violations.append(f"{reference}: missing key '{key}' present in {rel}")
        for key in sorted(reference_keys & keys):
            expected: set[str] = placeholders(payloads[reference], key)
            actual: set[str] = placeholders(payloads[rel], key)
            if actual and actual != expected:
                violations.append(
                    f"{rel}: key '{key}' declares placeholders {sorted(actual)}, "
                    f"{reference} declares {sorted(expected)}"
                )

    if violations:
        print("I18N-ARB GATE: violations found:")
        for violation in violations:
            print(f"  {violation}")
        return 1
    print(f"I18N-ARB GATE: CLEAN ({len(reference_keys)} keys in {len(files)} locales)")
    return 0


if __name__ == "__main__":
    sys.exit(check())
