/// The Android runtime permissions a host page asks the WebView for.
///
/// A WebView's `onPermissionRequest` cannot grant anything until Android has
/// granted the runtime permission, so the page's ask waits on this channel.
/// Only the resources the page actually declared are requested; anything else
/// is denied rather than silently granted.
library;

import 'package:flutter/services.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

/// How one Android permission ask settled.
///
/// The distinction that matters is the one the system does not hand back
/// directly: a denial the system will ask about again is recoverable by
/// asking, while a permanently denied ask can only be changed in app
/// settings. Collapsing the two leaves the user with a dead microphone and
/// no path back to it.
enum WebViewPermissionOutcome {
  /// Every requested permission is granted now. No dialog was needed, or the
  /// user allowed this ask.
  granted,

  /// The user denied this ask, but the system may still show a dialog on a
  /// later ask.
  denied,

  /// Every still-missing permission was asked before and none currently
  /// reports a rationale, so the system will not show the dialog again;
  /// only app settings can change it.
  permanentlyDenied,

  /// The request could not be started (e.g. the activity was destroyed) or
  /// no activity answered it.
  unavailable,
}

/// Maps a WebView permission ask to Android runtime permissions and answers
/// it through the activity.
abstract final class WebViewPermissions {
  static const MethodChannel _channel = MethodChannel('dsh/webview');

  /// The manifest declarations each resource needs. A camera capture asks for
  /// the camera only; a `<video>` capture that also records audio declares
  /// both resources, and then both permissions are requested.
  static List<String> androidPermissionsFor(
    Set<WebViewPermissionResourceType> types,
  ) {
    final permissions = <String>[];
    if (types.contains(WebViewPermissionResourceType.microphone)) {
      permissions.add('android.permission.RECORD_AUDIO');
    }
    if (types.contains(WebViewPermissionResourceType.camera)) {
      permissions.add('android.permission.CAMERA');
    }
    return permissions;
  }

  /// Asks for the runtime permissions behind [types] and reports how the ask
  /// settled.
  ///
  /// A resource no Android permission covers is [WebViewPermissionOutcome.denied]:
  /// the page's ask cannot be satisfied. An unrecognised answer is denied too,
  /// because a reply this client cannot read must not grant anything. A null
  /// answer, a missing channel or a platform error is
  /// [WebViewPermissionOutcome.unavailable] — the ask never reached an
  /// activity, so it says nothing about the user's choice.
  static Future<WebViewPermissionOutcome> ensure(
    Set<WebViewPermissionResourceType> types,
  ) async {
    final permissions = androidPermissionsFor(types);
    if (permissions.isEmpty) return WebViewPermissionOutcome.denied;
    try {
      final reply = await _channel.invokeMethod<String>('requestPermissions', {
        'permissions': permissions,
      });
      return switch (reply) {
        null => WebViewPermissionOutcome.unavailable,
        'granted' => WebViewPermissionOutcome.granted,
        'denied' => WebViewPermissionOutcome.denied,
        'permanentlyDenied' => WebViewPermissionOutcome.permanentlyDenied,
        'unavailable' => WebViewPermissionOutcome.unavailable,
        _ => WebViewPermissionOutcome.denied,
      };
    } on PlatformException {
      return WebViewPermissionOutcome.unavailable;
    } on MissingPluginException {
      return WebViewPermissionOutcome.unavailable;
    }
  }

  /// Opens this app's Android settings entry, where a permanently denied
  /// runtime permission can be re-allowed.
  ///
  /// A host without the channel simply stays on the page: the banner's action
  /// has nowhere to go, and that is not an error the reader can act on.
  static Future<void> openAppSettings() async {
    try {
      await _channel.invokeMethod<bool>('openAppSettings');
    } on PlatformException {
      // A device that refuses the settings intent leaves the user where they
      // were; the banner still names the path they can take by hand.
    } on MissingPluginException {
      // Widget tests and non-Android hosts have no activity channel.
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
