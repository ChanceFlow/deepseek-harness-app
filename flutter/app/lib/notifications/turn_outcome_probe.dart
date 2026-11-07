/// How a session's latest turn ended, and how its reply opened.
///
/// The notification center calls a [TurnOutcomeProbe] when the session roster
/// reports a turn completion (running → idle). The probe reads the host's own
/// terminal fact instead of inferring one: a turn that ended in an error or a
/// cancellation is announced as such rather than as a new reply, and a
/// completed turn carries the first line of its answer.
///
/// The facts are domain facts only — no dsh wire type crosses this file
/// (import boundary: `app` outside `lib/di/` speaks `domain`).
library;

import 'dart:async';

import 'package:domain/model/chat_message.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:domain/repository/chat_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How the session's latest turn ended.
///
/// [stopped] is a cancellation: the user stopped the turn (or another owner
/// cancelled it). [failed] is every terminal kind that produced no finished
/// answer.
enum TurnOutcome { completed, failed, stopped }

/// What the notification path announces about the turn that just ended.
final class TurnOutcomeFacts {
  const TurnOutcomeFacts({required this.outcome, this.replyPreview});

  final TurnOutcome outcome;

  /// The reply's opening line: the newest text-bearing assistant message of
  /// the turn, first line, trimmed, at most 80 characters. Null when the turn
  /// left no assistant text.
  final String? replyPreview;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TurnOutcomeFacts &&
          other.outcome == outcome &&
          other.replyPreview == replyPreview);

  @override
  int get hashCode => Object.hash('turn-outcome', outcome, replyPreview);

  @override
  String toString() =>
      'TurnOutcomeFacts(outcome: $outcome, replyPreview: $replyPreview)';
}

/// The seam the notification center codes against.
abstract class TurnOutcomeProbe {
  /// Reads [sessionId]'s timeline once and reports how its latest turn ended.
  ///
  /// Returns null when the read yields nothing usable: the timeout elapsed
  /// before a snapshot arrived, the stream closed or failed first, or the
  /// snapshot carried no item. A caller must treat null as "no extra facts"
  /// and keep its notification (a dropped timeline read never drops the
  /// notice).
  Future<TurnOutcomeFacts?> probe(String sessionId);
}

/// Reads the outcome and reply preview from one `observeTimeline` snapshot.
///
/// The read subscribes, keeps the first list, and cancels the subscription —
/// one snapshot is all the notification path needs, and [timeout] bounds a
/// socket that never delivers, so a dead host connection can never hang a
/// notification. No network call is made beyond that subscription and no
/// decoder is touched; the facts come from the domain items the adapter
/// already publishes.
final class RepositoryTurnOutcomeProbe implements TurnOutcomeProbe {
  RepositoryTurnOutcomeProbe(
    this._repository, {
    this._timeout = const Duration(seconds: 3),
  });

  final ChatRepository _repository;
  final Duration _timeout;

  @override
  Future<TurnOutcomeFacts?> probe(String sessionId) async {
    final completer = Completer<List<TimelineItem>?>();
    StreamSubscription<List<TimelineItem>>? subscription;
    try {
      subscription = _repository
          .observeTimeline(sessionId)
          .listen(
            (items) {
              if (!completer.isCompleted) completer.complete(items);
            },
            onError: (Object _) {
              if (!completer.isCompleted) completer.complete(null);
            },
            onDone: () {
              if (!completer.isCompleted) completer.complete(null);
            },
          );
      final items = await completer.future.timeout(
        _timeout,
        onTimeout: () => null,
      );
      if (items == null || items.isEmpty) return null;
      return TurnOutcomeFacts(
        outcome: _outcomeOf(items),
        replyPreview: _replyPreviewOf(items),
      );
    } finally {
      await subscription?.cancel();
    }
  }

