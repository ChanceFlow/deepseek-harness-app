# Agent Note: CI code jobs hang — runner env injection and shared SDK lock

Status: implemented

## Problem

PR #118 (real on-device ASR) code gate failed repeatedly: the job either
was cancelled 31 s in with 1970 timestamps, or started and hung for tens of
minutes inside `flutter pub get --example`. Local `verify_all.py code` was
green (586 tests), so the defect was in the gitea runner container fleet,
not the change. Three distinct causes stacked:

1. **Unreachable proxy in runner env.** One runner container was launched
   with a proxy address on a VPN peer that had gone unreachable. The
   runner could not clone `actions/checkout`, so gitea cancelled the job
   ~31 s in with steps never starting (1970 timestamps).
2. **`container.env` is not a real config field.** Both runners' configs
   carried `container.env: {PUB_CACHE: ...}`. The runner daemon v0.6.1
   silently ignores unknown `container` keys (the generated default config
   has no
   `env` there), so job containers never inherited PUB_CACHE and always
   cold-downloaded the pub cache. With sherpa_onnx's ten platform bundles
   in the graph, that cold download now hangs through the LAN proxy.
3. **Capacity 4 deadlocks shared SDK.** One runner ran `capacity: 4`
   while the other runner's comment documents why it must be 1: Flutter's
   startup lock is a file lock on the SHARED toolcache SDK, so concurrent
   code jobs across any runners sharing the toolcache volume deadlock
   ("Waiting for another flutter command to release the startup lock").

## Decision

- **Relaunch the runner container pointing at the reachable proxy** in
  its container env, matching the working runner.
- **Move pub-cache injection from `container.env` to `runner.envs`**, the
  field the runner daemon v0.6.1 actually injects into job environments:
  `PUB_CACHE: /opt/hostedtoolcache/pub-cache`. Same fix applied to the
  other runner, whose `container.env` had likewise never taken effect.
- **Set both runners' `capacity: 1`** so the shared SDK startup lock
  serializes code jobs.
- **Warm the shared toolcache volume** by copying the host pub cache into
  it once (mount the host pub cache read-only into a root container and
  copy into the volume's pub-cache); all packages including the sherpa
  bundles now live on the volume.
- **Add a `flutter pub get` warm step to the CI code job** (ci.yaml).
  Even with a full pub cache, the flutter tool's bootstrap
  `pub get --example` contacts pub.dev for version checks, and one stalled
  proxy connection there burned the entire 600 s flutter-analyze gate
  timeout (the second pub get in the same job completed in seconds —
  proof the stall was a one-off network hang, not missing packages).
  Resolving dependencies in a dedicated step first keeps the gates'
  internal pub gets on the fast path.

## Alternatives considered

- **Chasing the hang with strace/job logs**: rejected — the job container
  lacks strace and gitea's action-log API paths 404'd; the config schema
  diff (`generate-config`) pinned the actual cause faster.
- **Per-job SDK volumes to allow capacity > 1**: rejected as future work —
  serialized jobs are the documented safe mode and the fleet is small.
- **Pinning PUB_CACHE via the workflow YAML**: rejected — the CI workflow
  is the repo's public surface and must not carry environment specifics
  that only this runner fleet needs.

## Consequences

Code gates run again: jobs are serialized, pub bootstrap is warm (fast,
no LAN-proxy cold downloads), and the runner fleet reaches GitHub through
the surviving proxy address. PR #118's code gate is the first to prove the
fix end to end. The `container.env` and `capacity: 4` mistakes are recorded
here so future runner edits use `runner.envs` and capacity 1. Internal
infrastructure details (proxy URLs, container names) are deliberately
omitted from this note — the repo history is public-clean by gate.