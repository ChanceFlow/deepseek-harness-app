/// Active-reminder strip — the input dock's schedule seat.
///
/// A session's durable reminders are the fold of its versioned
/// `schedule/change` stream (`packages/schedule/schedule/src/types.ts`),
/// published as [ScheduleReminder]s through `observeSchedules`. The pinned
/// `dsh web` deployment composes no `schedule` session projection — a live
/// `session/list` probe carries no `schedule` key — so this event stream is
/// the only source and a reminder created before the loaded history page
/// stays invisible until its create folds.
///
/// The reference renders the catalog as a session-header action (an alarm
/// trigger with the reminder count opening a popup). On a phone the dock
/// already owns the session's standing strips — the todo panel, the goal
/// strip, the queue dock — so the catalog ports there as one more strip,
/// beside the goal it schedules against, rather than as an app-bar popup a
/// 360dp bar has no room for.
///
/// Honesty rule: [reminders] is null while nothing has been published for
/// the session, which is not the same as "no reminders" — the strip states
/// the set is unreported rather than showing a reassuring zero.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/schedule.dart';
import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// How many reminder rows the expanded strip shows before summarizing the
/// rest. A dock strip may not grow without bound: the schedule is context
/// for the next send, not a screen of its own.
const int kScheduleStripMaxRows = 4;

/// The composer dock's reminder strip.
class ScheduleReminderStrip extends StatefulWidget {
  const ScheduleReminderStrip({required this.reminders, super.key, this.now});

  /// Active reminders, or null when the stream has published nothing for
  /// this session.
  final List<ScheduleReminder>? reminders;

  /// Test seam for the relative-time wording; null reads the wall clock.
  final DateTime? now;

  @override
  State<ScheduleReminderStrip> createState() => _ScheduleReminderStripState();
}

