/// The transcript's Turn-level process disclosure.
///
/// Port of the reference's `turn-process` projection and control
/// (`reference/deepseek-harness/packages/client/ui-chat/src/client/
/// conversation-nodes/turn-process.ts` plus `chat/TurnProcessNodeView.tsx`):
/// one control per Turn owns everything the agent did before its finalized
/// answer, and reports what the Turn is doing or how long it took.
///
/// Departure from the reference, forced by this client's flat item list: the
/// reference learns per-Step answers and interleaved input from its Node
/// locations, while a [TimelineItem] carries only its own seq. The answer is
/// therefore read as the Turn's last reply-bearing assistant message with no
/// tool call after it, which is the same fact for every transcript this client
/// renders and keeps the Fold's order untouched.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/chat_message.dart';
import 'package:domain/model/timeline_item.dart';

import 'run_duration.dart';
import 'timeline_folding.dart';

/// The reference's `TurnProcessSpec`, reduced to the facts this client's
/// control renders and folds on.
final class TurnProcessFacts {
  const TurnProcessFacts({
    required this.turn,
    required this.closed,
    this.endReason,
    this.startedAtEpochMs,
    this.endedAtEpochMs,
    this.answerSeq,
    this.hasInterleavedInput = false,
  });

  final int turn;

  /// Whether the Turn's `turn/end` folded: a closed Turn may fold its process.
  final bool closed;

  /// The `turn/end` reason kind; null while the Turn is open.
  final String? endReason;

  final int? startedAtEpochMs;
  final int? endedAtEpochMs;

  /// The finalized answer's seq; null when the Turn ended without one.
  final int? answerSeq;

  /// Whether a human message landed inside the Turn after its opening one.
  final bool hasInterleavedInput;

  /// Whether the Turn refuses to fold: it is still running, it was stopped or
  /// failed, or a human spoke inside it (the reference's
  /// `turnProcessAlwaysOpen` plus its `hasInterleavedInput` rule).
  bool get alwaysOpen =>
      !closed ||
      endReason == 'aborted' ||
      endReason == 'error' ||
      hasInterleavedInput;
}

/// One row a Turn's process section owns, and whether collapsing may hide it.
final class TurnProcessMember {
  const TurnProcessMember(this.row, {required this.folds});

  final Object row;

  /// Whether the Turn control's collapse hides this row.
  final bool folds;
}

/// One Turn's rows, in transcript order, under the Turn's own control.
///
/// The order is the transcript's: the control replaces the `turn/start`
/// boundary that opened the Turn, and everything the Turn logged follows it
/// where it was logged. Collapsing drops the rows marked [TurnProcessMember.folds]
/// and keeps the rest, so the reader's own words and the answer never move.
final class TurnProcessSection {
  const TurnProcessSection({required this.facts, required this.members});

  final TurnProcessFacts facts;

  final List<TurnProcessMember> members;

  /// Whether the control starts open.
  bool get defaultOpen => facts.alwaysOpen;

  /// Whether the Turn has work to fold. The reference's `hasContent`: a Turn
  /// with nothing behind the control stays open, because a chevron that
  /// reveals an empty body is a lie. A human interrupting the Turn is handled
  /// by [TurnProcessFacts.alwaysOpen] instead.
  bool get hasContent => members.any((member) => member.folds);
}

/// Whether one folded row is process work the Turn control owns.
///
/// The reference's `INDEPENDENT` set keeps `user`, `steering`, `turn-trigger`,
/// `model-retry`, `turn-error`, `turn-max-tokens`, and `turn-tail` out of the
/// process range. This client adds the two interactive cards: the reference
/// renders approvals and questions through a slot outside the transcript, so
/// they can never be folded away there, while here they are transcript rows
/// and hiding a blocking prompt behind a disclosure would lose the reader's
/// only way to answer it.
bool isFoldableProcessRow(Object row) => switch (row) {
  // A phase card is process like its members are: the reference's
  // `processMember` admits every visible node in the Turn's range, the group
  // seat included, so a collapsed Turn hides the whole card rather than the
  // card surviving its own owner's fold.
  TimelineActivityGroup() => true,
  TimelineToolCall() => true,
  TimelineContextInjection() => true,
  TimelineMessage(:final value) => value.role == MessageRole.assistant,
  // The reference groups a slash-command card and a compaction marker as
  // process. This client keeps both outside the fold: they are the transcript's
  // only surface for "a command ran" and "context was compacted", so a
  // collapsed Turn would not hide work, it would hide the record of it.
  TimelineCommand() => false,
  TimelineCompaction() => false,
  TimelineTurnBoundary() => false,
  TimelineError() => false,
  TimelineQueue() => false,
  TimelineJobs() => false,
  TimelineHookAudit() => false,
  TimelineWorkflowRun() => false,
  TimelineQuestionRequest() => false,
  TimelineApprovalRequest() => false,
  // A row kind this fold does not know stays visible: a disclosure may hide
  // work it can name, never a fact it cannot.
  _ => false,
};

/// Split a folded timeline into one [TurnProcessSection] per Turn.
///
/// Rows outside any Turn (the pre-turn prefix and any trailing row the fold
/// could not place) pass through untouched.
List<Object> foldTurnProcesses(List<Object> rows) {
  final out = <Object>[];
  var section = <Object>[];
  var turnStart = <TimelineItem>[];

  void flush() {
    if (section.isNotEmpty) {
      out.add(_sectionFor(turnStart, section));
      section = <Object>[];
      turnStart = <TimelineItem>[];
    }
  }

  for (final row in rows) {
    if (row is TimelineTurnBoundary) {
      flush();
      turnStart = <TimelineItem>[row];
      section = <Object>[];
      continue;
    }
    if (turnStart.isEmpty) {
      out.add(row);
      continue;
    }
    section.add(row);
  }
  flush();
  return out;
}

