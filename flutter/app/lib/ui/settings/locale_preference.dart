/// App locale preference — the App-settings row for the interface
/// language (web LanguageRow, moved to the app plane).
///
/// The value persists in the shared LocalStateStore under
/// `app.localePreference`; `DshApp` resolves its MaterialApp locale
/// from it, with `system` (the default) delegating to the device
/// locale. Storage is device-local: the preference never rides a wire
/// call, so the row works with or without a reachable host.
library;

import 'dart:async';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../local_state/local_state_providers.dart';
import '../../local_state/local_state_store.dart';
import '../state_stream.dart';

/// KV key shared with `DshApp`'s locale resolution.
const String kAppLocalePreferenceKey = 'app.localePreference';

/// The interface language choice. Labels for `zh`/`en` render in their
/// own language (web locale display names); `system` follows the
/// device locale.
enum AppLocalePreference {
  system,
  zh,
  en;

  /// The stored form (the KV value); also the display id.
  String get wireName => name;

  /// Resolve a stored value; null when it names no preference, so an
  /// unknown value leaves the system default standing.
  static AppLocalePreference? fromStored(String? stored) {
    for (final preference in AppLocalePreference.values) {
      if (preference.wireName == stored) return preference;
    }
    return null;
  }
}

/// The MaterialApp locale for one preference; null (delegating to the
/// device locale) unless an explicit language is chosen.
Locale? resolveAppLocale(AppLocalePreference? preference) =>
    switch (preference) {
      AppLocalePreference.zh => const Locale('zh'),
      AppLocalePreference.en => const Locale('en'),
      AppLocalePreference.system || null => null,
    };

/// UDF controller over the shared store: reads the stored value on
/// construction (the provider hands over an already-loaded store —
/// re-loading would race a concurrent write and drop it), publishes
/// every change, and persists writes before confirming them.
class LocalePreferenceController {
  LocalePreferenceController(this._store) {
    final stored = _store.read(kAppLocalePreferenceKey);
    final preference = AppLocalePreference.fromStored(
      stored is String ? stored : null,
    );
    if (preference != null) _state.value = preference;
  }

  final LocalStateStore _store;
  final AppStateStream<AppLocalePreference> _state =
      AppStateStream<AppLocalePreference>(AppLocalePreference.system);

  AppLocalePreference get state => _state.value;
  Stream<AppLocalePreference> get uiState => _state.stream;

  void dispose() {
    unawaited(_state.close());
  }

  /// Persist one preference. The row updates optimistically and snaps
  /// back when the store refuses the write. [LocalStateStore.write] is
  /// synchronous against the cache; [LocalStateStore.flush] is what
  /// carries the value to disk, so a language toggle persists
  /// immediately.
  Future<void> select(AppLocalePreference preference) async {
    final before = _state.value;
    if (preference == before) return;
    _state.value = preference;
    try {
      _store.write(kAppLocalePreferenceKey, preference.wireName);
      await _store.flush();
    } catch (_) {
      _state.value = before;
    }
  }
}

/// One controller per store; the store instance is shared with every
/// other LocalStateStore consumer (the App-settings language row).
final localePreferenceProvider =
    FutureProvider<LocalePreferenceController>((ref) async {
      final store = await ref.watch(localStateStoreProvider.future);
      final controller = LocalePreferenceController(store);
      ref.onDispose(controller.dispose);
      return controller;
    });

/// The effective preference for MaterialApp locale resolution; null
/// (system) while the store loads or is unavailable. `DshApp` watches
/// this so a language tap re-localizes the whole app.
final appLocalePreferenceProvider =
    StreamProvider<AppLocalePreference>((ref) async* {
      final controller = await ref.watch(localePreferenceProvider.future);
      yield* controller.uiState;
    });
