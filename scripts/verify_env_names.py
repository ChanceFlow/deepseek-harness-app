#!/usr/bin/env python3
"""Gate: every DSH_* name the docs mention exists in source.

Prose names dart-defines and environment variables by hand, and a typo
(`DSH_E2_URL` for `DSH_E2E_URL`) yields a command that runs green while
doing nothing. Every `DSH_[A-Z0-9_]+` token in a markdown file in scope
must appear in some non-markdown file outside the excluded trees. A token
ending in `_` is a documented prefix (`DSH_KEYSTORE_*`) and is satisfied by
any source name starting with it. A name no file declares — one a deployment
sets, or a wrong spelling a decision note quotes — needs an entry with its
reason in gates_manifest.json (`env_names.exceptions`). This file is excluded
from the source scan: a gate may not vouch for the names it uses as examples.

Exit code 0 = every documented name exists, 1 = violations found.
"""

from __future__ import annotations

import fnmatch
import json
import re
import sys
from pathlib import Path

REPO: Path = Path(__file__).resolve().parent.parent
MANIFEST: Path = REPO / "scripts" / "gates_manifest.json"

SKIP_DIR_NAMES: set[str] = {".git", ".dart_tool", ".gradle", "build", "node_modules"}
MAX_SOURCE_BYTES: int = 2_000_000


def load_manifest() -> dict[str, object]:
    return json.loads(MANIFEST.read_text(encoding="utf-8"))


def doc_scope(manifest: dict[str, object]) -> list[Path]:
    """Markdown files in scope: manifest include minus exclude plus extra_include."""
    docs: dict[str, list[str]] = manifest["docs"]  # type: ignore[assignment]
    all_md: list[str] = []
    for path in REPO.rglob("*.md"):
        if SKIP_DIR_NAMES & set(path.parts):
            continue
        all_md.append(path.relative_to(REPO).as_posix())
    included: set[str] = {p for p in all_md if any(fnmatch.fnmatch(p, pat) for pat in docs["include"])}
    included = {p for p in included if not any(fnmatch.fnmatch(p, pat) for pat in docs["exclude"])}
    included |= {p for p in all_md if any(fnmatch.fnmatch(p, pat) for pat in docs.get("extra_include", []))}
    return sorted(REPO / p for p in included)


def source_names(pattern: re.Pattern[str], excludes: list[str]) -> set[str]:
    """Every matching name declared outside the doc corpus."""
    found: set[str] = set()
    for path in REPO.rglob("*"):
        if not path.is_file() or path.suffix == ".md":
            continue
        if SKIP_DIR_NAMES & set(path.parts):
            continue
        rel: str = path.relative_to(REPO).as_posix()
        if any(fnmatch.fnmatch(rel, pat) for pat in excludes):
            continue
        try:
            if path.stat().st_size > MAX_SOURCE_BYTES:
                continue
            text: str = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        found.update(pattern.findall(text))
    return found


def satisfied(name: str, declared: set[str]) -> bool:
    if name in declared:
        return True
    return name.endswith("_") and any(other.startswith(name) for other in declared)


def check() -> int:
    manifest: dict[str, object] = load_manifest()
    config: dict[str, object] = manifest["env_names"]  # type: ignore[assignment]
    pattern: re.Pattern[str] = re.compile(str(config["pattern"]))
    excludes: list[str] = list(config["source_exclude"])  # type: ignore[arg-type]
    exceptions: set[str] = set(config.get("exceptions", {}))  # type: ignore[arg-type]

    declared: set[str] = source_names(pattern, excludes)
    violations: list[str] = []
    for doc in doc_scope(manifest):
        rel: str = doc.relative_to(REPO).as_posix()
        for number, line in enumerate(doc.read_text(encoding="utf-8").splitlines(), start=1):
            for name in pattern.findall(line):
                if name in exceptions or satisfied(name, declared):
                    continue
                violations.append(
                    f"{rel}:{number}: {name} appears in no source file — "
                    "fix the name, declare it, or add it to env_names.exceptions"
                )

    if violations:
        print("ENV-NAMES GATE: violations found:")
        for violation in sorted(set(violations)):
            print(f"  {violation}")
        return 1
    print(f"ENV-NAMES GATE: CLEAN ({len(declared)} names declared in source)")
    return 0


if __name__ == "__main__":
    sys.exit(check())
