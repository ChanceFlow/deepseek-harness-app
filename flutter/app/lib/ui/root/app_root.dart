/// App root — three bottom destinations (Places): the conversation
/// work surface, the workspace browser, and host configuration.
/// Session-scoped tools (Models/Goals/Subagents) live in the chat
/// sidebar's tools region, mirroring the web's context embedding.
/// The selected destination is [appDestinationProvider] state — the
/// bottom bar and the chat sidebar's settings trigger switch it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../chat/chat_screen.dart';
import '../settings/settings_screen.dart';
import '../workspace/workspace_screen.dart';
import 'app_destination.dart';

class AppRoot extends ConsumerWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final destination = ref.watch(appDestinationProvider);
    return Scaffold(
      // IndexedStack keeps every destination's state alive across tab
      // switches — the composer draft, scroll positions, and expansion
      // states survive leaving and returning to a tab (a switch here
      // would unmount the route and drop them).
      body: IndexedStack(
        index: destination.index,
        children: const [ChatRoute(), WorkspaceRoute(), SettingsRoute()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: destination.index,
        onDestinationSelected: (index) => ref
            .read(appDestinationProvider.notifier)
            .select(AppDestination.values[index]),
        destinations: [
          for (final destination in AppDestination.values)
            NavigationDestination(
              icon: Icon(destination.icon),
              label: destination.label,
            ),
        ],
      ),
    );
  }
}
