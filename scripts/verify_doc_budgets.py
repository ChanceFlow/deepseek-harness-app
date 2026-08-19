#!/usr/bin/env python3
"""Gate: instruction files and standards stay inside their word ceilings.

Budgets live in scripts/gates_manifest.json (budgets section). Also rejects:
  - a budgeted file that has disappeared (stale manifest entry)
  - an AGENTS.md anywhere in scope without a budget entry (ungoverned file)

Over a ceiling: relocate content to its owning tier, condense, or raise the
ceiling via a manifest diff plus a decision note — never delete the budget.

Exit code 0 = all budgets respected, 1 = violations found.
"""

from __future__ import annotations

import fnmatch
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
MANIFEST = REPO / "scripts" / "gates_manifest.json"
SKIP_DIR_NAMES = {".git", ".dart_tool", ".gradle", "build"}


def word_count(path: Path) -> int:
    return len(path.read_text(encoding="utf-8").split())


def discover_agents_md(manifest: dict) -> set[str]:
    """AGENTS.md files in this repository, excluding the pinned reference submodule."""
    found = set()
    for path in REPO.rglob("AGENTS.md"):
        if SKIP_DIR_NAMES & set(path.parts):
            continue
        if "reference" in path.parts and "deepseek-harness" in path.parts:
            continue  # pinned submodule — externally owned
        rel = path.relative_to(REPO).as_posix()
        if fnmatch.fnmatch(rel, manifest["agents_md_discovery"]):
            found.add(rel)
    return found


def check() -> int:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    budgets: dict[str, int] = manifest["budgets"]
    violations: list[str] = []

    for rel, ceiling in sorted(budgets.items()):
        path = REPO / rel
        if not path.exists():
            violations.append(f"{rel}: budgeted file is missing — remove or fix the manifest entry")
            continue
        words = word_count(path)
        if words > ceiling:
            violations.append(
                f"{rel}: {words} words exceeds ceiling {ceiling} — relocate or condense; "
                "raising needs a manifest diff plus a decision note"
            )

    for rel in sorted(discover_agents_md(manifest)):
        if rel not in budgets:
            violations.append(f"{rel}: AGENTS.md without a budget entry in gates_manifest.json")

    if violations:
        print("DOC-BUDGETS GATE: violations found:")
        for violation in violations:
            print(f"  {violation}")
        return 1
    print("DOC-BUDGETS GATE: CLEAN")
    return 0


if __name__ == "__main__":
    sys.exit(check())
