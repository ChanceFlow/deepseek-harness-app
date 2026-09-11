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
- **Flutter toolchain**: The recipe pins the SDK with
  `srclibs: [flutter@3.47.1]` and drives it through `$$flutter$$/bin/flutter`;
  F-Droid's build metadata has no `flutter:` flag, so the SDK always arrives
  as a source library at the repository's pinned version.
- **Build defines**: every Android build passes
  `--dart-define=cronetHttpNoPlay=true` (embedded Cronet — the
  play-services-cronet chain fails AGP 9's namespace check) and
  `--dart-define=DSH_TELEMETRY_ENABLED=false`. `--build-name=$$VERSION$$` /
  `--build-number=$$VERCODE$$` pin the APK to the recipe's declared
  `versionName`/`versionCode`. The full contract is owned by
  [the Android release build contract note](../.agents/notes/implemented/process/2026-09-11-android-release-build-contract.md).

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
   Release tags follow SemVer format `v<semver>` (e.g., `v0.1.1`, `v0.1.2`);
   the rolling `dev` prerelease tag is not a release and is filtered out by
   the recipe's `UpdateCheckMode` pattern. `CurrentVersion` matches the tag
   without its `v` prefix, and `CurrentVersionCode` is
   `major*10000 + minor*100 + patch` (`v0.1.2` -> `102`), bumped with each
   stable tag. `version:` in `flutter/app/pubspec.yaml` is the single source
   both fields derive from.
2. **Fork `fdroiddata`**: Fork `https://gitlab.com/fdroid/fdroiddata`.
3. **Add Recipe**: Copy `metadata/com.deepseek.harness.app.yml`
   into `metadata/com.deepseek.harness.app.yml` on the forked repository.
4. **Open a Merge Request**: Target `fdroid/fdroiddata:master` with title
   `Add com.deepseek.harness.app`.
5. **Continuous Sync via F-Droid Bot**:
   The metadata specifies:
   ```yaml
   AutoUpdateMode: Version
   UpdateCheckMode: Tags v\d+\.\d+\.\d+
   UpdateCheckData: flutter/app/pubspec.yaml|version:\s.+\+(\d+)|.|version:\s(.+)\+
   ```
   `UpdateCheckData` is the documented Flutter form: it reads both the
   version name and the version code from `flutter/app/pubspec.yaml`
   (`version: X.Y.Z+N`). Whenever a stable `v<semver>` tag is pushed, the
   F-Droid `checkupdates` bot creates a new build entry from it. F-Droid
   cannot derive the new `versionCode` from the tag alone, so the release
   commit bumps the `+N` suffix in `pubspec.yaml` before tagging and
   `checkupdates` reads it back from the tag.
