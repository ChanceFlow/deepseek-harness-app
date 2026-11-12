/// Unit tests for NotificationLedger / StoreNotificationLedger.
///
/// Asserts that posted notification entries record and evict per row family
/// over LocalStateStore, survive reloading the underlying JSON file, keep the
/// pre-pending on-disk shape decodable, and handle corrupt or malformed
/// stored state gracefully.
library;

import 'dart:io';

import 'package:app/local_state/local_state_store.dart';
import 'package:app/notifications/notification_ledger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late File file;
  late LocalStateStore store;
  late StoreNotificationLedger ledger;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('notification_ledger_test');
    file = File('${tempDir.path}/local_state.json');
    store = LocalStateStore(file);
    await store.load();
    ledger = StoreNotificationLedger(store);
  });

  tearDown(() async {
    for (var i = 0; i < 50; i++) {
      try {
        await tempDir.delete(recursive: true);
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }
  });

  NotificationRowEntry work(String backendId, String sessionId) =>
      NotificationRowEntry(backendId: backendId, sessionId: sessionId);

  NotificationRowEntry pending(String backendId, String sessionId) =>
      NotificationRowEntry(
        backendId: backendId,
        sessionId: sessionId,
        work: false,
        pending: true,
      );

  NotificationRowEntry both(String backendId, String sessionId) =>
      NotificationRowEntry(
        backendId: backendId,
        sessionId: sessionId,
        pending: true,
      );

  test('empty store yields empty entries', () {
    expect(ledger.readEntries(), isEmpty);
  });

  test('recordWork adds entries and persists across store reloads', () async {
    ledger.recordWork(backendId: 'b1', sessionId: 's1');
    ledger.recordWork(backendId: 'b2', sessionId: 's2');

    expect(ledger.readEntries(), [work('b1', 's1'), work('b2', 's2')]);

    await store.flush();

    final reopenedStore = LocalStateStore(file);
    await reopenedStore.load();
    final reopenedLedger = StoreNotificationLedger(reopenedStore);

    expect(reopenedLedger.readEntries(), [work('b1', 's1'), work('b2', 's2')]);
  });

  test('recordPending keeps a single entry with the pending row', () async {
    ledger.recordPending(backendId: 'b1', sessionId: 's1');

    expect(ledger.readEntries(), [pending('b1', 's1')]);

    await store.flush();

    final reopenedStore = LocalStateStore(file);
    await reopenedStore.load();

    expect(StoreNotificationLedger(reopenedStore).readEntries(), [
      pending('b1', 's1'),
    ]);
  });

  test('a session that posts both rows keeps one merged entry', () {
    ledger.recordPending(backendId: 'b1', sessionId: 's1');
    ledger.recordWork(backendId: 'b1', sessionId: 's1');
    ledger.recordPending(backendId: 'b1', sessionId: 's1');

    expect(ledger.readEntries(), [both('b1', 's1')]);
  });

  test('recording duplicate entry is idempotent', () {
    ledger.recordWork(backendId: 'b1', sessionId: 's1');
    ledger.recordWork(backendId: 'b1', sessionId: 's1');

    expect(ledger.readEntries(), [work('b1', 's1')]);
  });

  test('removing one row keeps the entry while the other is recorded', () {
    ledger.recordWork(backendId: 'b1', sessionId: 's1');
    ledger.recordPending(backendId: 'b1', sessionId: 's1');

    ledger.removeWork(backendId: 'b1', sessionId: 's1');
    expect(ledger.readEntries(), [pending('b1', 's1')]);

    ledger.removePending(backendId: 'b1', sessionId: 's1');
    expect(ledger.readEntries(), isEmpty);
  });

  test('removePending on a work-only entry leaves it recorded', () {
    ledger.recordWork(backendId: 'b1', sessionId: 's1');

    ledger.removePending(backendId: 'b1', sessionId: 's1');

    expect(ledger.readEntries(), [work('b1', 's1')]);
  });

  test('removing the last row evicts the entry and persists', () async {
    ledger.recordWork(backendId: 'b1', sessionId: 's1');
    ledger.recordWork(backendId: 'b2', sessionId: 's2');
    ledger.recordPending(backendId: 'b2', sessionId: 's2');

    ledger.removeWork(backendId: 'b1', sessionId: 's1');
    ledger.removeWork(backendId: 'b2', sessionId: 's2');

    expect(ledger.readEntries(), [pending('b2', 's2')]);

    ledger.removePending(backendId: 'b2', sessionId: 's2');

    await store.flush();

    final reopenedStore = LocalStateStore(file);
    await reopenedStore.load();
    expect(StoreNotificationLedger(reopenedStore).readEntries(), isEmpty);
  });

  test('removing non-existent entry is safe', () {
    ledger.recordWork(backendId: 'b1', sessionId: 's1');
    ledger.removeWork(backendId: 'b99', sessionId: 's99');
    ledger.removePending(backendId: 'b99', sessionId: 's99');

    expect(ledger.readEntries(), [work('b1', 's1')]);
  });

  test('ignores malformed entries in local store', () {
    store.write('notifications.posted_rows', [
      'not a map',
      {'backendId': 123, 'sessionId': 's1'},
      {'backendId': 'b1'},
      {'backendId': 'b1', 'sessionId': 's1'},
    ]);

    expect(ledger.readEntries(), [work('b1', 's1')]);
  });

  test('decodes pre-pending JSON (no row flags) as a work row', () {
    // The shape written before the pending row existed: two string fields
    // and nothing else.
    store.write('notifications.posted_rows', [
      {'backendId': 'b1', 'sessionId': 's1'},
      {'backendId': 'b2', 'sessionId': 's2', 'unrelated': true},
    ]);

    expect(ledger.readEntries(), [work('b1', 's1'), work('b2', 's2')]);
  });

  test('every stored entry keeps the old backendId/sessionId fields', () {
    // A build predating the pending row decodes entries by these two string
    // fields and ignores unknown keys, so the extra row flags must ride
    // alongside them rather than replace them.
    ledger.recordWork(backendId: 'b1', sessionId: 's1');
    ledger.recordPending(backendId: 'b2', sessionId: 's2');

    final raw = store.read('notifications.posted_rows');
    expect(raw, isA<List<Object?>>());
    for (final item in raw! as List<Object?>) {
      expect(item, isA<Map<String, Object?>>());
      final map = item! as Map<String, Object?>;
      expect(map['backendId'], isA<String>());
      expect(map['sessionId'], isA<String>());
    }
  });

  test('drops a stored entry that explicitly records no row', () {
    store.write('notifications.posted_rows', [
      {'backendId': 'b1', 'sessionId': 's1', 'work': false, 'pending': false},
      {'backendId': 'b2', 'sessionId': 's2', 'work': false, 'pending': true},
    ]);

    expect(ledger.readEntries(), [pending('b2', 's2')]);
  });
}
