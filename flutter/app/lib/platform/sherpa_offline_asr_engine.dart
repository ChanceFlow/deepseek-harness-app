/// Real on-device offline ASR engine backed by sherpa-onnx.
///
/// Implements [AsrEngine] (pure-Dart interface from `packages/asr`) over the
/// sherpa-onnx FFI bindings. Offline only by design: audio is accumulated
/// during the session and decoded once in [finish] via
/// `OfflineRecognizer` — there is no network, and the streaming Zipformer
/// path (OnlineRecognizer) is intentionally not wired up yet.
///
/// Supported models (see `packages/asr` manifest):
/// - `sensevoice-small`: `OfflineSenseVoiceModelConfig` (model.int8.onnx +
///   tokens.txt), auto language.
/// - `whisper-large-v3-turbo`: `OfflineWhisperModelConfig`
///   (turbo-encoder.int8.onnx + turbo-decoder.int8.onnx + turbo-tokens.txt).
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:asr/asr.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Real offline recognizer built on sherpa-onnx.
class SherpaOfflineAsrEngine implements AsrEngine {
  SherpaOfflineAsrEngine();

  static bool _bindingsInitialized = false;

  final StreamController<AsrTranscriptionChunk> _chunkController =
      StreamController<AsrTranscriptionChunk>.broadcast(sync: true);

  AsrEngineState _state = AsrEngineState.uninitialized;
  sherpa.OfflineRecognizer? _recognizer;
  final List<double> _accumulatedSamples = <double>[];

  @override
  AsrEngineState get state => _state;

  @override
  Stream<AsrTranscriptionChunk> get transcriptionStream =>
      _chunkController.stream;

  @override
  Future<void> initialize(AsrModelInfo model, Directory modelDir) async {
    if (_state != AsrEngineState.uninitialized &&
        _state != AsrEngineState.ready) {
      return;
    }
    final file = File('${modelDir.path}/${modelFileNameFor(model)}');
    if (!await file.exists()) {
      throw StateError(
        'ASR model file missing at ${file.path}; download the model in '
        'Settings first',
      );
    }
    if (!_bindingsInitialized) {
      sherpa.initBindings();
      _bindingsInitialized = true;
    }
    _recognizer?.free();
    _recognizer = sherpa.OfflineRecognizer(
      sherpa.OfflineRecognizerConfig(model: modelConfigFor(model, modelDir)),
    );
    _state = AsrEngineState.ready;
  }

  @override
  void acceptAudio(Float32List samples) {
    if (_state != AsrEngineState.ready && _state != AsrEngineState.listening) {
      return;
    }
    _state = AsrEngineState.listening;
    _accumulatedSamples.addAll(samples);
  }

  @override
  Future<String> finish() async {
    final recognizer = _recognizer;
    if (recognizer == null) {
      _state = AsrEngineState.ready;
      return '';
    }
    _state = AsrEngineState.transcribing;
    if (_accumulatedSamples.isEmpty) {
      _state = AsrEngineState.ready;
      return '';
    }

    // Synchronous decode on the calling isolate: for SenseVoice int8 this
    // is typically a few hundred ms to ~1-2 s on a phone, spent in the
    // finalizing state of the recording dock. Acceptable for v1; a
    // background-isolate decode (with its own initBindings) is the
    // documented upgrade path.
    final stream = recognizer.createStream();
    stream.acceptWaveform(
      samples: Float32List.fromList(_accumulatedSamples),
      sampleRate: 16000,
    );
    recognizer.decode(stream);
    final result = recognizer.getResult(stream);
    stream.free();
    _accumulatedSamples.clear();

    if (!_chunkController.isClosed) {
      _chunkController.add(
        AsrTranscriptionChunk(text: result.text, isFinal: true),
      );
    }
    _state = AsrEngineState.ready;
    return result.text;
  }

  @override
  void reset() {
    _accumulatedSamples.clear();
    _state = _recognizer == null
        ? AsrEngineState.uninitialized
        : AsrEngineState.ready;
  }

  @override
  Future<void> dispose() async {
    _state = AsrEngineState.disposed;
    _accumulatedSamples.clear();
    _recognizer?.free();
    _recognizer = null;
    await _chunkController.close();
  }

  /// The single ONNX file that identifies the model family, used for the
  /// download-completeness check and to reject unsupported models loudly.
  ///
  /// Public for pure-Dart tests (no native load).
  static String modelFileNameFor(AsrModelInfo model) => switch (model.id) {
        'sensevoice-small' => 'model.int8.onnx',
        'whisper-large-v3-turbo' => 'turbo-encoder.int8.onnx',
        _ => throw UnsupportedError(
            'Model ${model.id} is not supported by the offline engine '
            '(streaming models are not wired up yet)',
          ),
      };

  /// Builds the sherpa-onnx offline model configuration for [model].
  /// Pure Dart object construction — no native calls — so it is unit
  /// testable without model files or an Android runtime.
  static sherpa.OfflineModelConfig modelConfigFor(
    AsrModelInfo model,
    Directory modelDir,
  ) {
    switch (model.id) {
      case 'sensevoice-small':
        return sherpa.OfflineModelConfig(
          senseVoice: sherpa.OfflineSenseVoiceModelConfig(
            model: '${modelDir.path}/model.int8.onnx',
            language: '', // auto
            useInverseTextNormalization: true,
          ),
          tokens: '${modelDir.path}/tokens.txt',
          numThreads: 1,
          debug: false,
        );
      case 'whisper-large-v3-turbo':
        return sherpa.OfflineModelConfig(
          whisper: sherpa.OfflineWhisperModelConfig(
            encoder: '${modelDir.path}/turbo-encoder.int8.onnx',
            decoder: '${modelDir.path}/turbo-decoder.int8.onnx',
          ),
          tokens: '${modelDir.path}/turbo-tokens.txt',
          modelType: 'whisper',
          numThreads: 1,
          debug: false,
        );
      default:
        throw UnsupportedError(
          'Model ${model.id} is not supported by the offline engine '
          '(streaming models are not wired up yet)',
        );
    }
  }
}