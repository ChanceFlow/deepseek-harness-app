/// Run-duration part tests, matching the reference's `formatRunDuration`
/// (`reference/deepseek-harness/packages/client/ui-chat/src/client/chat/
/// message-chrome.ts`): whole seconds from a floored, non-negative elapsed,
/// hours once the total reaches 60 minutes, minutes once it reaches 60
/// seconds, seconds always, and no zero padding.
library;

import 'dart:ui';

import 'package:app/l10n/app_localizations.dart';
import 'package:app/ui/chat/run_duration.dart';
import 'package:flutter_test/flutter_test.dart';

final AppLocalizations _en = lookupAppLocalizations(const Locale('en'));
final AppLocalizations _zh = lookupAppLocalizations(const Locale('zh'));

/// The parts as one rendered string, the way a label joins them.
String _text(List<RunDurationPart> parts) =>
    parts.map((part) => part.text).join();

void main() {
  group('runDurationParts', () {
    test('a sub-minute run is seconds alone', () {
      expect(_text(runDurationParts(45000, _en)), '45s');
      expect(runDurationParts(45000, _en), <RunDurationPart>[
        const RunDurationPart('45', numeric: true),
        const RunDurationPart('s', numeric: false),
      ]);
    });

    // Fixture: message-chrome.ts pushes the minute part when `total >= 60`,
    // never zero-padding the seconds under it.
    test('minutes start at 60 seconds without padding', () {
      expect(_text(runDurationParts(60000, _en)), '1m 0s');
      expect(_text(runDurationParts(123000, _en)), '2m 3s');
      expect(_text(runDurationParts(59999, _en)), '59s');
    });

    // Fixture: hours start at 60 minutes, and the minutes under them stay
    // unpadded too.
    test('hours start at 60 minutes without padding', () {
      expect(_text(runDurationParts(3600000, _en)), '1h 0m 0s');
      expect(_text(runDurationParts(3723000, _en)), '1h 2m 3s');
      expect(_text(runDurationParts(3903000, _en)), '1h 5m 3s');
    });

    test('every numeral is marked numeric and every unit is not', () {
      expect(runDurationParts(3903000, _en), <RunDurationPart>[
        const RunDurationPart('1', numeric: true),
        const RunDurationPart('h ', numeric: false),
        const RunDurationPart('5', numeric: true),
        const RunDurationPart('m ', numeric: false),
        const RunDurationPart('3', numeric: true),
        const RunDurationPart('s', numeric: false),
      ]);
    });

    // Fixture: `Math.floor(ms / 1000)` — a partial second is not yet a second.
    test('a partial second floors to whole seconds', () {
      expect(_text(runDurationParts(1999, _en)), '1s');
      expect(_text(runDurationParts(999, _en)), '0s');
    });

    // Fixture: `Math.max(0, …)` — a clock that went backwards never reads as
    // negative time.
    test('a negative elapsed clamps to zero', () {
      expect(_text(runDurationParts(-1, _en)), '0s');
      expect(_text(runDurationParts(-500000, _en)), '0s');
    });

    test('the units come from the locale, the numerals never do', () {
      expect(_text(runDurationParts(3903000, _zh)), '1小时5分3秒');
      expect(
        runDurationParts(
          3903000,
          _zh,
        ).where((part) => part.numeric).map((part) => part.text),
        <String>['1', '5', '3'],
      );
    });
  });
}
