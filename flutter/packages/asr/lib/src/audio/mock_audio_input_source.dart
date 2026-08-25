/// Mock audio input source for testing and headless environments.
library;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'audio_input_source.dart';

/// Test implementation of [AudioInputSource] emitting simulated PCM and amplitude.
class MockAudioInputSource implements AudioInputSource {
  MockAudioInputSource({this.simulatedDuration = const Duration(seconds: 3)});

  final Duration simulatedDuration;

  final StreamController<Float32List> _audioController =
      StreamController<Float32List>.broadcast();
  final StreamController<double> _amplitudeController =
      StreamController<double>.broadcast();

  Timer? _timer;
  bool _isRecording = false;

  @override
  Stream<Float32List> get audioStream => _audioController.stream;

  @override
  Stream<double> get amplitudeStream => _amplitudeController.stream;

  @override
  bool get isRecording => _isRecording;

  @override
  Future<void> start({int sampleRate = 16000}) async {
    if (_isRecording) return;
    _isRecording = true;

    final random = Random();
    int ticks = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!_isRecording) return;
      ticks++;
      // 100ms at 16kHz = 1600 samples
      final samples = Float32List(1600);
      final double amp = 0.2 + 0.6 * random.nextDouble();
      for (int i = 0; i < samples.length; i++) {
        samples[i] = (random.nextDouble() * 2 - 1) * amp;
      }
      if (!_audioController.isClosed) {
        _audioController.add(samples);
      }
      if (!_amplitudeController.isClosed) {
        _amplitudeController.add(amp);
      }
      if (ticks * 100 >= simulatedDuration.inMilliseconds) {
        unawaited(stop());
      }
    });
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _isRecording = false;
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _audioController.close();
    await _amplitudeController.close();
  }
}
