/// Pure-Dart stateful coordinator for non-streaming offline ASR models (SenseVoice, Whisper).
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../manifest/model_manifest.dart';
import 'asr_engine.dart';

/// Handler for executing native/ONNX non-streaming offline speech recognition forward steps.
typedef OfflineAsrRunner = Future<String> Function(Float32List audioSamples);

/// Coordinates buffer accumulation and full-utterance inference for offline models
/// like SenseVoice-Small and Whisper-Turbo.
class NonStreamingAsrEngine implements AsrEngine {
  NonStreamingAsrEngine({
    OfflineAsrRunner? runner,
  }) : _runner = runner ?? _defaultRunner;

  final OfflineAsrRunner _runner;
  final StreamController<AsrTranscriptionChunk> _streamController =
      StreamController<AsrTranscriptionChunk>.broadcast(sync: true);

  final List<double> _accumulatedSamples = <double>[];
  AsrEngineState _state = AsrEngineState.uninitialized;

  static Future<String> _defaultRunner(Float32List audioSamples) async {
    return '';
  }

  @override
  AsrEngineState get state => _state;

  @override
  Stream<AsrTranscriptionChunk> get transcriptionStream =>
      _streamController.stream;

  @override
  Future<void> initialize(AsrModelInfo model, Directory modelDir) async {
    _state = AsrEngineState.ready;
    reset();
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
    _state = AsrEngineState.transcribing;
    if (_accumulatedSamples.isEmpty) {
      _state = AsrEngineState.ready;
      return '';
    }

    final Float32List allSamples = Float32List.fromList(_accumulatedSamples);
    final String result = await _runner(allSamples);

    if (!_streamController.isClosed) {
      _streamController.add(
        AsrTranscriptionChunk(
          text: result,
          isFinal: true,
        ),
      );
    }
    _state = AsrEngineState.ready;
    return result;
  }

  @override
  void reset() {
    _accumulatedSamples.clear();
    _state = AsrEngineState.ready;
  }

  @override
  Future<void> dispose() async {
    _state = AsrEngineState.disposed;
    reset();
    await _streamController.close();
  }
}