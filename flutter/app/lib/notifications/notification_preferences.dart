/// Device-local notification preferences — the master switch and one seat per
/// notification kind the settings page renders.
///
/// The app owns this choice; the host knows nothing about it. Each value
/// persists in the shared [LocalStateStore] under its own `app.notify.*` key,
/// and an absent key means the default `true`, so an untouched device keeps
/// telling the user about everything it always did. [NotificationPreferences.allows]
/// is the one gate the notification center reads before routing an event.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../local_state/local_state_providers.dart';
import '../local_state/local_state_store.dart';
import '../logging/error_log_collector.dart';
import 'notification_events.dart';

/// KV key for the master switch.
const String kAppNotifyEnabledKey = 'app.notify.enabled';

/// KV key for the "new replies" seat (finished turns).
const String kAppNotifyRepliesKey = 'app.notify.replies';

/// KV key for the "failures and stops" seat.
const String kAppNotifyFailuresKey = 'app.notify.failures';

/// KV key for the "needs your input" seat (approvals and plan reviews).
const String kAppNotifyAttentionKey = 'app.notify.attention';

/// The notification preferences, all on by default.
final class NotificationPreferences {
  const NotificationPreferences({
    this.enabled = true,
    this.replies = true,
    this.failures = true,
    this.attention = true,
  });

  /// The master switch: off silences every kind without discarding the
  /// per-kind values below.
  final bool enabled;

  /// Finished turns — a new reply in a session the user is not reading.
  final bool replies;

  /// Turns that failed or were stopped.
  final bool failures;

  /// Approvals and plan reviews — the host is waiting on the user.
  final bool attention;

  /// Whether an event of [kind] may be delivered. The master switch wins: off
  /// refuses every kind even when its own seat is on.
  bool allows(AppNotificationKind kind) {
    if (!enabled) return false;
    return switch (kind) {
      AppNotificationKind.selectedTurnComplete ||
      AppNotificationKind.otherTurnComplete => replies,
      AppNotificationKind.turnFailed ||
      AppNotificationKind.turnStopped => failures,
      AppNotificationKind.approvalRequested ||
      AppNotificationKind.planReviewRequested => attention,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is NotificationPreferences &&
      other.enabled == enabled &&
      other.replies == replies &&
      other.failures == failures &&
      other.attention == attention;

  @override
  int get hashCode => Object.hash(enabled, replies, failures, attention);
}

/// UDF controller over the shared store: adopts the stored values the first
/// time the store resolves, publishes every change, and writes each seat
/// through before confirming it.
///
/// The provider is synchronous, so the page renders the defaults for the one
/// frame before a cold store resolves and then adopts the document; a setter
/// that lands before that adoption keeps its own value, and its pending write
/// carries it to disk.
class NotificationPreferencesController
    extends Notifier<NotificationPreferences> {
  LocalStateStore? _store;
  bool _adopted = false;
  bool _touched = false;
  NotificationPreferences _value = const NotificationPreferences();

  @override
  NotificationPreferences build() {
    final AsyncValue<LocalStateStore> storeState = ref.watch(
      localStateStoreProvider,
    );
    final LocalStateStore? store = storeState.value;
    if (store != null && !_adopted) {
      _adopted = true;
      _store = store;
      // A setter that ran before the store resolved already published its
      // value and its own write carries it; do not overwrite that with the
      // document snapshot.
      if (!_touched) _value = _read(store);
    }
    return _value;
  }

  /// Persists the master switch; the per-kind values are kept.
  Future<void> setEnabled(bool value) => _commit(
    before: state,
    next: NotificationPreferences(
      enabled: value,
      replies: state.replies,
      failures: state.failures,
      attention: state.attention,
    ),
    key: kAppNotifyEnabledKey,
    value: value,
  );

  /// Persists the "new replies" seat.
  Future<void> setReplies(bool value) => _commit(
    before: state,
    next: NotificationPreferences(
      enabled: state.enabled,
      replies: value,
      failures: state.failures,
      attention: state.attention,
    ),
    key: kAppNotifyRepliesKey,
    value: value,
  );

  /// Persists the "failures and stops" seat.
  Future<void> setFailures(bool value) => _commit(
    before: state,
    next: NotificationPreferences(
      enabled: state.enabled,
      replies: state.replies,
      failures: value,
      attention: state.attention,
    ),
    key: kAppNotifyFailuresKey,
    value: value,
  );

  /// Persists the "needs your input" seat.
  Future<void> setAttention(bool value) => _commit(
    before: state,
    next: NotificationPreferences(
      enabled: state.enabled,
      replies: state.replies,
      failures: state.failures,
      attention: value,
    ),
    key: kAppNotifyAttentionKey,
    value: value,
  );

  static NotificationPreferences _read(LocalStateStore store) =>
      NotificationPreferences(
        enabled: _storedBool(store, kAppNotifyEnabledKey),
        replies: _storedBool(store, kAppNotifyRepliesKey),
        failures: _storedBool(store, kAppNotifyFailuresKey),
        attention: _storedBool(store, kAppNotifyAttentionKey),
      );

  /// A stored key is the boolean it names; anything else (a document from a
  /// newer build, a corrupt value) leaves the default standing.
  static bool _storedBool(LocalStateStore store, String key) {
    final Object? stored = store.read(key);
    return stored is bool ? stored : true;
  }

  Future<void> _commit({
    required NotificationPreferences before,
    required NotificationPreferences next,
    required String key,
    required bool value,
  }) async {
    if (before == next) return;
    _touched = true;
    _value = next;
    state = next;
    final LocalStateStore? store = await _storeForWrite();
    if (store == null) return;
    try {
      store.write(key, value);
      await store.flush();
    } on Object catch (error) {
      if (state == next) {
        _value = before;
        state = before;
      }
      ErrorLogCollector.instance.addBreadcrumb(
        'Failed to persist a notification preference: $error',
        level: 'warning',
      );
    }
  }

  /// The shared store, read once it resolves; null when the device-local
  /// cache is unavailable, in which case the row keeps its choice for this
  /// session instead of failing the tap.
  Future<LocalStateStore?> _storeForWrite() async {
    final LocalStateStore? current = _store;
    if (current != null) return current;
    try {
      final LocalStateStore store = await ref.read(
        localStateStoreProvider.future,
      );
      _store = store;
      return store;
    } on Object {
      return null;
    }
  }
}

/// The app-wide notification preferences. The settings page watches this; the
/// notification center reads it when deciding whether an event may surface.
final NotifierProvider<
  NotificationPreferencesController,
  NotificationPreferences
>
notificationPreferencesProvider =
    NotifierProvider<
      NotificationPreferencesController,
      NotificationPreferences
    >(NotificationPreferencesController.new);
