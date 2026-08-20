/// App root — three bottom destinations (Places): the conversation
/// work surface, the workspace browser, and host configuration.
/// Session-scoped tools (Models/Goals/Subagents) live in the chat
/// sidebar's tools region, mirroring the web's context embedding.
library;

import 'package:flutter/material.dart';

import '../chat/chat_screen.dart';
import '../settings/settings_screen.dart';
import '../workspace/workspace_screen.dart';

enum AppDestination {
  chat('Chat', Icons.chat_bubble_outline),
  workspaces('Workspaces', Icons.folder_outlined),
  settings('Settings', Icons.settings_outlined);

  const AppDestination(this.label, this.icon);

  final String label;
  final IconData icon;
}

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack keeps every destination's state alive across tab
      // switches — the composer draft, scroll positions, and expansion
      // states survive leaving and returning to a tab (a switch here
      // would unmount the route and drop them).
      body: IndexedStack(
        index: _selectedIndex,
        children: const [ChatRoute(), WorkspaceRoute(), SettingsRoute()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
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
