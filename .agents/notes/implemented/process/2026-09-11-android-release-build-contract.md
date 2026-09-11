# Agent Note: Android release build define and F-Droid version contract

Status: implemented

## Problem

The build configuration drifted across distribution channels. The F-Droid
recipe
([metadata/com.deepseek.harness.app.yml](../../../../metadata/com.deepseek.harness.app.yml))
ran a bare `flutter build apk --release --no-tree-shake-icons`: it omitted the
mandatory `--dart-define=cronetHttpNoPlay=true`
([README §APK releases](../../../../README.md#apk-releases)) and the
`--dart-define=DSH_TELEMETRY_ENABLED=false` that
[docs/fdroid-submission-guide.md](../../../../docs/fdroid-submission-guide.md)
promised, so a source build failed AGP 9's namespace check or shipped the
telemetry the guide said was compiled out. The recipe also carried a
`flutter: 3.47.1` build flag that F-Droid's metadata schema does not define,
named a `v0.1.0` commit with a `versionCode` no build produced, and read no
version at all: `flutter/app/pubspec.yaml` had no `version:`, and
`build.gradle.kts` only forwards `flutter.versionCode`. A gitignored scratch
copy under `publish-prep/fdroid/` had drifted to a different `Repo:` host and
`versionCode`.

## Decision

One define set governs every Android release build, and one tracked recipe at
`metadata/com.deepseek.harness.app.yml` owns the F-Droid channel.

- **Mandatory defines.** `cronetHttpNoPlay=true` ships embedded Cronet and is
  required by every Android build
  ([HTTP/3 Cronet note](../feature/2026-09-02-http3-cronet-engine-default.md)).
  `DSH_TELEMETRY_ENABLED` rides the version channel: stable tags and the
  F-Droid recipe set it `false`; the rolling `dev` prerelease keeps `true`
  ([dev telemetry note](../feature/2026-08-21-dev-telemetry-otlp.md)). The two
  release workflows
  ([.gitea](../../../../.gitea/workflows/release-apk.yaml),
  [.github](../../../../.github/workflows/release-apk.yaml)) pass the same
  define set plus tag-derived `--build-name`/`--build-number`; the GitHub
  mirror keeps its green-skip without signing secrets.
- **Version source.** `flutter/app/pubspec.yaml` gains `version: 0.1.2+102`,
  and the recipe reads both fields from it with the documented Flutter form
  `UpdateCheckData: flutter/app/pubspec.yaml|version:\s.+\+(\d+)|.|version:\s(.+)\+`,
  `UpdateCheckMode: Tags v\d+\.\d+\.\d+` (the rolling `dev` tag is excluded),
  and Tags-mode `AutoUpdateMode: Version`. `versionCode` is
  `major*10000 + minor*100 + patch`; the release commit bumps it before
  tagging. The recipe still passes `--build-name=$$VERSION$$
  --build-number=$$VERCODE$$`, so the pinned `v0.1.2` build — whose tag
  predates `version:` — produces exactly the declared fields.
- **Toolchain.** The unrecognised `flutter:` flag is replaced by
  `srclibs: [flutter@3.47.1]` and `$$flutter$$/bin/flutter`, the mechanism
  every Flutter app in `fdroiddata` uses.
- **One recipe home.** `metadata/` is tracked and is what
  `publish-prep/submit_fdroid_mr.py` uploads; `publish-prep/fdroid/` is
  gitignored scratch and is now a comment-only pointer to it.

## Alternatives considered

- **Leave `version:` out of pubspec and pass literal `--build-name`/
  `--build-number` only.** Rejected: `UpdateCheckMode: Tags` has nothing to
  read, since the version lives in neither `build.gradle.kts` nor the
  manifest, so `AutoUpdateMode` could never derive a new build; the
  `UpdateCheckData` pubspec form is the documented Flutter path.
- **Keep both recipe copies in sync by hand.** Rejected: the directory is
  gitignored and pruned from the public tree, so a copy there is invisible to
  review and drifted once already.
- **Keep `flutter: 3.47.1`.** Rejected: `fdroidserver` rejects an
  unrecognised build flag, and the `flutter` source library already pins the
  SDK.
- **Derive `versionCode` from `$GITHUB_RUN_NUMBER`, matching the release
  channel.** Rejected: F-Droid signs with its own key, so its sequence is
  independent, and a run number is not reproducible from a tag.

## Consequences

`flutter/app/pubspec.yaml` is the version authority for plain and F-Droid
builds; the release workflows override it with the tag-derived
`--build-name`/`--build-number`, so their APK metadata is unchanged. F-Droid's
`UpdateCheckData` resolves at the first stable tag cut after this change —
tags up to `v0.1.2` carry no `version:`, so `fdroid checkupdates` may warn and
skip them until then, while the pinned `v0.1.2` build stays correct through
the `$$VERSION$$`/`$$VERCODE$$` flags. F-Droid version codes are independent
of the release channel's run numbers; cross-channel installs cannot update
over each other regardless, because the signing keys differ. The contract is
restated in the two release workflows and in
[docs/fdroid-submission-guide.md](../../../../docs/fdroid-submission-guide.md).
