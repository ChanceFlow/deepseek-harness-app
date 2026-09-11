/// Locale resolution for notification copy.
///
/// Regression coverage for the pre-`runApp` locale lookup: a device language
/// outside the app's shipped set (`fr`, `ja`) must resolve to English instead
/// of throwing out of `SystemNotifier.initialize`, and a region variant
/// (`en-GB`, `zh-Hant`) must resolve to its base language. The raw
/// [lookupAppLocalizations] call is kept honest here as the hazard the
/// resolver clamps.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:app/l10n/app_localizations_en.dart';
import 'package:app/l10n/app_localizations_zh.dart';
import 'package:app/notifications/notification_localizations.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the supported set matches the generated delegate set', () {
    expect(kAppSupportedLocales, AppLocalizations.supportedLocales);
  });

  test('the raw lookup throws for an unsupported language', () {
    // The failure path the resolver exists to prevent: this throw used to
    // escape SystemNotifier.initialize before runApp and strand the splash.
    expect(
      () => lookupAppLocalizations(const Locale('fr')),
      throwsFlutterError,
    );
  });

  test('a supported language resolves to its AppLocalizations instance', () {
    expect(
      resolveAppLocalizations(const Locale('en')),
      isA<AppLocalizationsEn>(),
    );
    expect(
      resolveAppLocalizations(const Locale('zh')),
      isA<AppLocalizationsZh>(),
    );
  });

  test('an unsupported language falls back to English', () {
    for (final language in ['fr', 'ja', 'es', 'de']) {
      final l10n = resolveAppLocalizations(Locale(language));
      expect(l10n, isA<AppLocalizationsEn>(), reason: language);
      expect(l10n.localeName, 'en', reason: language);
    }
  });

  test('a region variant resolves to its base language', () {
    expect(
      resolveAppLocalizations(const Locale('en', 'GB')),
      isA<AppLocalizationsEn>(),
    );
    expect(
      resolveAppLocalizations(const Locale('zh', 'Hant')),
      isA<AppLocalizationsZh>(),
    );
  });

  test('every supported locale resolves without throwing', () {
    for (final locale in kAppSupportedLocales) {
      expect(() => resolveAppLocalizations(locale), returnsNormally);
    }
  });
}
