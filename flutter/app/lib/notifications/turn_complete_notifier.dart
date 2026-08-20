/// Turn-complete local notifications.
///
/// Posts a system notification when the selected session's turn finishes
/// while the app is backgrounded (mobile-useful; web has no equivalent).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class TurnCompleteNotifier {
  TurnCompleteNotifier();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  int _nextId = 1;

  Future<void> initialize() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: android));
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
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
        'Turn complete',
        sessionTitle,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'turns',
            'Turn completion',
            channelDescription:
                'Notifies when a running conversation turn finishes.',
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
