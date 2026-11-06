/// Appearance preference — the host `ui-theme` preference and the
/// `ThemeMode` the app resolves from it.
///
/// The three host preferences live in the host user-settings document's
/// `ui-theme` namespace under `preference` (`light`/`dark`/`system`),
/// exactly as the reference web client persists it
/// (`reference/.../client/ui-theme/src/theme-settings.ts:9-21`,
/// `.../client/index.ts:231-239`). Reads and writes ride the existing
/// settings plane (`settings.describe` / `settings.mutate`) and the writes
/// are revision-checked against the revision the last describe reported, the
/// same CAS guard the agent-preset default uses.
///
/// The OLED appearance is device-local instead: the host union is closed at
/// `light`/`dark`/`system` (`THEME_PREFERENCES`, reference `ui-theme`
/// plugin), and whether a panel lights a black pixel is a fact about this
/// phone, not about the host's shared user document. It persists in the
/// shared `LocalStateStore` under [kOledAppearanceKey], overrides the host
/// preference while it is on, and is off by default — so an untouched device
/// and every already-stored host value keep the meaning they had.
///
/// The namespace is loopback-gated on the host, so a directly-connected
/// phone can neither read nor write it; the app then resolves `system`
/// instead of pretending a stored value existed. The WebView shell draws no
/// appearance row; `DshApp` still reads the resolved mode and theme.
library;

import 'dart:async';
import 'dart:convert';

import 'package:domain/repository/chat_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../di/providers.dart';
import '../local_state/local_state_providers.dart';
import '../local_state/local_state_store.dart';
import '../state_stream.dart';
import 'theme.dart';

/// The settings namespace the host theme preference lives in.
const String kThemeSettingsNamespace = 'ui-theme';

/// The field carrying the selected built-in theme preference.
const String kThemePreferenceField = 'preference';

/// Device-local KV key for the OLED appearance flag. Absent (or false) is
/// the default; a false selection deletes the key.
const String kOledAppearanceKey = 'app.oledAppearance';

/// The built-in appearance choices: the host union's three members plus the
/// device-local OLED appearance.
enum ThemePreference {
  light,
  dark,

  /// The dark scheme on a pure-black page, for an OLED panel. Device-local:
  /// it never rides the host `ui-theme.preference` field.
  oled,

  system;

  /// The stored form (the wire value).
  String get wireName => name;

  /// The Flutter theme mode this preference resolves to. OLED wears the
  /// dark scheme; what differs is the surface family
  /// ([DshTheme.oled]), not the mode.
  ThemeMode get themeMode => switch (this) {
    ThemePreference.light => ThemeMode.light,
    ThemePreference.dark => ThemeMode.dark,
    ThemePreference.oled => ThemeMode.dark,
    ThemePreference.system => ThemeMode.system,
  };

  /// Whether the host's `ui-theme.preference` union accepts this value.
  /// OLED does not: the reference plugin's `THEME_PREFERENCES` is closed at
  /// `light`/`dark`/`system`, so OLED is written to the device-local store
  /// instead.
  bool get hostStored => this != ThemePreference.oled;

  /// Resolve a stored host value; null when it names no host preference, so
  /// an unknown value leaves the system default standing. The device-local
  /// OLED flag is read separately, never through this.
  static ThemePreference? fromStored(Object? stored) {
    for (final preference in ThemePreference.values) {
      if (preference.hostStored && preference.wireName == stored) {
        return preference;
      }
    }
    return null;
  }
}

/// One resolved appearance state.
final class ThemePreferenceState {
  const ThemePreferenceState({
    this.preference = ThemePreference.system,
    this.revision,
    this.exposed = false,
    this.writable = false,
    this.loading = false,
    this.saving = false,
    this.failed = false,
  });

  /// The persisted host preference (`light`/`dark`/`system`); `system` while
  /// unread or unknown. The device-local OLED flag is not this value — the
  /// row and the app resolution layer combine the two.
  final ThemePreference preference;

  /// The `ui-theme` revision the last describe reported (the write's CAS
  /// guard); null before a successful describe.
  final int? revision;

  /// Whether the host exposed the `ui-theme.preference` field.
  final bool exposed;

  /// Whether the host accepts settings writes at all.
  final bool writable;

  final bool loading;
  final bool saving;

  /// A read or write failed; the row states it and offers a retry.
  final bool failed;

  ThemePreferenceState copyWith({
    ThemePreference? preference,
    int? revision,
    bool? exposed,
    bool? writable,
    bool? loading,
    bool? saving,
    bool? failed,
  }) {
    return ThemePreferenceState(
      preference: preference ?? this.preference,
      revision: revision ?? this.revision,
      exposed: exposed ?? this.exposed,
      writable: writable ?? this.writable,
      loading: loading ?? this.loading,
      saving: saving ?? this.saving,
      failed: failed ?? this.failed,
    );
  }
}

/// UDF controller over the host `ui-theme` namespace: reads on construction,
/// publishes every change, and writes the preference with the described
/// revision as CAS guard before confirming it with a fresh describe.
class ThemePreferenceController {
  ThemePreferenceController(this._repository) {
    unawaited(refresh());
  }

  final ChatRepository _repository;
  final AppStateStream<ThemePreferenceState> _state =
      AppStateStream<ThemePreferenceState>(const ThemePreferenceState());

  ThemePreferenceState get state => _state.value;
  Stream<ThemePreferenceState> get uiState => _state.stream;

