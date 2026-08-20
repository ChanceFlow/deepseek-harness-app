# AGENTS.md — deepseek-harness-android

Flutter client for DeepSeek Harness (dsh): a pub workspace under `flutter/`
talking to an unmodified `dsh web` backend. Before touching the wire adapter,
RPC coverage, or design tokens, read the homes linked below — each owns one
subject; this file never restates them.

## Repository layout

```text
AGENTS.md                     This file — standing orders (single instruction home)
flutter/                      pub workspace root — run flutter analyze/test here
flutter/app/                  UI: screens, controllers, markdown renderer, lib/di wiring
flutter/packages/domain/      Neutral models (ChatMessage, Session, TimelineItem) — pure Dart
flutter/packages/harness_adapter/  The ONLY code that knows the dsh wire protocol
flutter/packages/network/     Transport: RPC envelopes, HTTP/WebSocket seams
scripts/                      Gates (verify_*.py, check_dart_imports.py) + generators
docs/                         spec.md (wire contract + coverage), testing.md, prose-standard.md
.agents/notes/                Decision records — the repo's memory (see its README)
.agents/skills/               Project skills: vendored Flutter/Dart set + repo `dsh-*`
reference/deepseek-harness/   Pinned submodule — the dsh source of truth (read-only)
tasks/                        Human execution ledgers (plan/todo)
```

## Commands

All commands from repo root unless noted. Flutter 3.47 stable at
`$HOME/tools/flutter-3.47.0/bin`.

```sh
python3 scripts/verify_all.py        # ALL gates — run before closing any task
python3 scripts/verify_all.py docs   # doc/format gates only (seconds, no Flutter)
cd flutter && flutter analyze        # static analysis — zero issues required
cd flutter && flutter test app/test packages/domain/test packages/network/test packages/harness_adapter/test
                                     # full suite (real-host e2e self-skips)
cd flutter && flutter build apk --debug --dart-define=DSH_BASE_URL=http://10.0.2.2:3080
```

- Real-host e2e (needs a running dsh host): see
  [README §Opt-in real-host e2e](README.md#opt-in-real-host-e2e).
- Wire-contract truth for any adapter change:
  [reference/README.md](reference/README.md) maps the submodule paths.

## Branch workflow

`master` takes no direct task pushes: one branch per task
(`feat/…`, `fix/…`, `docs/…`), push, open a PR, let CI's verify aggregate
gate it, then merge — the repo auto-deletes the merged branch (Gitea
setting). Release tags (`v*`) ride `master` only. Cut every task branch in
a fresh worktree off latest `master`
(`git fetch origin && git worktree add -b <branch> ../dsha-<slug> origin/master`),
never by switching branches in the shared checkout — concurrent tasks
stay isolated and the main worktree keeps its state. Mechanics and API
shortcuts: [`.agents/skills/dsh-close-out/`](.agents/skills/dsh-close-out/SKILL.md) §3.

## Conventions

- **The import boundary is absolute.** `app` (outside `lib/di/`) and `domain`
  never import `harness_adapter`/`network` or any dsh type (`SessionEvent`,
  `MuxFrame`, `HostFrame`); boundaries are owned by
  [README §Module boundaries](README.md#module-boundaries) and enforced by
  `python3 scripts/check_dart_imports.py` (part of `verify_all`).
- **Wire truth is the reference submodule.** Never invent request/response
  shapes; read them under `reference/deepseek-harness/` per
  [reference/README.md](reference/README.md). Adapter-local rules:
  [flutter/packages/harness_adapter/AGENTS.md](flutter/packages/harness_adapter/AGENTS.md);
  the workflow for changing coverage: [`.agents/skills/dsh-wire-parity/`](.agents/skills/dsh-wire-parity/SKILL.md).
- **No codegen.** DTOs are hand-written decoders with required-field
  semantics; adding `freezed`/`json_serializable`/build_runner is a
  rejected-alternative decision (see
  [ADR-0001](docs/adr-0001-flutter-rewrite.md) and
  [docs/spec.md](docs/spec.md) §Non-Goals).
- **Design tokens are generated.** Never hand-edit
  `flutter/app/lib/ui/theme/deepsuite_tokens.dart`; regenerate with
  `python3 scripts/gen_deepsuite_tokens.py` — drift fails
  `gen_deepsuite_tokens.py --check` in `verify_all`. Workflow:
  [`.agents/skills/dsh-design-tokens/`](.agents/skills/dsh-design-tokens/SKILL.md).
- **Analyzer strictness is non-negotiable.** `strict-casts`,
  `strict-inference`, `strict-raw-types` are on; fix code, never the options
  ([flutter/analysis_options.yaml](flutter/analysis_options.yaml)).
- **State is controllers with UDF streams, not per-screen Notifiers.** UI
  spatial layout is owned by `app` alone; the adapter publishes facts, never
  placement ([README §Goals](README.md#goals)).
- **Every non-trivial change updates a decision note in the same change.**
  Non-trivial = behavior, architecture, cross-file contract, process/tooling,
  testing strategy, or an on-disk/wire format change. Format and lifecycle:
  [`.agents/notes/README.md`](.agents/notes/README.md); enforced by
  `verify_note_format` in `verify_all`.
- **Prose states contracts, not history.** Comments, docs, and commit text
  carry current behavior and failure modes; no "previously/now/we used to".
  Standard: [docs/prose-standard.md](docs/prose-standard.md).
- **Tests assert external state through real entry paths.** Widget trees are
  real widgets; wire decoding goes through the real decoders; never assert a
  self-report. Policy: [docs/testing.md](docs/testing.md).

## Defensive patterns

- **Fail loud on malformed wire data.** Required-field decode throws with the
  field name; never silently default a missing referent.
- **Switches on discriminants are exhaustive.** Closed unions (wire event
  types, timeline item kinds) end without a wildcard so a new variant fails
  compilation, not production.
- **One async operation, one lifecycle owner.** Connection readiness,
  cancellation, and disposal fold into `DshConnectionManager`; split only with
  a settlement point.

## Closing a task

Run `python3 scripts/verify_all.py` (or the narrowest gate group that covers
your change — [docs/testing.md](docs/testing.md) §Select evidence by surface),
update the owning decision note, then commit. Full workflow:
[`.agents/skills/dsh-close-out/`](.agents/skills/dsh-close-out/SKILL.md).

## Editing these instructions

This file is the single instruction home — no `CLAUDE.md`, no copies.
Subtree `AGENTS.md` files carry only deltas. Word budgets live in
[scripts/gates_manifest.json](scripts/gates_manifest.json) and are enforced by
`verify_doc_budgets`; raise a ceiling only via a manifest diff plus a decision
note saying why. Rules here must link their owning home; a rule without a home
is a smell.
