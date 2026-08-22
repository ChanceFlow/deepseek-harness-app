# Agent Note: One APK build channel — the mirror skips, the shadow delivers

Status: implemented

## Problem

The public repo ran its own copy of the release pipeline on every
mirror push and failed every time: the signing secrets live only on
the internal forge, so the GitHub job decoded an empty keystore and
Gradle rejected the signing step — eighteen consecutive red runs. The
shadow-release step on the internal pipeline meanwhile created the
GitHub releases but never attached the artifacts: it POSTed assets to
`api.github.com`, while GitHub serves release-asset uploads from
`uploads.github.com`, and the miss degraded to a non-fatal warning —
so the public Releases page showed empty releases for days, and the
stable `v0.0.1`/`v0.0.2` releases were lost outright.

## Decision

One build channel; the mirror is delivery, not production.
`.github/workflows/release-apk.yaml` gains a first-step gate: when
`ANDROID_KEYSTORE_B64` is absent the job prints where the artifacts
come from and skips every remaining step green, so the public Actions
page shows the real contract instead of a permanent failure. The gate
step carries the escape clause in its own header — adding the four
signing secrets turns the repo into an independent build channel, and
the shadow step must be removed in the same change so the two
pipelines do not fight over the rolling `dev` release. On the internal
side, the shadow step uploads assets to `uploads.github.com`, and a
failed upload now fails the run instead of warning: the artifact is
the point of the shadow release, and a soft warning is exactly how the
endpoint bug shipped empty releases unnoticed. The README (both
locales) states the channel split in place of the old "built by GitHub
Actions" claim. The lost stable GitHub releases are restored once from
the internal artifacts.

## Alternatives considered

- **Copy the signing secrets to GitHub**: turns the mirror into a
  second build channel — two builds per push, divergent build numbers
  on the two forges, and the release keystore duplicated onto a second
  platform. Rejected against the standing "Gitea Releases as the only
  APK channel" decision.
- **Delete the GitHub workflow file**: also stops the failures, but
  leaves nothing in-repo that documents the channel contract, and the
  re-enablement path becomes archaeology instead of four secrets.
- **Keep the warning-level asset failure**: the failure mode that hid
  the bug; delivery misses must surface as red runs.

## Consequences

- GitHub Actions shows CI green and Release APK green-skipped on every
  mirror push; artifacts on the public Releases page come from the
  shadow step with a hard delivery guarantee.
- The gate is self-documenting: the workflow header names both the
  mirror policy and the exact change needed to flip channels.
- The internal release body keeps its full changelog; the public
  shadow body stays sanitized (version metadata + hash only).
