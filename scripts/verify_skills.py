#!/usr/bin/env python3
"""Gate: every project skill can trigger.

For each directory under .agents/skills/ (root from gates_manifest.json):
  - SKILL.md exists
  - a frontmatter block delimited by '---' lines opens the file
  - 'name:' matches the directory name
  - 'description:' is present and states a trigger (>= min chars from manifest)

Exit code 0 = all skills conform, 1 = violations found.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
MANIFEST = REPO / "scripts" / "gates_manifest.json"


def frontmatter(text: str) -> dict[str, str]:
    """Parse flat 'key: value' lines and YAML block scalars (>-, |-, >, |)."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}
    fields: dict[str, str] = {}
    index = 1
    while index < len(lines):
        line = lines[index]
        if line.strip() == "---":
            return fields
        if line.startswith((" ", "\t", "#")) or ":" not in line:
            index += 1
            continue
        key, _, value = line.partition(":")
        key = key.strip()
        value = value.strip()
        if value in (">-", "|-", ">", "|"):
            block: list[str] = []
            index += 1
            while index < len(lines) and (lines[index].startswith(" ") or lines[index].startswith("\t")):
                block.append(lines[index].strip())
                index += 1
            fields[key] = " ".join(block)
            continue
        fields[key] = value
        index += 1
    return fields


def check() -> int:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    skills_root = REPO / manifest["skills"]["root"]
    min_desc = manifest["skills"]["min_description_chars"]

    violations: list[str] = []
    skill_dirs = sorted(d for d in skills_root.iterdir() if d.is_dir())
    if not skill_dirs:
        print("SKILLS GATE: no skill directories found under", skills_root)
        return 1
    for skill_dir in skill_dirs:
        rel = skill_dir.relative_to(REPO)
        skill_md = skill_dir / "SKILL.md"
        if not skill_md.exists():
            violations.append(f"{rel}: missing SKILL.md")
            continue
        fields = frontmatter(skill_md.read_text(encoding="utf-8"))
        if not fields:
            violations.append(f"{rel}: SKILL.md must open with a '---' frontmatter block")
            continue
        name = fields.get("name", "")
        if name != skill_dir.name:
            violations.append(f"{rel}: frontmatter name '{name}' must match directory name")
        description = fields.get("description", "")
        if len(description) < min_desc:
            violations.append(
                f"{rel}: description must state what the skill does AND when to use it "
                f"(>= {min_desc} chars, got {len(description)})"
            )

    if violations:
        print("SKILLS GATE: violations found:")
        for violation in violations:
            print(f"  {violation}")
        return 1
    print(f"SKILLS GATE: CLEAN ({len(skill_dirs)} skills)")
    return 0


if __name__ == "__main__":
    sys.exit(check())
