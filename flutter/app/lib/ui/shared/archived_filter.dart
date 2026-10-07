/// Archived-session visibility: which archived rows the browsing surfaces
/// show, and the persisted choice behind it.
///
/// A [Notifier] over the shared store rather than a future: the browsing
/// surfaces mount this for the app's lifetime, and the store resolves
/// asynchronously (and never at all on a host without the platform documents
/// directory, such as a widget test). The stored value is adopted the moment
/// the store arrives — unless the user already chose inside that pre-load
/// window, the same rule the sidebar's own browsing toggles follow — and an
/// unknown or pre-filter stored value reads as [ArchivedFilter.hide], the
/// reference's own backward-compatible default. Both browsing surfaces read
/// the one provider, so switching the filter in either moves both.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../local_state/local_state_providers.dart';
import '../../local_state/local_state_store.dart';
import '../../logging/error_log_collector.dart';

/// KV key holding the archived-visibility choice.
const String kArchivedFilterKey = 'app.archivedFilter';

/// Which archived sessions a browsing list shows (the reference's
/// `ArchivedFilter`).
enum ArchivedFilter {
  /// Archived rows are hidden; only the current session's own blank
  /// placeholder can still show.
  hide,

  /// Ordinary rows plus archived ones, the archived row marked.
  show,

  /// Archived rows only.
  only;

  /// The stored form (the KV value).
  String get storedName => name;

  /// Resolve a stored value; null when it names no filter, so an unknown
  /// value leaves the default standing.
  static ArchivedFilter? fromStored(String? stored) {
    for (final filter in ArchivedFilter.values) {
      if (filter.storedName == stored) return filter;
    }
    return null;
  }
}

/// The live choice, persisted on every change.
class ArchivedFilterNotifier extends Notifier<ArchivedFilter> {
  /// The user's own choice once one was made; it outranks whatever the store
  /// held when it finally resolved.
  ArchivedFilter? _choice;

  @override
  ArchivedFilter build() {
    final chosen = _choice;
    if (chosen != null) return chosen;
    final store = ref.read(localStateStoreProvider).value;
    if (store != null) return _storedFilter(store) ?? ArchivedFilter.hide;
    // The store resolves asynchronously. A listener rather than a watch:
    // re-running this build through the provider scheduler would invalidate
    // every reader a frame after the read, and the stored choice is durable
    // state read once.
    ref.listen(localStateStoreProvider, (previous, next) {
      final resolved = next.value;
      if (resolved == null || _choice != null) return;
      final filter = _storedFilter(resolved);
      if (filter != null && filter != state) state = filter;
    });
    return ArchivedFilter.hide;
  }

  /// The stored filter, or null when the document holds no readable choice
  /// (a pre-filter or foreign value).
  static ArchivedFilter? _storedFilter(LocalStateStore store) {
    final stored = store.read(kArchivedFilterKey);
    return ArchivedFilter.fromStored(stored is String ? stored : null);
  }

  /// Persist one choice. The list updates optimistically and snaps back when
  /// the store refuses the write; before the store resolves the choice is
  /// live-only, and the next change after load writes it.
  Future<void> select(ArchivedFilter filter) async {
    final before = state;
    if (filter == before) return;
    _choice = filter;
    state = filter;
    final store = ref.read(localStateStoreProvider).value;
    if (store == null) return;
    try {
      store.write(kArchivedFilterKey, filter.storedName);
      await store.flush();
    } catch (e) {
      _choice = before;
      state = before;
      ErrorLogCollector.instance.addBreadcrumb(
        'Failed to persist archived filter: $e',
        level: 'warning',
      );
    }
  }
}

/// The one archived-visibility choice both browsing surfaces read.
final archivedFilterProvider =
    NotifierProvider<ArchivedFilterNotifier, ArchivedFilter>(
      ArchivedFilterNotifier.new,
    );
