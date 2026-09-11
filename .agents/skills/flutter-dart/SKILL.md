---
name: flutter-dart
description: Complete engineering guide and workflow reference for Dart and Flutter development. Use whenever developing, refactoring, testing, or debugging Dart code or Flutter applications, including: Dart language features (pattern matching, primary constructors), native interop (FFI assets, ffigen), testing & quality (unit tests with test/checks, mockito mocks, code coverage, static analysis, package conflict resolution, CLI apps, runtime error fixes), and Flutter development (layered architecture, widget tests, integration tests, responsive layout, layout overflow debugging, JSON serialization, declarative routing with go_router, l10n localization, HTTP networking, widget previews).
---

# Flutter & Dart Engineering Guide

Comprehensive guide and single entrypoint for Dart language and Flutter framework workflows. For deep-dive task instructions, checklists, and code templates, consult the corresponding topic guides in `references/`.

---

## Capability & Reference Index

When executing a specific task, load the corresponding reference document:

| Category | Task / Problem | Target Reference |
|---|---|---|
| **Testing** | Unit testing Dart functions, classes, and async code with `package:test` | [`references/dart-unit-testing.md`](references/dart-unit-testing.md) |
| **Testing** | Generating and verifying mock objects using `package:mockito` and `build_runner` | [`references/dart-test-mocks.md`](references/dart-test-mocks.md) |
| **Testing** | Migrating test assertions from `package:matcher` (`expect`) to `package:checks` | [`references/dart-checks-package-migration.md`](references/dart-checks-package-migration.md) |
| **Testing** | Collecting code coverage and generating LCOV reports (`lcov.info`) | [`references/dart-code-coverage.md`](references/dart-code-coverage.md) |
| **Testing** | Component/widget UI testing using `WidgetTester`, finders, and gesture pumps | [`references/flutter-widget-testing.md`](references/flutter-widget-testing.md) |
| **Testing** | End-to-end integration testing using `package:integration_test` | [`references/flutter-integration-testing.md`](references/flutter-integration-testing.md) |
| **Tooling & Quality** | Running static analysis (`dart analyze`), strict lints, and `dart fix --apply` | [`references/dart-static-analysis.md`](references/dart-static-analysis.md) |
| **Tooling & Quality** | Resolving `pub get` dependency and package version conflicts | [`references/dart-package-conflicts.md`](references/dart-package-conflicts.md) |
| **Tooling & Quality** | Investigating runtime errors, stack traces, and verifying fixes | [`references/dart-runtime-error-fixing.md`](references/dart-runtime-error-fixing.md) |
| **Tooling & Quality** | Building command-line tools, CLI entrypoints, arg parsing, and exit codes | [`references/dart-cli-apps.md`](references/dart-cli-apps.md) |
| **Language & Native** | Switch expressions, pattern matching, destructuring, and guard clauses | [`references/dart-pattern-matching.md`](references/dart-pattern-matching.md) |
| **Language & Native** | Dart primary constructor syntax, initializer lists, and concise constructors | [`references/dart-primary-constructors.md`](references/dart-primary-constructors.md) |
| **Language & Native** | Compiling and packaging C/C++ native assets via hooks (`build.dart`/`link.dart`) | [`references/dart-ffi-assets.md`](references/dart-ffi-assets.md) |
| **Language & Native** | Generating Dart FFI bindings from C headers using `package:ffigen` | [`references/dart-ffigen-bindings.md`](references/dart-ffigen-bindings.md) |
| **UI & Layout** | Responsive UI using `LayoutBuilder`, `MediaQuery`, and adaptive breakpoints | [`references/flutter-responsive-layout.md`](references/flutter-responsive-layout.md) |
| **UI & Layout** | Diagnosing and fixing layout errors (RenderFlex overflow, unbounded height/width) | [`references/flutter-layout-debugging.md`](references/flutter-layout-debugging.md) |
| **UI & Layout** | Interactive widget previews and design review scaffolding | [`references/flutter-widget-previews.md`](references/flutter-widget-previews.md) |
| **Architecture** | Layered app architecture (UI Presentation, Domain Logic, Data Repository) | [`references/flutter-architecture-best-practices.md`](references/flutter-architecture-best-practices.md) |
| **Features** | Declarative navigation and deep-linking using `go_router` | [`references/flutter-declarative-routing.md`](references/flutter-declarative-routing.md) |
| **Features** | Internationalization setup with ARB files and `flutter_localizations` | [`references/flutter-localization.md`](references/flutter-localization.md) |
| **Features** | Hand-written JSON serialization (`fromJson`/`toJson`) without code generators | [`references/flutter-json-serialization.md`](references/flutter-json-serialization.md) |
| **Features** | REST API calls, HTTP verbs, headers, and error handling via `package:http` | [`references/flutter-http-networking.md`](references/flutter-http-networking.md) |

