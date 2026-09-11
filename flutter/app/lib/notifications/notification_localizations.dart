/// Device-locale resolution for notification copy.
///
/// Notification copy resolves once at startup, before any widget tree exists,
/// so it cannot ride `MaterialApp`'s locale resolution. The raw platform
/// locale may name a language the app does not ship (`fr`, `ja`), which
/// [lookupAppLocalizations] rejects with a `FlutterError`; callers clamp the
/// platform locale to [kAppSupportedLocales] through [resolveAppLocalizations]
/// instead.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart' show Locale;

/// The interface languages the app ships: the set `DshApp` hands to
/// `MaterialApp.supportedLocales` and the set [lookupAppLocalizations]
/// accepts. The generated [AppLocalizations.supportedLocales] is the same set;
/// `notification_localizations_test` fails if the two drift.
const List<Locale> kAppSupportedLocales = <Locale>[Locale('en'), Locale('zh')];

/// The [AppLocalizations] for [locale], matched on language code so a region
/// variant (`en-GB`, `zh-Hant`) resolves to its base language instead of
/// falling back. English is the fallback when [locale] names no supported
/// language.
AppLocalizations resolveAppLocalizations(Locale locale) {
  for (final supported in kAppSupportedLocales) {
    if (supported.languageCode == locale.languageCode) {
      return lookupAppLocalizations(supported);
    }
  }
  return lookupAppLocalizations(const Locale('en'));
}
