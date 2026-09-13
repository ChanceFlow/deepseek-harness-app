/// The one-shot gate behind the notification-permission ask.
///
/// Android spends its own permission dialog sparingly: once the user has
/// declined twice the app can never prompt again, and a request made on the
/// first launch — before the user has seen a session, let alone work in
/// flight — is the ask they decline. So the app asks once, at the moment
/// there is a reason on screen, and explains itself first. This gate records
/// that the explanation has been shown so it is never shown twice.
///
/// The fact is device-local: it describes what this device's user has seen,
/// not anything about a host, so it lives in the same UI-state cache the
/// other one-shot preferences use.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../local_state/local_state_providers.dart';
import '../local_state/local_state_store.dart';

/// Local-state key: whether the rationale has already been shown.
const String kNotificationPermissionPromptedKey =
    'app.notificationPermissionPrompted';

/// Reads and records the one-shot rationale fact.
class NotificationPermissionGate {
  const NotificationPermissionGate(this._store);

  final LocalStateStore _store;

  /// Whether this device has already seen the rationale.
  bool get prompted => _store.read(kNotificationPermissionPromptedKey) == true;

  /// Records that the rationale has been shown. A write failure only costs
  /// one repeated explanation on the next launch, so it is not surfaced.
  Future<void> markPrompted() async {
    _store.write(kNotificationPermissionPromptedKey, true);
    await _store.flush();
  }
}

/// The gate over the shared local-state cache; null while that cache loads.
final notificationPermissionGateProvider =
    FutureProvider<NotificationPermissionGate>((ref) async {
      final store = await ref.watch(localStateStoreProvider.future);
      return NotificationPermissionGate(store);
    });
