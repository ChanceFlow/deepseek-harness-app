# AGENTS.md — deepseek-harness-app (public)

Flutter client for DeepSeek Harness (dsh): a pub workspace under `flutter/`
talking to an unmodified `dsh web` backend pinned via the reference
submodule.

## Repository layout

```text
flutter/                           pub workspace root — run flutter analyze/test here
flutter/app/                       UI: screens, controllers, markdown renderer, l10n, lib/di wiring
flutter/packages/domain/           Neutral models (ChatMessage, Session, TimelineItem) — pure Dart
flutter/packages/harness_adapter/  The ONLY code that knows the dsh wire protocol
flutter/packages/network/          Transport: RPC envelopes, HTTP/WebSocket seams
flutter/packages/dev/              Debug-build tooling: telemetry, frame stats, crash capture
scripts/                           Gates (verify_*.py) and generators; gates_manifest.json holds every ceiling
.github/workflows/                 ci.yaml — the merge gate; release-apk.yaml — the distribution channel
.gitea/workflows/                  Same CI + release + GitHub-mirror pipelines for the internal forge
reference/deepseek-harness/        Pinned submodule — the dsh wire source of truth (read-only)
docs/                              spec.md (wire contract + coverage), design-standard.md, testing.md, prose-standard.md
.agents/notes/                     Public decision records — the repo's memory
.agents/skills/                    Vendored Flutter/Dart skills (BSD-3-Clause, flutter/agent-plugins)
```

## Commands

All commands from repo root unless noted. Flutter 3.47.1 stable is expected
on PATH ([ci.yaml](.github/workflows/ci.yaml) is the pin's source).

Reach for the narrowest tool that would fail for your change:

```sh
cd flutter && flutter test app/test/ui/chat/chat_screen_test.dart   # one behavior
cd flutter && flutter analyze app/lib/ui/chat                       # one directory
python3 scripts/verify_all.py docs                                  # every doc gate, ~2s
python3 scripts/check_dart_imports.py                               # the import boundary
cd flutter && flutter build apk --debug --dart-define=DSH_BASE_URL=http://127.0.0.1:3080
```

CI owns the exhaustive run — [.github/workflows/ci.yaml](.github/workflows/ci.yaml)
executes `verify_all.py docs` and `verify_all.py code` on every push and PR
as two parallel required statuses — so a local full aggregate before each
commit buys a slower loop. Pick the tool by surface:
[docs/testing.md](docs/testing.md) §Select evidence by surface;
`python3 scripts/verify_all.py --list` names every gate, and
[flutter/AGENTS.md](flutter/AGENTS.md) carries the whole-workspace suite
command.

- Real-host e2e needs a running dsh host and `DSH_E2E_URL`:
  [README §Opt-in real-host e2e](README.md#opt-in-real-host-e2e).
- Wire-contract truth for any adapter change:
  [reference/README.md](reference/README.md) maps the submodule paths.

## Contribution workflow

- Cut a branch off latest `master`, open a PR, get both CI statuses green;
  `master` is protected.
- CI: [ci.yaml](.github/workflows/ci.yaml) runs the aggregate as two
  parallel jobs — `docs` (python only, seconds) and `code` (analyze, full
  suite, import gate) — so a doc-only change settles on `docs` alone.
- [release-apk.yaml](.github/workflows/release-apk.yaml) publishes: every
  `master` push refreshes the rolling `dev` prerelease, a `v<semver>` tag
  cuts the stable Release, and both attach a signed APK to the Releases
  page ([README §APK releases](README.md#apk-releases)).

## Conventions

- **The import boundary is absolute.** `app` (outside `lib/di/`) and
  `domain` speak `domain` types only; dsh types (`SessionEvent`, `MuxFrame`,
  `HostFrame`) and the `harness_adapter`/`network` packages stay on their
  side of it, and `packages/dev` stays a leaf on `flutter` plus its OTel
  SDK. Boundaries are owned by
  [README §Module boundaries](README.md#module-boundaries) and enforced by
  `python3 scripts/check_dart_imports.py`.
- **Wire truth is the reference submodule.** Read request/response shapes
  under `reference/deepseek-harness/` before encoding or decoding anything;
  [reference/README.md](reference/README.md) maps the paths.
- **DTOs are hand-written decoders** with required-field semantics; reaching
  for `freezed`, `json_serializable`, or build_runner reopens a rejected
  decision ([ADR-0001](docs/adr-0001-flutter-rewrite.md),
  [docs/spec.md](docs/spec.md) §Non-Goals).
- **The aesthetic is stock Material 3.** Component choice, the `ColorScheme`
  role map, and the home for a color Material 3 has no role for are owned by
  [flutter/app/AGENTS.md](flutter/app/AGENTS.md) — read it before touching a
  widget's look, and [docs/design-standard.md](docs/design-standard.md) for
  the facts those values derive from.
- **User-visible text is an ARB key** in both locales, added in the same
  change ([flutter/app/AGENTS.md](flutter/app/AGENTS.md)); `verify_i18n_arb`
  fails a key that reaches one locale only.
- **Telemetry is optional at every call site.** App code emits through
  `DebugTelemetry.instance?` and behaves identically when it is null; who
  actually reports is owned by
  [flutter/packages/dev/AGENTS.md](flutter/packages/dev/AGENTS.md).
- **Analyzer strictness is non-negotiable.** `strict-casts`,
  `strict-inference`, `strict-raw-types` stay on; fix the code and keep the
  options ([flutter/analysis_options.yaml](flutter/analysis_options.yaml)).
- **State is controllers with UDF streams**, one per screen, rather than
  per-screen Notifiers. UI spatial layout is owned by `app` alone; the
  adapter publishes facts, never placement
  ([README §Goals](README.md#goals)).
- **Every non-trivial change updates a decision note in the same change.**
  Non-trivial = behavior, architecture, cross-file contract, process,
  testing strategy, or an on-disk/wire format change. Format and lifecycle:
  [`.agents/notes/README.md`](.agents/notes/README.md); enforced by
  `verify_note_format` in `verify_all`.
- **Prose states current contracts.** Comments, docs, and commit text carry
  live behavior and failure modes; the story of how it got there belongs to
  a decision record. Standard: [docs/prose-standard.md](docs/prose-standard.md).
- **Tests assert external state through real entry paths.** Widget trees
  are real widgets; wire decoding goes through the real decoders. Policy:
  [docs/testing.md](docs/testing.md).

## Defensive patterns

- **Fail loud on malformed wire data.** Required-field decode throws with
  the field name; a missing referent surfaces, never defaults silently.
- **Switches on discriminants are exhaustive.** Closed unions (wire event
  types, timeline item kinds) end without a wildcard so a new variant fails
  compilation, not production.
- **One async operation, one lifecycle owner.** Connection readiness,
  cancellation, and disposal fold into `DshConnectionManager`; a split
  needs a settlement point.

## Editing these instructions

This file is the single instruction home. Subtree `AGENTS.md` files carry
deltas only: `flutter/` (workspace mechanics), `flutter/app/` (UI and
aesthetic), `flutter/packages/harness_adapter/` (wire seam),
`flutter/packages/dev/` (debug tooling). Word budgets live in
[scripts/gates_manifest.json](scripts/gates_manifest.json) and are enforced
by `verify_doc_budgets`; raising a ceiling takes a manifest diff plus a
decision note saying why. A rule here links its owning home; a rule without
a home is a smell.