# Agent Note: Release APK pipeline runs one-at-a-time, latest wins

Status: implemented

## Problem

The release pipeline fans out on every master push and every `v*` tag push.
On 2026-08-29 a master merge (#127) and the v0.0.4 tag push landed within
seconds of each other, queueing two full Gradle builds of adjacent commits
(#714 dev + #715 stable) on a shared, capacity-limited runner pool — while
unrelated repos' builds (EasyTier) were also queuing behind them. The dev
channel is rolling and a stable cut is re-runnable, so every superseded build
is pure waste and runner starvation.

## Decision

Declare workflow-level concurrency on `release-apk.yaml`:

```yaml
concurrency:
  group: release-apk-${{ github.ref_type == 'tag' && 'stable' || 'latest' }}
  cancel-in-progress: true
```

- All branch builds (the rolling dev channel) share one group: a newer push
  cancels an older queued/running build — latest master always wins.
- Tag builds get their own group so a merge landing mid-release cannot
  cancel a stable cut in flight (the previous note's caveat is designed out).
- Within the tag group, a superseding tag push still cancels the older tag
  build (two tags in quick succession → only the newest ships).

## Alternatives considered

- **One global group for all runs**: rejected — a routine master merge would
  cancel a stable release mid-publish, risking a half-attached GitHub release
  that needs manual cleanup and a re-tag.
- **A first-step "am I superseded?" guard script**: rejected — it can only
  skip queued runs; it cannot abort an already-running Gradle build, which is
  the expensive case.
- **Rely on the observed auto-cancel of #714**: rejected — Gitea cancelled it
  without any declared group; behavior without an explicit concurrency block
  is not a contract and cannot be depended on across upgrades.

## Consequences

Master pushes during a burst start at most one dev build; the dev tag
advances only from the newest commit. Stable and dev channels stay isolated
from each other's cancellations. The EasyTier-style shared-pool starvation is
reduced because fewer long builds occupy the flutter-android runner.
