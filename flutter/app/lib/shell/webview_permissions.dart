/// The Android runtime permissions a host page asks the WebView for.
///
/// A WebView's `onPermissionRequest` cannot grant anything until Android has
/// granted the runtime permission, so the page's ask waits on this channel.
/// Only the resources the page actually declared are requested; anything else
/// is denied rather than silently granted.
library;

import 'package:flutter/services.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

/// Maps a WebView permission ask to Android runtime permissions and answers
/// it through the activity.
abstract final class WebViewPermissions {
  static const MethodChannel _channel = MethodChannel('dsh/webview');

  /// The manifest declarations each resource needs. Video capture also needs
  /// the microphone: a `<video>` capture with audio asks for both.
  static List<String> androidPermissionsFor(
    Set<WebViewPermissionResourceType> types,
  ) {
    final permissions = <String>[];
    if (types.contains(WebViewPermissionResourceType.microphone) ||
        types.contains(WebViewPermissionResourceType.camera)) {
      permissions.add('android.permission.RECORD_AUDIO');
    }
    if (types.contains(WebViewPermissionResourceType.camera)) {
      permissions.add('android.permission.CAMERA');
    }
    return permissions;
  }

  /// Asks for the runtime permissions behind [types]; false when the user
  /// declined or the platform has no answer for the ask.
  static Future<bool> ensure(Set<WebViewPermissionResourceType> types) async {
    final permissions = androidPermissionsFor(types);
    if (permissions.isEmpty) return false;
    try {
      return await _channel.invokeMethod<bool>('requestPermissions', {
            'permissions': permissions,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Attaches the native download listener to the plugin's WebViews.
  /// Idempotent; safe to call before the page exists.
  static Future<void> attachDownloads() async {
    try {
      await _channel.invokeMethod<bool>('attachDownloads');
    } on PlatformException {
      // A host without the channel simply has no download handling.
    } on MissingPluginException {
      // Widget tests and non-Android hosts have no activity channel.
    }
  }
}
