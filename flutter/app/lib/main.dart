import 'dart:io';

import 'package:app/l10n/app_localizations.dart';
import 'package:dev/dev.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'config.dart';
import 'di/providers.dart' show systemNotifierProvider;
import 'notifications/system_notifier.dart';
import 'ui/root/app_root.dart';
import 'ui/theme/theme.dart';

/// Debug-only crash capture bootstrap; null in release or when unavailable.
DevCrashBootstrap? crashBootstrap;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // One system notifier, initialized here (permission request + launch-time
  // locale + cold-start tap capture) and handed to the DI layer through an
  // override so the provider consumers share the exact initialized instance.
  final notifier = SystemNotifier();
  await notifier.initialize();
  _initCrashCapture();
  runApp(
    ProviderScope(
      overrides: [systemNotifierProvider.overrideWithValue(notifier)],
      child: const DshApp(),
    ),
  );
}

/// Wire the crash capture chain on debug builds only. Failure here must
/// never prevent the app from starting: capture is best-effort by design.
void _initCrashCapture() {
  if (!kDebugMode) return;
  // flutter_test runs with kDebugMode=true but no platform plugins; skip so
  // widget tests keep importing main.dart without a real documents dir.
  if (Platform.environment.containsKey('FLUTTER_TEST')) return;
  try {
    final documents = getApplicationDocumentsDirectory();
    // Fire-and-forget directory lookup; bootstrap starts once it resolves.
    documents.then((dir) {
      crashBootstrap = DevCrashBootstrap(
        buffer: LogBuffer(capacity: 300),
        marker: CrashMarker(File('${dir.path}/${CrashMarker.markerName}')),
        reporter: CrashReporter(
          intakeUrl: Uri.parse(kPiCrashIntakeUrl),
        ),
        build: const CrashBuildInfo(
          app: 'dsh-android',
          version: kDshAppVersion,
          build: kDshBuildNumber,
          platform: 'android',
          sourceRepo: kDshSourceRepo,
          sourceCommit: kDshSourceCommit,
        ),
        dshBaseUrl: kDshBaseUrl,
      )..start();
    }).catchError((Object _) {
      // No documents dir (plugin missing) — disable capture silently.
      crashBootstrap = null;
    });
  } catch (_) {
    crashBootstrap = null;
  }
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