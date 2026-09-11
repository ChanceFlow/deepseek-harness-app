/// Platform bridge for the Android keep-alive foreground service.
///
/// Agent work can outlive the moment the user pockets the phone: Android
/// freezes a cached process (screen lock included) and the mux WebSocket
/// dies with it. The foreground service registered as `dsh/keep_alive` in
/// `MainActivity` keeps the process out of the cached state and holds a
/// partial wake lock, so the connection survives while a turn runs.
///
/// The copy is passed to the host rather than baked into Kotlin so
/// user-visible notification text stays owned by the ARB locales. The
/// channel's `start` answers an error when Android refuses a
/// foreground-service start from the background (Android 12+); callers
/// record that refusal and carry on — the connection then re-establishes on
/// the next foreground resume.
library;

import 'package:flutter/services.dart';

/// Method channel name; must match `MainActivity.kt`.
const String kKeepAliveChannel = 'dsh/keep_alive';

/// The user-visible copy for one keep-alive notification. The title and
/// body are the notification's own text; the channel name and description
/// are the system settings row the notification belongs to.
final class KeepAliveNotificationCopy {
  const KeepAliveNotificationCopy({
    required this.title,
    required this.text,
    required this.channelName,
    required this.channelDescription,
  });

  final String title;
  final String text;
  final String channelName;
  final String channelDescription;

  Map<String, String> toMap() => <String, String>{
    'title': title,
    'text': text,
    'channelName': channelName,
    'channelDescription': channelDescription,
  };
}

/// The foreground-service seam. Overridden in tests; the real one talks to
/// [kKeepAliveChannel].
class KeepAliveService {
  const KeepAliveService();

  /// Requests the service (starting it, or refreshing its notification when
  /// it already runs).
  ///
  /// Throws [PlatformException] when the host refuses the start and
  /// [MissingPluginException] where no host implements the channel.
  Future<void> start(KeepAliveNotificationCopy copy) async {
    await const MethodChannel(kKeepAliveChannel)
        .invokeMethod<void>('start', copy.toMap());
  }

  /// Stops the service and removes its notification. Idempotent: stopping a
  /// service that is not running is a no-op on the host.
  Future<void> stop() async {
    await const MethodChannel(kKeepAliveChannel).invokeMethod<void>('stop');
  }
}
