# Project Skills (Flutter / Dart)

Project-scoped Agent Skills for this repository. Loaded automatically by the
harness from `.agents/skills/` (the standard agents-spec location) when working
inside this repo.

## Source

These 22 skills are installed from
[flutter/agent-plugins](https://github.com/flutter/agent-plugins)
(BSD-3-Clause, Copyright 2026 The Flutter Authors) — the official Flutter team
agent plugin repository.

Installed with the agents-spec **universal** method (not the Claude Code /
Codex / Cursor plugin systems):

```sh
npx skills@1.5.17 add flutter/agent-plugins --skill '*' --agent universal --yes --copy
```

`--agent universal` installs plain skills into the standard `.agents/skills/`
folder; `--copy` keeps real files (tracked in git) instead of symlinks into a
local cache. `skills-lock.json` at the repo root records sources and hashes.

Only the `skills/*` directories were installed. The rest of the upstream
repository was intentionally **not** installed:

| Upstream path | What it is | Why not installed |
|---|---|---|
| `.claude-plugin/`, `.codex-plugin/`, `.cursor-plugin/` | Agent-specific plugin packaging | We don't use Claude Code, Codex, or Cursor |
| `.mcp.json` | Dart MCP server config (`dart mcp-server`) | Skills work standalone; wire the MCP server into the harness separately if its tools are needed |
| `rules/hot_reload.md` | Hot-reload rule (glob-triggered) | Rules are not part of the `.agents/skills` skills spec |
| `tool/`, `resources/`, `pubspec.yaml` | Upstream lint/generator tooling | Repository-internal, not meant for installation |

## Skills

| Skill | Purpose |
|-------|---------|
| `dart-add-unit-test` | Unit tests with `package:test` |
| `dart-build-cli-app` | CLI entrypoints, exit codes, cross-platform scripts |
| `dart-collect-coverage` | Coverage collection and LCOV reports |
| `dart-fix-runtime-errors` | Stack-trace driven fix + hot-reload verification |
| `dart-generate-test-mocks` | Mockito mocks via `build_runner` |
| `dart-migrate-to-checks-package` | Migrate `package:matcher` to `package:checks` |
| `dart-resolve-package-conflicts` | Fix `pub get` version conflicts |
| `dart-run-static-analysis` | `dart analyze` + `dart fix --apply` |
| `dart-setup-ffi-assets` | Native assets build hooks for C/C++ |
| `dart-use-ffigen` | Generate FFI bindings with `package:ffigen` |
| `dart-use-pattern-matching` | Switch expressions and pattern matching |
| `dart-use-primary-constructors` | Primary constructor syntax |
| `flutter-add-integration-test` | `integration_test` flows from MCP actions |
| `flutter-add-widget-preview` | Interactive widget previews (`previews.dart`) |
| `flutter-add-widget-test` | Component tests with `WidgetTester` |
| `flutter-apply-architecture-best-practices` | Layered architecture (UI / Logic / Data) |
| `flutter-build-responsive-layout` | Adaptive layouts across form factors |
| `flutter-fix-layout-issues` | Fix overflow / unbounded-constraint errors |
| `flutter-implement-json-serialization` | `fromJson` / `toJson` models |
| `flutter-setup-declarative-routing` | `MaterialApp.router` + `go_router` |
| `flutter-setup-localization` | `flutter_localizations`, `intl`, `l10n.yaml` |
| `flutter-use-http-package` | REST calls with the `http` package |

## Updating

```sh
npx skills@1.5.17 update
```

This reads `skills-lock.json` at the repo root and refreshes the skills in
place.
