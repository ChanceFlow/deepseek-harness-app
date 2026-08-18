/// App root — port of AppRoot.kt: six-destination bottom navigation.
///
/// The remaining four destinations are placeholder surfaces until their
/// screens land (tracked in ROADMAP §4).
library;

import 'package:flutter/material.dart';

import '../chat/chat_screen.dart';
import '../workspace/workspace_screen.dart';

enum AppDestination {
  chat('Chat'),
  workspaces('Workspaces'),
  models('Models'),
  subagents('Subagents'),
  goals('Goals'),
  settings('Settings');

  const AppDestination(this.label);

  final String label;
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
      body: switch (AppDestination.values[_selectedIndex]) {
        AppDestination.chat => const ChatRoute(),
        AppDestination.workspaces => const WorkspaceRoute(),
        AppDestination.models => const _PlaceholderScreen('Models'),
        AppDestination.subagents => const _PlaceholderScreen('Subagents'),
        AppDestination.goals => const _PlaceholderScreen('Goals'),
        AppDestination.settings => const _PlaceholderScreen('Settings'),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: [
          for (final destination in AppDestination.values)
            NavigationDestination(
              icon: Text(destination.label.substring(0, 1)),
              label: destination.label,
            ),
        ],
      ),
    );
  }
}

/// Temporary stand-in for the four routes not yet ported.
class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(child: Text('$title screen pending port')),
    );
  }
}
