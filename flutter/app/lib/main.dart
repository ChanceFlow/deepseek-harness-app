import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'notifications/turn_complete_notifier.dart';
import 'ui/root/app_root.dart';
import 'ui/theme/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await TurnCompleteNotifier().initialize();
  runApp(const ProviderScope(child: DshApp()));
}

class DshApp extends StatelessWidget {
  const DshApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DeepSeek Harness',
      theme: DshTheme.light(),
      darkTheme: DshTheme.dark(),
      home: const AppRoot(),
    );
  }
}
