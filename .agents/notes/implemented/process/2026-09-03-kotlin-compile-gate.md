# Agent Note: The merge gate compiles the app's Kotlin

Status: implemented

## Problem

The merge gate's jobs (`docs`, `code`) are Dart- and doc-side: nothing in
`ci.yaml` compiles the Android host. PR #153 mapped the capture earcons to
`AudioManager.FX_TOGGLE_ON`/`FX_ADD`/`FX_REMOVE` — constants no public API
has — and both required statuses stayed green; the release channel's
`compileReleaseKotlin` failed the master push and the rolling `dev` APK
stopped publishing until the fix landed. Lint cannot close this gap: the
references are syntactically valid, and no ktlint/detekt rule resolves
Android SDK symbols, so the compiler is the only check that sees an
unresolved platform reference.

## Decision

`ci.yaml` gains a third parallel job, `android`, in both the forge and the
public mirror:

- It runs `:app:compileDebugKotlin` from `flutter/app/android` — Kotlin's
  type check is its compile, and this task is that check alone: the Dart
  AOT, asset merge, R8, packaging and signing of
  `assembleDebug`/`assembleRelease` are all skipped. Warm, the task is
  seconds; the job stays bounded for a cold gradle.
- The forge job runs on the `flutter-android` label, which this forge
  registers as host execution: Flutter, the Android SDK and the JDK come from
  the runner's `PATH`, and the host's own `~/.gradle` holds the artifacts the
  task resolves — no cache step is involved
  ([2026-09-11-ci-runner-host-mode.md](2026-09-11-ci-runner-host-mode.md)).
  Egress downloads still flake, so the
  compile is bounded and retried like the pub resolve above. The Flutter
  embedding resolves through gradle from `download.flutter.io` — no
  `flutter precache` and no `bin/cache` engine artifacts are involved. The
  egress address rides `vars.EGRESS_PROXY` and the compile step rewrites the
  user-level `gradle.properties` from it at runtime: Gradle's JVM reads that
  file and its `systemProp` proxy outranks every env layer, so an address left
  there from an earlier route silently eats every egress download.
  An internal address is never committed, and the leak rule covers both
  internal subnets.
- `flutter pub get` runs before the compile because its outputs are compile
  inputs: `android/local.properties` (the plugin's `flutter.sdk`),
  `.flutter-plugins-dependencies` (the plugin projects `settings.gradle`
  includes), and the SDK cache's universal `gradle_wrapper` artifact — the
  wrapper scripts are deliberately untracked
  (`flutter/app/android/.gitignore`), so the job mirrors
  `GradleUtils.injectGradleWrapperIfNeeded` in one shell step instead of
  letting gradle bootstrap itself.
- The mirror job is the same shape on `ubuntu-latest` with `setup-java`
  temurin 17; ubuntu-latest carries the Android SDK.

Every push and PR now carries three required statuses: `CI / docs`,
`CI / code`, `CI / android`.

## Alternatives considered

- **ktlint/detekt lint**: does not type-resolve platform symbols; the exact
  failure class passes clean.
- **Full `flutter build apk --debug`**: faithful but minutes-heavy,
  duplicating what the release channel already builds on `master`.
- **A paths filter** running the job only for `flutter/app/android/**`:
  cheaper, but one missed path is a silent false green — the worst failure
  mode a gate can have.

## Consequences

A merge-gate job finally sees Android-native breakage, so the failure
returns to the PR that caused it instead of the release channel after the
merge. The verdict covers `MainActivity.kt` — the app's only hand-written
Kotlin — and any future native source under `flutter/app/android`; plugin
code stays out (its own project compiles it during the full release build).
No cache key moves with this gate: the host's `~/.gradle` is the runner
machine's own directory and carries the artifacts between jobs.
