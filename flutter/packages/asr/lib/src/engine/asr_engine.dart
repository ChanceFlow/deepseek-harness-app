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

/// Abstract interface for on-device speech recognition engines.
abstract interface class AsrEngine {
  /// Current lifecycle state of the engine.
  AsrEngineState get state;

  /// Stream of recognized text chunks.
  Stream<AsrTranscriptionChunk> get transcriptionStream;

  /// Initializes the engine with the model configuration and local weights directory.
  Future<void> initialize(AsrModelInfo model, Directory modelDir);

  /// Accepts incoming PCM audio samples (16 kHz, 16-bit Mono, float32 normalized [-1.0, 1.0]).
  void acceptAudio(Float32List samples);

  /// Signals that the audio input has ended and flushes/finalizes the transcription.
  Future<String> finish();

  /// Resets intermediate state and discards in-flight audio buffers.
  void reset();

  /// Releases native and memory resources.
  Future<void> dispose();
}
