# Agent Note: The machine keeps no Flutter toolchain of its own

Status: implemented

## Problem

Moving CI into the container image took the gates off the runner machine's
toolchain but left the toolchain installed, and two consumers still used it by
name.

Anything that resolved `flutter` or `dart` from PATH did. `~/.local/bin/dart`
was a symlink into `~/tools/flutter-3.47.1/bin/cache/dart-sdk`, and that name is
what the Dart language server runs: DSH's editing support is `command: dart`,
`args: ['language-server']`, with its index in `~/.dartServer` — 2.8 GB, last
written minutes before this change. Deleting the toolchain would have taken the
editor's Dart support with it. Interactive sessions also ran gates and tests
from that PATH, so the machine and CI could still disagree about the toolchain.

Nothing held the workflows to the container label either. A job naming a host
label looks exactly like one naming a container label — the schema lives in the
runner's configuration, outside the repository — which is how CI reached the
machine's toolchain in the first place.

## Decision

- **The toolchain is deleted**: `~/tools/flutter-*`, `~/tools/jdk-*`,
  `~/tools/gradle-*`, `~/android-sdk`, `~/.gradle`, `~/.pub-cache` and
  `~/.dartServer` — 19 GB, leaving podman, the repository and the image.
- **Two entry points replace it.**
  [scripts/container.sh](../../../../scripts/container.sh) runs any command in
  the image with the repository mounted at its own path and the working
  directory preserved; [scripts/flutter.sh](../../../../scripts/flutter.sh) is
  the same thing rooted at the pub workspace.
- **PATH itself is served from the image.** `~/.local/bin/flutter` and
  `~/.local/bin/dart` are shims (`~/.local/bin/container-tool`) that run the
  named tool in the image, mounting the project tree — or, outside it, the
  caller's own directory. That is what keeps the Dart language server working
  without touching its configuration, and it puts the analysis index in a podman
  volume instead of the home directory.
- **A gate holds CI to the container.**
  [scripts/verify_ci_container_jobs.py](../../../../scripts/verify_ci_container_jobs.py)
  reads the label from `gates_manifest.json` (`ci`) and fails when a job in a
  listed workflow names any other one, reporting the file and the line.

## Alternatives considered

- **Keep the toolchain for humans and delete only what CI used.** Rejected: it is
  the same bytes, and a machine that can build locally is a machine whose build
  can disagree with CI's.
- **A per-repository wrapper only.** Rejected: every stray `flutter` invocation —
  a script, a Makefile, the language server — would resolve to nothing.
- **Pointing the language-server command at podman inside the DSH profile.**
  Rejected: the shim keeps `command: dart` true for every consumer, and the
  profile stays a plain command list.
- **Keeping `~/.dartServer`.** Rejected: that index belongs in the image's
  volume, and a home directory that accumulates it is what this change removes.

## Consequences

The first Dart analysis after this change re-indexes into the new volume. The
shims need podman on PATH and the image present — both said in their own error
paths — and they mount the project tree, so a tool run outside it sees only its
own directory. A branch cut before the container label existed still asks for
the host label; rebasing it onto `master` is what picks the container up, and
its jobs then resolve `flutter` through the shim rather than a toolchain that is
no longer installed.
