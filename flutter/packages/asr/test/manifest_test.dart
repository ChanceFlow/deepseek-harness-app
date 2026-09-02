import 'package:asr/asr.dart';
import 'package:test/test.dart';

void main() {
  group('AsrModelManifest', () {
    test('contains 4 downloadable models plus 2 discontinued with valid metadata', () {
      expect(AsrModelManifest.all.length, equals(6));
      expect(AsrModelManifest.downloadable.length, equals(4));

      const AsrModelInfo senseVoice = AsrModelManifest.senseVoiceSmall;
      expect(senseVoice.id, equals('sensevoice-small'));
      expect(senseVoice.name, equals('SenseVoice-Small'));
      expect(senseVoice.files.isNotEmpty, isTrue);
      expect(
        senseVoice.huggingFaceRepo,
        equals(
          'csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09',
        ),
        reason: 'the entry must track the 2025 retrained int8 export',
      );

      const AsrModelInfo funasrNano = AsrModelManifest.funasrNanoCtc;
      expect(funasrNano.id, equals('funasr-nano-ctc'));
      expect(funasrNano.isStreaming, isFalse);
      expect(funasrNano.isDiscontinued, isFalse);
      expect(funasrNano.files.length, equals(2));

      // The two streaming Zipformers: encoder + decoder + joiner + tokens
      // each, streaming, and unique ids.
      const List<AsrModelInfo> zipformers = <AsrModelInfo>[
        AsrModelManifest.streamingZipformerZh,
        AsrModelManifest.streamingZipformerMultilingual,
      ];
      for (final AsrModelInfo zipformer in zipformers) {
        expect(zipformer.isStreaming, isTrue, reason: zipformer.id);
        expect(zipformer.isDiscontinued, isFalse, reason: zipformer.id);
        expect(zipformer.files.length, equals(4), reason: zipformer.id);
        expect(
          zipformer.estimatedSizeBytes,
          greaterThan(0),
          reason: zipformer.id,
        );
      }
      expect(
        zipformers.map((AsrModelInfo m) => m.id).toSet().length,
        equals(2),
      );

      // Both shipped-then-retired entries stay listed for installed copies.
      const AsrModelInfo paraformer =
          AsrModelManifest.paraformerBilingualStreaming;
      expect(paraformer.id, equals('paraformer-bilingual-streaming'));
      expect(paraformer.isStreaming, isTrue);
      expect(paraformer.files.length, equals(3));
      expect(paraformer.isDiscontinued, isTrue);

      const AsrModelInfo whisper = AsrModelManifest.whisperLargeV3Turbo;
      expect(whisper.id, equals('whisper-large-v3-turbo'));
      expect(whisper.files.length, equals(3));
      expect(
        whisper.isDiscontinued,
        isTrue,
        reason: 'Whisper is download-refused but keeps installed copies usable',
      );
      expect(
        AsrModelManifest.downloadable.map((AsrModelInfo m) => m.id),
        everyElement(
          isNot(
            anyOf(
              equals('whisper-large-v3-turbo'),
              equals('paraformer-bilingual-streaming'),
            ),
          ),
        ),
      );
    });

    test('findById retrieves correct model and returns null for unknown', () {
      expect(AsrModelManifest.findById('sensevoice-small'), isNotNull);
      expect(AsrModelManifest.findById('funasr-nano-ctc'), isNotNull);
      expect(
        AsrModelManifest.findById('paraformer-bilingual-streaming'),
        isNotNull,
      );
      expect(AsrModelManifest.findById('whisper-large-v3-turbo'), isNotNull);
      expect(AsrModelManifest.findById('non-existent'), isNull);
    });

    test('resolves file URLs for Hugging Face and the China mirror', () {
      for (final AsrModelInfo model in AsrModelManifest.all) {
        expect(model.repoFor(ModelSource.hfMirror), isNotEmpty);
        expect(model.repoFor(ModelSource.huggingFace), isNotEmpty);
        for (final AsrModelFile file in model.files) {
          expect(file.urlFor(ModelSource.hfMirror), contains('hf-mirror.com'));
          expect(
            file.urlFor(ModelSource.huggingFace),
            contains('huggingface.co'),
          );
          expect(file.sizeBytes, greaterThan(0));
          // Unprovisioned checksums are an explicit empty sentinel; any
          // provisioned value must be a full lowercase hex digest.
          expect(
            file.sha256.isEmpty ||
                RegExp(r'^[0-9a-f]{64}$').hasMatch(file.sha256),
            isTrue,
            reason: 'sha256 must be empty (unprovisioned) or 64 hex chars',
          );
        }
      }
    });
  });
}
