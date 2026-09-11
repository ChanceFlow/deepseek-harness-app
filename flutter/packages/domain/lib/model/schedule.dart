/// Durable schedule (reminder) vocabulary.
///
/// A session's versioned `schedule/change` stream is the only durable
/// schedule state (`reference/deepseek-harness/packages/schedule/schedule/
/// src/types.ts`). The `schedule` session projection carries the active
/// records; the reducer folds the change stream into the same fact.
library;

/// The v1 rule discriminator (`ScheduleRecord.kind`).
enum ScheduleReminderKind { after, at, every }

/// One active durable reminder.
///
/// [scheduledAt] is the four-digit-year RFC 3339 UTC next target; for a
/// fixed-rate reminder the host advances it. [afterSeconds] is present only
/// for [ScheduleReminderKind.after] and [everySeconds] only for
/// [ScheduleReminderKind.every].
final class ScheduleReminder {
  const ScheduleReminder({
    required this.id,
    required this.kind,
    required this.prompt,
    required this.scheduledAt,
    this.afterSeconds,
    this.everySeconds,
  });

  /// Session-local stable identity.
  final String id;

  final ScheduleReminderKind kind;

  /// Trimmed reminder content supplied at creation.
  final String prompt;

  /// Four-digit-year RFC 3339 UTC target instant.
  final String scheduledAt;

  /// Creation delay for [ScheduleReminderKind.after].
  final int? afterSeconds;

  /// Fixed interval for [ScheduleReminderKind.every].
  final int? everySeconds;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScheduleReminder &&
          other.id == id &&
          other.kind == kind &&
          other.prompt == prompt &&
          other.scheduledAt == scheduledAt &&
          other.afterSeconds == afterSeconds &&
          other.everySeconds == everySeconds);

  @override
  int get hashCode =>
      Object.hash(id, kind, prompt, scheduledAt, afterSeconds, everySeconds);
}
