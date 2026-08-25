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

      const AsrModelInfo zipformer = AsrModelManifest.zipformerBilingual;
      expect(zipformer.id, equals('zipformer-bilingual'));
      expect(zipformer.files.length, equals(4));

      const AsrModelInfo whisper = AsrModelManifest.whisperLargeV3Turbo;
      expect(whisper.id, equals('whisper-large-v3-turbo'));
      expect(whisper.files.length, equals(2));
    });

    test('findById retrieves correct model and returns null for unknown', () {
      expect(AsrModelManifest.findById('sensevoice-small'), isNotNull);
      expect(AsrModelManifest.findById('zipformer-bilingual'), isNotNull);
      expect(AsrModelManifest.findById('whisper-large-v3-turbo'), isNotNull);
      expect(AsrModelManifest.findById('non-existent'), isNull);
    });

    test('resolves file URLs for both ModelScope and Hugging Face', () {
      for (final AsrModelInfo model in AsrModelManifest.all) {
        expect(model.repoFor(ModelSource.modelScope), isNotEmpty);
        expect(model.repoFor(ModelSource.huggingFace), isNotEmpty);
        for (final AsrModelFile file in model.files) {
          expect(file.urlFor(ModelSource.modelScope), contains('modelscope.cn'));
          expect(file.urlFor(ModelSource.huggingFace), contains('huggingface.co'));
          expect(file.sizeBytes, greaterThan(0));
          expect(file.sha256.length, equals(64));
        }
      }
    });
  });
}
