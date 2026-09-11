# Agent Note: The forge CI runs jobs in an image built from upstream releases

Status: implemented

## Problem

The prebaked-image design survived the Docker→Podman migration only as a
quadlet that was not running: the image had been reclaimed with the old store,
and the runner that stayed online declared `flutter-android:host`. Jobs ran on
the runner machine with its `~/tools` toolchain and the machine's own
`~/.gradle` — and nothing failed: a label switches execution mode silently.
Measured 2026-09-11: 16 GB of JDK, Flutter, Android SDK, pub, Gradle and
`actions/cache` state on a host that also runs the forge, a database, a proxy and
interactive sessions; a 2.6 GB / 100 s `actions/cache` restore that overwrote
live caches and reported `not saving cache`; and a toolchain pin whose source is
a comment in [ci.yaml](../../../../.gitea/workflows/ci.yaml) while the binary
came from the machine's PATH.

Verdicts inherited the machine's load too. The same `code` job measured 261 s
idle and 887 s under load, and two runs failed on two different single tests — a
debounce test asserting one catalog re-pull against two — both re-running green.

Attaching a container label to that runner exposed the hazard directly:
`runner.envs.PATH` names the runner machine's toolchain, so the job container got
a PATH with no Node on it and every `uses:` step died with exit 127 (run 1410),
while `flutter` and `java` were absent.

## Decision

- **Container execution owns the merge gate and the release channel.**
  `runs-on: flutter-android-ctr` is registered as
  `docker://localhost/flutter-3.47-android:latest`, so the label itself puts the
  job in the image. The `localhost/` prefix is load-bearing: a bare tag resolves
  to docker.io and the runner tries to pull it.
- **That label has its own runner process** (capacity 1) so it inherits none of
  the host runner's `runner.envs`. Host labels stay for the mirror jobs, which
  need only git, python3 and curl.
- **The image is built from upstream releases, not from the machine**
  ([docker/flutter-android.Dockerfile](../../../../docker/flutter-android.Dockerfile)):
  OpenJDK 17 in a stage, the Android SDK via Google's command-line tools, Flutter
  from the pinned upstream tarball. The only host input is a git archive of the
  committed `flutter/` tree, and the Android stage derives from the JDK stage
  because `sdkmanager` is a Java program.
- **Layer order is the cache.** Manifests and `pubspec.lock` resolve in their own
  layer, the sources land after them, and the warmup build's Gradle build-cache
  snapshot rides the image. No `actions/cache`, no cache server, no `~/.gradle`
  or `~/.pub-cache` to provision.
- **The job container is bounded** (`--memory=9g --memory-swap=11g`,
  `--shm-size=1g`) and `gradle.properties` asks Gradle and its Kotlin daemon for
  3 GB each instead of 8: the runner's cgroup does not cover the sibling
  container it creates, a 64 MB `/dev/shm` kills the Gradle daemon outright, and
  two 8 GB daemons are what took the host down.
- **The pin is asserted, not assumed** — the `code` job reads `flutter-version:`
  out of this workflow and fails when the image's `flutter --version` disagrees.
- **Superseded runs are cancelled** (`concurrency: ci-${{ github.ref }}`), which
  matters on a capacity-1 pool the release channel shares.
- **docker/ is versioned.** The recipe is the container CI contract; the internal
  addresses that kept it untracked are build arguments now.

Evidence: run 1411 on the disposable `container-smoke` label reports the job
container's PATH as the image's own (no `/home/`, Node found), the runner
machine's toolchain invisible inside, and checkout from the forge plus egress to
github.com and pub.dev green.

## Alternatives considered

- **One runner for both schemas, `container.envs` overriding the host path.**
  Rejected: `runner.envs` reached the container first (run 1410), and a variable
  meaning two things in two execution modes is a trap.
- **A host label with the toolchain path dropped from `runner.envs`.** Rejected:
  it breaks the host jobs that still serve the mirror workflows, and leaves CI on
  the machine's own JDK, Flutter and Android SDK.
- **`actions/cache` for `~/.gradle/caches/build-cache-1`.** Rejected for now: the
  image carries that snapshot, a container-side restore needs the cache server
  pinned and reachable from the container network, and a rebuild refreshes it.
- **Pointing the submodule at the local reference mirror.** Deferred: the mirror
  had frozen on a local clone's commit.
- **Tolerating the unreachable Microsoft apt index.** Rejected: `|| true` would
  mask a real breakage; the stage drops that source list.

## Consequences

The runner machine needs podman, the repo and a socket — and its interactive
sessions have to reach Flutter through the image too, or they re-install what
this change removes. `~/tools/flutter-3.47.1`, `~/tools/jdk-*`, `~/android-sdk`,
`~/.gradle`, `~/.pub-cache` and the `~/.cache/actcache` store become deletable
once the container label is the only path. A stale image silently ages its
build-cache snapshot, so the image is rebuilt by hand. The host runner's
`runner.envs` still names the machine's toolchain until its labels have no
consumer.
