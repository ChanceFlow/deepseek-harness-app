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

  test('falls back gracefully when method channel is not implemented', () async {
    final recorder = PlatformAudioRecorder();
    expect(await recorder.checkPermission(), isTrue);
    expect(await recorder.requestPermission(), isTrue);
    await recorder.start();
    await recorder.stop();
    await recorder.dispose();
  });

  test('propagates a native startRecording failure instead of swallowing it', () async {
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
      throwsA(isA<PlatformException>()
          .having((e) => e.code, 'code', 'record_error')),
    );
    expect(recorder.isRecording, isFalse);

    await recorder.dispose();
  });
}