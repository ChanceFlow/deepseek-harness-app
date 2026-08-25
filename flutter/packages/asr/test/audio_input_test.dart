import 'dart:typed_data';

import 'package:asr/asr.dart';
import 'package:test/test.dart';

void main() {
  group('AudioInputSource & MockAudioInputSource', () {
    test('MockAudioInputSource emits audio buffers and amplitude stream', () async {
      final source = MockAudioInputSource(
        simulatedDuration: const Duration(milliseconds: 350),
      );

      expect(source.isRecording, isFalse);

      final List<Float32List> audioBuffers = <Float32List>[];
      final List<double> amplitudes = <double>[];

      final sub1 = source.audioStream.listen(audioBuffers.add);
      final sub2 = source.amplitudeStream.listen(amplitudes.add);

      await source.start();
      expect(source.isRecording, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(audioBuffers.isNotEmpty, isTrue);
      expect(amplitudes.isNotEmpty, isTrue);
      for (final amp in amplitudes) {
        expect(amp, greaterThanOrEqualTo(0.0));
        expect(amp, lessThanOrEqualTo(1.0));
      }

      await sub1.cancel();
      await sub2.cancel();
      await source.dispose();
      expect(source.isRecording, isFalse);
    });
  });
}