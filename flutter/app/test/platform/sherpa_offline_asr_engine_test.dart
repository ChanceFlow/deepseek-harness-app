import 'dart:io';

import 'package:app/platform/sherpa_offline_asr_engine.dart';
import 'package:asr/asr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SherpaOfflineAsrEngine model mapping (pure Dart)', () {
    test('sensevoice-small maps to model.int8.onnx with SenseVoice config', () {
      const info = AsrModelManifest.senseVoiceSmall;
      final dir = Directory('/models');

      expect(SherpaOfflineAsrEngine.modelFileNameFor(info), 'model.int8.onnx');

      final config = SherpaOfflineAsrEngine.modelConfigFor(info, dir);
      expect(config.tokens, '/models/tokens.txt');
      expect(config.senseVoice.model, '/models/model.int8.onnx');
      expect(config.senseVoice.useInverseTextNormalization, isTrue);
      expect(config.modelType, isEmpty);
    });

    test(
      'whisper-large-v3-turbo maps to turbo encoder with Whisper config',
      () {
        const info = AsrModelManifest.whisperLargeV3Turbo;
        final dir = Directory('/models');

        expect(
          SherpaOfflineAsrEngine.modelFileNameFor(info),
          'turbo-encoder.int8.onnx',
        );

        final config = SherpaOfflineAsrEngine.modelConfigFor(info, dir);
        expect(config.tokens, '/models/turbo-tokens.txt');
        expect(config.whisper.encoder, '/models/turbo-encoder.int8.onnx');
        expect(config.whisper.decoder, '/models/turbo-decoder.int8.onnx');
        expect(config.modelType, 'whisper');
      },
    );

    test('streaming zipformer is rejected loudly, not silently', () {
      const info = AsrModelManifest.zipformerBilingual;

      expect(
        () => SherpaOfflineAsrEngine.modelFileNameFor(info),
        throwsUnsupportedError,
      );
      expect(
        () => SherpaOfflineAsrEngine.modelConfigFor(info, Directory('/m')),
        throwsUnsupportedError,
      );
    });
  });
}