  void dispose() {
    unawaited(_state.close());
  }

  /// Re-describe the namespace and adopt what the host reports.
  Future<void> refresh() async {
    _state.value = _state.value.copyWith(loading: true, failed: false);
    try {
      final snapshot = await _repository.describeSettings();
      final namespace = snapshot.namespaces
          .where((entry) => entry.ns == kThemeSettingsNamespace)
          .firstOrNull;
      final value = namespace?.value;
      final exposed = value is Map && value.containsKey(kThemePreferenceField);
      _state.value = ThemePreferenceState(
        preference:
            (value is Map
                ? ThemePreference.fromStored(value[kThemePreferenceField])
                : null) ??
            ThemePreference.system,
        revision: namespace?.revision,
        exposed: exposed,
        writable: snapshot.writable,
      );
    } catch (error) {
      _state.value = _state.value.copyWith(loading: false, failed: true);
      ErrorLogCollector.instance.addBreadcrumb(
        'Theme preference describe failed: $error',
        level: 'warning',
      );
    }
  }

  /// Persist one preference. The selection updates optimistically — the app
  /// theme flips with the tap — and reverts when the host refuses the write.
  Future<void> select(ThemePreference preference) async {
    final before = _state.value;
    if (preference == before.preference || before.saving) return;
    _state.value = before.copyWith(
      preference: preference,
      saving: true,
      failed: false,
    );
    try {
      await _repository.updateSetting(
        kThemeSettingsNamespace,
        kThemePreferenceField,
        jsonEncode(preference.wireName),
        expectedRevision: before.revision,
      );
      await refresh();
    } catch (error) {
      _state.value = before.copyWith(saving: false, failed: true);
      ErrorLogCollector.instance.addBreadcrumb(
        'Theme preference write failed: $error',
        level: 'warning',
      );
    }
  }
}

/// One controller per backend: the describe and the CAS-guarded write share
/// the repository the rest of the settings surface uses.
final themePreferenceControllerProvider = Provider.family
    .autoDispose<ThemePreferenceController, String>((ref, backendId) {
      final controller = ThemePreferenceController(
        ref.watch(chatRepositoryProvider(backendId)),
      );
      ref.onDispose(controller.dispose);
      return controller;
    });

/// UDF controller over the shared store: reads the stored flag on
/// construction, publishes every change, and persists writes before
/// confirming them. An absent key means off, so a device that never picked
/// OLED keeps the pre-OLED behaviour.
class OledAppearanceController {
  OledAppearanceController(this._store) {
    _state.value = _store.read(kOledAppearanceKey) == true;
  }

  final LocalStateStore _store;
  final AppStateStream<bool> _state = AppStateStream<bool>(false);

  bool get state => _state.value;
  Stream<bool> get uiState => _state.stream;

  void dispose() {
    unawaited(_state.close());
  }

  /// Persist one selection. The row updates optimistically and snaps back
  /// when the store refuses the write. Turning OLED off deletes the key,
  /// leaving the default standing rather than storing a `false`.
  Future<void> select(bool enabled) async {
    final before = _state.value;
    if (enabled == before) return;
    _state.value = enabled;
    try {
      _store.write(kOledAppearanceKey, enabled ? true : null);
      await _store.flush();
    } catch (error) {
      _state.value = before;
      ErrorLogCollector.instance.addBreadcrumb(
        'OLED appearance write failed: $error',
        level: 'warning',
      );
    }
  }
}

/// One controller per store; storage is device-local.
final oledAppearanceControllerProvider =
    FutureProvider<OledAppearanceController>((ref) async {
      final store = await ref.watch(localStateStoreProvider.future);
      final controller = OledAppearanceController(store);
      ref.onDispose(controller.dispose);
      return controller;
    });

/// The device-local OLED appearance: false while the store loads, when it is
/// unavailable, or when it was never chosen.
final appOledAppearanceProvider = StreamProvider<bool>((ref) async* {
  final controller = await ref.watch(oledAppearanceControllerProvider.future);
  yield* controller.uiState;
});

/// The host `ui-theme.preference` as a [ThemeMode]; `system` while the store
/// loads, the host is unreachable, or the namespace is absent.
final hostThemeModeProvider = StreamProvider<ThemeMode>((ref) async* {
  final backendId = await ref.watch(activeBackendIdProvider.future);
  if (backendId.isEmpty) {
    yield ThemeMode.system;
    return;
  }
  final controller = ref.watch(themePreferenceControllerProvider(backendId));
  yield* controller.uiState.map((state) => state.preference.themeMode);
});

/// The [ThemeMode] the app wears: the OLED appearance pins dark (its theme is
/// the pure-black one, so a light system appearance must not win), otherwise
/// the host preference.
final appThemeModeProvider = Provider<ThemeMode>((ref) {
  final oled = ref.watch(appOledAppearanceProvider).value ?? false;
  if (oled) return ThemeMode.dark;
  return ref.watch(hostThemeModeProvider).value ?? ThemeMode.system;
});

/// The dark [ThemeData] the app wears: [DshTheme.oled] while the OLED
/// appearance is on, [DshTheme.dark] otherwise.
final appDarkThemeProvider = Provider<ThemeData>((ref) {
  final oled = ref.watch(appOledAppearanceProvider).value ?? false;
  return oled ? DshTheme.oled() : DshTheme.dark();
});
