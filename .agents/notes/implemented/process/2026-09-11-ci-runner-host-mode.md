# Agent Note: The forge CI runner is host execution

Status: implemented

## Problem

The workflows, the image recipe and the notes all described a runner that runs
each job in the prebaked `flutter-3.47-android` container: the `code` job's
comment claimed "the image carries Flutter 3.47.1 on PATH and has the LAN
egress proxy baked in", the `android` job restored `/root/.gradle/caches`, and
the release channel restored a Gradle/pub snapshot "because job containers are
ephemeral".

The registered runner is not that. `native-app-runner`
(`~/services/act-runner-app/config.yaml`, unit `act-runner-app.service`)
declares `flutter-android:host`, while the container label's runner — a Podman
quadlet naming `:docker://flutter-3.47-android` — never registers at all. Host
execution runs a job's steps on the runner
machine, with the toolchain in `runner.envs.PATH` (`~/tools/flutter-3.47.1`,
`~/android-sdk`, `~/tools/jdk-17.0.13+11`) and the host's own `~/.pub-cache`
and `~/.gradle` as the dependency caches.

Three facts followed from the mismatch, all measured 2026-09-11:

- `/root/.gradle/caches` and `/root/.pub-cache` do not exist under the runner
  user's `$HOME`, so the `android` job's cache step never hit.
- The release channel's restore of the host's real caches moved 2.6 GB in 100 s
  only to overwrite live directories with an older snapshot and report
  `not saving cache` — host caches already persist between jobs.
- The toolchain pin is a text contract: `verify_toolchain_pin.py` reads
  `flutter-version:` out of `.gitea/workflows/ci.yaml`, while the binary comes
  from the runner's PATH, so a host `flutter upgrade` moves CI off the pin
  while every home still agrees.

Throughput: `runner.capacity: 2` against three required jobs, so they time-share
two slots — observed concurrency is 2 in eight of nine runs and 1 in the ninth
(908 s). Eight measured runs span 280–908 s (median 328 s), against 246 s
(median, n=7) for the same workflows on GitHub-hosted runners, and the release
channel's 1834 s build holds one slot on every `master` push.

## Decision

- **The workflows state the host path.** `.gitea/workflows/*.yaml` name host
  execution as the registered contract, keep the container-schema label as the
  documented alternative, and say what picks between them: the label's
  `docker://`.
- **No cache step on the host path.** `actions/cache` leaves
  `.gitea/workflows/ci.yaml`'s `android` job and
  `.gitea/workflows/release-apk.yaml` entirely; `~/.gradle` and `~/.pub-cache`
  are the runner machine's own persistent directories. It returns with the
  container label, whose job container starts from the image and loses every
  task output at teardown.
- **The pin is asserted, not assumed.** The `code` job's first step derives the
  version from this file's `flutter-version:` line and fails the job when
  `flutter --version` disagrees.
- **Superseded runs are cancelled.** `ci.yaml` declares
  `concurrency: ci-${{ github.ref }}` with `cancel-in-progress: true` on both
  forges, matching what `release-apk.yaml` already does for its own groups.

## Alternatives considered

- **Bring the container label back with its caches.** Rejected as this change's
  subject: it is a separate decision with its own costs — a 2.6 GB / 100 s
  restore, and a `docker/` recipe and quadlet that are gitignored and drift
  unbuilt. Host execution also measures better where it counts:
  `compileDebugKotlin` is 95 s against 205 s on GitHub's cold runner.
- **Point the host runner at the local reference mirror**
  (`url.file:///…/reference.git.insteadOf`, as the container config does).
  Rejected for now: the mirror holds `a98949c6e6`, not the pinned `fb2c4b9e`,
  so the redirect fails every job at checkout, and nothing refreshes it.
- **`cancel-in-progress` only on pull requests.** Rejected: a cancelled
  `master` run loses no verdict — the next merge's run covers its tree, and the
  release channel re-runs the whole suite itself before it signs an APK.
- **Fix the caches and leave the comments.** Rejected: the runner contract is
  what the next session reads before it touches capacity, a label or a cache
  step.

## Consequences

A job's toolchain and caches come from the machine it runs on, and the files say
so. The [kotlin compile gate note](2026-09-03-kotlin-compile-gate.md) carries
the corrected facts for the `android` job. Raising `runner.capacity` past 2
stays a separate decision: one job's peak measured 9.9 GB against the unit's
12 GB `MemoryMax`, so a third slot trades queue time for cgroup OOM.
