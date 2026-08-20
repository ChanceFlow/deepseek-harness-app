#!/usr/bin/env python3
"""Generate Dart deepsuite design tokens from the dsh web reference.

Source of truth:
  reference/deepseek-harness/packages/client/ui-theme/src/styles/design-platform.css
  reference/deepseek-harness/packages/client/ui-theme/src/styles/base.css

Usage:
  python3 scripts/gen_deepsuite_tokens.py           # write the Dart file
  python3 scripts/gen_deepsuite_tokens.py --check   # exit 1 on drift
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CSS_PATH = (
    REPO
    / "reference/deepseek-harness/packages/client/ui-theme/src/styles/design-platform.css"
)
OUT_PATH = REPO / "flutter/app/lib/ui/theme/deepsuite_tokens.dart"

DARK_SELECTOR = "body[data-ds-dark-theme]"


def parse_blocks(css: str) -> tuple[dict[str, str], dict[str, str]]:
    """Return (light, dark) maps of token name -> raw value."""
    light: dict[str, str] = {}
    dark: dict[str, str] = {}

    # A block starts at a selector line and ends at the matching close brace.
    # The file only uses flat one-level blocks (no nesting).
    block_re = re.compile(r"([^{}]+)\{([^{}]*)\}")
    for selector, body in block_re.findall(css):
        is_dark = DARK_SELECTOR in selector
        for name, value in parse_declarations(body):
            if is_dark:
                dark[name] = value
            else:
                light[name] = name not in light and value or light[name]
    # The static palette is defined on `body` (light) and repeated verbatim in
    # the dark block; merge both view of statics.
    for name, value in dark.items():
        if name.startswith("--dsw-static-") and name not in light:
            light[name] = value
    return light, dark


def parse_declarations(body: str) -> list[tuple[str, str]]:
    out = []
    for line in body.splitlines():
        line = line.strip()
        if not line.startswith("--"):
            continue
        if ":" not in line:
            continue
        name, _, value = line.partition(":")
        out.append((name.strip(), value.strip().rstrip(";").strip()))
    return out


def rgb_to_color(value: str) -> str:
    """rgb(a)?(...) -> Dart Color literal; var(--x) resolved later."""
    m = re.fullmatch(r"rgba?\(([^)]+)\)", value)
    if not m:
        raise ValueError(f"unsupported color value: {value!r}")
    parts = [p.strip() for p in m.group(1).split(",")]
    if len(parts) == 3:
        r, g, b = (int(p) for p in parts)
        return f"Color(0xff{r:02x}{g:02x}{b:02x})"
    r, g, b = (int(p) for p in parts[:3])
    a = float(parts[3])
    alpha = int(round(a * 255))
    return f"Color(0x{alpha:02x}{r:02x}{g:02x}{b:02x})"


def camel(name: str) -> str:
    """--dsw-alias-bg-layer-1 -> bgLayer1 (drop the dsw prefix)."""
    body = re.sub(r"^--dsw-(static-)?", "", name)
    body = body.replace("-700-delete", "-700")
    parts = body.split("-")
    return parts[0] + "".join(p.title() for p in parts[1:])


def resolve(token: str, tokens: dict[str, str]) -> str:
    """Resolve var() chains and rgba() literals to a Dart expression."""
    seen = 0
    while True:
        m = re.fullmatch(r"var\((--[a-z0-9-]+)\)", token)
        if not m:
            break
        ref = m.group(1)
        if ref not in tokens:
            raise ValueError(f"unresolved var reference {ref}")
        token = tokens[ref]
        seen += 1
        if seen > 8:
            raise ValueError("alias chain too deep")
    return rgb_to_color(token)


def dart_field(
    name: str,
    tokens: dict[str, str],
    comment: str,
    shared_statics: set[str],
) -> str:
    raw = tokens[name]
    var_m = re.fullmatch(r"var\((--[a-z0-9-]+)\)", raw)
    if (
        var_m
        and var_m.group(1) in shared_statics
    ):
        expr = f"DeepSuiteStatic.{camel(var_m.group(1))}"
    else:
        expr = resolve(raw, tokens)
    return f"  /// {comment}\n  static const Color {camel(name)} = {expr};"


def collect_names(light: dict[str, str], dark: dict[str, str]) -> tuple[list, list, list]:
    statics = sorted(n for n in light if n.startswith("--dsw-static-"))
    aliases = sorted(
        n
        for n in light
        if n.startswith(("--dsw-alias-", "--dsw-specific-"))
    )
    return statics, aliases, aliases


def main() -> int:
    css = CSS_PATH.read_text(encoding="utf-8")
    light, dark = parse_blocks(css)

    all_statics = {
        n for n in set(light) | set(dark) if n.startswith("--dsw-static-")
    }
    # Statics identical in both themes live in DeepSuiteStatic; the rest
    # (e.g. neutral-bluish-60) resolve inside each theme class.
    shared_statics = {
        n
        for n in all_statics
        if n in light and n in dark and light[n] == dark[n]
    }
    statics = sorted(shared_statics)
    alias_names = sorted(
        n
        for n in set(light) | set(dark)
        if n.startswith(("--dsw-alias-", "--dsw-specific-"))
    )
    missing = [n for n in alias_names if n not in light or n not in dark]
    if missing:
        raise SystemExit(f"aliases missing a theme block: {missing}")

    lines = [
        "// GENERATED by scripts/gen_deepsuite_tokens.py — DO NOT EDIT.",
        "// Source: reference/.../ui-theme/src/styles/{design-platform,base}.css",
        "// Regenerate: python3 scripts/gen_deepsuite_tokens.py",
        "library;",
        "",
        "import 'package:flutter/painting.dart' show Color;",
        "",
        "/// Raw deepsuite palette (theme-independent statics).",
        "final class DeepSuiteStatic {",
        "  const DeepSuiteStatic._();",
    ]
    for name in statics:
        raw_light = light.get(name) or dark[name]
        raw_dark = dark.get(name) or light[name]
        if raw_light != raw_dark:
            raise SystemExit(f"static token differs across themes: {name}")
        lines.append(
            f"  static const Color {camel(name)} = {rgb_to_color(raw_light)};"
        )
    lines.append("}")
    lines.append("")

    for theme, tokens, cls in (
        ("Light", light, "DeepSuiteLight"),
        ("Dark", dark, "DeepSuiteDark"),
    ):
        lines.append(f"/// Semantic `{theme}` aliases resolved to concrete colors.")
        lines.append(f"final class {cls} {{")
        lines.append(f"  const {cls}._();")
        for name in alias_names:
            lines.append(dart_field(name, tokens, name, shared_statics))
        lines.append("  /// Same tokens keyed by CSS name (parity tests, A2 consumers).")
        lines.append("  static const Map<String, Color> byName = <String, Color>{")
        for name in alias_names:
            lines.append(f"    {name!r}: {camel(name)},")
        lines.append("  };")
        lines.append("}")
        lines.append("")

    lines.append("/// Alias keys in declaration order (light/dark parity test).")
    lines.append("const List<String> kDeepSuiteAliasKeys = [")
    for name in alias_names:
        lines.append(f"  {name!r},")
    lines.append("];")
    lines.append("")
    lines.append(
        "// Font tokens from ui-theme/src/styles/base.css: the code stack\n"
        "// (SF Mono/JetBrains Mono/Fira Code/...) has no Flutter-side asset;\n"
        "// the platform monospace default is the accepted equivalent.\n"
        "const String kFontFamilyMonospace = 'monospace';\n"
        "// Motion tokens from ui-theme/src/styles/base.css.\n"
        "const Duration kDsDurationFast = Duration(milliseconds: 100);\n"
        "const Duration kDsDuration = Duration(milliseconds: 200);\n"
        "const Duration kDsDurationSlow = Duration(milliseconds: 300);\n"
        "// cubic-bezier(0.4, 0, 0.2, 1) maps onto Flutter Curves.easeInOut."
    )

    content = "\n".join(lines) + "\n"
    content = content.replace("'", '"')

    if "--check" in sys.argv:
        current = OUT_PATH.read_text(encoding="utf-8") if OUT_PATH.exists() else ""
        if current != content:
            print("DRIFT: committed tokens differ from reference CSS")
            return 1
        print("OK: tokens match reference CSS")
        return 0

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text(content, encoding="utf-8")
    print(f"wrote {OUT_PATH} ({len(statics)} statics, {len(alias_names)} aliases)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
