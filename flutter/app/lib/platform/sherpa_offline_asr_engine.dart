/// Real on-device ASR engine backed by sherpa-onnx supporting both
/// streaming (OnlineRecognizer) and offline (OfflineRecognizer) pipelines.
///
/// Implements [AsrEngine] (pure-Dart interface from `packages/asr`) over the
/// sherpa-onnx FFI bindings. Offline only by design (no network).
///
/// Supported models (see `packages/asr` manifest):
/// - `paraformer-bilingual-streaming`: `OnlineParaformerModelConfig` (encoder.int8.onnx +
///   decoder.int8.onnx + tokens.txt) with real-time partial drafts.
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

/// Real on-device recognizer built on sherpa-onnx.
class SherpaOfflineAsrEngine implements AsrEngine {
  SherpaOfflineAsrEngine();

  static bool _bindingsInitialized = false;

  final StreamController<AsrTranscriptionChunk> _chunkController =
      StreamController<AsrTranscriptionChunk>.broadcast(sync: true);

  AsrEngineState _state = AsrEngineState.uninitialized;
  bool _isStreaming = false;

  // Offline engine state
  sherpa.OfflineRecognizer? _offlineRecognizer;
  final List<double> _accumulatedSamples = <double>[];

  // Online / Streaming engine state
  sherpa.OnlineRecognizer? _onlineRecognizer;
  sherpa.OnlineStream? _onlineStream;
  String _lastPartialText = '';

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

    _disposeRecognizers();

    _isStreaming = isStreamingModel(model);
    if (_isStreaming) {
      final config = onlineModelConfigFor(model, modelDir);
      _onlineRecognizer = sherpa.OnlineRecognizer(config);
      _onlineStream = _onlineRecognizer!.createStream();
      _lastPartialText = '';
    } else {
      final config = offlineModelConfigFor(model, modelDir);
      _offlineRecognizer = sherpa.OfflineRecognizer(config);
      _accumulatedSamples.clear();
    }

