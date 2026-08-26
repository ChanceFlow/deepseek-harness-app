# Agent Note: F-Droid official distribution pipeline

Status: implemented

## Problem

Distribution was limited to direct GitHub/Gitea Release APK downloads.
Users in the FOSS Android ecosystem expect discoverability and automatic
background updates through the official F-Droid client without adding custom
third-party repositories. F-Droid builds entirely from source on isolated
builders, prohibiting prebuilt native binary blobs and requiring strict
package metadata and workspace build definitions.

## Decision

F-Droid official repository inclusion is standardized around source-built
releases:

- Fastlane structure under
  [fastlane/metadata/android/](../../../../fastlane/metadata/android/) holds
  localized strings (`en-US`, `zh-CN`), version changelogs, and the launcher
  icon.
- F-Droid recipe definition is pinned at
  [metadata/com.deepseek.harness.app.yml](../../../../metadata/com.deepseek.harness.app.yml),
  invoking `flutter pub get` from `flutter/` across the workspace before
  building `flutter/app/` in release mode.
- Submodule `reference/deepseek-harness` is enabled via `submodules: yes`.
- Anti-feature `NonFreeNet` is declared for network LLM backend access.
- Submission contracts and native dependency handling are documented in
  [docs/fdroid-submission-guide.md](../../../../docs/fdroid-submission-guide.md).

## Alternatives considered

- **Direct IzzyOnDroid inclusion only.** Rejected as sole target: while
  IzzyOnDroid accepts prebuilt APKs from GitHub Releases with zero recipe
  constraints, it requires users to manually add a third-party repository URL
  in the F-Droid client.
- **Self-hosted F-Droid repository via GitHub Pages.** Rejected as primary
  channel: self-hosting adds maintenance overhead and lacks the native trust
  and default inclusion of the official F-Droid main repository.
- **Embedded prebuilt native binaries in source tree.** Rejected: violates
  F-Droid inclusion policy and fails automated repository linters.

## Consequences

Releases tagged `v*` on `master` can be ingested by the F-Droid build
infrastructure. The application appears in the main F-Droid catalog with
bilingual descriptions and automated update tracking (`AutoUpdateMode`).
Maintenance requires preserving offline build compatibility for workspace
packages and ensuring native libraries adhere to FOSS build constraints.
