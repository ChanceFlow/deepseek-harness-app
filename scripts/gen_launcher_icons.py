#!/usr/bin/env python3
"""Generate Android launcher icons from the dsh favicon glyph (black mark).

Source of truth:
  reference/deepseek-harness/apps/web/public/favicon.svg  (the dsh web
  product favicon: the dsh glyph in black #000 on light backgrounds).

The favicon is a single M/C/Z path (nonzero fill, absolute coordinates) in
a 50x50 viewBox.  This script flattens the beziers, scanline-fills with the
SVG nonzero winding rule at 4x supersampling, box-downsamples, and writes
RGBA PNGs:

  mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png
      glyph box at 80% of canvas, centered — 48/72/96/144/192 px
  mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher_foreground.png
      glyph box at 60% of canvas, centered (inside the 66/108 adaptive
      safe zone) — 108/162/216/324/432 px

Usage:
  python3 scripts/gen_launcher_icons.py             # write the ten PNGs
  python3 scripts/gen_launcher_icons.py --check     # exit 1 on drift
  python3 scripts/gen_launcher_icons.py --repo DIR  # write into DIR (dev)
"""

from __future__ import annotations

import math
import re
import struct
import sys
import zlib
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SOURCE_SVG = REPO / "reference/deepseek-harness/apps/web/public/favicon.svg"
RES_DIR = REPO / "flutter/app/android/app/src/main/res"

# legacy canvas px per density folder suffix
DENSITY_LEGACY = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}
FOREGROUND_MULT = 108 / 48  # adaptive canvas is 108dp, legacy 48dp (2.25x)

SUPERSAMPLE = 4  # box-filter factor; edges get 16-level antialiasing
TOL = 0.5 / SUPERSAMPLE  # flattening tolerance in supersampled pixels

Cubic = tuple[tuple[float, float], tuple[float, float], tuple[float, float], tuple[float, float]]


def parse_path(d: str) -> list[list[Cubic]]:
    """Parse an absolute M/C/Z path into per-subpath cubic segment lists.

    The favicon uses only absolute M, C, and Z commands.  Each C command is
    stored as (p0, c1, c2, p1); subpaths close implicitly back to their start.
    """
    toks = re.findall(r"[MCZ]|-?\d+\.?\d*(?:[eE][+-]?\d+)?", d)
    subpaths: list[list[Cubic]] = []
    i = 0
    while i < len(toks):
        t = toks[i]
        if t == "M":
            x, y = float(toks[i + 1]), float(toks[i + 2])
            i += 3
            cur = (x, y)
            subpaths.append([])
        elif t == "C":
            pts = [float(v) for v in toks[i + 1 : i + 7]]
            i += 7
            dest = (pts[4], pts[5])
            c1, c2 = (pts[0], pts[1]), (pts[2], pts[3])
            subpaths[-1].append((cur, c1, c2, dest))
            cur = dest
        elif t == "Z":
            i += 1  # close: polygon returns to its start when rasterizing
        elif t == "M":
            raise ValueError("relative M unsupported")  # unreachable
    return [sp for sp in subpaths if sp]


