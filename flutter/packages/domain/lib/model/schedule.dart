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

/// The host's reminder-rule discriminator (`ScheduleRecord.kind`).
///
/// The three [ScheduleReminderKind] values are the historical session-event
/// vocabulary; the Remote surface serves six rules.
enum ScheduleKind { after, at, every, daily, weekly, cron }

/// A durable host reminder (`ScheduleRecord`).
///
/// The wire type is a union keyed by [kind]; this carries the fields the
/// selected kind requires and leaves the others null. The decoder enforces
/// that invariant at the boundary — a record missing its kind's required
/// field fails loud — so a constructed value always describes one real rule.
final class ScheduleRecord {
  const ScheduleRecord({
    required this.id,
    required this.kind,
    required this.title,
    required this.prompt,
    required this.scheduledAt,
    this.afterSeconds,
    this.everySeconds,
    this.time,
    this.timeZone,
    this.weekdays = const <int>[],
    this.expression,
  });

  /// Globally unique task identity (`schedule-<uuid>`).
  final String id;

  final ScheduleKind kind;

  /// Stored task name: trimmed, non-empty, at most 120 characters.
  final String title;

  /// Trimmed reminder content supplied at creation.
  final String prompt;

  /// Four-digit-year RFC 3339 UTC target; a recurring rule's next occurrence.
  final String scheduledAt;

  /// Present only for [ScheduleKind.after].
  final int? afterSeconds;

  /// Present only for [ScheduleKind.every]; never below one minute.
  final int? everySeconds;

  /// Local wall-clock time (`HH:mm:ss[.SSS]`) for the wall-clock kinds.
  final String? time;

  /// Explicit IANA zone for the wall-clock kinds; absent for the
  /// instant-based ones, which store only the UTC target.
  final String? timeZone;

  /// ISO weekdays (Monday 1 … Sunday 7) for [ScheduleKind.weekly].
  final List<int> weekdays;

  /// Canonical five-field expression for [ScheduleKind.cron].
  final String? expression;

  /// Whether this rule repeats.
  bool get isRecurring => switch (kind) {
    ScheduleKind.after || ScheduleKind.at => false,
    ScheduleKind.every ||
    ScheduleKind.daily ||
    ScheduleKind.weekly ||
    ScheduleKind.cron => true,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScheduleRecord &&
          other.id == id &&
          other.kind == kind &&
          other.title == title &&
          other.prompt == prompt &&
          other.scheduledAt == scheduledAt &&
          other.afterSeconds == afterSeconds &&
          other.everySeconds == everySeconds &&
          other.time == time &&
          other.timeZone == timeZone &&
          _listEquals(other.weekdays, weekdays) &&
          other.expression == expression);

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    title,
    prompt,
    scheduledAt,
    afterSeconds,
    everySeconds,
    time,
    timeZone,
    Object.hashAll(weekdays),
    expression,
  );
}

/// Whether a reminder still schedules (`ScheduleCatalogEntry.status`).
enum ScheduleStatus { active, inactive }

/// One durably acknowledged inbox delivery (`ScheduleDeliveryReceipt`).
final class ScheduleDeliveryReceipt {
  const ScheduleDeliveryReceipt({
    required this.scheduledAt,
    required this.deliveredAt,
    required this.messageId,
  });

  /// Canonical UTC target of the delivered occurrence.
  final String scheduledAt;

  /// Canonical UTC time sampled after the session persistence acknowledged
  /// delivery.
  final String deliveredAt;

  final String messageId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScheduleDeliveryReceipt &&
          other.scheduledAt == scheduledAt &&
          other.deliveredAt == deliveredAt &&
          other.messageId == messageId);

  @override
  int get hashCode => Object.hash(scheduledAt, deliveredAt, messageId);
}

/// One saved delivery with its immutable sent prompt
/// (`ScheduleDeliveryRecord`); [prompt] is absent for legacy receipts.
final class ScheduleDeliveryRecord {
  const ScheduleDeliveryRecord({
    required this.scheduledAt,
    required this.deliveredAt,
    required this.messageId,
    this.prompt,
  });

  final String scheduledAt;
  final String deliveredAt;
  final String messageId;
  final String? prompt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScheduleDeliveryRecord &&
          other.scheduledAt == scheduledAt &&
          other.deliveredAt == deliveredAt &&
          other.messageId == messageId &&
          other.prompt == prompt);

  @override
  int get hashCode => Object.hash(scheduledAt, deliveredAt, messageId, prompt);
}

/// One catalog row: the record plus its original session binding
/// (`ScheduleCatalogEntry`).
final class ScheduleCatalogEntry {
  const ScheduleCatalogEntry({
    required this.record,
    required this.sessionId,
    required this.status,
    this.lastDelivery,
  });

  final ScheduleRecord record;

  /// The session that receives this reminder when it becomes due.
  final String sessionId;

  final ScheduleStatus status;

  /// Most recent durably acknowledged delivery, when there was one.
  final ScheduleDeliveryReceipt? lastDelivery;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScheduleCatalogEntry &&
          other.record == record &&
          other.sessionId == sessionId &&
          other.status == status &&
          other.lastDelivery == lastDelivery);

  @override
  int get hashCode => Object.hash(record, sessionId, status, lastDelivery);
}

/// The host's retention bounds for saved deliveries
/// (`DeliveryRetentionBounds`).
final class ScheduleRetentionBounds {
  const ScheduleRetentionBounds({required this.days, required this.records});

