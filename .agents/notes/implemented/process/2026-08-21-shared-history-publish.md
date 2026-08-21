# Agent Note: Shared public history and the dual-forge mirror

Status: implemented

## Problem

The repository developed on a private forge while a public mirror was
required. Sanitizing a copy per publish produced two divergent histories:
commit hashes differed between forges, so merge commits, issue references
and cross-links resolved on one side only — the public repo could never
carry a coherent history, and contributions could not map back.

## Decision

One shared history, identical on both forges. The tracked tree is
public-clean by construction: private working files (task ledgers, plan
docs, internal tooling) are gitignored locals that never enter git; the
CI configurations of both forges are tracked and free of internal
addressing; the reference submodule pins the official upstream commit.
The past was rewritten exactly once — private paths pruned, author
identity unified, internal addressing scrubbed from historical blobs —
after a full backup (bundle, private-file archive, server-side mirror
repo). Going forward a workflow mirrors master and tags to the public
forge on every merge, and the pre-commit/pre-push hooks run gitleaks on
staged and pushed changes, so the two forges stay byte-identical and
fast-forwardable in both directions.

## Alternatives considered

- **Divergent sanitized export per publish**: content syncs but every
  publish rewrites the public history; hashes never match and cross-forge
  references stay broken. Rejected for exactly that reason.
- **Separate private archive repository for internal files**: workable,
  but gitignored locals plus the pre-rewrite backup already cover
  archival without a second repo to maintain.
- **Single squashed public commit**: hides the development story and
  gains nothing over the full clean history.

## Consequences

- Both forges display identical logs; a merge commit cited anywhere
  resolves everywhere.
- Private material lives only on development machines and in the
  pre-rewrite backup; it can never re-enter history (gitignore + hooks).
- The mirror is authoritative-from-master: it force-converges the public
  forge, so the private side remains the single source of truth.
- History rewriting is a one-time tool kept as a local, untracked script;
  the tracked leak detectors carry their signatures obfuscated so the
  rewrite cannot corrupt them and the public never sees the vocabulary.