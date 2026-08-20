/// Turn-complete local notifications.
///
/// Posts a system notification when the selected session's turn finishes
/// while the app is backgrounded (mobile-useful; web has no equivalent).
/// The notification copy resolves once at [initialize] from the platform
/// locale — an app restart is what picks up a device-language change,
/// which matches how the plugin caches its Android channel metadata.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale, WidgetsBinding;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class TurnCompleteNotifier {
  TurnCompleteNotifier();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  int _nextId = 1;

  /// Notification copy for the launch-time device locale; the English
  /// seat is the pre-initialize default (posts are no-ops before
  /// initialize in debug builds).
  AppLocalizations _l10n = lookupAppLocalizations(const Locale('en'));

  Future<void> initialize() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: android));
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    // Resolve the launch-time device locale so notifications render in
    // the app's language without context plumbing into the DI layer.
    _l10n = lookupAppLocalizations(
      WidgetsBinding.instance.platformDispatcher.locale,
    );
    _initialized = true;
  }

  /// Show a turn-complete notification for [sessionTitle].
  Future<void> showTurnComplete(String sessionTitle) async {
    if (kDebugMode && !_initialized) {
      // Tests and headless hosts never initialize the plugin.
      return;
    }
    try {
      await _plugin.show(
        _nextId++,
        _l10n.turnCompleteTitle,
        sessionTitle,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'turns',
            _l10n.turnCompletionChannel,
            channelDescription: _l10n.turnCompletionChannelDescription,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
      );
    } catch (_) {
      // Notification failures never surface in the chat UI.
    }
  }
}