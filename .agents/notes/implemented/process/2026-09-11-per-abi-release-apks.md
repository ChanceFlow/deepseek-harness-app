# Agent Note: Release APKs are per-ABI

Status: implemented

## Problem

Every release shipped one universal APK — `dsh-android-<version>.apk`, measured
at 160.6 MB (161.4 MB uncompressed) on the rolling `dev` prerelease
(`0.1.3-alpha.890`). A universal APK carries every ABI's copy of every native
library, and the native libraries are the whole download:

| | |
|---|---|
| `lib/x86_64` | 61.4 MB |
| `lib/arm64-v8a` | 55.3 MB |
| `lib/armeabi-v7a` | 42.8 MB |
| everything that is not `lib/` (dex, assets, resources) | 2.0 MB |

A phone installs exactly one of those three. The download was ~3x the code the
device runs, and the internal release upload had to push it in one request the
LAN egress proxy resets above ~16 MB
([workflow note](../../../../.gitea/workflows/release-apk.yaml)).

## Decision

Both release workflows build with `--split-per-abi`, so Flutter emits
`app-<abi>-release.apk` per ABI (flutter_tools `android/gradle.dart`
`_apkFilesFor`). The staging step renames each to
`dsh-android-<version>-<abi>.apk`, writes its `.sha256` sidecar, and fails loud
if one is missing rather than publishing a release with an ABI hole; it also
renders a `hashes.md` artifact list that both release bodies embed. Every
publish step uploads `*.apk` and `*.sha256` from the staging directory.

Measured effect: arm64-v8a ≈ 57 MB, armeabi-v7a ≈ 45 MB, x86_64 ≈ 63 MB — the
ARM64 APK is 64% smaller than the universal one, and each upload is small
enough to stay under the proxy's reset threshold.

Both READMEs document the three files and which one to take; arm64-v8a is the
headline (every phone made since ~2017) and stays the name the release
metadata leads with.

## Alternatives considered

- **Android App Bundle**: rejected — an AAB is a Play Store delivery format,
  and this app ships through the forge's Releases page and F-Droid, neither of
  which consumes one.
- **Drop `x86_64` only** with `abiFilters` (~100 MB, one file, unchanged UX):
  rejected as the stopping point — it gives up half the win and the emulator
  install target, where splitting keeps both.
- **Make the offline ASR backend optional** (`libonnxruntime.so` is 20.7 MB on
  arm64, 58.8 MB across the three): rejected here — that is a feature
  decision (the offline engine would need a downloaded model and a runtime
  library fetch), not a packaging one. It is the next real lever.
- **Keep the universal APK beside the splits**: rejected — it triples the
  upload size for a file nobody should install.

## Consequences

- A release now carries three APKs and three sidecars. The rolling `dev` tag is
  deleted and recreated on every `master` push, so they replace each other
  rather than accumulate; stable tags keep whatever they published.
- The F-Droid recipe is unchanged: its channel still builds a universal APK
  from source under a single `output:` path and splits for delivery on its own
  side. The two channels share the define set but differ in packaging, which is
  deliberate — the invariant that matters is the
  [define/version contract](2026-09-11-android-release-build-contract.md).
- `dsh-android-<version>.apk` is no longer a published name; the install
  instruction in both READMEs and any external bookmark of the old asset
  changes with it.
