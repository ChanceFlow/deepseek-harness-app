# Agent Note: Real on-device ASR inference via sherpa-onnx

Status: implemented

## Problem

Voice input recorded audio end to end (proven by the in-app diagnostics:
`reads=84 max=0.011 sent=84 got=84`), but the `asr` package's engines
(`NonStreamingAsrEngine._defaultRunner`, `StreamingZipformerEngine`)
returned empty strings — the speech engine was a stub, so the recording
dock showed a live waveform and yet no transcription ever appeared. The
model catalog already carried the exact sherpa-onnx ONNX packages
(`csukuangfj/sherpa-onnx-*`), so the missing piece was the inference
integration, not the models.

## Decision

Wire real offline ASR through the official `sherpa_onnx` 1.13.6 Flutter
FFI plugin (pub.dev, Android/iOS prebuilt `.so` via
`sherpa_onnx_android_arm64` etc., no JitPack wiring needed):

- **Scope: offline-only.** The user chose non-streaming recognition:
  SenseVoice-Small and Whisper large-v3-turbo via `OfflineRecognizer`
  (whole-utterance decode in `finish()`). The streaming Zipformer
  (`OnlineRecognizer`) is not wired up; selecting it now surfaces a
  localizable `MODEL_UNSUPPORTED` error instead of the old silent empty
  result.
- **New `SherpaOfflineAsrEngine` in `flutter/app/lib/platform/`** — the
  `asr` package stays pure Dart (no Flutter/FFI dependency); the real
  engine implements its `AsrEngine` interface in the app layer, mirroring
  how `PlatformAudioRecorder` lives outside the pure-Dart packages.
  `initialize()` loads bindings once and builds model-specific
  `OfflineRecognizerConfig`; `acceptAudio()` accumulates; `finish()`
  decodes the whole utterance and returns `getResult().text`.
- **Engine instance reuse (the second stub-masking bug).**
  `VoiceInputController.stopRecording` recreated the engine via
  `_createEngineForModel`, so `finish()` ran on a fresh instance whose
  buffer never saw audio — a defect the stub hid (it returned '' either
  way). The session engine is now held in `_activeEngine`, created in
  `startRecording` and reused by `finish()`; a factory seam keeps the
  reuse testable. Cancelled sessions dispose self-created engines; injected
  engines (tests) are reset, not disposed.
- **Model-gated config**: `modelFileNameFor`/`modelConfigFor` map
  `sensevoice-small` (model.int8.onnx + tokens.txt, ITN on) and
  `whisper-large-v3-turbo` (turbo encoder/decoder + turbo-tokens.txt,
  `modelType: whisper`), reject everything else loudly. Missing model
  files fail at `initialize()` with a download-first message.

## Alternatives considered

- **JitPack `com.k2fsa.sherpa.onnx` AAR + hand-written Kotlin channels**:
  rejected — the official Flutter plugin already wraps the same C API
  with FFI and publishes per-ABI prebuilt libraries; a second native seam
  duplicates the transport for no benefit.
- **Streaming Zipformer now**: rejected by the user (offline-only scope);
  the ModelScope/sherpa catalog entry stays for a future streaming round.
- **Running decode in a background isolate**: rejected for v1 — sherpa
  requires per-isolate `initBindings`, and the finalizing dock state
  absorbs a few hundred ms to ~1-2 s sensevoice decode; the isolate path
  is the documented next step if latency matters.
- **Keeping the stub and only fixing the engine-reuse bug**: rejected —
  the user asked for real inference ("就是要接入"), and the catalog was
  built for it.

## Consequences

Voice input now transcribes: SenseVoice and Whisper produce real text
offline in the composer (no network, no cloud). The `MODEL_UNSUPPORTED`
error gives streaming-Zipformer selectors a clear, localized message
instead of empty output, and the engine-reuse fix means `finish()` always
sees the session's audio. Tests: pure-Dart model-mapping tests for the
engine (no native load), a controller regression asserting one engine
instance across acceptAudio/finish, and existing mock-engine paths still
pass. APK size grows by the sherpa-onnx native libraries; the router
isolate and streaming Zipformer remain follow-ups.