#!/usr/bin/env python3
"""Gate: toolchain jobs run in the container image, never on a runner machine.

A Gitea label decides where a job runs, and the schema behind the label name
(`host` or `docker://<image>`) is registered in the runner's own configuration —
outside this repository. A workflow naming a host label therefore looks exactly
like one naming a container label, and the toolchain can move onto whatever
machine the runner is installed on without a single error: that is how CI ended
up building on a developer's `~/tools`, `~/android-sdk` and `~/.gradle`, and why
a container job once inherited that machine's PATH and lost its own `node`
(run 1410).

The label a toolchain job must use is declared in `gates_manifest.json` (`ci`),
and every workflow listed there is held to it. The runner configuration owns
the label-to-schema mapping; this file owns the assertion that the mapping is
still the container one.

The label's *name* is only half of it. What the label resolves to — the image
reference in the runner's configuration — is equally outside the repository, so
the same manifest declares the build it expects (`ci.image_tag`), the image
bakes its own build name as `DSH_CI_IMAGE_VERSION`, and every toolchain job
compares them before running a gate. A job without that comparison is a job
that would not notice a label repointed at another image, so this file holds
each of them to carrying it.

Exit code 0 = every job in the listed workflows names the container label and
asserts the pinned image build, 1 = violations found.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPO: Path = Path(__file__).resolve().parent.parent
MANIFEST: Path = REPO / "scripts" / "gates_manifest.json"

_RUNS_ON: re.Pattern[str] = re.compile(r"^\s*runs-on:\s*(\S+)\s*$")
# The step name is the anchor: it is what a reader greps for, and what the
# workflows carry one of per toolchain job.
_IDENTITY_STEP = "Assert the job runs the pinned image build"
# A tag that moves under a pin is not a pin.
_MOVING_TAGS = {"latest", "dev", "unknown", ""}


def check() -> int:
    manifest: dict[str, object] = json.loads(MANIFEST.read_text(encoding="utf-8"))
    config: dict[str, object] = manifest["ci"]  # type: ignore[assignment]
    expected: str = str(config["container_label"])
    workflows: list[str] = list(config["workflows"])  # type: ignore[arg-type]
    image_tag: str = str(config.get("image_tag", "")).strip()

    violations: list[str] = []
    if image_tag in _MOVING_TAGS:
        violations.append(
            f"scripts/gates_manifest.json: ci.image_tag is {image_tag!r} — the manifest must pin the "
            f"image build a toolchain job asserts, and a moving name pins nothing"
        )

    jobs = 0
    for rel in workflows:
        path: Path = REPO / rel
        if not path.exists():
            violations.append(f"{rel}: listed workflow is missing — remove or fix the manifest entry")
            continue
        found = 0
        asserted = 0
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            if line.lstrip().startswith("#"):
                continue
            if _IDENTITY_STEP in line:
                asserted += 1
            match: re.Match[str] | None = _RUNS_ON.match(line)
            if match is None:
                continue
            found += 1
            label = match.group(1).strip("\"'")
            if label != expected:
                violations.append(
                    f"{rel}:{number}: runs-on {label!r} — a toolchain job runs in the container "
                    f"image, and the label this repository registers for that is {expected!r}"
                )
        if found == 0:
            violations.append(f"{rel}: names no runs-on label — the job shape this gate guards is gone")
        elif asserted < found:
            violations.append(
                f"{rel}: {found} job(s) on {expected!r} but {asserted} of them assert the pinned image "
                f"build — a job that does not compare DSH_CI_IMAGE_VERSION with ci.image_tag cannot "
                f"notice a label repointed at another image"
            )
        jobs += found

    if violations:
        print("CI-CONTAINER-JOBS GATE: violations found:")
        for violation in violations:
            print(f"  {violation}")
        return 1
    print(
        f"CI-CONTAINER-JOBS GATE: CLEAN ({jobs} jobs in {len(workflows)} workflows, "
        f"label {expected}, image build {image_tag})"
    )
    return 0


if __name__ == "__main__":
    sys.exit(check())