TurnProcessSection _sectionFor(
  List<TimelineItem> boundaries,
  List<Object> rows,
) {
  final boundary = boundaries.first as TimelineTurnBoundary;
  // A phase card hides its members behind its own fold, but the members are
  // still this Turn's log: the answer is decided over the expanded order, or a
  // call inside a card would look like it never ran.
  final items = <TimelineItem>[boundary];
  for (final row in rows) {
    switch (row) {
      case TimelineItem():
        items.add(row);
      case TimelineActivityGroup(:final entries):
        items.addAll(entries);
      default:
        break;
    }
  }
  final facts = turnProcessFacts(boundary, items);
  final members = <TurnProcessMember>[];
  // The finalized answer is not process. The reference's `processMember` wants
  // `anchorSeq < answerAnchorSeq`, so the reply the Turn produced stays visible
  // while everything that led to it folds; the answer's own reasoning, which
  // the phase split off as a row of its own, is process like any other thought.
  var passedAnswer = false;
  for (final row in rows) {
    if (!passedAnswer &&
        facts.answerSeq != null &&
        row is TimelineMessage &&
        row.value.seq == facts.answerSeq &&
        row.value.text.trim().isNotEmpty) {
      passedAnswer = true;
    }
    members.add(
      TurnProcessMember(row, folds: !passedAnswer && isFoldableProcessRow(row)),
    );
  }
  return TurnProcessSection(
    facts: facts,
    members: List<TurnProcessMember>.unmodifiable(members),
  );
}

/// Derive one Turn's process facts from its boundary and its own items.
TurnProcessFacts turnProcessFacts(
  TimelineTurnBoundary boundary,
  List<TimelineItem> items,
) {
  final closed = boundary.endSeq != null;
  // The opening human message is not interleaved input; anything the reader
  // said after it is.
  var sawOpeningHuman = false;
  var interleaved = false;
  for (final item in items) {
    if (item is TimelineTurnBoundary) continue;
    if (item is TimelineMessage && item.value.role == MessageRole.user) {
      if (sawOpeningHuman) {
        interleaved = true;
        break;
      }
      sawOpeningHuman = true;
    }
  }

  // The finalized answer (the reference's `latestAnswer`): the Turn's last
  // reply-bearing assistant message, and only when nothing ran after it. The
  // scan therefore stops at the first of the two — a call logged after the
  // candidate reply is work the model started on top of it, which is exactly
  // the case where the Turn has no answer to keep out of the fold.
  TimelineMessage? answer;
  for (var index = items.length - 1; index >= 0; index--) {
    final item = items[index];
    if (item is TimelineToolCall) break;
    if (item is TimelineMessage &&
        item.value.role == MessageRole.assistant &&
        item.value.text.trim().isNotEmpty) {
      answer = item;
      break;
    }
  }

  return TurnProcessFacts(
    turn: boundary.turn,
    closed: closed,
    endReason: boundary.endReason,
    startedAtEpochMs: boundary.startedAtEpochMs,
    endedAtEpochMs: boundary.endedAtEpochMs,
    answerSeq: answer?.value.seq,
    hasInterleavedInput: interleaved,
  );
}

/// The Turn control's settled label: the localized leading copy, and the
/// duration parts that follow it for a Turn that ended on its own.
final class TurnProcessLabel {
  const TurnProcessLabel(this.prefix, this.duration);

  /// The localized leading copy (`Completed in `, `Stopped`, `Failed`).
  final String prefix;

  /// The elapsed duration's parts; empty when the Turn's clock is unknown, so
  /// the label reads as its prefix alone (`Completed`).
  final List<RunDurationPart> duration;
}

/// The Turn control's label, or null while the Turn is open.
///
/// The reference renders no control label until `turn/end` folds
/// (`chat/TurnProcessNodeView.tsx` returns null while the Turn's status is not
/// `closed`); the running row is the live status. A stopped or failed Turn
/// replaces its duration with the reason, and a Turn whose start or end time
/// never arrived keeps the bare `Completed`.
TurnProcessLabel? turnProcessLabel(
  TurnProcessFacts facts,
  AppLocalizations l10n,
) {
  if (!facts.closed) return null;
  return switch (facts.endReason) {
    'aborted' => TurnProcessLabel(
      l10n.turnProcessStopped,
      const <RunDurationPart>[],
    ),
    'error' => TurnProcessLabel(
      l10n.turnProcessFailed,
      const <RunDurationPart>[],
    ),
    _ => _settledLabel(facts, l10n),
  };
}

TurnProcessLabel _settledLabel(TurnProcessFacts facts, AppLocalizations l10n) {
  final elapsed = _elapsedMs(facts);
  if (elapsed == null) {
    return TurnProcessLabel(l10n.turnProcessWorked, const <RunDurationPart>[]);
  }
  return TurnProcessLabel(
    l10n.turnProcessTook,
    runDurationParts(elapsed, l10n),
  );
}

/// The Turn's elapsed time: the reference's `Math.max(1000, end - start)` over
/// the Turn's own timestamps, or null when either never arrived.
int? _elapsedMs(TurnProcessFacts facts) {
  final start = facts.startedAtEpochMs;
  final end = facts.endedAtEpochMs;
  if (start == null || end == null) return null;
  final elapsed = end - start;
  return elapsed < 1000 ? 1000 : elapsed;
}
