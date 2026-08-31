/// Record of posted notification rows persisted across app restarts.
///
/// When an ongoing or promoted work notification is shown, its (backendId,
/// sessionId) pair is recorded in the ledger; when cancelled, it is evicted.
/// At startup, the ledger is swept against the enabled backend set: any row
/// belonging to a disabled or removed host is cancelled so orphaned rows do
/// not survive a process restart.
library;

import '../local_state/local_state_store.dart';

/// One posted notification row identity.
final class NotificationRowEntry {
  const NotificationRowEntry({
    required this.backendId,
    required this.sessionId,
  });

  final String backendId;
  final String sessionId;

  @override
  bool operator ==(Object other) =>
      other is NotificationRowEntry &&
      other.backendId == backendId &&
      other.sessionId == sessionId;

  @override
  int get hashCode => Object.hash(backendId, sessionId);

  @override
  String toString() => 'NotificationRowEntry($backendId, $sessionId)';
}

/// Abstract contract for recording and querying posted OS notification rows.
abstract class NotificationLedger {
  /// All currently recorded posted rows.
  List<NotificationRowEntry> readEntries();

  /// Records a posted notification row.
  void record({required String backendId, required String sessionId});

  /// Evicts a cancelled notification row.
  void remove({required String backendId, required String sessionId});
}

/// [NotificationLedger] implementation over the shared [LocalStateStore].
class StoreNotificationLedger implements NotificationLedger {
  StoreNotificationLedger(this._store);

  final LocalStateStore _store;
  static const String _storageKey = 'notifications.posted_rows';

  @override
  List<NotificationRowEntry> readEntries() {
    final raw = _store.read(_storageKey);
    if (raw is! List<Object?>) return const <NotificationRowEntry>[];
    final entries = <NotificationRowEntry>[];
    for (final item in raw) {
      if (item is Map<String, Object?>) {
        final backendId = item['backendId'];
        final sessionId = item['sessionId'];
        if (backendId is String && sessionId is String) {
          entries.add(
            NotificationRowEntry(backendId: backendId, sessionId: sessionId),
          );
        }
      }
    }
    return entries;
  }

  @override
  void record({required String backendId, required String sessionId}) {
    final current = readEntries().toSet();
    final entry = NotificationRowEntry(
      backendId: backendId,
      sessionId: sessionId,
    );
    if (current.add(entry)) {
      _save(current);
    }
  }

  @override
  void remove({required String backendId, required String sessionId}) {
    final current = readEntries().toSet();
    final entry = NotificationRowEntry(
      backendId: backendId,
      sessionId: sessionId,
    );
    if (current.remove(entry)) {
      _save(current);
    }
  }

  void _save(Set<NotificationRowEntry> entries) {
    if (entries.isEmpty) {
      _store.write(_storageKey, null);
    } else {
      _store.write(
        _storageKey,
        entries
            .map(
              (e) => <String, Object?>{
                'backendId': e.backendId,
                'sessionId': e.sessionId,
              },
            )
            .toList(growable: false),
      );
    }
  }
}
