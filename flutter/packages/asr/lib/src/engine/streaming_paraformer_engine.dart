/// Pure-Dart stateful coordinator for streaming Paraformer models.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../manifest/model_manifest.dart';
import 'asr_engine.dart';

/// Handler for executing native/ONNX streaming Paraformer forward steps.
typedef StreamingParaformerRunner = Future<String> Function(
  Float32List chunk,
  bool isLast,
);

/// Coordinates streaming chunking, partial emission, and finalization for
/// streaming models like FunASR Paraformer Bilingual Streaming.
class StreamingParaformerEngine implements AsrEngine {
  StreamingParaformerEngine({
    this.chunkSizeSamples = 1600, // 100ms at 16kHz
    StreamingParaformerRunner? runner,
  }) : _runner = runner ?? _defaultRunner;

  final int chunkSizeSamples;
  final StreamingParaformerRunner _runner;

  final StreamController<AsrTranscriptionChunk> _streamController =
      StreamController<AsrTranscriptionChunk>.broadcast(sync: true);

  final List<double> _pendingBuffer = <double>[];
  final StringBuffer _accumulatedText = StringBuffer();

  AsrEngineState _state = AsrEngineState.uninitialized;

  static Future<String> _defaultRunner(Float32List chunk, bool isLast) async {
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
    _pendingBuffer.addAll(samples);

    while (_pendingBuffer.length >= chunkSizeSamples) {
      final chunkList = _pendingBuffer.sublist(0, chunkSizeSamples);
      _pendingBuffer.removeRange(0, chunkSizeSamples);
      final chunk = Float32List.fromList(chunkList);

      unawaited(
        _runner(chunk, false).then((deltaText) {
          if (deltaText.isNotEmpty && !_streamController.isClosed) {
            _accumulatedText.write(deltaText);
            _streamController.add(
              AsrTranscriptionChunk(
                text: _accumulatedText.toString(),
                isFinal: false,
              ),
            );
          }
        }),
      );
    }
  }

  @override
  Future<String> finish() async {
    _state = AsrEngineState.transcribing;
    final remainingSamples = Float32List.fromList(_pendingBuffer);
    _pendingBuffer.clear();

    final lastDelta = await _runner(remainingSamples, true);
    if (lastDelta.isNotEmpty) {
      _accumulatedText.write(lastDelta);
    }

    final String finalResult = _accumulatedText.toString();
    if (!_streamController.isClosed) {
      _streamController.add(
        AsrTranscriptionChunk(text: finalResult, isFinal: true),
      );
    }
    _state = AsrEngineState.ready;
    return finalResult;
  }

  @override
  void reset() {
    _pendingBuffer.clear();
    _accumulatedText.clear();
    _state = AsrEngineState.ready;
  }

  @override
  Future<void> dispose() async {
    _state = AsrEngineState.disposed;
    reset();
    await _streamController.close();
  }
}
