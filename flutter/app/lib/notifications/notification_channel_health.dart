/// Whether Android is actually letting the app's notification channels
/// through.
///
/// The app can create a channel but can never raise its importance, and a
/// user (or an OEM battery setting) can silence it forever. The settings page
/// reads this to say so and to offer the one place where it can be fixed.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Per-channel state as Android reports it, not as we wish it were.
final class NotificationChannelHealth {
  const NotificationChannelHealth({
    this.appEnabled = true,
    this.replies = true,
    this.attention = true,
  });

  /// The app-level notifications switch (`areNotificationsEnabled`).
  final bool appEnabled;

  /// The `turns` channel (new replies) can still post.
  final bool replies;

  /// The `pending` channel (needs your input) can still post.
  final bool attention;

  /// Whether every channel this app uses can post.
  bool get allEnabled => appEnabled && replies && attention;
}

/// Assumes health until the platform says otherwise: a headless test or a
/// non-Android host must never touch notification APIs to render settings.
final notificationChannelHealthProvider =
    FutureProvider<NotificationChannelHealth>(
      (ref) async => const NotificationChannelHealth(),
    );

/// Opens the system notification settings, optionally scoped to one channel.
typedef OpenNotificationSettings = Future<void> Function({String? channelId});

/// No-op default; the platform implementation replaces it.
final openNotificationSettingsProvider = Provider<OpenNotificationSettings>(
  (ref) => ({String? channelId}) async {},
);
