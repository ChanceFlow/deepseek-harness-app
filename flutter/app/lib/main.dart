import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'di/providers.dart' show systemNotifierProvider;
import 'notifications/system_notifier.dart';
import 'ui/root/app_root.dart';
import 'ui/theme/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // One system notifier, initialized here (permission request + launch-time
  // locale + cold-start tap capture) and handed to the DI layer through an
  // override so the provider consumers share the exact initialized instance.
  final notifier = SystemNotifier();
  await notifier.initialize();
  runApp(
    ProviderScope(
      overrides: [systemNotifierProvider.overrideWithValue(notifier)],
      child: const DshApp(),
    ),
  );
}

class DshApp extends StatelessWidget {
  const DshApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // Brand title; resolves through l10n so the OS task-switcher
      // label follows the device locale (DSH Mobile stays the
      // canonical name in every locale).
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      theme: DshTheme.light(),
      darkTheme: DshTheme.dark(),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('zh'),
      ],
      home: const AppRoot(),
    );
  }
}
