/// The page's permission ask maps to the runtime permissions it needs.
library;

import 'package:app/shell/webview_permissions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a microphone ask requests only RECORD_AUDIO', () {
    expect(
      WebViewPermissions.androidPermissionsFor({
        WebViewPermissionResourceType.microphone,
      }),
      ['android.permission.RECORD_AUDIO'],
    );
  });

  test('a camera ask also requests the microphone', () {
    expect(
      WebViewPermissions.androidPermissionsFor({
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

  test('an ask without a platform channel is refused, not granted', () async {
    expect(
      await WebViewPermissions.ensure({
        WebViewPermissionResourceType.microphone,
      }),
      isFalse,
    );
  });
}
