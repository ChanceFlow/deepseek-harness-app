/// App destination selection — the shared navigation state behind the
/// bottom bar and every in-surface destination switch (the sidebar's
/// settings trigger). The enum names the three Places; the notifier
/// owns the selection so widgets outside `app_destination.dart` can
/// switch destinations without a callback chain.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../local_state/local_state_providers.dart';

enum AppDestination {
  chat(Icons.chat_bubble_outline),
  workspaces(Icons.folder_outlined),
  settings(Icons.settings_outlined);

  const AppDestination(this.icon);

  final IconData icon;

  /// Bottom-navigation label, localized.
  String label(AppLocalizations l10n) => switch (this) {
    AppDestination.chat => l10n.destinationChat,
    AppDestination.workspaces => l10n.destinationWorkspaces,
    AppDestination.settings => l10n.destinationSettings,
  };
}

/// Local state store key: the selected [AppDestination]'s `index`.
const String kAppDestinationKey = 'app.destination';

/// The app's selected destination.
///
/// Restores `app.destination` once [localStateStoreProvider] resolves
/// (Chat covers the pre-load window and an unreadable store); writes
/// the selection on every [select].
class AppDestinationNotifier extends Notifier<AppDestination> {
  /// A selection made before the store resolved; it outranks the
  /// persisted snapshot restored by the store-triggered rebuild.
  AppDestination? _userSelection;

  @override
  AppDestination build() {
    if (_userSelection != null) return _userSelection!;
    final store = ref.watch(localStateStoreProvider).value;
    if (store != null) {
      final index = store.read(kAppDestinationKey);
      if (index is int && index >= 0 && index < AppDestination.values.length) {
        return AppDestination.values[index];
      }
    }
    return AppDestination.chat;
  }

  /// Selects [destination] for every destination surface and persists
  /// the choice; before the store resolves the selection stays in
  /// memory only.
  void select(AppDestination destination) {
    _userSelection = destination;
    state = destination;
    ref
        .read(localStateStoreProvider)
        .value
        ?.write(kAppDestinationKey, destination.index);
  }
}

/// The selected [AppDestination]; Chat until the store restores the
/// persisted selection.
final appDestinationProvider =
    NotifierProvider<AppDestinationNotifier, AppDestination>(
      AppDestinationNotifier.new,
    );
