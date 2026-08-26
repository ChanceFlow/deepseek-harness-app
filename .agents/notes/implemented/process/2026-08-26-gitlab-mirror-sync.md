# Agent Note: Dual public mirror with GitLab sync

Status: implemented

## Problem

The internal Gitea repository mirrored only to GitHub
([publish-github.yaml](../../../../.gitea/workflows/publish-github.yaml)).
Distributing to FOSS ecosystems like F-Droid benefited from maintaining an
identical public presence on GitLab (`gitlab.com/ChanceFlow/deepseek-harness-app`),
providing redundancy and direct repository reference within GitLab-native
toolchains.

## Decision

Automated GitLab mirroring is established alongside GitHub:

- Added [publish-gitlab.yaml](../../../../.gitea/workflows/publish-gitlab.yaml)
  to `.gitea/workflows/` with identical Model A sync semantics.
- Pre-push leak sweeps (`scan_leaks.py`) guard both tree and historical blobs
  before pushing.
- Synchronizes `master` fast-forward and updates tags with `--prune`.
- Gated by `secrets.GL_PUBLISH_TOKEN`; skips gracefully when token is absent.
- Failures create an alert issue in Gitea.

## Alternatives considered

- **Manual push to GitLab on release.** Rejected: manual operations are
  error-prone and easily desync from master commits.
- **GitLab CI pull mirroring.** Rejected: requires premium GitLab subscription
  or scheduled pipelines, whereas Gitea event-driven push mirrors instantly.

## Consequences

Pushes to `master` automatically update both GitHub and GitLab public mirrors
when the corresponding publishing secrets are configured. History and tags
stay bit-for-bit identical across all three platforms.
