import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ui/root/app_root.dart';
import 'ui/theme/theme.dart';

void main() {
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
