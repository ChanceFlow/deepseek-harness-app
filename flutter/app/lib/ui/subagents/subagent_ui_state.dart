/// Subagents screen UI state and intents.
///
/// Semantics mirror the web subagent catalog surface
/// (reference/deepseek-harness/packages/client/ui-subagent/src/client/):
/// `SubagentCatalogAction.tsx` (tree rows, branch expansion, diagnostic
/// rows), `SubagentReadOnlyComposer.tsx` (why an addressed child cannot
/// accept input), and `QueueDock.tsx` (`queueMutable = subagent === null`:
/// a child view renders its queue read-only).
library;

import 'package:domain/model/plan.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/subagent.dart';
import 'package:domain/model/timeline_item.dart';

/// Why the opened child's composer seat is read-only
/// (web `SubagentReadOnlyMatch.reason`).
enum SubagentReadOnlyReason {
  /// One-shot record: the task never accepts follow-ups.
  oneShot,

  /// Continuable child whose parent session is offline.
  parentUnavailable,
}

final class SubagentUiState {
  const SubagentUiState({
    this.sessions = const <SessionSummary>[],
    this.selectedParentId,
    this.catalog = const SubagentCatalog(),
    this.branchCatalogs = const <String, SubagentCatalog>{},
    this.branchFailures = const <String>{},
    this.selectedChildId,
    this.childTimeline = const <TimelineItem>[],
    this.childPlan,
    this.isChildLoading = false,
    this.isSendingChild = false,
    this.isLoading = false,
    this.errorMessage,
  });

  final List<SessionSummary> sessions;
  final String? selectedParentId;
  final SubagentCatalog catalog;

  /// Catalogs of expanded branch nodes keyed by their owning session id
  /// (web `subagentsByParent` beyond the root level).
  final Map<String, SubagentCatalog> branchCatalogs;

  /// Branch ids whose catalog load failed (web catalog `state: 'error'`).
  final Set<String> branchFailures;

  final String? selectedChildId;
  final List<TimelineItem> childTimeline;

  /// Plan projection of the opened child (the composer plan seat on the
  /// web); null while no child is open or the projection is unset/off.
  final PlanState? childPlan;

  final bool isChildLoading;
  final bool isSendingChild;
  final bool isLoading;
  final String? errorMessage;

  /// The catalog that owns the opened child's row: the root tree or the
  /// expanded branch the row was loaded from. Availability and addressing
  /// are facts of that level, not of the tree root.
  SubagentCatalog? get selectedChildCatalog {
    final id = selectedChildId;
    if (id == null) return null;
    if (catalog.entries.any((entry) => entry.id == id)) return catalog;
    for (final branch in branchCatalogs.values) {
      if (branch.entries.any((entry) => entry.id == id)) return branch;
    }
    return null;
  }

  /// The opened child's catalog entry, looked up in its owning catalog.
  SubagentEntry? get selectedChildEntry {
    final id = selectedChildId;
    if (id == null) return null;
    return selectedChildCatalog?.entries
        .where((entry) => entry.id == id)
        .firstOrNull;
  }

  /// Read-only composer reason for the opened child: one-shot records
  /// never accept input, and a continuable child needs the parent of the
  /// catalog its row lives in online (web `selectReadOnlySubagent`;
  /// mobile keeps the simple rule — only continuable + parent-available
  /// keeps the message field).
  SubagentReadOnlyReason? get childReadOnlyReason {
    final entry = selectedChildEntry;
    if (entry == null) return null;
    if (entry.mode == SubagentMode.oneShot) {
      return SubagentReadOnlyReason.oneShot;
    }
    if (selectedChildCatalog?.parentAvailable == false) {
      return SubagentReadOnlyReason.parentUnavailable;
    }
    return null;
  }

  /// Timeline rows for the child detail view: the queue rides the dock
  /// above the composer (web QueueDock placement), jobs render nothing.
  List<TimelineItem> get childTimelineRows => childTimeline
      .where((item) => item is! TimelineQueue && item is! TimelineJobs)
      .toList(growable: false);

  /// Inbox items of the opened child, rendered as read-only queue
  /// previews (`queueMutable = false`).
  List<SessionQueueItem> get childQueueItems => <SessionQueueItem>[
    for (final dock in childTimeline.whereType<TimelineQueue>()) ...dock.items,
  ];
}

sealed class SubagentAction {
  const SubagentAction();
}

final class SelectParent extends SubagentAction {
  const SelectParent(this.sessionId);

  final String sessionId;

  @override
  bool operator ==(Object other) =>
      other is SelectParent && other.sessionId == sessionId;

  @override
  int get hashCode => sessionId.hashCode;
}

final class OpenChild extends SubagentAction {
  const OpenChild(this.childSessionId, this.mode);

  final String childSessionId;

  /// The addressed row's catalog mode. `subagent.history` must request a
  /// child under its own mode — the host matches the request mode against
  /// the durable entry and answers a mismatch with `subagent-not-found`.
  final SubagentMode mode;

  @override
  bool operator ==(Object other) =>
      other is OpenChild &&
      other.childSessionId == childSessionId &&
      other.mode == mode;

  @override
  int get hashCode => Object.hash(childSessionId, mode);
}

final class SendSubagentPrompt extends SubagentAction {
  const SendSubagentPrompt(this.text);

  final String text;

  @override
  bool operator ==(Object other) =>
      other is SendSubagentPrompt && other.text == text;

  @override
  int get hashCode => text.hashCode;
}

final class InterruptSubagent extends SubagentAction {
  const InterruptSubagent(this.childSessionId);

  final String childSessionId;

  @override
  bool operator ==(Object other) =>
      other is InterruptSubagent && other.childSessionId == childSessionId;

  @override
  int get hashCode => childSessionId.hashCode;
}

/// Load (or retry) the catalog of one expanded branch node — the child
/// becomes the parent of the next tree level (web `toggleBranch` →
/// `setCatalogOpen(childSessionId, true)`).
final class LoadSubagentBranch extends SubagentAction {
  const LoadSubagentBranch(this.childSessionId);

  final String childSessionId;

  @override
  bool operator ==(Object other) =>
      other is LoadSubagentBranch && other.childSessionId == childSessionId;

  @override
  int get hashCode => childSessionId.hashCode;
}

/// Leave the child detail view and return to the catalog (the mobile
/// back affordance of the web `openChild` navigation).
final class CloseChildView extends SubagentAction {
  const CloseChildView();

  @override
  bool operator ==(Object other) => other is CloseChildView;

  @override
  int get hashCode => 'close-child-view'.hashCode;
}

final class RefreshSubagentsAction extends SubagentAction {
  const RefreshSubagentsAction();

  @override
  bool operator ==(Object other) => other is RefreshSubagentsAction;

  @override
  int get hashCode => 'refresh-subagents'.hashCode;
}

final class DismissSubagentError extends SubagentAction {
  const DismissSubagentError();

  @override
  bool operator ==(Object other) => other is DismissSubagentError;

  @override
  int get hashCode => 'dismiss-subagent-error'.hashCode;
}
