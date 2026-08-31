/// Shared widget-test harness: a MaterialApp pre-wired with the app's
/// localization delegates so screens can resolve `AppLocalizations`.
///
/// Every widget test that pumps a screen (directly or through a screen
/// shell) must wrap it in [l10nApp] — the production app wires the same
/// delegates in `DshApp`; without them `AppLocalizations.of(context)!`
/// throws, which fails loudly instead of silently rendering English.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// MaterialApp carrying the app's localization delegates and locales,
/// with [home] as the pumped surface.
///
/// Pass [theme] to pump a surface under a specific [ColorScheme]: a test that
/// pumps the same widget under two themes and reads the painted color back
/// fails the moment the widget names a color instead of a role.
Widget l10nApp({required Widget home, ThemeData? theme, Locale? locale}) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    locale: locale,
    theme: theme,
    home: home,
  );
}