class _ScheduleReminderStripState extends State<ScheduleReminderStrip> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final reminders = widget.reminders;
    final now = widget.now ?? DateTime.now();
    final rows = reminders == null
        ? const <ScheduleReminder>[]
        : orderScheduleReminders(reminders, now);
    final overdueCount = rows
        .where((reminder) => scheduleReminderOverdue(reminder, now))
        .length;
    // The collapsed line answers "is anything pending, and when": the count
    // and the next target. Everything else is one tap away.
    final String summary;
    if (reminders == null) {
      summary = l10n.scheduleUnknown;
    } else if (reminders.isEmpty) {
      summary = l10n.scheduleEmpty;
    } else {
      summary = l10n.scheduleNextAt(
        formatScheduleLocalTime(rows.first.scheduledAt),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(kShapeDock),
          ),
          border: Border(
            top: BorderSide(color: scheme.outlineVariant),
            left: BorderSide(color: scheme.outlineVariant),
            right: BorderSide(color: scheme.outlineVariant),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: reminders == null || reminders.isEmpty
                  ? null
                  : () => setState(() => _expanded = !_expanded),
              child: Row(
                children: [
                  Icon(
                    Icons.alarm_outlined,
                    size: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l10n.scheduleStripTitle,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      reminders == null || reminders.isEmpty
                          ? summary
                          : '${l10n.scheduleReminderCount(reminders.length)}'
                                ' · $summary',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        height: 1.2,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (overdueCount > 0) ...[
                    Icon(Icons.schedule, size: 12, color: scheme.warning),
                    const SizedBox(width: 4),
                    Text(
                      l10n.scheduleOverdueCount(overdueCount),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.warning,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  if (reminders != null && reminders.isNotEmpty)
                    Icon(
                      _expanded ? Icons.expand_more : Icons.chevron_right,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                ],
              ),
            ),
            if (_expanded && rows.isNotEmpty) ...[
              const SizedBox(height: 2),
              for (final reminder in rows.take(kScheduleStripMaxRows))
                _ReminderRow(reminder: reminder, now: now),
              if (rows.length > kScheduleStripMaxRows)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    l10n.scheduleMoreCount(rows.length - kScheduleStripMaxRows),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One reminder: state glyph, prompt (the durable content), and the target
/// instant with its frequency.
class _ReminderRow extends StatelessWidget {
  const _ReminderRow({required this.reminder, required this.now});

  final ScheduleReminder reminder;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final overdue = scheduleReminderOverdue(reminder, now);
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Icon(
              overdue ? Icons.schedule : Icons.alarm,
              size: 12,
              color: overdue ? scheme.warning : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reminder.prompt,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    height: 1.2,
                    color: scheme.onSurface,
                  ),
                ),
                Text(
                  '${formatScheduleLocalTime(reminder.scheduledAt)}'
                  ' · ${scheduleFrequencyLabel(reminder, l10n)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    height: 1.2,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The reference `orderScheduleRecords`: overdue first, then ascending
/// target time, exact ties keeping input order. An unparseable target is not
/// overdue and sorts last among parseable targets — the durable instant is
/// opaque here, so the strip invents no verdict for it.
List<ScheduleReminder> orderScheduleReminders(
  List<ScheduleReminder> records,
  DateTime now,
) {
  final indexed = <(int, ScheduleReminder)>[
    for (var index = 0; index < records.length; index++)
      (index, records[index]),
  ];
  final nowMs = now.millisecondsSinceEpoch;
  indexed.sort((left, right) {
    final leftTarget = _scheduleTarget(left.$2);
    final rightTarget = _scheduleTarget(right.$2);
    if (leftTarget == null || rightTarget == null) {
      if (leftTarget != rightTarget) return leftTarget == null ? 1 : -1;
      return left.$1.compareTo(right.$1);
    }
    final leftOverdue = leftTarget <= nowMs;
    final rightOverdue = rightTarget <= nowMs;
    if (leftOverdue != rightOverdue) return rightOverdue ? 1 : -1;
    final byTime = leftTarget.compareTo(rightTarget);
    return byTime != 0 ? byTime : left.$1.compareTo(right.$1);
  });
  return [for (final entry in indexed) entry.$2];
}

/// Whether the reminder's next target has passed.
bool scheduleReminderOverdue(ScheduleReminder reminder, DateTime now) {
  final target = _scheduleTarget(reminder);
  if (target == null) return false;
  return target <= now.millisecondsSinceEpoch;
}

int? _scheduleTarget(ScheduleReminder reminder) =>
    DateTime.tryParse(reminder.scheduledAt)?.millisecondsSinceEpoch;

/// The target instant in the device's local zone. An unparseable target
/// renders verbatim: the durable string is the fact, and a substituted
/// instant would be an invention.
String formatScheduleLocalTime(String scheduledAt) {
  final target = DateTime.tryParse(scheduledAt);
  if (target == null) return scheduledAt;
  final local = target.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')} $hour:$minute';
}

/// The reference `formatScheduleFrequency`: a one-shot is `Once`, a
/// fixed-rate record names the largest whole unit that divides its interval
/// exactly (so the durable interval is never rounded).
String scheduleFrequencyLabel(
  ScheduleReminder reminder,
  AppLocalizations l10n,
) {
  if (reminder.kind != ScheduleReminderKind.every) {
    return l10n.scheduleFrequencyOnce;
  }
  final seconds = reminder.everySeconds;
  if (seconds == null) return l10n.scheduleFrequencyOnce;
  const units = <(int, String Function(AppLocalizations, int))>[
    (86400, _scheduleDays),
    (3600, _scheduleHours),
    (60, _scheduleMinutes),
    (1, _scheduleSeconds),
  ];
  for (final (size, label) in units) {
    if (seconds % size != 0) continue;
    final value = seconds ~/ size;
    return l10n.scheduleFrequencyEvery(value, label(l10n, value));
  }
  return l10n.scheduleFrequencyOnce;
}

String _scheduleDays(AppLocalizations l10n, int count) =>
    count == 1 ? l10n.scheduleUnitDay : l10n.scheduleUnitDays;
String _scheduleHours(AppLocalizations l10n, int count) =>
    count == 1 ? l10n.scheduleUnitHour : l10n.scheduleUnitHours;
String _scheduleMinutes(AppLocalizations l10n, int count) =>
    count == 1 ? l10n.scheduleUnitMinute : l10n.scheduleUnitMinutes;
String _scheduleSeconds(AppLocalizations l10n, int count) =>
    count == 1 ? l10n.scheduleUnitSecond : l10n.scheduleUnitSeconds;
