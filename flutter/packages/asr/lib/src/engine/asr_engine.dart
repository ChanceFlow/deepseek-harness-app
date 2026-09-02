/// ASR engine interface and transcription chunk models.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../manifest/model_manifest.dart';

/// Chunk of transcription emitted during speech recognition.
class AsrTranscriptionChunk {
  const AsrTranscriptionChunk({
    required this.text,
    required this.isFinal,
    this.confidence,
  });

  /// The recognized text segment.
  final String text;

  /// Whether this is a finalized segment or an intermediate partial draft.
  final bool isFinal;

  /// Optional recognition confidence score (0.0 - 1.0).
  final double? confidence;

  @override
  String toString() => 'AsrTranscriptionChunk(text: $text, isFinal: $isFinal)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AsrTranscriptionChunk &&
          runtimeType == other.runtimeType &&
          text == other.text &&
          isFinal == other.isFinal &&
          confidence == other.confidence;

  @override
  int get hashCode => Object.hash(text, isFinal, confidence);
}

/// Lifecycle state of an [AsrEngine].
enum AsrEngineState { uninitialized, ready, listening, transcribing, disposed }

/// Abstract interface for speech recognition engines.
///
/// Implementations are either on-device ([SherpaOfflineAsrEngine]-style,
/// backed by local model weights) or cloud-backed streaming engines that
/// ship audio to an online service. On-device engines require both the
/// model info and its local weights directory; cloud engines ignore both
/// (their identity lives in the constructor config) and fail loud if
/// handed credentials that are not configured.
abstract interface class AsrEngine {
  /// Current lifecycle state of the engine.
  AsrEngineState get state;

  /// Stream of recognized text chunks.
  ///
  /// Engines report failures through [finish] (throwing) rather than
  /// [Stream.addError]: consumers listen without an [onError] handler.
  Stream<AsrTranscriptionChunk> get transcriptionStream;

  /// Initializes the engine. On-device engines use [model] (catalog entry)
  /// and [modelDir] (local weights directory); cloud engines ignore both.
  Future<void> initialize(AsrModelInfo? model, Directory? modelDir);

  /// Accepts incoming PCM audio samples (16 kHz, 16-bit Mono, float32 normalized [-1.0, 1.0]).
  void acceptAudio(Float32List samples);

  /// Signals that the audio input has ended and flushes/finalizes the transcription.
  Future<String> finish();

  /// Resets intermediate state and discards in-flight audio buffers.
  void reset();

  /// Releases native and memory resources.
  Future<void> dispose();
}
