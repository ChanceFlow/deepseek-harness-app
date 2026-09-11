# Project Skills

Project-scoped Agent Skills for this repository. Loaded automatically by the
harness from `.agents/skills/` (the standard agents-spec location) when working
inside this repo.

## Repository Skills

| Skill | Purpose |
|---|---|
| [`flutter-dart`](flutter-dart/SKILL.md) | Consolidated single entrypoint for all Dart language and Flutter framework workflows, routing to 22 modular topic guides under `references/` |

The `dsh-close-out`, `dsh-design-review` and `dsh-wire-parity` skills are
**local-only**: `.gitignore` excludes their directories, so they exist in a
developer's checkout and never in a clone. They are named in backticks rather
than linked for that reason — a link to an ignored path resolves here and
breaks everywhere else.

## Source of Flutter / Dart Capabilities

The Dart and Flutter engineering guides bundled under `flutter-dart/references/`
are sourced from
[flutter/agent-plugins](https://github.com/flutter/agent-plugins)
(BSD-3-Clause, Copyright 2026 The Flutter Authors) — the official Flutter team
agent plugin repository.

To reduce context load and eliminate system prompt catalog clutter, the 22
individual upstream plugins are organized into a single entrypoint skill
([`flutter-dart`](flutter-dart/SKILL.md)) with progressive disclosure via
topic documents:

| Reference Document | Sourced Topic | Description |
|---|---|---|
| `dart-unit-testing.md` | `dart-add-unit-test` | Unit tests with `package:test` |
| `dart-cli-apps.md` | `dart-build-cli-app` | CLI entrypoints, exit codes, cross-platform scripts |
| `dart-code-coverage.md` | `dart-collect-coverage` | Coverage collection and LCOV reports |
| `dart-runtime-error-fixing.md` | `dart-fix-runtime-errors` | Stack-trace driven fix + hot-reload verification |
| `dart-test-mocks.md` | `dart-generate-test-mocks` | Mockito mocks via `build_runner` |
| `dart-checks-package-migration.md` | `dart-migrate-to-checks-package` | Migrate `package:matcher` to `package:checks` |
| `dart-package-conflicts.md` | `dart-resolve-package-conflicts` | Fix `pub get` version conflicts |
| `dart-static-analysis.md` | `dart-run-static-analysis` | `dart analyze` + `dart fix --apply` |
| `dart-ffi-assets.md` | `dart-setup-ffi-assets` | Native assets build hooks for C/C++ |
| `dart-ffigen-bindings.md` | `dart-use-ffigen` | Generate FFI bindings with `package:ffigen` |
| `dart-pattern-matching.md` | `dart-use-pattern-matching` | Switch expressions and pattern matching |
| `dart-primary-constructors.md` | `dart-use-primary-constructors` | Primary constructor syntax |
| `flutter-integration-testing.md` | `flutter-add-integration-test` | `integration_test` flows from MCP actions |
| `flutter-widget-previews.md` | `flutter-add-widget-preview` | Interactive widget previews (`previews.dart`) |
| `flutter-widget-testing.md` | `flutter-add-widget-test` | Component tests with `WidgetTester` |
| `flutter-architecture-best-practices.md` | `flutter-apply-architecture-best-practices` | Layered architecture (UI / Logic / Data) |
| `flutter-responsive-layout.md` | `flutter-build-responsive-layout` | Adaptive layouts across form factors |
| `flutter-layout-debugging.md` | `flutter-fix-layout-issues` | Fix overflow / unbounded-constraint errors |
| `flutter-json-serialization.md` | `flutter-implement-json-serialization` | Hand-written `fromJson` / `toJson` models |
| `flutter-declarative-routing.md` | `flutter-setup-declarative-routing` | `MaterialApp.router` + `go_router` |
| `flutter-localization.md` | `flutter-setup-localization` | `flutter_localizations`, `intl`, `l10n.yaml` |
| `flutter-http-networking.md` | `flutter-use-http-package` | REST calls with the `http` package |