def flatten_curve(
    seg: Cubic,
    tol: float,
    out: list[tuple[float, float]],
    depth: int,
) -> None:
    """Append the cubic's polyline approximation, ending with its endpoint.

    Stop when the control points lie within `tol` of the chord p0-p3 AND
    project onto the chord segment: the curve then stays within the convex
    hull of the four points, which lies within `tol` (plus slack times the
    chord length) of the segment.
    """
    p0, p1, p2, p3 = seg
    if depth <= 0:
        out.append(p3)
        return
    dx, dy = p3[0] - p0[0], p3[1] - p0[1]
    length = math.hypot(dx, dy)
    if length > 0:
        d1 = abs(dx * (p1[1] - p0[1]) - dy * (p1[0] - p0[0])) / length
        d2 = abs(dx * (p2[1] - p0[1]) - dy * (p2[0] - p0[0])) / length
        t1 = ((p1[0] - p0[0]) * dx + (p1[1] - p0[1]) * dy) / (length * length)
        t2 = ((p2[0] - p0[0]) * dx + (p2[1] - p0[1]) * dy) / (length * length)
        if d1 < tol and d2 < tol and -1e-4 <= t1 <= 1.0001 and -1e-4 <= t2 <= 1.0001:
            out.append(p3)
            return
    # de Casteljau split at t = 0.5
    q0 = ((p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2)
    q1 = ((p1[0] + p2[0]) / 2, (p1[1] + p2[1]) / 2)
    q2 = ((p2[0] + p3[0]) / 2, (p2[1] + p3[1]) / 2)
    r0 = ((q0[0] + q1[0]) / 2, (q0[1] + q1[1]) / 2)
    r1 = ((q1[0] + q2[0]) / 2, (q1[1] + q2[1]) / 2)
    s = ((r0[0] + r1[0]) / 2, (r0[1] + r1[1]) / 2)
    flatten_curve((p0, q0, r0, s), tol, out, depth - 1)
    flatten_curve((s, r1, q2, p3), tol, out, depth - 1)


def flatten_subpaths(
    subpaths: list[list[Cubic]],
) -> list[list[tuple[float, float]]]:
    out: list[list[tuple[float, float]]] = []
    for sp in subpaths:
        flat = [sp[0][0]]
        for seg in sp:
            flatten_curve(seg, TOL, flat, 30)
        out.append(flat)
    return out


def render(
    subpaths: list[list[tuple[float, float]]],
    size: int,
    fraction: float,
) -> list[bytearray]:
    """Rasterize the glyph: glyph box `fraction`*size, centered, binary alpha.

    Returns RGBA rows (black glyph on transparent canvas) at supersampled
    resolution; downsample() box-filters them down afterwards.
    """
    scale = fraction * size / 50.0
    offset = (size - 50.0 * scale) / 2.0

    def tf(x: float, y: float) -> tuple[float, float]:
        return (x * scale + offset, y * scale + offset)

    edges: list[tuple[float, float, float, float, int]] = []
    for poly in subpaths:
        pts = [tf(x, y) for (x, y) in poly]
        n = len(pts)
        for i in range(n):
            x1, y1 = pts[i]
            x2, y2 = pts[(i + 1) % n]
            if y1 == y2:
                continue
            if y1 < y2:
                ymin, ymax, w = y1, y2, 1
            else:
                ymin, ymax, w = y2, y1, -1
            xat = x1 + (x2 - x1) * (ymin - y1) / (y2 - y1)
            slope = (x2 - x1) / (y2 - y1)
            edges.append((ymin, ymax, xat, slope, w))

    rows = [bytearray(size * 4) for _ in range(size)]
    for yy in range(size):
        yc = yy + 0.5  # pixel center; edges use the half-open range [ymin, ymax)
        xs: list[tuple[float, int]] = []
        for ymin, ymax, xat, slope, w in edges:
            if ymin <= yc < ymax:
                xs.append((xat + (yc - ymin) * slope, w))
        if not xs:
            continue
        xs.sort(key=lambda t: t[0])
        row = rows[yy]
        winding = 0
        prev_x = -1e18
        for x, w in xs:
            if winding != 0 and x > prev_x:
                lo = math.ceil(max(0.0, prev_x) - 0.5)
                hi = math.floor(min(float(size), x) - 0.5)
                for px in range(max(0, lo), min(size, hi + 1)):
                    row[px * 4 + 3] = 255
            winding += w
            prev_x = x
    return rows


def downsample(rows: list[bytearray], size: int) -> list[bytearray]:
    """Box-filter the SUPERSAMPLE x SUPERSAMPLE blocks down to final size."""
    out = [bytearray(size * 4) for _ in range(size)]
    step = SUPERSAMPLE
    for ty in range(size):
        row = out[ty]
        for tx in range(size):
            a = 0
            for sy in range(step):
                src = rows[ty * step + sy]
                base = tx * step * 4
                for sx in range(step):
                    if src[base + sx * 4 + 3]:
                        a += 1
            if a:
                i = tx * 4
                alpha = a * 255 // (step * step)
                row[i] = 0
                row[i + 1] = 0
                row[i + 2] = 0
                row[i + 3] = alpha
    return out


def png_bytes(w: int, h: int, rows: list[bytearray]) -> bytes:
    """Encode RGBA rows as a PNG (filter 0 per scanline)."""
    if len(rows) != h or any(len(r) != w * 4 for r in rows):
        raise ValueError("row geometry mismatch")

    def chunk(typ: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + typ
            + data
            + struct.pack(">I", zlib.crc32(typ + data) & 0xFFFFFFFF)
        )

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    raw = b"".join(b"\x00" + bytes(r) for r in rows)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def glyph_bbox(rows: list[bytearray], size: int) -> tuple[int, int, int, int]:
    """Bounding box (min_x, min_y, max_x, max_y) of opaque pixels."""
    xs: list[int] = []
    ys: list[int] = []
    for y, row in enumerate(rows):
        for x in range(size):
            if row[x * 4 + 3]:
                xs.append(x)
                ys.append(y)
    return (min(xs), min(ys), max(xs), max(ys))


def decode_png(data: bytes) -> tuple[int, int, list[bytearray]]:
    """Decode a PNG (any filter) into RGBA rows — validation only."""
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    pos = 8
    width = height = bitdepth = colortype = None
    idat = b""
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos : pos + 4])
        typ = data[pos + 4 : pos + 8]
        body = data[pos + 8 : pos + 8 + length]
        pos += 12 + length
        if typ == b"IHDR":
            width, height, bitdepth, colortype = struct.unpack(">IIBB", body[:10])
        elif typ == b"IDAT":
            idat += body
    if colortype != 6 or bitdepth != 8:
        raise ValueError(f"unsupported color type {colortype}")
    stride = width * 4
    raw = zlib.decompress(idat)
    rows: list[bytearray] = []
    prev = bytearray(stride)
    p = 0
    for _ in range(height):
        f = raw[p]
        p += 1
        line = bytearray(raw[p : p + stride])
        p += stride
        if f == 1:  # sub
            for i in range(4, stride):
                line[i] = (line[i] + line[i - 4]) & 0xFF
        elif f == 2:  # up
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif f == 3:  # average
            for i in range(stride):
                a = line[i - 4] if i >= 4 else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 0xFF
        elif f == 4:  # paeth
            for i in range(stride):
                a = line[i - 4] if i >= 4 else 0
                b = prev[i]
                c = prev[i - 4] if i >= 4 else 0
                pv = a + b - c
                pa, pb, pc = abs(pv - a), abs(pv - b), abs(pv - c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 0xFF
        elif f != 0:
            raise ValueError(f"unknown filter {f}")
        rows.append(line)
        prev = line
    return width, height, rows


def render_one(
    subpaths: list[list[tuple[float, float]]],
    size: int,
    fraction: float,
) -> bytes:
    rows = downsample(render(subpaths, int(size * SUPERSAMPLE), fraction), size)
    return png_bytes(size, size, rows)


def main(argv: list[str]) -> int:
    repo = REPO
    if "--repo" in argv:
        repo = Path(argv[argv.index("--repo") + 1]).resolve()
    svg = repo / "reference/deepseek-harness/apps/web/public/favicon.svg"
    res = repo / "flutter/app/android/app/src/main/res"
    if not svg.exists():
        print(f"missing {svg}", file=sys.stderr)
        return 1

    text = svg.read_text()
    m = re.search(r'<path[^>]*d="([^"]+)"', text)
    if not m:
        print(f"no <path> in {svg}", file=sys.stderr)
        return 1
    subpaths = flatten_subpaths(parse_path(m.group(1)))

    check = "--check" in argv
    failures = 0
    for folder, legacy in DENSITY_LEGACY.items():
        foreground = int(legacy * FOREGROUND_MULT)
        for name, size, fraction in (
            ("ic_launcher.png", legacy, 0.8),
            ("ic_launcher_foreground.png", foreground, 0.6),
        ):
            target = res / f"mipmap-{folder}" / name
            blob = render_one(subpaths, size, fraction)
            if check:
                if target.read_bytes() != blob:
                    print(f"drift: {target}", file=sys.stderr)
                    failures += 1
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(blob)
                print(f"wrote {target.relative_to(repo)} ({size} px)")
    if check:
        print("launcher icons: up to date" if not failures else "launcher icons: DRIFT")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))