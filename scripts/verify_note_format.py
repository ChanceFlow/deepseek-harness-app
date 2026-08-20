#!/usr/bin/env python3
"""Gate: decision-record format in .agents/notes/.

Enforces the rules owned by .agents/notes/README.md:
  - path shape {lifecycle}/{class}/yyyy-mm-dd-topic.md, class in the closed set
  - first line is '# Agent Note: <title>'
  - 'Status:' line agrees with the lifecycle folder
  - required sections per lifecycle present; proposal-era sections absent
    from implemented notes
  - '## Alternatives considered' has substance (>= 20 words) in every note
  - per-note word ceiling from scripts/gates_manifest.json (notes.max_words)

Exit code 0 = all notes conform, 1 = violations found.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
MANIFEST = REPO / "scripts" / "gates_manifest.json"
FILENAME_RE = re.compile(r"^\d{4}-\d{2}-\d{2}-[a-z0-9][a-z0-9-]*\.md$")

REQUIRED_SECTIONS = {
    "proposed": ["Problem", "Proposal", "Alternatives considered", "Acceptance criteria", "Risks"],
    "implemented": ["Problem", "Decision", "Alternatives considered", "Consequences"],
    "rejected": ["Problem", "Proposal", "Alternatives considered"],
}
FORBIDDEN_IN_IMPLEMENTED = ["Proposal", "Plan", "Acceptance criteria"]


def sections(text: str) -> dict[str, str]:
    """Map H2 heading -> body text."""
    result: dict[str, str] = {}
    current: str | None = None
    buffer: list[str] = []
    for line in text.splitlines():
        match = re.match(r"^##\s+(.+?)\s*$", line)
        if match:
            if current is not None:
                result[current] = "\n".join(buffer)
            current = match.group(1)
            buffer = []
        elif current is not None:
            buffer.append(line)
    if current is not None:
        result[current] = "\n".join(buffer)
    return result


def check_note(path: Path, lifecycle: str, cls: str, classes: set[str], max_words: int) -> list[str]:
    rel = path.relative_to(REPO)
    violations: list[str] = []
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()

    if cls not in classes:
        violations.append(f"{rel}: class '{cls}' not in closed set {sorted(classes)}")
    if not FILENAME_RE.match(path.name):
        violations.append(f"{rel}: filename must be yyyy-mm-dd-topic.md (lowercase kebab)")

    if not lines or not lines[0].startswith("# Agent Note: ") or len(lines[0].split(":", 1)[1].strip()) < 8:
        violations.append(f"{rel}: first line must be '# Agent Note: <title>'")

    status_line = next((l for l in lines[:6] if l.startswith("Status:")), None)
    if status_line is None:
        violations.append(f"{rel}: missing 'Status:' line within the first 6 lines")
    else:
        status = status_line[len("Status:"):].strip()
        if lifecycle == "proposed" and status != "proposed":
            violations.append(f"{rel}: Status '{status}' disagrees with folder proposed/")
        if lifecycle == "implemented" and status != "implemented":
            violations.append(f"{rel}: Status '{status}' disagrees with folder implemented/")
        if lifecycle == "rejected" and not re.match(r"^rejected\s+[—-]\s+\S", status):
            violations.append(f"{rel}: rejected notes need 'Status: rejected — <why, one line>'")

    found = sections(text)
    for section in REQUIRED_SECTIONS[lifecycle]:
        if section not in found:
            violations.append(f"{rel}: missing required section '## {section}'")
    if lifecycle == "implemented":
        for section in FORBIDDEN_IN_IMPLEMENTED:
            if section in found:
                violations.append(f"{rel}: proposal-era section '## {section}' has no place in an implemented note")

    alternatives = found.get("Alternatives considered", "")
    if len(alternatives.split()) < 20:
        violations.append(
            f"{rel}: '## Alternatives considered' must record real alternatives (>= 20 words), not a placeholder"
        )

    words = len(text.split())
    if words > max_words:
        violations.append(f"{rel}: {words} words exceeds note ceiling {max_words} — split or condense")
    return violations


def check() -> int:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    notes_cfg = manifest["notes"]
    root = REPO / notes_cfg["root"]
    classes = set(notes_cfg["classes"])
    max_words = notes_cfg["max_words"]

    violations: list[str] = []
    lifecycles = {"proposed", "implemented", "rejected"}
    for lifecycle_dir in sorted(root.iterdir()):
        if not lifecycle_dir.is_dir() or lifecycle_dir.name not in lifecycles:
            continue
        lifecycle = lifecycle_dir.name
        for note in sorted(lifecycle_dir.rglob("*.md")):
            parts = note.relative_to(lifecycle_dir).parts
            if len(parts) != 2:
                violations.append(
                    f"{note.relative_to(REPO)}: path must be {lifecycle}/<class>/yyyy-mm-dd-topic.md"
                )
                continue
            violations += check_note(note, lifecycle, parts[0], classes, max_words)

    if violations:
        print("NOTE-FORMAT GATE: violations found:")
        for violation in violations:
            print(f"  {violation}")
        return 1
    print("NOTE-FORMAT GATE: CLEAN")
    return 0


if __name__ == "__main__":
    sys.exit(check())
