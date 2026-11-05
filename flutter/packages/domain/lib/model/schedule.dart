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
enum ScheduleKind { after, at, every, daily, weekly, cron, rrule }

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
    this.rrule,
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

  /// One DTSTART line and one RRULE line for [ScheduleKind.rrule].
  final String? rrule;

  /// Whether this rule repeats.
  bool get isRecurring => switch (kind) {
    ScheduleKind.after || ScheduleKind.at => false,
    ScheduleKind.every ||
    ScheduleKind.daily ||
    ScheduleKind.weekly ||
    ScheduleKind.cron ||
    ScheduleKind.rrule => true,
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
          other.expression == expression &&
          other.rrule == rrule);

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
    rrule,
  );
}

/// Whether a task still schedules (`ScheduleCatalogEntry.status`).
enum ScheduleStatus { active, paused, ended }

/// Values used when a target creates a Session.
final class ScheduleSessionCreateSpec {
  const ScheduleSessionCreateSpec({this.cwd, this.agentPreset});

  /// Project directory of the created Session; null uses the host default.
  final String? cwd;

  /// Agent preset of the created Session; null uses the default preset.
  final String? agentPreset;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScheduleSessionCreateSpec &&
          other.cwd == cwd &&
          other.agentPreset == agentPreset);

  @override
  int get hashCode => Object.hash(cwd, agentPreset);
}

/// Where a task's deliveries go (`ScheduleTarget`).
sealed class ScheduleTarget {
  const ScheduleTarget();

  /// Every Session named by this target, for a surface that groups tasks by
  /// Session.
  List<String> get sessionIds;
}

/// Every occurrence goes to one existing Session.
final class ScheduleSessionTarget extends ScheduleTarget {
  const ScheduleSessionTarget({required this.sessionId});

  final String sessionId;

  @override
  List<String> get sessionIds => <String>[sessionId];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScheduleSessionTarget && other.sessionId == sessionId);

  @override
  int get hashCode => sessionId.hashCode;
}

/// The first delivery creates one Session; later deliveries go to it.
final class ScheduleNewOnceTarget extends ScheduleTarget {
  const ScheduleNewOnceTarget({required this.sessionId, required this.create});

  /// Reserved at creation; the first delivery creates it.
  final String sessionId;
  final ScheduleSessionCreateSpec create;

  @override
  List<String> get sessionIds => <String>[sessionId];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScheduleNewOnceTarget &&
          other.sessionId == sessionId &&
          other.create == create);

  @override
  int get hashCode => Object.hash(sessionId, create);
}

/// Every delivery creates a fresh Session.
final class ScheduleNewTarget extends ScheduleTarget {
  const ScheduleNewTarget({required this.create});

  final ScheduleSessionCreateSpec create;

  @override
  List<String> get sessionIds => const <String>[];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScheduleNewTarget && other.create == create);

  @override
  int get hashCode => create.hashCode;
}

/// One durably acknowledged inbox delivery (`ScheduleDeliveryReceipt`).
final class ScheduleDeliveryReceipt {
  const ScheduleDeliveryReceipt({
    required this.scheduledAt,
    required this.deliveredAt,
    required this.messageId,
    this.targetSessionId,
  });

  /// Canonical UTC target of the delivered occurrence.
  final String scheduledAt;

  /// Canonical UTC time sampled after the session persistence acknowledged
  /// delivery.
  final String deliveredAt;

  final String messageId;

  /// Session that durably accepted this delivery, when the host reported it.
  final String? targetSessionId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScheduleDeliveryReceipt &&
          other.scheduledAt == scheduledAt &&
          other.deliveredAt == deliveredAt &&
          other.messageId == messageId &&
          other.targetSessionId == targetSessionId);

  @override
  int get hashCode =>
      Object.hash(scheduledAt, deliveredAt, messageId, targetSessionId);
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