  /// Derives the outcome from the latest closed [TimelineTurnBoundary].
  ///
  /// The wire's `turn/end` reason is `{ turn, reason: { kind, … } }`
  /// (`reference/deepseek-harness/packages/core/session/src/types.ts`,
  /// `TurnEndReasonMap`), whose kinds are `completed`, `aborted`, `blocked`,
  /// `error`, `max-tokens`, `interrupted` and `forked`. The adapter keeps that
  /// outer kind on [TimelineTurnBoundary.endReason].
  ///
  /// `aborted` is the reference's cancellation reason — "a cancellation
  /// request interrupted the live turn" — and the only kind the wire models
  /// as a stop, so it maps to [TurnOutcome.stopped]. **Gap:** the adapter does
  /// not carry the nested `aborted.reason.kind` (`user` / `parent` / `hook` /
  /// `disposed` / `legacy`), so a parent, hook or disposal cancellation is
  /// indistinguishable here from the user pressing stop. Every other
  /// non-`completed` kind ends the turn without a finished answer and maps to
  /// [TurnOutcome.failed].
  ///
  /// A boundary whose `turn/end` has not folded (endReason null) leaves no
  /// terminal fact in the snapshot; the roster transition that triggered the
  /// probe is the completion signal, so [TurnOutcome.completed] is the
  /// fallback. A future wire kind the pinned adapter has not taught us also
  /// ends the turn without a clean completion, so it falls through to
  /// [TurnOutcome.failed] rather than a misleading "new reply".
  static TurnOutcome _outcomeOf(List<TimelineItem> items) {
    String? endReason;
    for (final item in items) {
      if (item is TimelineTurnBoundary && item.endReason != null) {
        endReason = item.endReason;
      }
    }
    switch (endReason) {
      case null:
      case 'completed':
        return TurnOutcome.completed;
      case 'aborted':
        return TurnOutcome.stopped;
      case 'error':
      case 'max-tokens':
      case 'interrupted':
      case 'blocked':
      case 'forked':
        return TurnOutcome.failed;
      default:
        return TurnOutcome.failed;
    }
  }

  /// The newest text-bearing assistant message of the turn that just ended.
  ///
  /// Scoped to the latest [TimelineTurnBoundary] so a failed turn that
  /// produced no assistant text reports no preview instead of borrowing the
  /// previous turn's reply; a snapshot without a boundary (a hand-built list,
  /// or a window cut that removed `turn/start`) reads the whole list. Like the
  /// host's own turn-outline fold
  /// (`session-turn-outline/src/projection.ts`, "newest text-bearing message
  /// wins"), a later blank assistant row does not hide an earlier answer.
  static String? _replyPreviewOf(List<TimelineItem> items) {
    var start = 0;
    for (var i = items.length - 1; i >= 0; i--) {
      if (items[i] is TimelineTurnBoundary) {
        start = i;
        break;
      }
    }
    for (var i = items.length - 1; i >= start; i--) {
      final item = items[i];
      if (item is! TimelineMessage) continue;
      if (item.value.role != MessageRole.assistant) continue;
      final preview = _firstLine(item.value.text);
      if (preview != null) return preview;
    }
    return null;
  }

  /// A markdown fence opener or closer: three or more backticks or tildes,
  /// optionally followed by an info string (the language tag).
  static final RegExp _fenceLine = RegExp(r'^(?:`{3,}|~{3,})');

  /// First line of [text], trimmed, at most [_previewLimit] characters.
  ///
  /// Leading and trailing whitespace lines are dropped by the trim, and a
  /// trivial enclosing code fence is stripped, so a reply that is one fenced
  /// block previews its first code line rather than the backticks. Null when
  /// every remaining line is blank or a fence.
  static String? _firstLine(String text) {
    final lines = text.trim().split('\n');
    var last = lines.length - 1;
    if (last > 0 && _fenceLine.hasMatch(lines[0].trim())) {
      // A closing fence in the final line closes the block the opener began.
      if (_fenceLine.hasMatch(lines[last].trim())) last--;
    }
    for (var i = 0; i <= last; i++) {
      final line = lines[i].trim();
      if (line.isEmpty || _fenceLine.hasMatch(line)) continue;
      return _clip(line);
    }
    return null;
  }

  static const int _previewLimit = 80;

  /// Caps [line] at [_previewLimit] characters, marking the cut with an
  /// ellipsis and never splitting a surrogate pair.
  static String _clip(String line) {
    if (line.length <= _previewLimit) return line;
    var end = _previewLimit - 1;
    final lastUnit = line.codeUnitAt(end - 1);
    if (lastUnit >= 0xD800 && lastUnit <= 0xDBFF) end--;
    return '${line.substring(0, end).trimRight()}…';
  }
}

/// Per-backend probe seam.
///
/// The default is null: a headless test or the WebView-only shell must not
/// open a timeline socket just by reading the provider. The assembly wiring
/// (`lib/di/providers.dart`) overrides it with a [RepositoryTurnOutcomeProbe]
/// once the notification center consumes the facts.
final turnOutcomeProbeProvider = Provider.family<TurnOutcomeProbe?, String>(
  (ref, backendId) => null,
);
