#!/usr/bin/env python3
"""Gate: every markdown link and anchor resolves.

Reads include/exclude globs from scripts/gates_manifest.json (docs section).
Checks relative file targets exist and #anchors match a GitHub-style slug of
a heading in the target file. Skips fenced code blocks and external
(http/https/mailto) targets — no network in gates.

Exit code 0 = all links resolve, 1 = violations found.
"""

from __future__ import annotations

import fnmatch
import json
import re
import sys
from pathlib import Path
from urllib.parse import unquote

REPO = Path(__file__).resolve().parent.parent
MANIFEST = REPO / "scripts" / "gates_manifest.json"

LINK_RE = re.compile(r"\[[^\]]*\]\(\s*(<[^>]+>|[^)\s]+)(?:\s+\"[^\"]*\")?\s*\)")
EXTERNAL_RE = re.compile(r"^(https?://|mailto:)", re.IGNORECASE)
FENCE_RE = re.compile(r"^\s*(```|~~~)")
HEADING_RE = re.compile(r"^\s{0,3}#{1,6}\s+(.*?)\s*#*\s*$")
SKIP_DIR_NAMES = {".git", ".dart_tool", ".gradle", "build"}


def load_scope() -> list[Path]:
    """Markdown files in scope: manifest include minus exclude plus extra_include."""
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    docs = manifest["docs"]
    all_md = []
    for path in REPO.rglob("*.md"):
        if SKIP_DIR_NAMES & set(part for part in path.parts):
            continue
        all_md.append(path.relative_to(REPO).as_posix())
    included = {p for p in all_md if any(fnmatch.fnmatch(p, pat) for pat in docs["include"])}
    included = {p for p in included if not any(fnmatch.fnmatch(p, pat) for pat in docs["exclude"])}
    included |= {p for p in all_md if any(fnmatch.fnmatch(p, pat) for pat in docs.get("extra_include", []))}
    return sorted(REPO / p for p in included)


def anchor_base(heading: str) -> str:
    """GitHub-style slug of one heading (no duplicate suffix)."""
    base = re.sub(r"[^\w\- ]", "", heading.strip().lower(), flags=re.UNICODE)
    return base.replace(" ", "-")


_anchors_cache: dict[Path, list[str]] = {}


def file_anchors(path: Path) -> list[str]:
    """All heading anchors in a markdown file, with -1/-2 duplicate suffixes."""
    if path in _anchors_cache:
        return _anchors_cache[path]
    headings: list[str] = []
    in_fence = False
    for line in path.read_text(encoding="utf-8").splitlines():
        if FENCE_RE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        match = HEADING_RE.match(line)
        if match:
            headings.append(match.group(1))
    anchors: list[str] = []
    counts: dict[str, int] = {}
    for heading in headings:
        base = anchor_base(heading)
        counts[base] = counts.get(base, 0) + 1
        anchors.append(base if counts[base] == 1 else f"{base}-{counts[base] - 1}")
    _anchors_cache[path] = anchors
    return anchors


def check() -> int:
    violations: list[str] = []
    for doc in load_scope():
        rel = doc.relative_to(REPO)
        in_fence = False
        for number, line in enumerate(doc.read_text(encoding="utf-8").splitlines(), start=1):
            if FENCE_RE.match(line):
                in_fence = not in_fence
                continue
            if in_fence:
                continue
            for match in LINK_RE.finditer(line):
                target = unquote(match.group(1).strip().strip("<>"))
                if EXTERNAL_RE.match(target):
                    continue
                anchor = None
                file_part = target
                if "#" in target:
                    file_part, anchor = target.split("#", 1)
                if file_part:
                    resolved = (doc.parent / file_part).resolve()
                    try:
                        resolved.relative_to(REPO)
                    except ValueError:
                        continue  # escapes the repo tree (e.g. reference submodule links)
                    if not resolved.exists():
                        violations.append(f"{rel}:{number}: link target does not exist: {target}")
                        continue
                    if anchor and resolved.suffix == ".md" and anchor not in file_anchors(resolved):
                        violations.append(f"{rel}:{number}: anchor '#{anchor}' not found in {file_part}")
                elif anchor and doc.suffix == ".md" and anchor not in file_anchors(doc):
                    violations.append(f"{rel}:{number}: anchor '#{anchor}' not found in {rel}")
    if violations:
        print("MD-LINKS GATE: violations found:")
        for violation in violations:
            print(f"  {violation}")
        return 1
    print("MD-LINKS GATE: CLEAN")
    return 0


if __name__ == "__main__":
    sys.exit(check())
