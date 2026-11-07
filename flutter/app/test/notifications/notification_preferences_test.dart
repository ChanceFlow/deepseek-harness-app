/// Notification preferences: the defaults, the store round-trip per seat, and
/// the kind gate the notification center reads before routing an event.
///
/// The store is the real [LocalStateStore] over a temp file, so a write is
/// proved by reopening the document rather than by trusting the controller's
/// own state.
library;

import 'dart:io';

import 'package:app/local_state/local_state_providers.dart';
import 'package:app/local_state/local_state_store.dart';
import 'package:app/notifications/notification_events.dart';
import 'package:app/notifications/notification_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

late Directory _tempDir;
late File _stateFile;

Future<LocalStateStore> _store({
  Map<String, Object?> seeded = const <String, Object?>{},
}) async {
  final LocalStateStore store = LocalStateStore(_stateFile);
  await store.load();
  if (seeded.isNotEmpty) {
    seeded.forEach(store.write);
    await store.flush();
  }
  return store;
}

ProviderContainer _container(LocalStateStore store) {
  final container = ProviderContainer(
    overrides: [localStateStoreProvider.overrideWith((ref) async => store)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  setUp(() async {
    _tempDir = await Directory.systemTemp.createTemp('notification_prefs_test');
    _stateFile = File('${_tempDir.path}/local_state.json');
  });

  tearDown(() async {
    await _tempDir.delete(recursive: true);
  });

  test('defaults are on for every kind', () async {
    final container = _container(await _store());
    await container.read(localStateStoreProvider.future);

    final NotificationPreferences preferences = container.read(
      notificationPreferencesProvider,
    );
    expect(preferences, const NotificationPreferences());
    for (final AppNotificationKind kind in AppNotificationKind.values) {
      expect(
        preferences.allows(kind),
        isTrue,
        reason: '${kind.name} is allowed out of the box',
      );
    }
  });

  test('stored values are adopted when the store resolves', () async {
    final LocalStateStore store = await _store(
      seeded: <String, Object?>{
        kAppNotifyEnabledKey: false,
        kAppNotifyRepliesKey: false,
        kAppNotifyFailuresKey: false,
        kAppNotifyAttentionKey: false,
      },
    );
    final container = _container(store);

    expect(
      container.read(notificationPreferencesProvider),
      const NotificationPreferences(),
      reason: 'the synchronous provider renders the defaults until the cache',
    );

    await container.read(localStateStoreProvider.future);
    await pumpEventQueue();

    expect(
      container.read(notificationPreferencesProvider),
      const NotificationPreferences(
        enabled: false,
        replies: false,
        failures: false,
        attention: false,
      ),
    );
  });

  test(
    'each setter writes its own key and the choice survives a restart',
    () async {
      final LocalStateStore store = await _store();
      final container = _container(store);
      await container.read(localStateStoreProvider.future);
      final NotificationPreferencesController controller = container.read(
        notificationPreferencesProvider.notifier,
      );

      await controller.setEnabled(false);
      await controller.setReplies(false);
      await controller.setFailures(false);
      await controller.setAttention(false);

      expect(
        container.read(notificationPreferencesProvider),
        const NotificationPreferences(
          enabled: false,
          replies: false,
          failures: false,
          attention: false,
        ),
      );
      expect(store.read(kAppNotifyEnabledKey), isFalse);
      expect(store.read(kAppNotifyRepliesKey), isFalse);
      expect(store.read(kAppNotifyFailuresKey), isFalse);
      expect(store.read(kAppNotifyAttentionKey), isFalse);

      final LocalStateStore reopened = LocalStateStore(_stateFile);
      await reopened.load();
      expect(reopened.read(kAppNotifyEnabledKey), isFalse);
      expect(reopened.read(kAppNotifyRepliesKey), isFalse);
      expect(reopened.read(kAppNotifyFailuresKey), isFalse);
      expect(reopened.read(kAppNotifyAttentionKey), isFalse);
    },
  );

  test('a non-boolean stored value leaves the default standing', () async {
    final LocalStateStore store = await _store(
      seeded: <String, Object?>{
        kAppNotifyRepliesKey: 'no',
        kAppNotifyAttentionKey: 7,
      },
    );
    final container = _container(store);
    await container.read(localStateStoreProvider.future);

    final NotificationPreferences preferences = container.read(
      notificationPreferencesProvider,
    );
    expect(preferences.replies, isTrue);
    expect(preferences.attention, isTrue);
  });

  test(
    'a toggle that lands before the store resolves survives adoption',
    () async {
      final LocalStateStore store = await _store();
      final container = _container(store);
      final NotificationPreferencesController controller = container.read(
        notificationPreferencesProvider.notifier,
      );

      await controller.setReplies(false);
      await pumpEventQueue();

      expect(container.read(notificationPreferencesProvider).replies, isFalse);
      expect(store.read(kAppNotifyRepliesKey), isFalse);
    },
  );

  test('each kind reads its own seat', () {
    const NotificationPreferences repliesOff = NotificationPreferences(
      replies: false,
    );
    expect(
      repliesOff.allows(AppNotificationKind.selectedTurnComplete),
      isFalse,
    );
    expect(repliesOff.allows(AppNotificationKind.otherTurnComplete), isFalse);
    expect(repliesOff.allows(AppNotificationKind.turnFailed), isTrue);
    expect(repliesOff.allows(AppNotificationKind.turnStopped), isTrue);
    expect(repliesOff.allows(AppNotificationKind.approvalRequested), isTrue);
    expect(repliesOff.allows(AppNotificationKind.planReviewRequested), isTrue);

    const NotificationPreferences failuresOff = NotificationPreferences(
      failures: false,
    );
    expect(failuresOff.allows(AppNotificationKind.turnFailed), isFalse);
    expect(failuresOff.allows(AppNotificationKind.turnStopped), isFalse);
    expect(
      failuresOff.allows(AppNotificationKind.selectedTurnComplete),
      isTrue,
    );
    expect(failuresOff.allows(AppNotificationKind.otherTurnComplete), isTrue);

    const NotificationPreferences attentionOff = NotificationPreferences(
      attention: false,
    );
    expect(attentionOff.allows(AppNotificationKind.approvalRequested), isFalse);
    expect(
      attentionOff.allows(AppNotificationKind.planReviewRequested),
      isFalse,
    );
    expect(
      attentionOff.allows(AppNotificationKind.selectedTurnComplete),
      isTrue,
    );
    expect(attentionOff.allows(AppNotificationKind.turnFailed), isTrue);

    const NotificationPreferences masterOff = NotificationPreferences(
      enabled: false,
    );
    for (final AppNotificationKind kind in AppNotificationKind.values) {
      expect(
        masterOff.allows(kind),
        isFalse,
        reason: 'the master switch wins over ${kind.name}',
      );
    }
  });
}
