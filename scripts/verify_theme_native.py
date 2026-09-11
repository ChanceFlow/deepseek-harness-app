#!/usr/bin/env python3
"""Gate: app widgets take their colors from the Material 3 scheme and their
corner radii from the named shape scale.

A hard-coded color survives a theme change in silence — nothing throws, the
widget just stops matching the scheme in one brightness, and a review diff
shows a plausible hex. Under the scanned root every color comes from a
`ColorScheme` role or from the one exempt file, `ui/theme/theme.dart`, which
holds the values Material 3 has no role for (`scheme.success`, the elevation
shadows) so that a call site never has to invent one.

A hard-coded corner radius is the same failure one step over: the number
reads as a local choice and the surface stops matching the scale beside it.
Every radius comes from a named step in the exempt file
(`kShapeSheet`/`kShapeDock`/`kShapeCard`/`kShapeMenuSheet`/`kShapeChip`/
`kShapePill`).

Rejected in scanned files: `Color(0x…)` and `Color.fromARGB` literals, the
`Colors.<name>` palette (allowlist in the manifest), `ThemeExtension`
declarations — a custom token layer is a rejected alternative
(docs/adr-0001-flutter-rewrite.md) — and a numeric literal passed to
`BorderRadius.circular(...)` or `Radius.circular(...)`. Comments are
ignored: prose may name a color or a radius, code may not.

Configuration lives in gates_manifest.json (`theme`).
Exit code 0 = every color comes from the scheme and every radius from the
scale, 1 = violations found.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPO: Path = Path(__file__).resolve().parent.parent
MANIFEST: Path = REPO / "scripts" / "gates_manifest.json"

LINE_COMMENT_RE: re.Pattern[str] = re.compile(r"//.*$")
PATTERNS: dict[str, re.Pattern[str]] = {
    "hex color literal": re.compile(r"\bColor\(\s*0x"),
    "channel color literal": re.compile(r"\bColor\.fromARGB\b|\bColor\.fromRGBO\b"),
    "Material palette color": re.compile(r"\bColors\.[A-Za-z]\w*"),
    "ThemeExtension declaration": re.compile(r"\bThemeExtension\s*<"),
}
# A radius constructor whose argument is a number. `\s*` spans newlines so a
# formatter-split call cannot hide one; the closing paren keeps a numeric
# first argument followed by more arguments out of the match.
RADIUS_PATTERN: re.Pattern[str] = re.compile(
    r"(?<![\w.])(?:Border)?Radius\.circular\(\s*\d+(?:\.\d+)?\s*,?\s*\)"
)
RADIUS_FIX: str = (
    "use a named step from ui/theme/theme.dart: kShapeSheet, kShapeDock, "
    "kShapeCard, kShapeMenuSheet, kShapeChip, or kShapePill"
)


def code_only(line: str) -> str:
    """The line with any trailing `//` comment removed."""
    return LINE_COMMENT_RE.sub("", line)


def check() -> int:
    manifest: dict[str, object] = json.loads(MANIFEST.read_text(encoding="utf-8"))
    config: dict[str, object] = manifest["theme"]  # type: ignore[assignment]
    root: Path = REPO / str(config["root"])
    exempt: set[str] = set(config["exempt"])  # type: ignore[arg-type]
    allowed: set[str] = set(config["allow"])  # type: ignore[arg-type]

    if not root.is_dir():
        print(f"THEME GATE: scanned root {config['root']} does not exist")
        return 1

    violations: list[str] = []
    scanned: int = 0
    for dart_file in sorted(root.rglob("*.dart")):
        rel: str = dart_file.relative_to(REPO).as_posix()
        if rel in exempt:
            continue
        scanned += 1
        lines: list[str] = dart_file.read_text(encoding="utf-8").splitlines()
        for number, raw in enumerate(lines, start=1):
            line: str = code_only(raw)
            for label, pattern in PATTERNS.items():
                for match in pattern.finditer(line):
                    if match.group(0) in allowed:
                        continue
                    violations.append(
                        f"{rel}:{number}: {label} `{match.group(0)}` — "
                        "use a ColorScheme role, or give it a home in "
                        f"{config['exempt'][0]}"  # type: ignore[index]
                    )
        stripped: str = "\n".join(code_only(raw) for raw in lines)
        for match in RADIUS_PATTERN.finditer(stripped):
            number = stripped.count("\n", 0, match.start()) + 1
            snippet = " ".join(match.group(0).split())
            violations.append(
                f"{rel}:{number}: hardcoded corner radius "
                f"`{snippet}` — {RADIUS_FIX}"
            )

    if violations:
        print("THEME GATE: violations found:")
        for violation in violations:
            print(f"  {violation}")
        return 1
    print(f"THEME GATE: CLEAN ({scanned} files scanned)")
    return 0


if __name__ == "__main__":
    sys.exit(check())
