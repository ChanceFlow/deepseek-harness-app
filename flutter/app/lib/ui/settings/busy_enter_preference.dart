/// Busy-Enter preference — the General row for the composer's
/// busy-state send behavior (web EnterBehaviorRow).
///
/// The value persists in the shared LocalStateStore under
/// `chat.busyEnterBehavior`; the composer's busy-send path reads the
/// same key, so this row is the only writer. Storage is device-local:
/// the preference never rides a wire call.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../local_state/local_state_providers.dart';
import '../../local_state/local_state_store.dart';
import '../state_stream.dart';

/// KV key shared with the composer's busy-send path.
const String kBusyEnterBehaviorKey = 'chat.busyEnterBehavior';

/// Delivery mode for a send issued while the session's turn runs.
enum BusyEnterBehavior {
  /// Queue the message behind the running turn (the default).
  queue,

  /// Steer: interrupt the running turn with the message.
  steer;

  /// The stored form (the KV value); also the display id.
  String get wireName => name;

  /// Resolve a stored value; null when it names no behavior, so an
  /// unknown value leaves the default standing.
  static BusyEnterBehavior? fromStored(String? stored) {
    for (final behavior in BusyEnterBehavior.values) {
      if (behavior.wireName == stored) return behavior;
    }
    return null;
  }
}

/// UDF controller over the shared store: reads the stored value on
/// construction (the provider hands over an already-loaded store —
/// re-loading would race a concurrent write and drop it), publishes
/// every change, and persists writes before confirming them.
class BusyEnterPreferenceController {
  BusyEnterPreferenceController(this._store) {
    final stored = _store.read(kBusyEnterBehaviorKey);
    final behavior = BusyEnterBehavior.fromStored(
      stored is String ? stored : null,
    );
    if (behavior != null) _state.value = behavior;
  }

  final LocalStateStore _store;
  final AppStateStream<BusyEnterBehavior> _state =
      AppStateStream<BusyEnterBehavior>(BusyEnterBehavior.queue);

  BusyEnterBehavior get state => _state.value;
  Stream<BusyEnterBehavior> get uiState => _state.stream;

  void dispose() {
    unawaited(_state.close());
  }

  /// Persist one behavior. The row updates optimistically and snaps
  /// back when the store refuses the write. [LocalStateStore.write] is
  /// synchronous against the cache; [LocalStateStore.flush] is what
  /// carries the value to disk, so a settings toggle (unlike a draft
  /// keystroke) persists immediately.
  Future<void> select(BusyEnterBehavior behavior) async {
    final before = _state.value;
    if (behavior == before) return;
    _state.value = behavior;
    try {
      _store.write(kBusyEnterBehaviorKey, behavior.wireName);
      await _store.flush();
    } catch (_) {
      _state.value = before;
    }
  }
}

/// One controller per store; the store instance is shared with every
/// other LocalStateStore consumer (the composer's busy-send path).
final busyEnterPreferenceProvider =
    FutureProvider<BusyEnterPreferenceController>((ref) async {
      final store = await ref.watch(localStateStoreProvider.future);
      final controller = BusyEnterPreferenceController(store);
      ref.onDispose(controller.dispose);
      return controller;
    });
