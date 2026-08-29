# Agent Note: Mirror pipelines run on the prebaked local image

Status: implemented

## Problem

`publish-github.yaml`, `publish-gitlab.yaml`, and `reconcile-github.yaml`
declared `runs-on: ubuntu-latest` with no container pin. On 2026-08-26 the
runner had no `docker.gitea.com/runner-images:ubuntu-latest` image cached and
the pull timed out (`Client.Timeout exceeded while awaiting headers`), so
three consecutive mirror runs died at container start — before a single
workflow line executed. GitHub stayed silently behind for three days until
the push of #126; reconcile caught the drift (alert issue #125) but its own
alerting chain had also been starved by the same missing image.

## Decision

Pin all three mirror jobs to the same runner and prebaked container image
`release-apk.yaml` already relies on:

- `runs-on: flutter-android` + `container: image: flutter-3.47-android:latest`

The image ships git, python3, curl, and node (what checkout@v4 needs) and is
guaranteed present on the runner host, so a mirror run no longer depends on
docker.gitea.com availability. The image is heavier than ubuntu-latest, but
the mirror jobs are few and network-bound; pull-freedom beats image weight.

## Alternatives considered

- **Pre-cache ubuntu-latest on the runner host**: rejected — the cache can be
  pruned by any docker housekeeping run, and the failure was invisible for
  three days; the fix must live in the committed workflow, not in host state.
- **Add retry around image pulls**: not possible from workflow YAML — the pull
  happens inside act before any step can run, which is exactly where it hung.

## Consequences

All Gitea workflows (CI, release, mirrors, reconcile) run on the
flutter-android runner with local images only; the docker.gitea.com dependency
disappears from the pipeline. Reconcile alerting is now as durable as the
release pipeline it watches.
