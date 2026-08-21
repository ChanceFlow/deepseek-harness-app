#!/usr/bin/env python3
"""Gate: one Flutter version string across every file that pins it.

The pin lives in CI, the aggregate runner, the runner image, and the
instruction corpus, so a version bump that misses one home leaves a document
telling the next session to install a toolchain CI does not run.
`.gitea/workflows/ci.yaml` is the source: whatever `flutter-version:` says
there, every home in gates_manifest.json (`toolchain.homes`) must agree.

Each home is read for versioned Flutter references (`flutter-3.47.1`,
`Flutter 3.47.1`) and each one must equal the pin — a home needs at least one,
and a stale copy beside a fresh one fails the same way a missed home does.
Two-component family names (`Flutter 3.47`, the `flutter-3.47-android` image
tag) are not pins and are ignored. Ledgers and dated analyses that record an
older version as history stay out of `homes`.

Exit code 0 = every home agrees with the CI pin, 1 = violations found.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPO: Path = Path(__file__).resolve().parent.parent
MANIFEST: Path = REPO / "scripts" / "gates_manifest.json"

def check() -> int:
    manifest: dict[str, object] = json.loads(MANIFEST.read_text(encoding="utf-8"))
    config: dict[str, object] = manifest["toolchain"]  # type: ignore[assignment]
    source: Path = REPO / str(config["source"])
    pattern: re.Pattern[str] = re.compile(str(config["pattern"]))
    occurrence: re.Pattern[str] = re.compile(str(config["occurrence_pattern"]))
    homes: list[str] = list(config["homes"])  # type: ignore[arg-type]

    if not source.exists():
        print(f"TOOLCHAIN-PIN GATE: source {config['source']} is missing")
        return 1
    match: re.Match[str] | None = pattern.search(source.read_text(encoding="utf-8"))
    if match is None:
        print(f"TOOLCHAIN-PIN GATE: {config['source']} has no match for {config['pattern']}")
        return 1
    pin: str = match.group(1)

    violations: list[str] = []
    for home in homes:
        path: Path = REPO / home
        if not path.exists():
            violations.append(f"{home}: pinned file is missing — remove or fix the manifest entry")
            continue
        found: list[str] = []
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            for version in occurrence.findall(line):
                found.append(version)
                if version != pin:
                    violations.append(f"{home}:{number}: names Flutter {version}, CI pins {pin}")
        if not found:
            violations.append(f"{home}: names no Flutter version — remove or fix the manifest entry")

    if violations:
        print(f"TOOLCHAIN-PIN GATE: violations found (CI pins {pin}):")
        for violation in violations:
            print(f"  {violation}")
        return 1
    print(f"TOOLCHAIN-PIN GATE: CLEAN ({pin} in {len(homes)} homes)")
    return 0


if __name__ == "__main__":
    sys.exit(check())
