import 'dart:async';
import 'dart:typed_data';

import 'package:app/platform/audio_recorder.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel methodChannel = MethodChannel(kAudioRecordChannel);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
  });

  test('checks and requests recording permission via method channel', () async {
    bool requested = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (MethodCall call) async {
          if (call.method == 'hasPermission') return false;
          if (call.method == 'requestPermission') {
            requested = true;
            return true;
          }
          return null;
        });

    final recorder = PlatformAudioRecorder();
    expect(await recorder.checkPermission(), isFalse);
    expect(await recorder.requestPermission(), isTrue);
    expect(requested, isTrue);

    await recorder.dispose();
  });

  test(
    'falls back gracefully when method channel is not implemented',
    () async {
      final recorder = PlatformAudioRecorder();
      expect(await recorder.checkPermission(), isTrue);
      expect(await recorder.requestPermission(), isTrue);
      await recorder.start();
      await recorder.stop();
      await recorder.dispose();
    },
  );

  test(
    'propagates a native startRecording failure instead of swallowing it',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (MethodCall call) async {
            if (call.method == 'startRecording') {
              throw PlatformException(
                code: 'record_error',
                message: 'Failed to initialize AudioRecord',
              );
            }
            return null;
          });

      final recorder = PlatformAudioRecorder();
      await expectLater(
        recorder.start(),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'record_error',
          ),
        ),
      );
      expect(recorder.isRecording, isFalse);

      await recorder.dispose();
    },
  );

  test('surfaces an event-channel error on the errors stream instead of silently stopping', () async {
    final recorder = PlatformAudioRecorder();
    await recorder.start();

    final errors = <Object>[];
    final sub = recorder.errors.listen(errors.add);
    expect(recorder.isRecording, isTrue);

    // Deliver a native error envelope on the audio stream channel exactly
    // as the platform would: EventChannel → onError → errors stream.
    const codec = StandardMethodCodec();
    unawaited(
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            kAudioStreamChannel,
            codec.encodeErrorEnvelope(
              code: 'input_silent',
              message: 'No audio signal detected from the microphone',
              details: null,
            ),
            (_) {},
          ),
    );

    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(errors, hasLength(1));
    expect(errors.single, isA<PlatformException>());
    expect((errors.single as PlatformException).code, 'input_silent');
    // onError must not leave the recorder in a phantom recording state.
    expect(recorder.isRecording, isFalse);

    await sub.cancel();
    await recorder.dispose();
  });

  test(
    'adaptive amplitude keeps quiet frames visibly above the floor',
    () async {
      final recorder = PlatformAudioRecorder();
      await recorder.start();

      final amplitudes = <double>[];
      final sub = recorder.amplitudeStream.listen(amplitudes.add);

      const codec = StandardMethodCodec();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

      // A quiet frame: peak 0.011 — the level seen on the user's device.
      // The adaptive tracker must normalize it well above the old rms*8
      // result (~0.03), so the waveform is actually visible.
      final quiet = Float32List(1600)..[100] = 0.011;
      // A later loud frame: peak 0.3.
      final loud = Float32List(1600)..[50] = 0.3;

      unawaited(
        messenger.handlePlatformMessage(
          kAudioStreamChannel,
          codec.encodeSuccessEnvelope(quiet),
          (_) {},
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      unawaited(
        messenger.handlePlatformMessage(
          kAudioStreamChannel,
          codec.encodeSuccessEnvelope(loud),
          (_) {},
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(amplitudes, hasLength(2));
      // First frame: peak == _peakLevel → normalized to 1.0 (instant attack).
      expect(amplitudes[0], 1.0);
      // Loud frame: peak 0.3 far exceeds released 0.0106 → also 1.0.
      expect(amplitudes[1], 1.0);

      await sub.cancel();
      await recorder.stop();
      await recorder.dispose();
    },
  );

  test('debugStats reads native stats and reports events received', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(kAudioDebugChannel), (
          MethodCall call,
        ) async {
          return <String, Object?>{
            'reads': 42,
            'eventsSent': 30,
            'maxAbs': 0.5,
            'sourceUsed': 'mic',
            'isRecording': true,
            'micMuted': false,
          };
        });

    final recorder = PlatformAudioRecorder();
    await recorder.start();

    final stats = await recorder.debugStats();
    expect(stats.reads, 42);
    expect(stats.eventsSent, 30);
    expect(stats.maxAbs, 0.5);
    expect(stats.sourceUsed, 'mic');
    expect(stats.nativeSawSignal, isTrue);
    expect(stats.eventsReceived, recorder.eventsReceived);

    await recorder.stop();
    await recorder.dispose();
  });
}
