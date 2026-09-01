# Agent Note: Shadow-release asset uploads bypass the egress proxy

Status: implemented

## Problem

With the Gradle proxy repair landed, the dev-channel build reached the
*Publish GitHub shadow Release (mirror)* step for the first time in days —
and died there: the small JSON release-creation POST through the LAN egress
proxy succeeded, the 139 MB APK upload to `uploads.github.com` was reset
mid-stream (~16 MB in, ~23 s). The shadow release shipped with zero assets
— the exact empty-release failure the step's hard-fail exists to catch.
The proxy tolerates small bodies and kills large ones; git-payload mirror
jobs never noticed because their pushes ride chunked smart-HTTP transfers
under the reset threshold.

## Decision

The shadow-publish step of `.gitea/workflows/release-apk.yaml` overrides
the job's proxy env: all proxy variables are set empty and `NO_PROXY=*`,
running the step over direct egress — which the runner network has to
GitHub (measured: 3.5 MB/s sustained, no resets). No base-URL or endpoint
logic changes; the step already separates `api.github.com` from
`uploads.github.com`
(see [the mirror pipeline's channel decision](2026-08-22-release-mirror-single-channel.md)).
Clearing the variables *and* setting the wildcard covers a runner that
drops empty env values.

## Alternatives considered

- **Chunk the upload / retry loop**: rejected — the GitHub release-asset
  API has no resumable upload; retries just re-pay the reset.
- **Point the whole job at direct egress**: rejected — Gradle and pub
  downloads still need the proxy (Google Maven is not reachable directly
  from this network), and
  [the Gradle step now rewrites proxy config anyway](2026-09-01-gradle-proxy-egress-rewrite.md);
  a step-scoped override keeps that machinery intact.
- **Add github hosts to the job's `NO_PROXY`**: rejected — the image bakes
  its own `NO_PROXY`, and job-env merge order against image env is not
  documented enough to bet the release channel on; the step-level override
  wins unambiguously.

## Consequences

Stable and dev shadow releases attach their APK and `.sha256` sidecar
again. If direct egress to GitHub ever disappears from this network, the
step fails loudly (hard-fail already in place) rather than shipping empty
releases. The `.github` copy is untouched: GitHub-hosted runners have no
LAN proxy.
