import 'dart:async';
import 'dart:io';

import 'package:app/l10n/app_localizations.dart';
import 'package:dev/dev.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'config.dart';
import 'di/providers.dart' show systemNotifierProvider;
import 'logging/error_log_collector.dart';
import 'logging/error_log_entry.dart' show ErrorLogLevel;
import 'notifications/notification_localizations.dart';
import 'notifications/system_notifier.dart';
import 'ui/root/app_root.dart';
import 'ui/settings/locale_preference.dart';
import 'ui/settings/theme_preference.dart';
import 'ui/theme/theme.dart';

/// Debug-build telemetry bootstrap; null in release or when unavailable.
DebugToolBootstrap? debugBootstrap;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _initDisplayMode();
  _initErrorLogging();
  await runZonedGuarded(
    () async {
      // One system notifier, initialized here (permission request + launch-time
      // locale + cold-start tap capture) and handed to the DI layer through an
      // override so the provider consumers share the exact initialized instance.
      final notifier = SystemNotifier();
      await notifier.initialize();
      _initDebugTools();
      runApp(
        ProviderScope(
          overrides: [systemNotifierProvider.overrideWithValue(notifier)],
          child: const DshApp(),
        ),
      );
    },
    (error, stack) {
      ErrorLogCollector.instance.captureError(
        error,
        stackTrace: stack,
        level: ErrorLogLevel.fatal,
        type: 'uncaught-zone:${error.runtimeType}',
      );
      DebugTelemetry.instance?.log('uncaught-zone: $error', level: 'error');
    },
  );
}

/// Unlocks Android high-refresh-rate display mode (90Hz/120Hz) for fluid
/// touch gestures, scroll physics, and transitions.
void _initDisplayMode() {
  if (!kIsWeb &&
      Platform.isAndroid &&
      !Platform.environment.containsKey('FLUTTER_TEST')) {
    unawaited(
      FlutterDisplayMode.setHighRefreshRate().catchError((Object error) {
        ErrorLogCollector.instance.addBreadcrumb(
          'Display mode switch failed: $error',
          level: 'warning',
        );
      }),
    );
  }
}

/// Initialize in-app error log collection hooks and restore saved errors.
void _initErrorLogging() {
  ErrorLogCollector.instance.installHooks();
  ErrorLogCollector.instance.addBreadcrumb('App launch: initializing');

  if (!Platform.environment.containsKey('FLUTTER_TEST')) {
    try {
      final documents = getApplicationDocumentsDirectory();
      unawaited(
        documents
            .then((dir) async {
              await ErrorLogCollector.instance.initialize(storageDir: dir);
              ErrorLogCollector.instance.addBreadcrumb(
                'App launch: storage ready (v$kDshAppVersion+$kDshBuildNumber)',
              );
            })
            .catchError((Object error) {
              ErrorLogCollector.instance.addBreadcrumb(
                'App launch: storage init failed: $error',
                level: 'warning',
              );
            }),
      );
    } catch (e) {
      ErrorLogCollector.instance.addBreadcrumb(
        'App launch: storage setup failed: $e',
        level: 'warning',
      );
    }
  }
}

/// Wire debug telemetry on debug builds and prerelease release builds only:
/// OTLP export to the SigNoz collector, crash hooks (marker + restart
/// detection + fatal log record), and frame-rate tracking. Stable release
/// versions are compiled out entirely (zero residue). Failure here must
/// never prevent the app from starting: telemetry is best-effort by design.
void _initDebugTools() {
  // Debug builds always report; release builds report only when the release
  // pipeline enabled telemetry (`DSH_TELEMETRY_ENABLED=true` for prerelease
  // versions). Both flags are compile-time constants, so a stable release
  // folds this to `return` and the AOT compiler tree-shakes the whole
  // telemetry chain out of the binary.
  if (kReleaseMode && !kDebugTelemetryEnabled) return;
  // flutter_test runs with kDebugMode=true but no platform plugins; skip so
  // widget tests keep importing main.dart without a real documents dir.
  if (Platform.environment.containsKey('FLUTTER_TEST')) return;
  try {
    final documents = getApplicationDocumentsDirectory();
    // Fire-and-forget directory lookup; bootstrap starts once it resolves.
    unawaited(
      documents
          .then((dir) async {
            final bootstrap = await initDebugTelemetry(
              settings: const TelemetrySettings(
                endpoint: kDshDebugOtlpUrl,
                serviceName: 'dsh-android',
                serviceVersion: kDshAppVersion,
                resourceAttributes: {
                  'build.number': kDshBuildNumber,
                  'source.repo': kDshSourceRepo,
                  'source.commit': kDshSourceCommit,
                },
                metricFlushInterval: Duration(seconds: 15),
              ),
              markerDirectory: dir,
              dshBaseUrl: kDshBaseUrl,
            );
            debugBootstrap = bootstrap;
            if (bootstrap != null) {
              bootstrap.telemetry.event(
                'app.start',
                attributes: {
                  'version': kDshAppVersion,
                  'build': kDshBuildNumber,
                  'source.commit': kDshSourceCommit,
                },
              );
            }
          })
          .catchError((Object _) {
            // No documents dir (plugin missing) — disable telemetry silently.
            debugBootstrap = null;
          }),
    );
  } catch (_) {
    debugBootstrap = null;
  }
}

class DshApp extends ConsumerWidget {
  const DshApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The App-settings language choice; null while the store loads (or
    // when it is unavailable), which delegates to the device locale.
    final preference = ref.watch(appLocalePreferenceProvider).value;
    // The host-backed appearance preference for the chat-active backend;
    // system while it loads or when the host does not expose it. The
    // device-local OLED appearance, while it is on, pins dark and swaps the
    // dark theme for the pure-black one.
    final themeMode = ref.watch(appThemeModeProvider);
    final darkTheme = ref.watch(appDarkThemeProvider);
    return MaterialApp(
      // Brand title; resolves through l10n so the OS task-switcher
      // label follows the active locale (DSH Mobile stays the
      // canonical name in every locale).
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      // An explicit zh/en pins the whole app to that locale; system (or
      // an unresolved store) leaves the resolution to the device.
      locale: resolveAppLocale(preference),
      theme: DshTheme.light(),
      darkTheme: darkTheme,
      themeMode: themeMode,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: kAppSupportedLocales,
      home: const AppRoot(),
    );
  }
}