/// One catalog row: the record, its delivery target, and its state
/// (`ScheduleCatalogEntry`).
final class ScheduleCatalogEntry {
  const ScheduleCatalogEntry({
    required this.record,
    required this.target,
    required this.status,
    this.involvedSessionIds = const <String>[],
    this.createdAt,
    this.updatedAt,
    this.executionActive = false,
    this.deliveryFloorEndsAt,
    this.lastDelivery,
  });

  final ScheduleRecord record;

  /// Where the next delivery goes.
  final ScheduleTarget target;

  /// Sessions told about later changes while their Agent is live.
  final List<String> involvedSessionIds;

  final ScheduleStatus status;

  /// Canonical UTC creation time, when the host stored one.
  final String? createdAt;

  /// Canonical UTC time of the latest stored change; an editor sends it back
  /// as the compare-and-update revision.
  final String? updatedAt;

  /// The latest delivery is queued or running in its reused target Session.
  final bool executionActive;

  /// End of the minimum delivery interval, while it remains in the future.
  final String? deliveryFloorEndsAt;

  /// Most recent durably acknowledged delivery, when there was one.
  final ScheduleDeliveryReceipt? lastDelivery;

  /// Every Session this row names, for search and grouping.
  List<String> get sessionIds => <String>[
    ...involvedSessionIds,
    ...target.sessionIds,
  ];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScheduleCatalogEntry &&
          other.record == record &&
          other.target == target &&
          other.status == status &&
          _listEquals(other.involvedSessionIds, involvedSessionIds) &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt &&
          other.executionActive == executionActive &&
          other.deliveryFloorEndsAt == deliveryFloorEndsAt &&
          other.lastDelivery == lastDelivery);

  @override
  int get hashCode => Object.hash(
    record,
    target,
    status,
    Object.hashAll(involvedSessionIds),
    createdAt,
    updatedAt,
    executionActive,
    deliveryFloorEndsAt,
    lastDelivery,
  );
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

/// One page of the host-wide task list (`schedule/list`).
final class ScheduleListPage {
  const ScheduleListPage({
    required this.items,
    required this.shown,
    required this.total,
    required this.limit,
    required this.offset,
  });

  final List<ScheduleCatalogEntry> items;
  final int shown;
  final int total;
  final int limit;
  final int offset;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScheduleListPage &&
          _listEquals(other.items, items) &&
          other.shown == shown &&
          other.total == total &&
          other.limit == limit &&
          other.offset == offset);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(items), shown, total, limit, offset);
}

/// Fields one atomic edit changes (`SchedulePatch`); an omitted field keeps
/// its stored value.
final class SchedulePatch {
  const SchedulePatch({
    this.title,
    this.prompt,
    this.timing,
    this.target,
    this.active,
  });

  final String? title;
  final String? prompt;
  final ScheduleTimingChange? timing;
  final ScheduleTarget? target;

  /// `false` pauses the task; `true` resumes a recurrence.
  final bool? active;

  bool get isEmpty =>
      title == null &&
      prompt == null &&
      timing == null &&
      target == null &&
      active == null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SchedulePatch &&
          other.title == title &&
          other.prompt == prompt &&
          other.timing == timing &&
          other.target == target &&
          other.active == active);

  @override
  int get hashCode => Object.hash(title, prompt, timing, target, active);
}

/// The two closed operations of `schedule/edit`.
enum ScheduleEditAction { update, delete }

/// The answer to `schedule/edit`.
sealed class ScheduleEditResult {
  const ScheduleEditResult();
}

/// The committed task after an update.
final class ScheduleEditUpdated extends ScheduleEditResult {
  const ScheduleEditUpdated({required this.entry});

  final ScheduleCatalogEntry entry;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScheduleEditUpdated && other.entry == entry);

  @override
  int get hashCode => entry.hashCode;
}

/// The task and its saved deliveries were removed.
final class ScheduleEditDeleted extends ScheduleEditResult {
  const ScheduleEditDeleted({required this.id});