---

## Essential Workflows

### 1. Static Analysis and Formatting

Always verify analyzer hygiene before and after making changes:

```sh
# Run analysis across the Dart / Flutter workspace
flutter analyze

# Automatically fix mechanical lint violations where supported
dart fix --apply

# Check formatting without modifying files
dart format --output=none --set-exit-if-changed .

# Reformat code in place
dart format .
```

Strict analyzer rules (`strict-casts`, `strict-inference`, `strict-raw-types`) are enforced across this repository. Resolve analyzer complaints by providing explicit type annotations or refining control flow, not by disabling options.

### 2. Testing

Choose the narrowest test runner for the task at hand:

```sh
# Run a single Dart unit test file
dart test test/path/to/target_test.dart

# Run a single Flutter widget test
flutter test app/test/path/to/widget_test.dart

# Run all tests in a package or workspace directory
flutter test

# Run tests with code coverage output
flutter test --coverage
# or for pure Dart:
dart test --coverage=coverage

# Run integration tests
flutter test integration_test/app_test.dart
```

When writing tests:
- Mirror the source path under `lib/` in the `test/` directory, suffixing with `_test.dart`.
- Prefer real objects or hand-written fakes; when mocking external network/system boundaries, use `package:mockito` with `@GenerateNiceMocks` and run `dart run build_runner build --delete-conflicting-outputs`.
- Assert external state through real public APIs and decoders rather than inspecting private internals.

### 3. Layout and UI Diagnostics

When diagnosing Flutter layout errors:
- **`RenderFlex overflowed by X pixels`**: Identify the offending Axis. Wrap child in `Expanded` or `Flexible` inside a `Row`/`Column`, or wrap the flex container in `SingleChildScrollView`.
- **`Vertical viewport was given unbounded height`**: Usually caused by a `ListView`, `GridView`, or `Column` inside an unbounded parent. Set `shrinkWrap: true` and `physics: const ClampingScrollPhysics()`, or constrain the parent with `Expanded` or `SizedBox(height: ...)`.
- Check [`references/flutter-layout-debugging.md`](references/flutter-layout-debugging.md) for concrete patterns and before/after code fixes.

### 4. Dependency & Package Management

When resolving dependency version conflicts or updating packages:

```sh
# Fetch dependencies
flutter pub get

# Check what would change on upgrade
flutter pub upgrade --dry-run

# Diagnose outdated or conflicting constraints
flutter pub outdated
```

If transient dependency conflicts arise, inspect `pubspec.yaml` constraint bounds and consult [`references/dart-package-conflicts.md`](references/dart-package-conflicts.md).

---

## Conventions for this Repository

When working on this repository (`deepseek-harness-android`), adhere to the project conventions:

1. **Import Boundaries**: Pure Dart packages (`packages/domain`) must never import Flutter or wire adapter packages. UI (`app/`) interacts with domain models, not raw dsh wire envelopes.
2. **DTO & JSON Decoding**: Write explicit, hand-written `fromJson`/`toJson` decoders with required-field validation. Do not introduce `freezed` or `json_serializable` build_runner generators.
3. **Design Aesthetic**: Stock Material 3 aesthetic strictly adhering to the `ColorScheme` roles defined in `flutter/app/AGENTS.md`.
4. **Localization**: Every user-facing string must be an ARB key in both English (`app_en.arb`) and Chinese (`app_zh.arb`).
5. **Decisions & Notes**: Any non-trivial structural, architectural, or workflow change must be accompanied by an Agent Note under `.agents/notes/`.