    _state = AsrEngineState.ready;
  }

  void _disposeRecognizers() {
    _onlineStream?.free();
    _onlineStream = null;
    _onlineRecognizer?.free();
    _onlineRecognizer = null;
    _offlineRecognizer?.free();
    _offlineRecognizer = null;
    _lastPartialText = '';
    _accumulatedSamples.clear();
  }

  @override
  void acceptAudio(Float32List samples) {
    if (_state != AsrEngineState.ready && _state != AsrEngineState.listening) {
      return;
    }
    _state = AsrEngineState.listening;

    if (_isStreaming) {
      final stream = _onlineStream;
      final recognizer = _onlineRecognizer;
      if (stream == null || recognizer == null) return;

      stream.acceptWaveform(samples: samples, sampleRate: 16000);
      while (recognizer.isReady(stream)) {
        recognizer.decode(stream);
      }
      final partialText = recognizer.getResult(stream).text;
      if (partialText.isNotEmpty && partialText != _lastPartialText) {
        _lastPartialText = partialText;
        if (!_chunkController.isClosed) {
          _chunkController.add(
            AsrTranscriptionChunk(text: partialText, isFinal: false),
          );
        }
      }
    } else {
      _accumulatedSamples.addAll(samples);
    }
  }

  @override
  Future<String> finish() async {
    _state = AsrEngineState.transcribing;

    if (_isStreaming) {
      final stream = _onlineStream;
      final recognizer = _onlineRecognizer;
      if (stream == null || recognizer == null) {
        _state = AsrEngineState.ready;
        return '';
      }

      stream.inputFinished();
      while (recognizer.isReady(stream)) {
        recognizer.decode(stream);
      }
      final resultText = recognizer.getResult(stream).text;
      final finalText = resultText.isNotEmpty ? resultText : _lastPartialText;

      if (!_chunkController.isClosed) {
        _chunkController.add(
          AsrTranscriptionChunk(text: finalText, isFinal: true),
        );
      }
      _state = AsrEngineState.ready;
      return finalText;
    } else {
      final recognizer = _offlineRecognizer;
      if (recognizer == null) {
        _state = AsrEngineState.ready;
        return '';
      }
      if (_accumulatedSamples.isEmpty) {
        _state = AsrEngineState.ready;
        return '';
      }

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
  }

  @override
  void reset() {
    _accumulatedSamples.clear();
    _lastPartialText = '';
    if (_isStreaming) {
      _onlineStream?.free();
      _onlineStream = _onlineRecognizer?.createStream();
    }
    _state = (_onlineRecognizer != null || _offlineRecognizer != null)
        ? AsrEngineState.ready
        : AsrEngineState.uninitialized;
  }

  @override
  Future<void> dispose() async {
    _state = AsrEngineState.disposed;
    _disposeRecognizers();
    await _chunkController.close();
  }

  /// Whether the [model] runs in real-time streaming mode via [sherpa.OnlineRecognizer].
  static bool isStreamingModel(AsrModelInfo model) => switch (model.id) {
    'paraformer-bilingual-streaming' => true,
    _ => false,
  };

  /// The single ONNX file that identifies the model family, used for the
  /// download-completeness check and to reject unsupported models loudly.
  ///
  /// Public for pure-Dart tests (no native load).
  static String modelFileNameFor(AsrModelInfo model) => switch (model.id) {
    'sensevoice-small' => 'model.int8.onnx',
    'whisper-large-v3-turbo' => 'turbo-encoder.int8.onnx',
    'paraformer-bilingual-streaming' => 'encoder.int8.onnx',
    _ => throw UnsupportedError(
      'Model ${model.id} is not supported by the ASR engine',
    ),
  };

  /// Builds the sherpa-onnx offline recognizer configuration for offline [model].
  static sherpa.OfflineRecognizerConfig offlineModelConfigFor(
    AsrModelInfo model,
    Directory modelDir,
  ) {
    switch (model.id) {
      case 'sensevoice-small':
        return sherpa.OfflineRecognizerConfig(
          model: sherpa.OfflineModelConfig(
            senseVoice: sherpa.OfflineSenseVoiceModelConfig(
              model: '${modelDir.path}/model.int8.onnx',
              language: '', // auto
              useInverseTextNormalization: true,
            ),
            tokens: '${modelDir.path}/tokens.txt',
            numThreads: 1,
            debug: false,
          ),
        );
      case 'whisper-large-v3-turbo':
        return sherpa.OfflineRecognizerConfig(
          model: sherpa.OfflineModelConfig(
            whisper: sherpa.OfflineWhisperModelConfig(
              encoder: '${modelDir.path}/turbo-encoder.int8.onnx',
              decoder: '${modelDir.path}/turbo-decoder.int8.onnx',
            ),
            tokens: '${modelDir.path}/turbo-tokens.txt',
            modelType: 'whisper',
            numThreads: 1,
            debug: false,
          ),
        );
      default:
        throw UnsupportedError('Model ${model.id} is not an offline model');
    }
  }

  /// Legacy helper returning the [sherpa.OfflineModelConfig] component.
  static sherpa.OfflineModelConfig modelConfigFor(
    AsrModelInfo model,
    Directory modelDir,
  ) => offlineModelConfigFor(model, modelDir).model;

  /// Builds the sherpa-onnx online recognizer configuration for streaming [model].
  static sherpa.OnlineRecognizerConfig onlineModelConfigFor(
    AsrModelInfo model,
    Directory modelDir,
  ) {
    switch (model.id) {
      case 'paraformer-bilingual-streaming':
        return sherpa.OnlineRecognizerConfig(
          model: sherpa.OnlineModelConfig(
            paraformer: sherpa.OnlineParaformerModelConfig(
              encoder: '${modelDir.path}/encoder.int8.onnx',
              decoder: '${modelDir.path}/decoder.int8.onnx',
            ),
            tokens: '${modelDir.path}/tokens.txt',
            numThreads: 1,
            debug: false,
          ),
          enableEndpoint: true,
          rule1MinTrailingSilence: 2.4,
          rule2MinTrailingSilence: 1.2,
          rule3MinUtteranceLength: 20,
          decodingMethod: 'greedy_search',
        );
      default:
        throw UnsupportedError('Model ${model.id} is not a streaming model');
    }
  }
}
