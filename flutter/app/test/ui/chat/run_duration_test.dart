/// Run-duration formatting parity with the reference's `formatRunDuration` /
/// `formatLiveRunDuration`
/// (`reference/deepseek-harness/packages/client/ui-chat/src/client/chat/
/// message-chrome.ts`): the settled form pads the units below the leading one,
/// the live form starts a new unit exactly at 60 and leaves its trailing unit
/// unpadded.
library;

import 'dart:ui';

import 'package:app/l10n/app_localizations.dart';
import 'package:app/ui/chat/run_duration.dart';
import 'package:flutter_test/flutter_test.dart';

final AppLocalizations _en = lookupAppLocalizations(const Locale('en'));

void main() {
  group('formatRunDuration', () {
    // Fixture: message-chrome.ts `formatRunDuration` — whole seconds, and
    // `pad2` on every unit below the leading one.
    test('settled time pads the units below the leading one', () {
      expect(formatRunDuration(45000, _en), _en.runDurationSeconds('45'));
      expect(formatRunDuration(123000, _en), _en.runDurationMinutes('2', '03'));
      expect(
        formatRunDuration(3723000, _en),
        _en.runDurationHours(1, '02', '03'),
      );
    });

    // Fixture: the reference floors `Math.floor(ms / 1000)`, so a partial
    // second is not yet a second.
    test('a partial second floors to whole seconds', () {
      expect(formatRunDuration(1999, _en), _en.runDurationSeconds('1'));
      expect(formatRunDuration(59999, _en), _en.runDurationSeconds('59'));
    });

    // Fixture: `Math.max(0, Math.floor(ms / 1000))` — a clock that went
    // backwards never reads as negative time.
    test('a negative elapsed clamps to zero', () {
      expect(formatRunDuration(-1, _en), _en.runDurationSeconds('0'));
    });
  });

  group('formatLiveRunDuration', () {
    // Fixture: message-chrome.ts `formatLiveRunDuration` — `String(totalSeconds
    // % 60)` keeps the trailing unit unpadded so a running clock never shows a
    // leading zero.
    test('live time leaves its trailing unit unpadded', () {
      expect(formatLiveRunDuration(45000, _en), _en.runDurationSeconds('45'));
      expect(
        formatLiveRunDuration(123000, _en),
        _en.runDurationMinutes('2', '3'),
      );
      expect(
        formatLiveRunDuration(3723000, _en),
        _en.runDurationHours(1, '02', '3'),
      );
    });

    // Fixture: pad2 applies to the minutes below an hour, so crossing the hour
    // does not lose the settled padding of the middle unit.
    test('live time pads the minutes under an hour', () {
      expect(
        formatLiveRunDuration(3600000, _en),
        _en.runDurationHours(1, '00', '0'),
      );
      expect(
        formatLiveRunDuration(3660000, _en),
        _en.runDurationHours(1, '01', '0'),
      );
    });

    test('a negative elapsed clamps to zero', () {
      expect(formatLiveRunDuration(-500, _en), _en.runDurationSeconds('0'));
    });
  });
}
