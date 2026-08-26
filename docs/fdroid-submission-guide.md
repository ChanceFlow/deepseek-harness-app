# F-Droid Official Submission Guide

This document describes the structure, build contracts, and submission
workflow for publishing the application to the official F-Droid repository
(`fdroiddata`).

## Architecture and Build Model

F-Droid builds all applications from source on its own builder cluster. The
repository does not accept prebuilt APK binaries directly.

- **Source repository**: Git clone of this repository at a release tag.
- **Application ID**: `com.deepseek.harness.app`
- **Submodules**: Includes `reference/deepseek-harness` (enabled with
  `submodules: yes` in the recipe).
- **Workspace build**: The project is a pub workspace rooted at `flutter/`.
  The recipe invokes `flutter pub get` from `flutter/` before running
  `flutter build apk --release` under `flutter/app/`.

## Metadata and Assets

F-Droid consumes metadata from `fastlane/metadata/android/`:

- `fastlane/metadata/android/en-US/`: English title, short description, full
  description, and version changelogs.
- `fastlane/metadata/android/zh-CN/`: Simplified Chinese localization.
- `fastlane/metadata/android/images/icon.png`: Application launcher icon.

The F-Droid package recipe resides at:
`metadata/com.deepseek.harness.app.yml`.

## Native Dependencies and FOSS Compliance

F-Droid enforces strict compliance regarding prebuilt binaries:

1. **No prebuilt native shared libraries**:
   The build recipe must not package proprietary or unaccounted prebuilt
   `.so` binaries. For plugins with native libraries (e.g., `sherpa_onnx`),
   the F-Droid build flavor compiles cleanly or degrades offline ASR to
   the standard system voice/keyboard input.
2. **Anti-Features**:
   Tagged with `NonFreeNet` because the client interacts with upstream
   LLM APIs or remote self-hosted server instances.
3. **Telemetry**:
   Release builds compile with `DSH_TELEMETRY_ENABLED=false` to ensure zero
   telemetry tracking in distributed release APKs.

## Submission Workflow and Automated Sync

1. **Tag Alignment**:
   Release tags follow SemVer format `v<semver>` (e.g., `v0.0.3`, `v0.0.4`).
   The recipe's `CurrentVersion` matches the tag without `v` prefix, and
   `CurrentVersionCode` corresponds to the integer build sequence.
2. **Fork `fdroiddata`**: Fork `https://gitlab.com/fdroid/fdroiddata`.
3. **Add Recipe**: Copy `metadata/com.deepseek.harness.app.yml`
   into `metadata/com.deepseek.harness.app.yml` on the forked repository.
4. **Open a Merge Request**: Target `fdroid/fdroiddata:master` with title
   `Add com.deepseek.harness.app`.
5. **Continuous Sync via F-Droid Bot**:
   The metadata specifies:
   ```yaml
   AutoUpdateMode: Version v%v
   UpdateCheckMode: Tags
   ```
   Whenever a new tag matching `v*` is pushed to GitHub/Gitea, the F-Droid
   `checkupdates` bot automatically creates a new build entry and increments
   version numbers in the official repository without manual intervention.
