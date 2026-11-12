/// Record of posted notification rows persisted across app restarts.
///
/// When a work (ongoing/done) or pending-interaction notification is shown,
/// its (backendId, sessionId) pair and the row family are recorded in the
/// ledger; when a row is cancelled, that family is evicted, and an entry
/// disappears once neither row is thought live. At startup the ledger is
/// cleared wholesale — it is the record of what the *previous* process
/// posted, and none of it is confirmed by the new one — so an orphaned row
/// can never outlive the process that posted it.
///
/// The stored JSON keeps the original `backendId`/`sessionId` shape: the row
/// flags are written only when they differ from the pre-pending defaults
/// (work row present, no pending row), so a build that predates the pending
/// row still decodes every entry it reads.
library;

import '../local_state/local_state_store.dart';

/// One session's recorded notification rows.
final class NotificationRowEntry {
  const NotificationRowEntry({
    required this.backendId,
    required this.sessionId,
    this.work = true,
    this.pending = false,
  });

  final String backendId;
  final String sessionId;

  /// Whether a work row (the silent ongoing row or its promoted done
  /// notice) is thought posted for this session.
  final bool work;

  /// Whether a pending-interaction row (approval or plan review) is thought
  /// posted for this session.
  final bool pending;

  /// Whether this entry records no row at all; it is then evicted.
  bool get isEmpty => !work && !pending;

  @override
  bool operator ==(Object other) =>
      other is NotificationRowEntry &&
      other.backendId == backendId &&
      other.sessionId == sessionId &&
      other.work == work &&
      other.pending == pending;

  @override
  int get hashCode => Object.hash(backendId, sessionId, work, pending);

  @override
  String toString() =>
      'NotificationRowEntry($backendId, $sessionId, work: $work, '
      'pending: $pending)';
}

/// Abstract contract for recording and querying posted OS notification rows.
abstract class NotificationLedger {
  /// All currently recorded posted rows, one entry per session.
  List<NotificationRowEntry> readEntries();

  /// Records that a work (ongoing/done) row was posted for this session.
  void recordWork({required String backendId, required String sessionId});

  /// Records that a pending-interaction row was posted for this session.
  void recordPending({required String backendId, required String sessionId});

  /// Evicts a cancelled work row; the entry survives while its pending row
  /// is still recorded.
  void removeWork({required String backendId, required String sessionId});

  /// Evicts a cancelled pending row; the entry survives while its work row
  /// is still recorded.
  void removePending({required String backendId, required String sessionId});
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
          // An entry written before the pending row existed carries neither
          // flag; it is a work row.
          final work = item['work'];
          final pending = item['pending'];
          final entry = NotificationRowEntry(
            backendId: backendId,
            sessionId: sessionId,
            work: work is bool ? work : true,
            pending: pending is bool ? pending : false,
          );
          if (!entry.isEmpty) entries.add(entry);
        }
      }
    }
    return entries;
  }

  @override
  void recordWork({required String backendId, required String sessionId}) {
    _update(backendId: backendId, sessionId: sessionId, work: true);
  }

  @override
  void recordPending({required String backendId, required String sessionId}) {
    _update(backendId: backendId, sessionId: sessionId, pending: true);
  }

  @override
  void removeWork({required String backendId, required String sessionId}) {
    _update(backendId: backendId, sessionId: sessionId, work: false);
  }

  @override
  void removePending({required String backendId, required String sessionId}) {
    _update(backendId: backendId, sessionId: sessionId, pending: false);
  }

  /// Sets the named row flags on the session's entry, creating it when a row
  /// is being recorded and evicting it once neither row remains.
  void _update({
    required String backendId,
    required String sessionId,
    bool? work,
    bool? pending,
  }) {
    final entries = List.of(readEntries());
    final index = entries.indexWhere(
      (entry) => entry.backendId == backendId && entry.sessionId == sessionId,
    );
    final existing = index < 0 ? null : entries[index];
    final entry = NotificationRowEntry(
      backendId: backendId,
      sessionId: sessionId,
      work: work ?? existing?.work ?? false,
      pending: pending ?? existing?.pending ?? false,
    );
    if (entry == existing) return;
    if (entry.isEmpty) {
      if (existing == null) return;
      entries.removeAt(index);
    } else if (existing == null) {
      entries.add(entry);
    } else {
      entries[index] = entry;
    }
    _save(entries);
  }

  void _save(List<NotificationRowEntry> entries) {
    if (entries.isEmpty) {
      _store.write(_storageKey, null);
    } else {
      _store.write(_storageKey, entries.map(_encode).toList(growable: false));
    }
  }

  /// The stored shape: the original two fields always, row flags only when
  /// they differ from that original entry's meaning.
  static Map<String, Object?> _encode(NotificationRowEntry entry) =>
      <String, Object?>{
        'backendId': entry.backendId,
        'sessionId': entry.sessionId,
        if (!entry.work) 'work': false,
        if (entry.pending) 'pending': true,
      };
}
