# Agent Note: The on-device ASR runtime is downloaded, not bundled

Status: implemented

## Problem

The offline speech engine was 26.2 MB of every arm64 APK — `libonnxruntime.so`
21.7 MB plus `libsherpa-onnx-c-api.so` 4.5 MB (and, unused,
`libsherpa-onnx-cxx-api.so` 0.4 MB) — carried by every install whether or not
the user ever turned on offline voice input. Measured on the arm64 split APK
(`dsh-android-0.1.3-alpha.895-arm64-v8a.apk`, 56.3 MB download): the three
libraries were 26.6 MB of the 57.2 MB uncompressed payload, second only to the
Flutter engine's own `libflutter.so` (11.7 MB) and our `libapp.so` (10.3 MB).

The models were already downloaded per model (`AsrModelManifest`,
`AsrDownloader`, `AsrModelManager`); the runtime was the only part of the
feature that shipped.

## Decision

The runtime is an install, on the same footing as a model:

- **Out of the APK.** `android/app/build.gradle.kts` excludes
  `libonnxruntime.so`, `libsherpa-onnx-c-api.so` and the unused
  `libsherpa-onnx-cxx-api.so` from packaging. Both release workflows publish,
  next to the APKs, one asset per ABI and library:
  `asr-runtime-<sherpaVersion>-<abi>-<lib>.so`, staged from the same
  `sherpa_onnx_android_*` packages the excluded files came from.
- **Pinned bytes.** `packages/asr/lib/src/runtime/asr_runtime_manifest.dart`
  holds the ABI set with each library's size and SHA-256, and
  `asr_runtime_manager_test.dart` asserts the shape; the release workflow's
  staged assets were verified against those pins (6 sizes, 6 hashes). A
  `sherpa_onnx` bump regenerates both — the note in the manifest says so.
- **Installed through the model downloader.** `AsrRuntimeManager` reuses
  `AsrDownloader`, so the runtime gets the same HTTP Range resumption, bounded
  retries, stall detection and content verification as a model. The assets are
  served raw (no archive layer), so the bytes verification accepts are the
  bytes the loader maps.
- **Loaded from the install directory.** `SherpaOfflineAsrEngine` preloads
  `libonnxruntime.so` by absolute path and then calls
  `sherpa.initBindings(<dir>)`, which opens `libsherpa-onnx-c-api.so` from the
  same directory. The c-api library declares onnxruntime as a `DT_NEEDED`
  (`readelf -d`), so the preload lets the linker resolve it from the loaded
  image instead of searching a native library directory that no longer holds
  it. `AsrRuntimeMissingException` is the typed failure when nothing is
  installed.
- **Gated in the UI.** The voice dock's offline gate now needs the runtime as
  well as a model (its own setup dialog), the runtime-not-installed error has
  its own copy, and Settings → Voice input carries an
  engine row with install/delete, progress, and an "unavailable for this
  device" state for an ABI the release does not publish.
- **ABI from the running build.** `dsh/device`'s `abis` filters the device's
  supported ABI list to the class this process runs (`Process.is64Bit`) before
  appending the unfiltered list, and the app picks the first entry it
  publishes a runtime for. An empty list leaves the runtime unavailable rather
  than guessing an ABI and fetching libraries the device cannot map.

## Alternatives considered

- **Keep it bundled and ship only the per-ABI split** (previous change):
  rejected as the stopping point — the split already cut the universal 161 MB
  to 56 MB, and this removes another 26 MB from a feature most installs never
  use.
- **Serve gzipped libraries** (~7.3 MB instead of 21.7 MB for onnxruntime):
  rejected — it adds an unpack step whose output is what gets loaded, and the
  model downloads a user triggers alongside it are 237–675 MB, so 15 MB of
  transfer is noise against a bigger correctness surface.
- **Keep `libsherpa-onnx-c-api.so` in the APK and download only onnxruntime**:
  rejected — it leaves the load path crossing the app's classloader namespace
  (an APK-served library needing an app-storage library), which is the failure
  mode that is hardest to reason about; both libraries in one directory keeps
  the whole load inside one namespace.
- **A separate "lite" build without offline ASR**: rejected — it doubles the
  artifact matrix and needs the same conditional code, without letting a user
  who changes their mind enable the feature.
- **Verify only the download's size**: rejected — the manifest carries real
  hashes and the downloader already verifies them.

## Consequences

- The arm64 APK drops 26.6 MB (56.3 MB → ~30 MB download); the first
  offline-voice-input install downloads 26.2 MB more, once.
- The runtime assets are versioned by `sherpa_onnx` release and by the app's
  own release tag: the app installs from the tag it was built under, so an
  APK and its runtime always come from the same build.
- **Device verification is owed.** Loading a native library from app storage
  is the one step that cannot be checked on this machine (no device, no
  emulator, no JDK): the linker must accept the downloaded `libsherpa-onnx-c-api.so`
  and resolve its `DT_NEEDED` to the preloaded onnxruntime. The failure is
  loud (`AsrRuntimeMissingException` and a load error), not silent, and the
  device-acceptance pass covers it.
- The F-Droid channel is unchanged: its recipe still builds from source, and
  the runtime exclusion applies to every build, so that build also downloads
  the engine on first use.
