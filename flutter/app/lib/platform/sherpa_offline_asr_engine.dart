/// Real on-device ASR engine backed by sherpa-onnx supporting both
/// streaming (OnlineRecognizer) and offline (OfflineRecognizer) pipelines.
///
/// Implements [AsrEngine] (pure-Dart interface from `packages/asr`) over the
/// sherpa-onnx FFI bindings. Offline only by design (no network).
///
/// Supported models (see `packages/asr` manifest):
/// - Streaming (`OnlineRecognizer`): the transducer Zipformers
///   (`streaming-zipformer-zh`, `streaming-zipformer-multilingual`) via
///   `OnlineTransducerModelConfig` with manifest-resolved file names, plus
///   `paraformer-bilingual-streaming` (discontinued) via
///   `OnlineParaformerModelConfig` — all with real-time partial drafts.
/// - `sensevoice-small`, `funasr-nano-ctc`: `OfflineSenseVoiceModelConfig`
///   (model.int8.onnx + tokens.txt), auto language. Fun-ASR-Nano 2512's CTC
///   export is a SenseVoice-pipeline model (k2-fsa PR #2906) and loads
///   through the same config.
/// - `whisper-large-v3-turbo` (discontinued): `OfflineWhisperModelConfig`
///   (turbo-encoder.int8.onnx + turbo-decoder.int8.onnx + turbo-tokens.txt);
///   kept so an installed copy from an older release keeps working.
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
  Future<void> initialize(AsrModelInfo? model, Directory? modelDir) async {
    // On-device inference has no default: a missing model or weights
    // directory is a caller bug, not a fallback opportunity.
    if (model == null || modelDir == null) {
      throw ArgumentError('sherpa-onnx engines require a model and modelDir');
    }
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
  ///
  /// Manifest-driven: every entry flagged `isStreaming` decodes incrementally
  /// through the online recognizer, everything else decodes whole-utterance.
  static bool isStreamingModel(AsrModelInfo model) => model.isStreaming;

  /// The single ONNX file that identifies the model family, used for the
  /// download-completeness check and to reject unsupported models loudly.
  ///
  /// Sense-voice-family exports identify by their single model file; every
  /// other family identifies by its encoder file (resolved from the manifest
  /// file list). Public for pure-Dart tests (no native load).
  static String modelFileNameFor(AsrModelInfo model) => switch (model.id) {
    'sensevoice-small' || 'funasr-nano-ctc' => 'model.int8.onnx',
    'whisper-large-v3-turbo' => 'turbo-encoder.int8.onnx',
    'paraformer-bilingual-streaming' => 'encoder.int8.onnx',
    _ => _requiredFile(model, 'encoder').name,
  };

  /// Resolves the manifest file whose name starts with [prefix], or throws
  /// loudly — a model whose manifest lacks its identifying files cannot run.
  static AsrModelFile _requiredFile(AsrModelInfo model, String prefix) {
    for (final AsrModelFile file in model.files) {
      if (file.name.startsWith(prefix)) return file;
    }
    throw UnsupportedError(
      'Model ${model.id} has no "$prefix" file in its manifest entry',
    );
  }

  /// Builds the sherpa-onnx offline recognizer configuration for offline [model].
  static sherpa.OfflineRecognizerConfig offlineModelConfigFor(
    AsrModelInfo model,
    Directory modelDir,
  ) {
    switch (model.id) {
      case 'sensevoice-small':
      case 'funasr-nano-ctc':
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
      case 'streaming-zipformer-zh':
      case 'streaming-zipformer-multilingual':
        // Transducer Zipformers: encoder/decoder/joiner file names vary per
        // export (epoch-tagged names), so resolve them from the manifest.
        return sherpa.OnlineRecognizerConfig(
          model: sherpa.OnlineModelConfig(
            transducer: sherpa.OnlineTransducerModelConfig(
              encoder:
                  '${modelDir.path}/${_requiredFile(model, 'encoder').name}',
              decoder:
                  '${modelDir.path}/${_requiredFile(model, 'decoder').name}',
              joiner: '${modelDir.path}/${_requiredFile(model, 'joiner').name}',
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
