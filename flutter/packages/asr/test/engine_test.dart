import 'dart:io';
import 'dart:typed_data';

import 'package:asr/asr.dart';
import 'package:test/test.dart';

void main() {
  group('AsrEngine & Implementations', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('asr_engine_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('MockAsrEngine simulates streaming chunk delivery and finalization', () async {
      final engine = MockAsrEngine(
        simulatedChunks: <String>['测试', '语音', '识别'],
        finalTranscription: '测试语音识别。',
      );

      expect(engine.state, equals(AsrEngineState.uninitialized));
      await engine.initialize(AsrModelManifest.senseVoiceSmall, tempDir);
      expect(engine.state, equals(AsrEngineState.ready));

      final List<AsrTranscriptionChunk> chunks = <AsrTranscriptionChunk>[];
      final subscription = engine.transcriptionStream.listen(chunks.add);

      final samples = Float32List(1600);
      engine.acceptAudio(samples);
      engine.acceptAudio(samples);
      engine.acceptAudio(samples);

      expect(engine.state, equals(AsrEngineState.listening));
      expect(engine.receivedSamplesCount, equals(4800));

      final finalResult = await engine.finish();
      expect(finalResult, equals('测试语音识别。'));
      expect(chunks.length, equals(4)); // 3 partials + 1 final
      expect(chunks.last.isFinal, isTrue);
      expect(chunks.last.text, equals('测试语音识别。'));

      await subscription.cancel();
      await engine.dispose();
      expect(engine.state, equals(AsrEngineState.disposed));
    });

    test('StreamingZipformerEngine chunks audio and emits incremental output', () async {
      final engine = StreamingZipformerEngine(
        chunkSizeSamples: 1600,
        runner: (Float32List chunk, bool isLast) async {
          return isLast ? '结束' : '分块 ';
        },
      );

      await engine.initialize(AsrModelManifest.zipformerBilingual, tempDir);

      final List<AsrTranscriptionChunk> chunks = <AsrTranscriptionChunk>[];
      final subscription = engine.transcriptionStream.listen(chunks.add);

      // Supply 3200 samples (2 chunks)
      engine.acceptAudio(Float32List(3200));

      // Wait a microtask loop for runner futures
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(chunks.isNotEmpty, isTrue);

      final result = await engine.finish();
      expect(result, contains('结束'));
      expect(chunks.last.isFinal, isTrue);

      await subscription.cancel();
      await engine.dispose();
    });

    test('NonStreamingAsrEngine accumulates full buffer and decodes on finish', () async {
      int receivedLength = 0;
      final engine = NonStreamingAsrEngine(
        runner: (Float32List audioSamples) async {
          receivedLength = audioSamples.length;
          return '离线非流式识别文本';
        },
      );

      await engine.initialize(AsrModelManifest.senseVoiceSmall, tempDir);

      final List<AsrTranscriptionChunk> chunks = <AsrTranscriptionChunk>[];
      final subscription = engine.transcriptionStream.listen(chunks.add);

      engine.acceptAudio(Float32List(1600));
      engine.acceptAudio(Float32List(1600));

      expect(chunks, isEmpty); // Non-streaming produces no intermediate chunks

      final result = await engine.finish();
      expect(result, equals('离线非流式识别文本'));
      expect(receivedLength, equals(3200));
      expect(chunks.length, equals(1));
      expect(chunks.single.isFinal, isTrue);

      await subscription.cancel();
      await engine.dispose();
    });
  });
}