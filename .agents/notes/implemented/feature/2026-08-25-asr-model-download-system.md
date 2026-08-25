# Agent Note: Client-side ASR model download and management system

Status: implemented

## Problem

Voice input on mobile requires low-latency, privacy-preserving speech recognition models running on-device. Bundling large neural weights directly inside the application APK would drastically inflate app binary size (~500 MB+), violating store distribution limits and wasting storage for users who do not use voice input.

Furthermore, domestic users in China often experience severe network latency or connection failures when downloading large open-source weights from international repositories like Hugging Face without mirror fallbacks.

## Decision

### Decoupled ASR package architecture

We implemented a decoupled ASR management package `flutter/packages/asr` registered in the pub workspace:
- Neutral model manifest `AsrModelManifest` specifying static metadata, valid SHA-256 checksums (cross-verified against Hugging Face LFS `lfs.oid` and ModelScope's own `Sha256` metadata on 2026-08-25; see the [SHA-256 wiring fix](../bug-fix/2026-08-25-asr-download-checks-made-real.md)), and mirror URLs for 3 on-device ASR models (SenseVoice-Small, Zipformer Bilingual streaming, Whisper large-v3-turbo).
- Dual source adapters (`HfMirrorSourceClient` on the official hf-mirror.com China mirror as the default fast lane, and `HuggingFaceSourceClient` for the global hub; ModelScope was removed — none of these sherpa-onnx packages has a ModelScope mirror).
- Durable on-device model registry `ModelsRegistry` persisting model statuses, disk locations, and checksums to `getApplicationSupportDirectory()/models/models_registry.json`.
- Resilient download engine `AsrDownloader` supporting HTTP Range resumption, single-concurrency queueing, disk space pre-flight validation backed by the Android `StatFs` method channel (requiring at least 1.3x model size free space; probe injected from app DI), cellular network guard, and temporary `.downloading` file staging with live SHA-256 verification.

### UI integration in Settings

In `flutter/app/lib/ui/settings/settings_screen.dart`, under the App Preferences section card:
- Added a dedicated "Speech recognition models" entry tile with installed count badge (e.g. "已装 1/3").
- Implemented `AsrModelsScreen` and `AsrModelsController` UDF stream state machine:
  - Default download source switcher (HF Mirror vs Hugging Face).
  - Cellular download permission toggle.
  - Model card listings with detailed language chips, open-source licenses, repo identifiers, real-time download progress and speed, deletion with confirmation dialog, and one-click source-switching retry upon failure.

## Alternatives considered

- **Bundling model weights inside the application APK**: Rejected because shipping multi-hundred megabyte ONNX models inflates app installation package size, breaches app store download thresholds, and consumes precious flash storage for users who do not require voice recognition.
- **Dynamic in-band downloads during first voice recording tap**: Rejected because streaming hundreds of megabytes during immediate user interaction introduces unpredictably high latency and jarring failure modes mid-speech.
- **Relying solely on Hugging Face**: Rejected because direct connectivity to global Hugging Face endpoints is frequently throttled or inaccessible from mainland China networks without proxy configuration. The official hf-mirror.com China mirror serves identical bytes and is the default for domestic users; ModelScope was later dropped because it mirrors none of the three sherpa-onnx packages (see the bug-fix note).

## Consequences

- The app APK remains lightweight while allowing on-demand downloading of on-device ASR weights.
- Downloads are resilient across network drops and interruptions.
- Clean separation between model download/registry management and future ONNX runtime ASR inference engine execution.
