/// Turn-run duration parts for the process disclosure and the running row.
///
/// Port of the reference's `formatRunDuration`
/// (`reference/deepseek-harness/packages/client/ui-chat/src/client/chat/message-chrome.ts`):
/// whole seconds from a floored, non-negative elapsed; hours once the total
/// reaches 60 minutes; minutes once it reaches 60 seconds; seconds always; and
/// no zero padding anywhere. Each part carries whether its text is a numeral,
/// so the caller can set the code family and tabular figures on numbers only
/// while the localized unit stays in the label's own type.
library;

import 'package:app/l10n/app_localizations.dart';

/// One rendered piece of a run duration: [text] as it appears, and whether it
/// is a numeral.
final class RunDurationPart {
  const RunDurationPart(this.text, {required this.numeric});

  final String text;

  /// Whether [text] is a numeral, which the caller renders in the code family
  /// with tabular figures.
  final bool numeric;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RunDurationPart &&
          other.text == text &&
          other.numeric == numeric);

  @override
  int get hashCode => Object.hash(text, numeric);

  @override
  String toString() => 'RunDurationPart($text, numeric: $numeric)';
}

/// The elapsed time as localized parts, in display order.
///
/// A negative elapsed clamps to zero and a partial second floors, so the parts
/// never read as negative time or as a second that has not passed.
List<RunDurationPart> runDurationParts(int ms, AppLocalizations l10n) {
  final total = ms < 0 ? 0 : ms ~/ 1000;
  final hours = total ~/ 3600;
  final minutes = (total ~/ 60) % 60;
  final seconds = total % 60;
  return <RunDurationPart>[
    if (hours > 0) ...<RunDurationPart>[
      RunDurationPart(hours.toString(), numeric: true),
      RunDurationPart(l10n.runDurationHourUnit, numeric: false),
    ],
    if (total >= 60) ...<RunDurationPart>[
      RunDurationPart(minutes.toString(), numeric: true),
      RunDurationPart(l10n.runDurationMinuteUnit, numeric: false),
    ],
    RunDurationPart(seconds.toString(), numeric: true),
    RunDurationPart(l10n.runDurationSecondUnit, numeric: false),
  ];
}
