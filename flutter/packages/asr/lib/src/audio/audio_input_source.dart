/// Audio recording stream interface for 16 kHz Mono PCM capture.
library;

import 'dart:async';
import 'dart:typed_data';

/// Interface for audio capture devices providing 16 kHz Mono PCM audio.
abstract interface class AudioInputSource {
  /// Stream of 16 kHz Mono Float32 PCM audio buffers.
  Stream<Float32List> get audioStream;

  /// Stream of normalized audio amplitude levels (0.0 - 1.0) for UI waveforms.
  Stream<double> get amplitudeStream;

  /// Whether audio recording is currently active.
  bool get isRecording;

  /// Starts capturing audio at the given sample rate (defaults to 16000 Hz).
  Future<void> start({int sampleRate = 16000});

  /// Stops audio capture and closes the stream.
  Future<void> stop();

  /// Disposes recording resources.
  Future<void> dispose();
}
