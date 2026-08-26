import 'package:asr/asr.dart';
import 'package:test/test.dart';

void main() {
  group('AsrModelManifest', () {
    test('contains 3 official models with valid metadata', () {
      expect(AsrModelManifest.all.length, equals(3));

      const AsrModelInfo senseVoice = AsrModelManifest.senseVoiceSmall;
      expect(senseVoice.id, equals('sensevoice-small'));
      expect(senseVoice.name, equals('SenseVoice-Small'));
      expect(senseVoice.files.isNotEmpty, isTrue);

      const AsrModelInfo paraformer =
          AsrModelManifest.paraformerBilingualStreaming;
      expect(paraformer.id, equals('paraformer-bilingual-streaming'));
      expect(paraformer.isStreaming, isTrue);
      expect(paraformer.files.length, equals(3));

      const AsrModelInfo whisper = AsrModelManifest.whisperLargeV3Turbo;
      expect(whisper.id, equals('whisper-large-v3-turbo'));
      expect(whisper.files.length, equals(3));
    });

    test('findById retrieves correct model and returns null for unknown', () {
      expect(AsrModelManifest.findById('sensevoice-small'), isNotNull);
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
