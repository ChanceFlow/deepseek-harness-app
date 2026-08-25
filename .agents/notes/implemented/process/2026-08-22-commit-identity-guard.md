# Agent Note: Commit identity guard in the pre-commit hook

Status: implemented

## Problem

The shared history publishes under exactly one identity. Commits are
stamped from three independent sources — the local git config of whoever
commits, per-invocation author/committer environment overrides, and the
forge account that performs a PR merge (a forge stamps its account's
primary email onto merge commits). A drift in any of the three puts a
foreign identity into history that both forges publish, and undoing it
costs a full rewrite pass plus a force-push to both forges. That is
exactly what happened: merge commits carried the forge account's former
primary email until the account was reconfigured and the history was
rewritten a second time.

## Decision

The `check-identity.sh` pre-commit job (lefthook, see
`lefthook.yml`) refuses any commit whose author or committer identity
differs from the published one. The effective
identity is resolved the way git resolves it — `GIT_AUTHOR_*` /
`GIT_COMMITTER_*` environment first, then `user.name` / `user.email`
from git config — and both the name and the email must match. The
failure message prints the expected identity, the identity actually
seen, and the fix command. The guard runs before the leak scan and has
its own escape hatch (`git config identity.guard off`) so it can never
be silently skipped by the leak scan's switch. Server-side, the forge
account holds only the published email as its single registered
address, so forge-created merge commits inherit it.

## Alternatives considered

- **A `.mailmap` in the repo**: only rewrites how git *displays*
  identities; pushed objects and both forges still carry the foreign
  one. Does not prevent the problem.
- **Checking identity in CI**: CI sees the drift only after it is
  already merged; the hook rejects it before the commit exists.
- **Trusting local config alone**: it covers the common case but not
  per-invocation environment overrides, which is exactly the gap the
  guard closes.

## Consequences

- A misconfigured clone or a stray `GIT_COMMITTER_EMAIL` fails loud at
  commit time with an actionable message instead of publishing silently.
- Forge-created merge commits are covered by the account's single
  registered email, not by the hook; if another account ever gains merge
  rights, its primary email must match first.
- The guard is a lefthook pre-commit job in `lefthook.yml` calling
  `scripts/git-hooks/check-identity.sh`; a fresh clone must run
  `scripts/install-lefthook.sh` (same requirement as the leak gate it
  sits next to).
