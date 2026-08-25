/// Platform bridge for Android microphone recording and PCM streaming.
library;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:asr/asr.dart';
import 'package:flutter/services.dart';

/// Method channel for recording control & permissions.
const String kAudioRecordChannel = 'dsh/audio_record';

/// Event channel for streaming 16 kHz Mono Float32 PCM samples.
const String kAudioStreamChannel = 'dsh/audio_stream';

/// Real platform audio recording implementation of [AudioInputSource].
class PlatformAudioRecorder implements AudioInputSource {
  PlatformAudioRecorder({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  })  : _methodChannel = methodChannel ?? const MethodChannel(kAudioRecordChannel),
        _eventChannel = eventChannel ?? const EventChannel(kAudioStreamChannel);

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  final StreamController<Float32List> _audioStreamController =
      StreamController<Float32List>.broadcast();
  final StreamController<double> _amplitudeController =
      StreamController<double>.broadcast();

  StreamSubscription<dynamic>? _eventSubscription;
  bool _isRecording = false;

  @override
  Stream<Float32List> get audioStream => _audioStreamController.stream;

  @override
  Stream<double> get amplitudeStream => _amplitudeController.stream;

  @override
  bool get isRecording => _isRecording;

  /// Checks if the RECORD_AUDIO permission has been granted.
  Future<bool> checkPermission() async {
    try {
      final bool? granted =
          await _methodChannel.invokeMethod<bool>('hasPermission');
      return granted ?? false;
    } on MissingPluginException {
      return true; // Fallback in headless/test environments
    } on PlatformException {
      return false;
    }
  }

  /// Requests the RECORD_AUDIO permission from the operating system.
  Future<bool> requestPermission() async {
    try {
      final bool? granted =
          await _methodChannel.invokeMethod<bool>('requestPermission');
      return granted ?? false;
    } on MissingPluginException {
      return true; // Fallback in headless/test environments
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> start({int sampleRate = 16000}) async {
    if (_isRecording) return;
    _isRecording = true;

    try {
      _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
        (dynamic event) {
          Float32List? samples;
          if (event is Float32List) {
            samples = event;
          } else if (event is List<dynamic>) {
            samples = Float32List.fromList(
              event.map((e) => (e as num).toDouble()).toList(),
            );
          }

          if (samples != null && samples.isNotEmpty) {
            if (!_audioStreamController.isClosed) {
              _audioStreamController.add(samples);
            }

            // Calculate RMS amplitude normalized to [0.0, 1.0]
            double sumSquares = 0.0;
            for (int i = 0; i < samples.length; i++) {
              sumSquares += samples[i] * samples[i];
            }
            final double rms = sqrt(sumSquares / samples.length);
            final double normalizedAmp = (rms * 4.0).clamp(0.0, 1.0);

            if (!_amplitudeController.isClosed) {
              _amplitudeController.add(normalizedAmp);
            }
          }
        },
        onError: (Object error) {
          stop();
        },
      );

      await _methodChannel.invokeMethod<bool>(
        'startRecording',
        <String, Object>{'sampleRate': sampleRate},
      );
    } on MissingPluginException {
      // No-op fallback for headless/test environments.
    } on PlatformException {
      // Capture failed to start (e.g. AudioRecord init threw on the native
      // side). Never mask this: the caller must see it, or the UI presents a
      // phantom recording dock with no audio behind it.
      _isRecording = false;
      await _eventSubscription?.cancel();
      _eventSubscription = null;
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    _isRecording = false;
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    try {
      await _methodChannel.invokeMethod<bool>('stopRecording');
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _audioStreamController.close();
    await _amplitudeController.close();
  }
}