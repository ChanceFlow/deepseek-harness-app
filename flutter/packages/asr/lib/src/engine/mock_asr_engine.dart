/// Mock and simulated implementations of [AsrEngine] for testing and validation.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../manifest/model_manifest.dart';
import 'asr_engine.dart';

/// Test implementation of [AsrEngine] with controllable canned responses and chunk timing.
class MockAsrEngine implements AsrEngine {
  MockAsrEngine({
    this.simulatedChunks = const <String>['测试', '语音', '识别'],
    this.finalTranscription = '测试语音识别。',
  });

  final List<String> simulatedChunks;
  final String finalTranscription;

  final StreamController<AsrTranscriptionChunk> _chunkController =
      StreamController<AsrTranscriptionChunk>.broadcast(sync: true);

  AsrEngineState _state = AsrEngineState.uninitialized;
  int _chunkIndex = 0;
  int _receivedSamplesCount = 0;

  int get receivedSamplesCount => _receivedSamplesCount;

  @override
  AsrEngineState get state => _state;

  @override
  Stream<AsrTranscriptionChunk> get transcriptionStream => _chunkController.stream;

  @override
  Future<void> initialize(AsrModelInfo model, Directory modelDir) async {
    _state = AsrEngineState.ready;
  }

  @override
  void acceptAudio(Float32List samples) {
    if (_state != AsrEngineState.ready && _state != AsrEngineState.listening) return;
    _state = AsrEngineState.listening;
    _receivedSamplesCount += samples.length;

    if (_chunkIndex < simulatedChunks.length) {
      final chunkText = simulatedChunks[_chunkIndex++];
      _chunkController.add(
        AsrTranscriptionChunk(
          text: chunkText,
          isFinal: false,
        ),
      );
    }
  }

  @override
  Future<String> finish() async {
    _state = AsrEngineState.transcribing;
    _chunkController.add(
      AsrTranscriptionChunk(
        text: finalTranscription,
        isFinal: true,
      ),
    );
    _state = AsrEngineState.ready;
    return finalTranscription;
  }

  @override
  void reset() {
    _chunkIndex = 0;
    _receivedSamplesCount = 0;
    _state = AsrEngineState.ready;
  }

  @override
  Future<void> dispose() async {
    _state = AsrEngineState.disposed;
    await _chunkController.close();
  }
}