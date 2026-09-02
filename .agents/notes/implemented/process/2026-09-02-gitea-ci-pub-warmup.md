# Agent Note: the Gitea CI code job warms the pub cache before the gates

Status: implemented

## Problem

Every `code` job on the forge since the #150 merge failed only on the
`flutter-analyze` gate — the full suite (861 tests), format, imports, and
unused-deps stayed green, and the analyzer died inside its implicit
`Resolving dependencies...` exactly at the 600s gate timeout, then emitted
59 buffered `Failed to resolve package URI "package:flutter_lints/flutter.yaml"`
warnings. Nine seconds later the `flutter test` gate's own resolution
succeeded. The `.gitea/workflows/ci.yaml` `code` job runs checkout and
`verify_all.py code` with no resolution step of its own, so the first gate
performs the workspace's first pub resolve; when the shared pub cache is
contended (a release build on the same host) or the proxy flakes, that
resolve stalls past any ceiling — raising the timeout to 1800s only bought
a longer hang. The GitHub mirror has carried a *Warm pub cache* step for
exactly this failure mode; the Gitea mirror lost it.

## Decision

`.gitea/workflows/ci.yaml`'s `code` job gains a *Warm pub cache* step
(`cd flutter && flutter pub get`) between checkout and the gate aggregate,
mirroring the GitHub workflow. Resolution happens outside any gate timeout,
fails loud on its own step when the proxy or cache is sick, and leaves the
analyze gate a warm package config (the last healthy run measured it at
163s). The gate's 600s ceiling stays as the analyzer-only budget.

## Alternatives considered

- **Raise the analyze gate ceiling**: rejected as the fix (attempted in
  #154) — the hang is a stalled resolve, not a slow analyzer; 1800s timed
  out the same way. A larger ceiling remains reasonable as a separate
  knob but cures nothing here.
- **Run `pub get` inside the analyze gate's cmd**: rejected — it buries a
  resolution failure inside the gate whose timeout then masks it, and
  every other gate would re-resolve or depend on gate order.
- **Fix the runner's pub cache/proxy health**: necessary for the release
  build's own failure, but the workflow should not assume an idle host;
  the warm-up makes the code job correct under contention.

## Consequences

A `code` job resolves dependencies once, on its own step, with its own
failure surface; analyze, format, and tests consume the warm package
config. When the shared pub cache or the proxy is sick, the job now fails
in the warm-up step with pub's own diagnostic instead of a 600s analyzer
timeout. The GitHub mirror already had the step; the two mirrors carry the
same job shape again.