  final String id;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScheduleEditDeleted && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

/// The edit changed nothing: unknown task, or a stale compare-and-update
/// revision (`schedule_not_found` | `schedule_conflict`).
final class ScheduleEditMiss extends ScheduleEditResult {
  const ScheduleEditMiss({required this.id, required this.code});

  final String id;
  final String code;

  bool get isConflict => code == 'schedule_conflict';
  bool get isMissing => code == 'schedule_not_found';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScheduleEditMiss && other.id == id && other.code == code);

  @override
  int get hashCode => Object.hash(id, code);
}

/// The answer to `schedule/view`.
sealed class ScheduleViewResult {
  const ScheduleViewResult();
}

final class ScheduleViewFound extends ScheduleViewResult {
  const ScheduleViewFound({required this.entry});

  final ScheduleCatalogEntry entry;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScheduleViewFound && other.entry == entry);

  @override
  int get hashCode => entry.hashCode;
}

final class ScheduleViewMiss extends ScheduleViewResult {
  const ScheduleViewMiss({required this.id});

  final String id;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is ScheduleViewMiss && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

/// The answer to `schedule/run`.
sealed class ScheduleRunResult {
  const ScheduleRunResult();
}

final class ScheduleRunDelivered extends ScheduleRunResult {
  const ScheduleRunDelivered({required this.entry});

  final ScheduleCatalogEntry entry;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScheduleRunDelivered && other.entry == entry);

  @override
  int get hashCode => entry.hashCode;
}

final class ScheduleRunMiss extends ScheduleRunResult {
  const ScheduleRunMiss({required this.id});

  final String id;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is ScheduleRunMiss && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

/// One execution of the task already owns its admission slot.
final class ScheduleRunPending extends ScheduleRunResult {
  const ScheduleRunPending({required this.id});

  final String id;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is ScheduleRunPending && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

/// Result of removing every ended task (`schedule/deleteInactive`).
final class ScheduleDeleteInactiveResult {
  const ScheduleDeleteInactiveResult({required this.deleted});

  final int deleted;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScheduleDeleteInactiveResult && other.deleted == deleted);

  @override
  int get hashCode => deleted.hashCode;
}

/// Effective delivery limits (`schedule/deliveryLimits`).
final class ScheduleDeliveryLimits {
  const ScheduleDeliveryLimits({required this.newSessionIntervalSeconds});

  final int newSessionIntervalSeconds;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScheduleDeliveryLimits &&
          other.newSessionIntervalSeconds == newSessionIntervalSeconds);

  @override
  int get hashCode => newSessionIntervalSeconds.hashCode;
}

/// One `schedule/create` request.
final class ScheduleCreateRequest {
  const ScheduleCreateRequest({
    required this.title,
    required this.prompt,
    required this.timing,
    this.target,
  });

  final String title;
  final String prompt;
  final ScheduleTimingChange timing;

  /// Omission creates one Session at first delivery and reuses it.
  final ScheduleTarget? target;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScheduleCreateRequest &&
          other.title == title &&
          other.prompt == prompt &&
          other.timing == timing &&
          other.target == target);

  @override
  int get hashCode => Object.hash(title, prompt, timing, target);
}

/// A timing replacement inside `schedule/update` (`ScheduleTimingChange`).
///
/// Its kind may differ from the stored record's: one edit can turn a one-shot
/// into a recurrence.
sealed class ScheduleTimingChange {
  const ScheduleTimingChange();
}

/// A one-shot delay in seconds (`after`); creation only.
final class ScheduleAfterChange extends ScheduleTimingChange {
  const ScheduleAfterChange({required this.afterSeconds});

  final int afterSeconds;
}

/// An RFC 5545 rule with an explicit DTSTART anchor and zone.
final class ScheduleRruleChange extends ScheduleTimingChange {
  const ScheduleRruleChange({required this.rrule});

  /// One normalized DTSTART line and one RRULE line.
  final String rrule;
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

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
