/// Turn-run duration formatting for the process disclosure.
///
/// Port of the reference's `formatRunDuration` / `formatLiveRunDuration`
/// (`reference/deepseek-harness/packages/client/ui-chat/src/client/chat/
/// message-chrome.ts`): the settled form zero-pads the units below the leading
/// one, the live form starts a new unit exactly at 60 and leaves the trailing
/// unit unpadded, so a running clock never shows a leading zero.
library;

import 'package:app/l10n/app_localizations.dart';

String _pad2(int value) => value.toString().padLeft(2, '0');

/// Settled elapsed time: `45s`, `2m 03s`, `1h 05m 03s`.
String formatRunDuration(int ms, AppLocalizations l10n) {
  final total = ms < 0 ? 0 : ms ~/ 1000;
  final hours = total ~/ 3600;
  final minutes = (total ~/ 60) % 60;
  final seconds = total % 60;
  if (hours > 0) {
    return l10n.runDurationHours(hours, _pad2(minutes), _pad2(seconds));
  }
  return minutes > 0
      ? l10n.runDurationMinutes(minutes.toString(), _pad2(seconds))
      : l10n.runDurationSeconds(seconds.toString());
}

/// Live elapsed time: whole seconds without a leading zero, minutes from 60
/// seconds, hours from exactly 60 minutes.
String formatLiveRunDuration(int ms, AppLocalizations l10n) {
  final total = ms < 0 ? 0 : ms ~/ 1000;
  final hours = total ~/ 3600;
  final minutes = (total ~/ 60) % 60;
  final seconds = total % 60;
  if (hours > 0) {
    return l10n.runDurationHours(hours, _pad2(minutes), seconds.toString());
  }
  return minutes > 0
      ? l10n.runDurationMinutes(minutes.toString(), seconds.toString())
      : l10n.runDurationSeconds(seconds.toString());
}
