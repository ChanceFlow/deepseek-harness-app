#!/usr/bin/env python3
"""Render the design shots and publish them as a review page.

The shots are golden-file outputs of `flutter/app/test/design/`, always
written with --update-goldens: they are renders to look at, never a
regression baseline, so nothing here can fail on a pixel.

    python3 scripts/render_design.py                 # render only
    python3 scripts/render_design.py --publish       # render + publish
    python3 scripts/render_design.py --publish --baseline
    python3 scripts/render_design.py --publish --notes /tmp/pass.md

--baseline rotates what is already published into the "before" column, so
the page shows this pass against the last one. Run it once per pass,
before the first publish of that pass; a second run would compare the pass
against itself.

Publish target: $DSH_DESIGN_WWW (default ~/services/gitea/apk-www/design),
served at $DSH_DESIGN_URL (default http://127.0.0.1:8899/design/).

The harness skips itself unless this script sets $DSH_DESIGN_SHOTS, so a
plain `flutter test` never depends on host fonts or on the gitignored PNGs.
"""

from __future__ import annotations

import argparse
import html
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
FLUTTER_DIR = REPO / "flutter"
TEST_DIR = Path("app/test/design")
SHOTS = FLUTTER_DIR / "app" / "test" / "design" / "shots"
CATALOG = FLUTTER_DIR / "app" / "test" / "design" / "design_shots_test.dart"

DEFAULT_WWW = Path.home() / "services" / "gitea" / "apk-www" / "design"
DEFAULT_URL = "http://127.0.0.1:8899/design/"

# Widget tests get no font fallback chain, so a host with no Han face
# renders every Chinese string as a rectangle. The harness looks here
# first; --fetch-fonts fills it without touching the system font dirs.
FONT_CACHE = Path.home() / ".cache" / "dsh-design" / "fonts"
CJK_FONT = FONT_CACHE / "NotoSansSC.ttf"
CJK_URL = (
    "https://github.com/google/fonts/raw/main/ofl/notosanssc/"
    "NotoSansSC%5Bwght%5D.ttf"
)


def flutter_bin() -> str:
    """The pinned toolchain first, then whatever is on PATH."""
    pinned = Path.home() / "tools" / "flutter-3.47.1" / "bin" / "flutter"
    if pinned.exists():
        return str(pinned)
    found = shutil.which("flutter")
    if found is None:
        sys.exit("flutter not found: install the pin or put it on PATH")
    return found


def fetch_fonts() -> None:
    """One-time, ~17MB, into the user cache. Skipped once present."""
    if CJK_FONT.exists():
        print(f"Han face already cached at {CJK_FONT}")
        return
    FONT_CACHE.mkdir(parents=True, exist_ok=True)
    print(f"fetching Noto Sans SC -> {CJK_FONT}")
    result = subprocess.run(
        ["curl", "-sSL", "--fail", "-o", str(CJK_FONT), CJK_URL], check=False
    )
    if result.returncode != 0:
        CJK_FONT.unlink(missing_ok=True)
        sys.exit(
            "fetch failed. Any Han .ttf under "
            f"{FONT_CACHE} named NotoSansSC.ttf works instead."
        )


def shot_names() -> list[str]:
    """Shot names as the Dart catalog declares them, in order."""
    text = CATALOG.read_text(encoding="utf-8")
    return re.findall(r"DesignShot\(\s*name: '([^']+)'", text)


def render(only: str | None) -> None:
    command = [
        flutter_bin(),
        "test",
        "-t",
        "design",
        "--update-goldens",
        str(TEST_DIR),
    ]
    if only is not None:
        command[-1:-1] = ["--plain-name", only]
    print("$ " + " ".join(command))
    # The harness skips itself unless this is set, so no other run of the
    # suite — CI's included — depends on host fonts or on PNGs that are
    # gitignored.
    environment = {**os.environ, "DSH_DESIGN_SHOTS": "1"}
    result = subprocess.run(
        command, cwd=FLUTTER_DIR, env=environment, check=False
    )
    if result.returncode != 0:
        sys.exit("render failed — the harness threw before it wrote its PNGs")


def rotate(www: Path) -> None:
    """Published 'now' becomes 'before'; a first publish has neither."""
    now, before = www / "now", www / "before"
    if not now.is_dir():
        print("no published set yet — this pass has no before column")
        return
    if before.is_dir():
        shutil.rmtree(before)
    shutil.move(str(now), str(before))


def publish(www: Path, url: str, notes: Path | None) -> None:
    now = www / "now"
    now.mkdir(parents=True, exist_ok=True)
    for png in sorted(SHOTS.glob("*.png")):
        shutil.copy2(png, now / png.name)
    (www / "index.html").write_text(page(www, notes), encoding="utf-8")
    print(f"published {len(list(now.glob('*.png')))} shots -> {url}")
    if www != DEFAULT_WWW:
        print(f"(written to {www}, which $DSH_DESIGN_URL may not serve)")


def pairs(www: Path) -> list[tuple[str, str | None, str]]:
    """(title, before, now) per rendered shot, in catalog order."""
    order = shot_names()

    def rank(stem: str) -> tuple[int, int]:
        name, _, mode = stem.rpartition("_")
        index = order.index(name) if name in order else len(order)
        return (index, 0 if mode == "light" else 1)

    out: list[tuple[str, str | None, str]] = []
    for png in sorted((www / "now").glob("*.png"), key=lambda p: rank(p.stem)):
        before = www / "before" / png.name
        name, _, mode = png.stem.rpartition("_")
        title = f"{name.replace('-', ' ')} · {mode}"
        out.append(
            (
                title,
                f"before/{png.name}" if before.exists() else None,
                f"now/{png.name}",
            )
        )
    return out


