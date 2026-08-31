/// Unit tests for NotificationLedger / StoreNotificationLedger.
///
/// Asserts that posted notification entries record and evict properly
/// over LocalStateStore, survive reloading the underlying JSON file,
/// and handle corrupt or malformed stored state gracefully.
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

  test('empty store yields empty entries', () {
    expect(ledger.readEntries(), isEmpty);
  });

  test('record adds entries and persists across store reloads', () async {
    ledger.record(backendId: 'b1', sessionId: 's1');
    ledger.record(backendId: 'b2', sessionId: 's2');

    expect(ledger.readEntries(), [
      const NotificationRowEntry(backendId: 'b1', sessionId: 's1'),
      const NotificationRowEntry(backendId: 'b2', sessionId: 's2'),
    ]);

    await store.flush();

    final reopenedStore = LocalStateStore(file);
    await reopenedStore.load();
    final reopenedLedger = StoreNotificationLedger(reopenedStore);

    expect(reopenedLedger.readEntries(), [
      const NotificationRowEntry(backendId: 'b1', sessionId: 's1'),
      const NotificationRowEntry(backendId: 'b2', sessionId: 's2'),
    ]);
  });

  test('recording duplicate entry is idempotent', () {
    ledger.record(backendId: 'b1', sessionId: 's1');
    ledger.record(backendId: 'b1', sessionId: 's1');

    expect(ledger.readEntries(), [
      const NotificationRowEntry(backendId: 'b1', sessionId: 's1'),
    ]);
  });

  test('remove evicts entry from ledger and persists', () async {
    ledger.record(backendId: 'b1', sessionId: 's1');
    ledger.record(backendId: 'b2', sessionId: 's2');

    ledger.remove(backendId: 'b1', sessionId: 's1');

    expect(ledger.readEntries(), [
      const NotificationRowEntry(backendId: 'b2', sessionId: 's2'),
    ]);

    await store.flush();

    final reopenedStore = LocalStateStore(file);
    await reopenedStore.load();
    final reopenedLedger = StoreNotificationLedger(reopenedStore);

    expect(reopenedLedger.readEntries(), [
      const NotificationRowEntry(backendId: 'b2', sessionId: 's2'),
    ]);
  });

  test('removing non-existent entry is safe', () {
    ledger.record(backendId: 'b1', sessionId: 's1');
    ledger.remove(backendId: 'b99', sessionId: 's99');

    expect(ledger.readEntries(), [
      const NotificationRowEntry(backendId: 'b1', sessionId: 's1'),
    ]);
  });

  test('readEntries ignores malformed entries in local store', () {
    store.write('notifications.posted_rows', [
      'not a map',
      {'backendId': 123, 'sessionId': 's1'},
      {'backendId': 'b1'},
      {'backendId': 'b1', 'sessionId': 's1'},
    ]);

    expect(ledger.readEntries(), [
      const NotificationRowEntry(backendId: 'b1', sessionId: 's1'),
    ]);
  });
}
