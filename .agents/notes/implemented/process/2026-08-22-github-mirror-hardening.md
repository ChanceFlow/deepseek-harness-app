# Agent Note: GitHub mirror sync hardening

Status: implemented

## Problem

The Gitea→GitHub mirror is event-driven and unguarded. `publish-github.yaml`
runs only on a Gitea master push, so a failed mirror run leaves the public
repo silently stale until the next push — nothing reconciles the two
forges. Its "last line of defense" leak sweep scanned only the working
tree (`--tree`), so a leak that slipped into an old commit would never be
seen by the mirror. Tags were force-pushed but never pruned, so a tag
deleted on Gitea lingered on GitHub forever. And the master push was an
unconditional `--force`: a Gitea history rewrite was silently propagated to
the public repo with no human gate.

## Decision

Three hardening changes to `.gitea/workflows/publish-github.yaml` and one
new workflow:

- **Non-fast-forward gate**: the mirror fetches GitHub master and pushes
  fast-forward on normal merges. If GitHub master is not an ancestor of
  local master (a divergence or rewrite), the push is blocked unless the
  operator re-runs with `workflow_dispatch` input `confirm_rewrite=true` —
  rewriting the public history is a human decision, never an automatic
  side effect.
- **Comprehensive leak sweep**: the pre-push sweep now runs both `--tree`
  and `--all-blobs`, and a new periodic workflow re-runs `--all-blobs`
  every six hours, so a history leak is caught even when no push happens.
- **Tag convergence**: tags push with `--prune`, so deletions on Gitea
  propagate to GitHub instead of lingering.
- **Drift reconciliation**: new `reconcile-github.yaml` compares master and
  the full tag set against GitHub on a schedule and on demand; any drift
  opens a Gitea issue and fails the run. Any failure of the mirror workflow
  itself opens an alert issue via an `if: failure()` step.

## Alternatives considered

- **Trust the event-driven mirror**: leaves the stale-GitHub failure mode
  invisible; rejected because a public storefront must not silently drift.
- **Allow force-push always**: keeps the single-history property but makes
  history rewrites automatic; rejected — the two manual rewrites this repo
  already performed are exactly the kind of event that deserves a human
  gate.
- **Prune all remote heads**: converges branches too, but would clobber a
  future contributor's PR branch on GitHub; rejected — tags are
  mirror-owned, branches are not.

## Consequences

- A mirror failure or a Gitea/GitHub drift now surfaces as a red run plus a
  Gitea issue within six hours at worst, instead of silently desyncing.
- Rewriting public history requires an explicit `confirm_rewrite` dispatch;
  a plain push after a rewrite fails loudly until a human confirms.
- Every mirror push scans the full history (`--all-blobs`), roughly
  doubling sweep time on this repo's size — acceptable for an infrequent
  mirror operation; the periodic reconcile keeps that guarantee between
  pushes.
- The reconcile job reads GitHub anonymously (public repo); the alert issue
  uses the runner's auto-provided `GITHUB_TOKEN`, so no extra secret is
  needed for either workflow.