def notes_html(source: Path | None) -> str:
    """A deliberately small markdown subset: `##` headings, `-` bullets,
    `**bold**`, `` `code` ``, and paragraphs. The notes are the reviewer's
    reading of the pass, not a document."""
    if source is None:
        return ""
    blocks: list[str] = []
    bullets: list[str] = []

    def inline(text: str) -> str:
        escaped = html.escape(text)
        escaped = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", escaped)
        return re.sub(r"`([^`]+)`", r"<code>\1</code>", escaped)

    def flush() -> None:
        if bullets:
            items = "".join(f"<li>{inline(b)}</li>" for b in bullets)
            blocks.append(f"<ul class='rest'>{items}</ul>")
            bullets.clear()

    for line in source.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped:
            flush()
        elif stripped.startswith("## "):
            flush()
            blocks.append(f"<h2>{inline(stripped[3:])}</h2>")
        elif stripped.startswith("- "):
            bullets.append(stripped[2:])
        else:
            flush()
            blocks.append(f"<p class='lead'>{inline(stripped)}</p>")
    flush()
    return "\n".join(blocks)


def page(www: Path, notes: Path | None) -> str:
    figures: list[str] = []
    for title, before, now in pairs(www):
        safe = html.escape(title)
        if before is None:
            figures.append(
                f"<h2>{safe}</h2><div class='single'>"
                f"<figure><figcaption><span class='tag now'>this pass</span>"
                f"</figcaption><img src='{now}' alt='{safe}'></figure></div>"
            )
            continue
        figures.append(
            f"<h2>{safe}</h2><div class='pair'>"
            f"<figure><figcaption><span class='tag'>before</span>"
            f"</figcaption><img src='{before}' alt='{safe} before'></figure>"
            f"<figure><figcaption><span class='tag now'>this pass</span>"
            f"</figcaption><img src='{now}' alt='{safe} now'></figure></div>"
        )
    return TEMPLATE.format(notes=notes_html(notes), figures="\n".join(figures))


TEMPLATE = """<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>DSH Mobile · design review</title>
<style>
  :root {{
    color-scheme: light dark;
    --bg: #faf8ff; --fg: #1b1b22; --muted: #55535f;
    --line: #dedae8; --card: #fff; --seed: #4d6bfe;
  }}
  @media (prefers-color-scheme: dark) {{
    :root {{
      --bg: #131318; --fg: #e6e1e9; --muted: #c9c4d2;
      --line: #322f3a; --card: #1c1b21;
    }}
  }}
  * {{ box-sizing: border-box; }}
  body {{
    margin: 0; padding: 48px 24px 96px; background: var(--bg); color: var(--fg);
    font: 16px/1.6 -apple-system, "Segoe UI", Roboto, "Noto Sans SC", sans-serif;
  }}
  main {{ max-width: 1080px; margin: 0 auto; }}
  h1 {{ font-size: 30px; letter-spacing: -0.4px; margin: 0 0 8px; }}
  h2 {{
    font-size: 19px; letter-spacing: -0.2px; margin: 56px 0 4px;
    padding-top: 24px; border-top: 1px solid var(--line);
  }}
  p.lead {{ color: var(--muted); margin: 0 0 12px; }}
  .pair {{ display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin-top: 16px; }}
  .single {{ display: grid; grid-template-columns: 1fr; gap: 20px; max-width: 520px; margin-top: 16px; }}
  figure {{ margin: 0; }}
  figcaption {{ font-size: 13px; color: var(--muted); margin-bottom: 8px; }}
  .tag {{
    font-size: 11px; letter-spacing: 0.4px; text-transform: uppercase;
    padding: 2px 8px; border-radius: 999px; border: 1px solid var(--line);
  }}
  .tag.now {{ border-color: var(--seed); color: var(--seed); }}
  img {{
    width: 100%; display: block; border: 1px solid var(--line);
    border-radius: 14px; background: var(--card);
  }}
  ul.rest {{ color: var(--muted); padding-left: 20px; }}
  ul.rest li {{ margin-bottom: 6px; }}
  code {{
    font: 13px/1.4 ui-monospace, "SF Mono", Menlo, monospace;
    background: color-mix(in oklab, var(--fg) 8%, transparent);
    padding: 1px 5px; border-radius: 5px;
  }}
  @media (max-width: 720px) {{ .pair {{ grid-template-columns: 1fr; }} }}
</style>
</head>
<body>
<main>
  <h1>DSH Mobile · design review</h1>
  {notes}
  {figures}
</main>
</body>
</html>
"""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--list", action="store_true", help="name the shots")
    parser.add_argument(
        "--fetch-fonts",
        action="store_true",
        help="cache a Han face so Chinese renders as text, not boxes",
    )
    parser.add_argument("--only", help="render one shot (plain-name match)")
    parser.add_argument("--publish", action="store_true")
    parser.add_argument(
        "--baseline",
        action="store_true",
        help="rotate the published set into the before column first",
    )
    parser.add_argument("--notes", type=Path, help="markdown read into the page")
    parser.add_argument("--www", type=Path, help="publish directory")
    args = parser.parse_args()

    if args.list:
        for name in shot_names():
            print(name)
        return 0

    if args.fetch_fonts:
        fetch_fonts()
        return 0

    www = args.www or Path(os.environ.get("DSH_DESIGN_WWW", DEFAULT_WWW))
    url = os.environ.get("DSH_DESIGN_URL", DEFAULT_URL)

    render(args.only)
    if not args.publish:
        print(f"rendered -> {SHOTS}")
        return 0
    # Rotate only once the render has produced something to replace it with.
    if args.baseline:
        rotate(www)
    publish(www, url, args.notes)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
