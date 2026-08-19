/// App root — port of AppRoot.kt: six-destination bottom navigation.
///
/// The remaining four destinations are placeholder surfaces until their
/// screens land (tracked in ROADMAP §4).
library;

import 'package:flutter/material.dart';

import '../chat/chat_screen.dart';
import '../goal/goal_screen.dart';
import '../models/models_screen.dart';
import '../settings/settings_screen.dart';
import '../subagents/subagent_screen.dart';
import '../workspace/workspace_screen.dart';

enum AppDestination {
  chat('Chat', Icons.chat_bubble_outline),
  workspaces('Workspaces', Icons.folder_outlined),
  models('Models', Icons.tune),
  subagents('Subagents', Icons.account_tree_outlined),
  goals('Goals', Icons.flag_outlined),
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
      body: switch (AppDestination.values[_selectedIndex]) {
        AppDestination.chat => const ChatRoute(),
        AppDestination.workspaces => const WorkspaceRoute(),
        AppDestination.models => const ModelsRoute(),
        AppDestination.subagents => const SubagentRoute(),
        AppDestination.goals => const GoalRoute(),
        AppDestination.settings => const SettingsRoute(),
      },
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
