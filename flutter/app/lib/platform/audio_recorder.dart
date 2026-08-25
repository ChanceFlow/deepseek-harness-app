/// Platform bridge for Android microphone recording and PCM streaming.
library;

import 'dart:async';

import 'package:asr/asr.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Method channel for recording control & permissions.
const String kAudioRecordChannel = 'dsh/audio_record';

/// Event channel for streaming 16 kHz Mono Float32 PCM samples.
const String kAudioStreamChannel = 'dsh/audio_stream';

/// Method channel for native capture diagnostics (no adb/logcat needed).
const String kAudioDebugChannel = 'dsh/audio_debug';

/// Snapshot of what the native capture thread sees. Drives the in-app
/// debug strip that tells whether the device feeds silence (maxAbs stays
/// 0), read() is stalled, or events never reach Dart.
class AudioDebugStats {
  const AudioDebugStats({
    this.reads = 0,
    this.eventsSent = 0,
    this.maxAbs = 0,
    this.sourceUsed = 'unknown',
    this.isRecording = false,
    this.micMuted,
    this.eventsReceived = 0,
  });

  /// Native successful `read()` calls that returned samples.
  final int reads;

  /// Native events delivered to the event sink.
  final int eventsSent;

  /// Largest |sample| seen on the native side since recording started.
  final double maxAbs;

  /// Which AudioSource the native side ended up using.
  final String sourceUsed;

  /// Whether the native capture loop believes it is recording.
  final bool isRecording;

  /// Android 12+ mic toggle state (null when unknown/unsupported).
  final bool? micMuted;

  /// Events that actually arrived on the Dart side this session.
  final int eventsReceived;

  bool get nativeSawSignal => maxAbs > 0;

  static AudioDebugStats fromMap(Map<Object?, Object?> m, {int eventsReceived = 0}) {
    return AudioDebugStats(
      reads: (m['reads'] as num?)?.toInt() ?? 0,
      eventsSent: (m['eventsSent'] as num?)?.toInt() ?? 0,
      maxAbs: (m['maxAbs'] as num?)?.toDouble() ?? 0,
      sourceUsed: m['sourceUsed'] as String? ?? 'unknown',
      isRecording: m['isRecording'] as bool? ?? false,
      micMuted: m['micMuted'] as bool?,
      eventsReceived: eventsReceived,
    );
  }
}

/// Real platform audio recording implementation of [AudioInputSource].
class PlatformAudioRecorder implements AudioInputSource {
  PlatformAudioRecorder({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
    MethodChannel? debugChannel,
  })  : _methodChannel = methodChannel ?? const MethodChannel(kAudioRecordChannel),
        _eventChannel = eventChannel ?? const EventChannel(kAudioStreamChannel),
        _debugChannel = debugChannel ?? const MethodChannel(kAudioDebugChannel);

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  final MethodChannel _debugChannel;

  final StreamController<Float32List> _audioStreamController =
      StreamController<Float32List>.broadcast();
  final StreamController<double> _amplitudeController =
      StreamController<double>.broadcast();
  final StreamController<Object> _errorController =
      StreamController<Object>.broadcast();

  StreamSubscription<dynamic>? _eventSubscription;
  bool _isRecording = false;
  int _eventsReceived = 0;

  /// Adaptive peak tracker for the waveform: attacks instantly, releases
  /// slowly (0.96 per 100 ms frame ≈ -1.8 dB/s). Raw mic levels vary by an
  /// order of magnitude across devices and sources (VOICE_RECOGNITION/MIC
  /// carry no AGC), so a fixed gain cannot keep the waveform visible; the
  /// fastest recent peak normalizes every frame instead.
  double _peakLevel = 1e-4;

  @override
  Stream<Float32List> get audioStream => _audioStreamController.stream;

  @override
  Stream<double> get amplitudeStream => _amplitudeController.stream;

  /// Capture-side failures (event channel errors, native input_silent
  /// watchdog). The caller must surface these instead of a phantom
  /// recording dock.
  Stream<Object> get errors => _errorController.stream;

  @override
  bool get isRecording => _isRecording;

  /// Events that reached Dart since the last `start()`. Resets on start.
  int get eventsReceived => _eventsReceived;

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

  /// Snapshot of native capture stats for the in-app debug strip.
  Future<AudioDebugStats> debugStats() async {
    try {
      final map = await _debugChannel.invokeMapMethod<Object?, Object?>(
        'getStats',
      );
      return AudioDebugStats.fromMap(map ?? const {}, eventsReceived: _eventsReceived);
    } on MissingPluginException {
      return AudioDebugStats(eventsReceived: _eventsReceived);
    } on PlatformException {
      return AudioDebugStats(eventsReceived: _eventsReceived);
    }
  }

  @override
  Future<void> start({int sampleRate = 16000}) async {
    if (_isRecording) return;
    _isRecording = true;
    _eventsReceived = 0;

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
            _eventsReceived++;
            if (!_audioStreamController.isClosed) {
              _audioStreamController.add(samples);
            }

            // Peak-normalized amplitude for the waveform. Using the frame
            // peak (not RMS) with the adaptive tracker keeps the bars
            // visibly alive from near-silence to loud input on any device.
            double peak = 0.0;
            for (int i = 0; i < samples.length; i++) {
              final double v = samples[i].abs();
              if (v > peak) peak = v;
            }
            if (peak > _peakLevel) {
              _peakLevel = peak; // instant attack
            } else {
              _peakLevel *= 0.96; // slow release across frames
            }
            final double normalizedAmp =
                _peakLevel <= 1e-6 ? 0.0 : (peak / _peakLevel).clamp(0.0, 1.0);

            if (!_amplitudeController.isClosed) {
              _amplitudeController.add(normalizedAmp);
            }
          }
        },
        onError: (Object error) {
          // Never silently stop: the controller must learn the capture
          // died, or the dock sits in a phantom recording state.
          if (!_errorController.isClosed) {
            _errorController.add(error);
          }
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
    await _errorController.close();
  }
}

/// Wraps [debugStats] so the debug strip only exists in debug builds.
String? formatDebugStats(AudioDebugStats s) {
  if (!kDebugMode) return null;
  return 'reads=${s.reads} max=${s.maxAbs.toStringAsFixed(3)} '
      'sent=${s.eventsSent} got=${s.eventsReceived} '
      'src=${s.sourceUsed} muted=${s.micMuted}';
}