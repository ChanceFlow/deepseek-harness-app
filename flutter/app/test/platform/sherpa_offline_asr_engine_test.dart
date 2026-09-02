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
      expect(SherpaOfflineAsrEngine.isStreamingModel(info), isFalse);

      final config = SherpaOfflineAsrEngine.modelConfigFor(info, dir);
      expect(config.tokens, '/models/tokens.txt');
      expect(config.senseVoice.model, '/models/model.int8.onnx');
      expect(config.senseVoice.useInverseTextNormalization, isTrue);
      expect(config.modelType, isEmpty);
    });

    test('funasr-nano-ctc maps to model.int8.onnx with SenseVoice config', () {
      const info = AsrModelManifest.funasrNanoCtc;
      final dir = Directory('/models');

      expect(SherpaOfflineAsrEngine.modelFileNameFor(info), 'model.int8.onnx');
      expect(SherpaOfflineAsrEngine.isStreamingModel(info), isFalse);

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
        expect(SherpaOfflineAsrEngine.isStreamingModel(info), isFalse);

        final config = SherpaOfflineAsrEngine.modelConfigFor(info, dir);
        expect(config.tokens, '/models/turbo-tokens.txt');
        expect(config.whisper.encoder, '/models/turbo-encoder.int8.onnx');
        expect(config.whisper.decoder, '/models/turbo-decoder.int8.onnx');
        expect(config.modelType, 'whisper');
      },
    );

    test(
      'transducer Zipformer maps encoder/decoder/joiner from the manifest',
      () {
        const info = AsrModelManifest.streamingZipformerZh;
        final dir = Directory('/models');

        expect(
          SherpaOfflineAsrEngine.modelFileNameFor(info),
          'encoder.int8.onnx',
        );
        expect(SherpaOfflineAsrEngine.isStreamingModel(info), isTrue);

        final onlineConfig = SherpaOfflineAsrEngine.onlineModelConfigFor(
          info,
          dir,
        );
        expect(onlineConfig.model.tokens, '/models/tokens.txt');
        expect(
          onlineConfig.model.transducer.encoder,
          '/models/encoder.int8.onnx',
        );
        expect(onlineConfig.model.transducer.decoder, '/models/decoder.onnx');
        expect(
          onlineConfig.model.transducer.joiner,
          '/models/joiner.int8.onnx',
        );
        expect(onlineConfig.enableEndpoint, isTrue);
        expect(onlineConfig.decodingMethod, 'greedy_search');
      },
    );

    test('epoch-tagged transducer files resolve from the manifest entry', () {
      const multilingual = AsrModelManifest.streamingZipformerMultilingual;
      const config = SherpaOfflineAsrEngine.modelConfigFor;
      expect(
        () => config(multilingual, Directory('/m')),
        throwsUnsupportedError,
        reason: 'transducer models are streaming-only, offline config rejects',
      );
      expect(
        SherpaOfflineAsrEngine.modelFileNameFor(multilingual),
        'encoder-epoch-75-avg-11-chunk-16-left-128.int8.onnx',
      );
      expect(SherpaOfflineAsrEngine.isStreamingModel(multilingual), isTrue);

      final onlineConfig = SherpaOfflineAsrEngine.onlineModelConfigFor(
        multilingual,
        Directory('/models'),
      );
      expect(
        onlineConfig.model.transducer.encoder,
        '/models/encoder-epoch-75-avg-11-chunk-16-left-128.int8.onnx',
      );
      expect(
        onlineConfig.model.transducer.decoder,
        '/models/decoder-epoch-75-avg-11-chunk-16-left-128.onnx',
      );
      expect(
        onlineConfig.model.transducer.joiner,
        '/models/joiner-epoch-75-avg-11-chunk-16-left-128.int8.onnx',
      );

      // Discontinued-but-kept streaming entry: installed copies still map.
      const paraformer = AsrModelManifest.paraformerBilingualStreaming;
      expect(paraformer.isDiscontinued, isTrue);
      expect(SherpaOfflineAsrEngine.isStreamingModel(paraformer), isTrue);
      expect(
        SherpaOfflineAsrEngine.modelFileNameFor(paraformer),
        'encoder.int8.onnx',
      );
    });

    test('paraformer-bilingual-streaming maps to encoder.int8.onnx with online config', () {
      const info = AsrModelManifest.paraformerBilingualStreaming;
      final dir = Directory('/models');

      expect(
        SherpaOfflineAsrEngine.modelFileNameFor(info),
        'encoder.int8.onnx',
      );
      expect(SherpaOfflineAsrEngine.isStreamingModel(info), isTrue);

      final onlineConfig = SherpaOfflineAsrEngine.onlineModelConfigFor(
        info,
        dir,
      );
      expect(onlineConfig.model.tokens, '/models/tokens.txt');
      expect(
        onlineConfig.model.paraformer.encoder,
        '/models/encoder.int8.onnx',
      );
      expect(
        onlineConfig.model.paraformer.decoder,
        '/models/decoder.int8.onnx',
      );
      expect(onlineConfig.enableEndpoint, isTrue);
      expect(onlineConfig.decodingMethod, 'greedy_search');
    });

    test('unknown model is rejected loudly', () {
      const unknown = AsrModelInfo(
        id: 'unknown-model',
        name: 'Unknown',
        descriptionZh: '未知',
        descriptionEn: 'Unknown',
        languages: '未知',
        estimatedSizeBytes: 100,
        license: 'MIT',
        huggingFaceRepo: 'repo',
        files: <AsrModelFile>[],
      );

      expect(
        () => SherpaOfflineAsrEngine.modelFileNameFor(unknown),
        throwsUnsupportedError,
      );
      expect(
        () => SherpaOfflineAsrEngine.modelConfigFor(unknown, Directory('/m')),
        throwsUnsupportedError,
      );
      expect(
        () => SherpaOfflineAsrEngine.onlineModelConfigFor(
          unknown,
          Directory('/m'),
        ),
        throwsUnsupportedError,
      );
    });
  });
}