  final int days;
  final int records;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScheduleRetentionBounds &&
          other.days == days &&
          other.records == records);

  @override
  int get hashCode => Object.hash(days, records);
}

/// The answer to `schedule/history`: a page, or a non-mutating miss.
sealed class ScheduleHistoryResult {
  const ScheduleHistoryResult();
}

/// One page of saved deliveries, newest first.
final class ScheduleHistoryPage extends ScheduleHistoryResult {
  const ScheduleHistoryPage({
    required this.id,
    required this.records,
    required this.earlierRecordsUnavailable,
    required this.earlierRecordsPruned,
    required this.retention,
    this.nextBefore,
  });

  final String id;
  final List<ScheduleDeliveryRecord> records;

  /// Whether earlier records may be missing; nothing is reconstructed.
  final bool earlierRecordsUnavailable;

  /// True only after an append removed saved records.
  final bool earlierRecordsPruned;

  final ScheduleRetentionBounds retention;

  /// The oldest returned message id, present only when more remain.
  final String? nextBefore;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScheduleHistoryPage &&
          other.id == id &&
          _listEquals(other.records, records) &&
          other.earlierRecordsUnavailable == earlierRecordsUnavailable &&
          other.earlierRecordsPruned == earlierRecordsPruned &&
          other.retention == retention &&
          other.nextBefore == nextBefore);

  @override
  int get hashCode => Object.hash(
    id,
    Object.hashAll(records),
    earlierRecordsUnavailable,
    earlierRecordsPruned,
    retention,
    nextBefore,
  );
}

/// Why one task's history could not be read
/// (`schedule_not_found` | `delivery_cursor_not_found`).
final class ScheduleHistoryMiss extends ScheduleHistoryResult {
  const ScheduleHistoryMiss({required this.id, required this.code});

  final String id;
  final String code;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScheduleHistoryMiss && other.id == id && other.code == code);

  @override
  int get hashCode => Object.hash(id, code);
}

/// The answer to `schedule/delete`.
final class ScheduleDeleteResult {
  const ScheduleDeleteResult({
    required this.id,
    required this.deleted,
    this.code,
  });

  final String id;
  final bool deleted;

  /// `schedule_not_found` when the session no longer owns that task.
  final String? code;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScheduleDeleteResult &&
          other.id == id &&
          other.deleted == deleted &&
          other.code == code);

  @override
  int get hashCode => Object.hash(id, deleted, code);
}

/// A timing replacement inside `schedule/update` (`ScheduleTimingChange`).
///
/// Its kind may differ from the stored record's: one edit can turn a one-shot
/// into a recurrence.
sealed class ScheduleTimingChange {
  const ScheduleTimingChange();
}

/// An absolute one-shot target: an offset string, or a local date + time +
/// zone.
final class ScheduleAtChange extends ScheduleTimingChange {
  const ScheduleAtChange({required this.at});

  /// `YYYY-MM-DDTHH:mm:ss[.SSS](Z|±HH:MM)`, or the local record form.
  final Object at;
}

/// A fixed recurrence interval in seconds; never below one minute.
final class ScheduleEveryChange extends ScheduleTimingChange {
  const ScheduleEveryChange({required this.everySeconds});

  final int everySeconds;
}

/// A daily wall-clock time in an explicit IANA zone.
final class ScheduleDailyChange extends ScheduleTimingChange {
  const ScheduleDailyChange({required this.time, required this.timeZone});

  final String time;
  final String timeZone;
}

/// A weekly wall-clock time with ISO weekdays in an explicit IANA zone.
final class ScheduleWeeklyChange extends ScheduleTimingChange {
  const ScheduleWeeklyChange({
    required this.time,
    required this.timeZone,
    required this.weekdays,
  });

  final String time;
  final String timeZone;
  final List<int> weekdays;
}

/// A five-field cron expression in an explicit IANA zone.
final class ScheduleCronChange extends ScheduleTimingChange {
  const ScheduleCronChange({required this.expression, required this.timeZone});

  final String expression;
  final String timeZone;
}

/// The answer to `schedule/update`: the committed record, or a non-mutating
/// miss, or a tool-level refusal.
sealed class ScheduleUpdateResult {
  const ScheduleUpdateResult();
}

/// The committed record after an update.
final class ScheduleUpdateCommitted extends ScheduleUpdateResult {
  const ScheduleUpdateCommitted({required this.record});

  final ScheduleRecord record;
}

/// The update changed nothing: unknown, ended, or edited elsewhere first.
final class ScheduleUpdateMiss extends ScheduleUpdateResult {
  const ScheduleUpdateMiss({
    required this.id,
    required this.code,
    required this.message,
  });

  final String id;

  /// `schedule_not_found` | `schedule_ended` | `schedule_conflict`, or one of
  /// the tool-level codes.
  final String code;

  final String message;

  /// True when the caller's `expected` record was stale, so a re-read and a
  /// retry is the honest next step.
  bool get isConflict => code == 'schedule_conflict';

  /// True when the task no longer exists under that session.
  bool get isMissing => code == 'schedule_not_found';

  /// True when the task stopped scheduling; only a new task can replace it.
  bool get isEnded => code == 'schedule_ended';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScheduleUpdateMiss &&
          other.id == id &&
          other.code == code &&
          other.message == message);

  @override
  int get hashCode => Object.hash(id, code, message);
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
