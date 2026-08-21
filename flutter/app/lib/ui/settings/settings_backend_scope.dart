/// Settings backend scope — which backend's host-settings pages the
/// Settings tab presents, independent of the chat-active backend.
///
/// The scope follows the active backend until the user pins one (so the
/// pre-multi-backend behavior — settings describe what chat uses — stays
/// intact), then holds the pinned choice across active switches. A
/// pinned backend that leaves the registry resets the scope to
/// follow-active. The choice is device-local and session-scoped: the app
/// restarts to follow-active.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';

/// The effective backend id for the Settings host pages. Empty while
/// the registry has not resolved an active backend.
class SettingsBackendScope extends Notifier<String> {
  /// The user-pinned scope; null while following the active backend.
  String? _pinned;

  @override
  String build() {
    final active = ref.watch(activeBackendIdProvider).value ?? '';
    final registry = ref.watch(backendRegistryStateProvider).value;
    final candidate = _pinned ?? active;
    if (candidate.isNotEmpty && registry != null) {
      final exists = registry.backends.any((backend) => backend.id == candidate);
      if (!exists) {
        // The pinned backend is gone; fall back to following the active
        // one. The registry guard keeps the active backend removable-proof,
        // so the fallback target is always configured.
        _pinned = null;
        return active;
      }
    }
    return candidate;
  }

  /// Whether the user explicitly pinned a scope rather than following
  /// the active backend.
  bool get isPinned => _pinned != null;

  /// Pins the settings scope to a configured backend, independent of
  /// the chat-active backend.
  void select(String backendId) {
    _pinned = backendId;
    state = backendId;
  }

  /// Returns the scope to following the active backend.
  void followActive() {
    _pinned = null;
    state = ref.read(activeBackendIdProvider).value ?? '';
  }
}

/// The backend the Settings host pages describe. Follows the active
/// backend until [SettingsBackendScope.select] pins it.
final settingsBackendScopeProvider =
    NotifierProvider<SettingsBackendScope, String>(
      SettingsBackendScope.new,
    );
