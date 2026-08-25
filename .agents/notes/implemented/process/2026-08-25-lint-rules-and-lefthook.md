# Agent Note: Lint rule selection and lefthook hooks migration

Status: implemented

## Problem

Two tooling questions sat open: whether to adopt the strict
`very_good_analysis` lint bundle, and how to manage git hooks. The repo
ran `flutter_lints` plus a hand-curated rule list and two hand-written
bash hooks (`scripts/git-hooks/pre-commit`, `pre-push`) wired through
`core.hooksPath`. Nothing enforced formatting, and unused futures escaped
the curated lints because `unawaited_futures` only fires inside async
functions.

## Decision

A dry-run probe against the whole workspace settled the lint question
with numbers: layering `very_good_analysis` 10.3.0 over the current code
reports 3689 issues — every one `info` severity, but `flutter analyze`
fails CI on any issue. The long tail is style churn (1630
`public_member_api_docs`, 342 `omit_local_variable_types`, 228
`lines_longer_than_80_chars`), and several rules are false positives for
this codebase (`avoid_catching_errors` flags deliberate graceful
degradation, `avoid_slow_async_io` is server-oriented and would push
sync IO onto the mobile main isolate). The rules with real value are
cherry-picked into the curated list instead:

- `always_put_required_named_parameters_first` — required named
  parameters before optional ones; 189 mechanical fixes.
- `discarded_futures` — Future-returning calls in non-async functions
  must be wrapped in `unawaited(...)`; 51 fixes, the constructor
  fire-and-forget calls `unawaited_futures` could not see.

Git hooks migrate from the two bash files to **lefthook** (pinned
2.1.11, single static binary, installed by
`scripts/install-lefthook.sh`). `lefthook.yml` orchestrates the same
jobs plus new ones: identity guard, staged leak scan, `dart format` on
staged `.dart` files with `stage_fixed`, `git diff --cached --check`,
and the import gate; `pre-push` keeps the push leak scan. Both escape
hatches (`identity.guard off`, `leakscan.mode off`) survive in the split
scripts.

Formatting becomes enforced: the workspace was normalized with
`dart format` once, and `verify_all.py code` gained a `dart-format` gate
(`dart format --output=none --set-exit-if-changed` over every lib/test
tree) so CI holds the line. Local hooks stay the fast pre-check; CI owns
the exhaustive matrix.

## Alternatives considered

- **Wholesale `very_good_analysis`**: 3689 infos ≈ 91-file formatting
  churn plus 1630 doc comments, some contradicted by the repo's prose
  standard ("no comments on obvious facts"). Rejected on cost-benefit.
- **`dart_code_metrics`**: unmaintained/archived since 2023; the
  ecosystem moved to analyzer plugin rules. Rejected.
- **`custom_lint` for repo-specific rules**: would move the import
  boundary into the editor, but adds a plugin package and build-time
  coupling; the python import gate already covers CI. Kept as future
  option, not adopted.
- **husky + lint-staged / pre-commit**: introduce a Node or Python hook
  framework around a repo whose gates are already python scripts run by
  lefthook directly. Lefthook wins on zero-runtime single binary and
  `{staged_files}`/`stage_fixed` support.
- **Status quo hooks (no lefthook)**: the two bash files worked but had
  no globbing, parallelism, or staged-file passing; growing them means
  re-implementing lefthook. Rejected.

## Consequences

- `flutter analyze` now enforces the two new curated rules; new code
  must order required-named parameters first and wrap fire-and-forget
  futures in `unawaited(...)`.
- All Dart code must be `dart format`-clean; the CI `code` lane fails on
  drift. `dart format` runs as an auto-fix in pre-commit (`stage_fixed`
  re-stages its output).
- Fresh clones run `scripts/install-lefthook.sh` instead of setting
  `core.hooksPath scripts/git-hooks` (the install script migrates away
  from the legacy path when present). Hooks require the pinned lefthook
  binary; the identity-guard and leak-scan semantics are unchanged.
- The old `scripts/git-hooks/pre-commit`/`pre-push` files are gone; the
  gitleaks allowlist entry for `scripts/git-hooks/` still matches the
  split scripts that replaced them.