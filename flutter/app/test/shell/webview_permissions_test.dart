/// The page's permission ask maps to the runtime permissions it needs and
/// reads the activity's four-way answer.
library;

import 'package:app/shell/webview_permissions.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

const MethodChannel _channel = MethodChannel('dsh/webview');

void _mockChannel(Future<Object?> Function(MethodCall call) handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, handler);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  test('a microphone ask requests only RECORD_AUDIO', () {
    expect(
      WebViewPermissions.androidPermissionsFor({
        WebViewPermissionResourceType.microphone,
      }),
      ['android.permission.RECORD_AUDIO'],
    );
  });

  test('a camera ask requests only the camera', () {
    expect(
      WebViewPermissions.androidPermissionsFor({
        WebViewPermissionResourceType.camera,
      }),
      ['android.permission.CAMERA'],
    );
  });

  test('a microphone and camera ask requests both permissions', () {
    expect(
      WebViewPermissions.androidPermissionsFor({
        WebViewPermissionResourceType.microphone,
        WebViewPermissionResourceType.camera,
      }),
      ['android.permission.RECORD_AUDIO', 'android.permission.CAMERA'],
    );
  });

  test('a resource with no Android permission asks for nothing', () {
    expect(
      WebViewPermissions.androidPermissionsFor({
        AndroidWebViewPermissionResourceType.midiSysex,
      }),
      isEmpty,
    );
  });

  test(
    'an ask without a platform channel is unavailable, not denied',
    () async {
      expect(
        await WebViewPermissions.ensure({
          WebViewPermissionResourceType.microphone,
        }),
        WebViewPermissionOutcome.unavailable,
      );
    },
  );

  test(
    'an ask no Android permission covers is denied without the channel',
    () async {
      var contacted = false;
      _mockChannel((call) async {
        contacted = true;
        return 'granted';
      });

      expect(
        await WebViewPermissions.ensure({
          AndroidWebViewPermissionResourceType.midiSysex,
        }),
        WebViewPermissionOutcome.denied,
      );
      expect(contacted, isFalse);
    },
  );

  test('the channel is asked for the mapped permissions', () async {
    MethodCall? seen;
    _mockChannel((call) async {
      seen = call;
      return 'granted';
    });

    await WebViewPermissions.ensure({WebViewPermissionResourceType.microphone});

    expect(seen?.method, 'requestPermissions');
    expect(seen?.arguments, {
      'permissions': ['android.permission.RECORD_AUDIO'],
    });
  });

  test('a granted answer reads as granted', () async {
    _mockChannel((call) async => 'granted');

    expect(
      await WebViewPermissions.ensure({
        WebViewPermissionResourceType.microphone,
      }),
      WebViewPermissionOutcome.granted,
    );
  });

  test('a denied answer reads as denied', () async {
    _mockChannel((call) async => 'denied');

    expect(
      await WebViewPermissions.ensure({
        WebViewPermissionResourceType.microphone,
      }),
      WebViewPermissionOutcome.denied,
    );
  });

  test('a permanently denied answer reads as permanently denied', () async {
    _mockChannel((call) async => 'permanentlyDenied');

    expect(
      await WebViewPermissions.ensure({
        WebViewPermissionResourceType.microphone,
      }),
      WebViewPermissionOutcome.permanentlyDenied,
    );
  });

  test('an unavailable answer reads as unavailable', () async {
    _mockChannel((call) async => 'unavailable');

    expect(
      await WebViewPermissions.ensure({
        WebViewPermissionResourceType.microphone,
      }),
      WebViewPermissionOutcome.unavailable,
    );
  });

  test('an unrecognised answer is denied, not granted', () async {
    _mockChannel((call) async => 'maybe');

    expect(
      await WebViewPermissions.ensure({
        WebViewPermissionResourceType.microphone,
      }),
      WebViewPermissionOutcome.denied,
    );
  });

  test('a null answer is unavailable', () async {
    _mockChannel((call) async => null);

    expect(
      await WebViewPermissions.ensure({
        WebViewPermissionResourceType.microphone,
      }),
      WebViewPermissionOutcome.unavailable,
    );
  });

  test('a platform error is unavailable, not denied', () async {
    _mockChannel((call) async {
      throw PlatformException(code: 'no_activity');
    });

    expect(
      await WebViewPermissions.ensure({
        WebViewPermissionResourceType.microphone,
      }),
      WebViewPermissionOutcome.unavailable,
    );
  });
}
