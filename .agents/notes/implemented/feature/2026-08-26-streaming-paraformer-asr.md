# Agent Note: Streaming FunASR Paraformer bilingual model and online decoding

Status: implemented

## Problem

The previous on-device ASR system only supported non-streaming models
(SenseVoice-Small and Whisper large-v3-turbo via `OfflineRecognizer`), while
the middle model catalog entry was Zipformer Bilingual (which required 4
separate files and had not been wired to the inference engine). Voice input
required waiting for the whole recording to finish before starting
transcription, preventing a true real-time streaming dictation experience
where draft text appears dynamically in the composer as the user speaks.

## Decision

Adopt the FunASR Paraformer bilingual streaming architecture as the official
bilingual streaming solution and upgrade `SherpaOfflineAsrEngine` to support
both `OnlineRecognizer` and `OfflineRecognizer`:

- **Replaced middle model in `AsrModelManifest`**: Removed Zipformer Bilingual
  and added `paraformer-bilingual-streaming` (`Paraformer Bilingual (Streaming)`),
  backed by `csukuangfj/sherpa-onnx-streaming-paraformer-bilingual-zh-en`
  (`encoder.int8.onnx`, `decoder.int8.onnx`, and `tokens.txt`).
- **Unified `SherpaOfflineAsrEngine` online & offline inference**:
  - For streaming models (`isStreamingModel`), instantiate `sherpa.OnlineRecognizer`
    with `OnlineParaformerModelConfig` and initialize an `OnlineStream`.
  - In `acceptAudio()`, push 16kHz PCM chunks to `OnlineStream.acceptWaveform()`,
    decode ready frames in real-time, and emit intermediate non-final
    `AsrTranscriptionChunk` drafts onto `transcriptionStream`.
  - In `finish()`, signal `OnlineStream.inputFinished()`, decode remaining frames,
    and emit the final transcription result.
  - For non-streaming models (`sensevoice-small`, `whisper-large-v3-turbo`), preserve
    the batch `OfflineRecognizer` pipeline.
- **Pure-Dart coordinator**: Updated `StreamingParaformerEngine` in `packages/asr`
  for testing streaming chunking and incremental text emission without native FFI
  bindings.

## Alternatives considered

- **Retaining Zipformer Bilingual**: Rejected — Zipformer Bilingual requires 4
  distribution files (encoder, decoder, joiner, bpe.model) totaling ~198MB,
  whereas FunASR Paraformer is native streaming, specialized for Chinese-English
  code switching, and uses standard token dictionary mappings.
- **Whisper-based chunk streaming**: Rejected — Whisper is inherently
  non-streaming encoder-decoder architecture; simulating streaming via sliding
  audio windows on mobile devices incurs massive CPU overhead and severe latency.

## Consequences

Users can now speak naturally in Chinese, English, or mixed code-switching
and see immediate live text drafts streaming into the chat composer in real
time. Both streaming Paraformer and offline SenseVoice/Whisper models are
supported under a single clean `AsrEngine` contract. All unit and widget
tests pass with 100% compliance.
