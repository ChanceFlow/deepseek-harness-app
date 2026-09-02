# Agent Note: On-device voice input and speech recognition integration

Status: implemented

## Problem

While P1 delivered the client-side download and registry subsystem for on-device ASR models, the client still lacked the ability to actually record microphone audio, run on-device inference, and stream transcribed text into the chat composer.

Voice input on mobile requires:
1. Low-latency, privacy-preserving local audio capture (16 kHz Mono PCM) without sending user voice to external cloud servers.
2. Decoupled engine abstractions supporting both streaming transducer models (Zipformer) for real-time dictation and non-streaming models (SenseVoice, Whisper) for high-accuracy offline utterances.
3. A stock Material 3 recording dock adhering to the client's visual standards, with responsive amplitude waveforms, elapsed timer, and live cursor text injection.

## Decision

### Decoupled ASR engine and audio streaming architecture

In `flutter/packages/asr`:
- Defined `AsrEngine` abstraction supporting `StreamingZipformerEngine` (chunked forward steps) and `NonStreamingAsrEngine` (buffered utterance forward steps).
- Defined `AudioInputSource` interface for 16 kHz Mono Float32 PCM streaming with normalized RMS amplitude emission.
- Added `activeModelId` management to `ModelsRegistry` and `AsrModelManager`, enabling runtime selection of the primary voice recognition model with automatic fallback to any installed model.

### Platform audio capture & permission bridge

In `flutter/app`:
- Declared `RECORD_AUDIO` permission in `AndroidManifest.xml`.
- Implemented `PlatformAudioRecorder` talking to Android `AudioRecord` via `dsh/audio_record` and `dsh/audio_stream` channels in `MainActivity.kt`.
- Built `VoiceInputController` UDF stream state machine managing recording sessions, permission requests, and live transcription callbacks.

### Stock Material 3 composer integration

In `flutter/app/lib/ui/chat/`:
- Added `VoiceMicButton` (28px circular button matching the `_PlusButton` style) in the composer tools row.
- Implemented `VoiceRecordingDock` (M3 `surfaceContainerLow` banner with pulsing red record indicator, mm:ss timer, 8 dynamic soundwave bars, and Cancel / Done controls).
- Streamed transcription chunks directly into `_draftController` with pre-recording draft preservation on cancel.
- Added "Active speech model" selector in Settings ASR preferences when downloaded models are present.

## Alternatives considered

- **Cloud ASR proxy fallback**: Rejected because DeepSeek Harness is an offline-first, privacy-focused client; sending raw microphone audio to third-party endpoints violates user privacy expectations. (Partially superseded on 2026-09-02: offline remains the default mode, but the user can now opt into online voice input with their own provider credentials — see [online ASR providers](2026-09-02-online-asr-providers.md).)
- **Floating voice overlay / modal bottom sheet**: Rejected because modal sheets obscure the conversation transcript and disrupt the flow of message drafting. The dock-integrated `VoiceRecordingDock` keeps context visible while dictating.
- **Monolithic engine tied to Flutter UI**: Rejected to maintain absolute package boundaries: `packages/asr` handles models, engines, and audio streams independently of Flutter widgets.

## Consequences

- Users can dictact messages directly in the chat composer with zero network dependency.
- Material 3 aesthetic remains cohesive across light and dark modes with full bilingual ARB localization.
- Design review golden shots published for visual verification at `http://127.0.0.1:8899/design/`.