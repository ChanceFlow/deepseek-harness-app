/// Turn-tail file facts — the phone port of the reference deliverables fold's
/// two readers (`ui-deliverables/src/client/turn-deliverables.ts`
/// `selectProducedFiles` and `presentedForClosing`).
///
/// A finished turn closes with two independent file facts, and the reference
/// renders one row for each under the closing reply. [TurnFiles.produced] is
/// the paths the turn's successful first-party mutation calls wrote
/// ([producedMutationPath]); [TurnFiles.presented] is the files its successful
/// `present` calls declared. Produced paths keep first-seen order and appear
/// once per turn, so a file written and then edited in the same turn is one
/// entry. Presented files keep first-seen path order too, but a path declared
/// twice keeps its **last** declaration — the reference's `files.set(path,
/// file)` over the turn's declarations.
///
/// Turn membership comes from the transcript's own [TimelineTurnBoundary]
/// rows, so neither fact spills across turns. Both attach to the turn's
/// closing assistant message — the last assistant message with visible text —
/// which is the row the transcript's action row already rides under.
library;

import 'package:domain/model/chat_message.dart';
import 'package:domain/model/timeline_item.dart';

import 'produced_files.dart';
import 'timeline_grouping.dart';

/// The file facts one turn closes with.
final class TurnFiles {
  const TurnFiles({required this.produced, required this.presented});

  /// Mutation paths in first-seen order, already deduped per turn.
  final List<String> produced;

  /// Declared files in first-seen path order, each path's latest declaration.
  final List<PresentedFile> presented;
}

/// Both facts per closing assistant message id, in transcript order.
///
/// [latestTurnClosed] suppresses only the newest turn's rows while that turn
/// is still running — the reference renders them at the turn tail, after
/// `turn/end`. Every earlier turn is closed by definition and keeps its rows.
/// A closing message with neither fact publishes no entry.
Map<String, TurnFiles> turnFilesByClosingMessage(
  List<TimelineItem> items, {
  required bool latestTurnClosed,
}) {
  final groups = groupTimelineByTurn(items);
  final byMessageId = <String, TurnFiles>{};
  for (var index = 0; index < groups.length; index++) {
    final latest = index == groups.length - 1;
    if (latest && !latestTurnClosed) continue;
    final paths = <String>[];
    final seenPaths = <String>{};
    final order = <String>[];
    final byPath = <String, PresentedFile>{};
    String? closingId;
    var closingPaths = const <String>[];
    var closingPresented = const <PresentedFile>[];
    for (final item in groups[index].items) {
      if (item is TimelineToolCall) {
        final path = producedMutationPath(item);
        if (path != null && seenPaths.add(path)) paths.add(path);
        for (final file in item.presentedFiles) {
          if (!byPath.containsKey(file.path)) order.add(file.path);
          byPath[file.path] = file;
        }
      } else if (item is TimelineMessage &&
          item.value.role == MessageRole.assistant &&
          item.value.text.trim().isNotEmpty) {
        // Calls logged after the closing reply belong to no rendered body,
        // so the snapshot is taken at the reply rather than at turn end.
        closingId = item.value.id;
        closingPaths = List<String>.unmodifiable(paths);
        closingPresented = List<PresentedFile>.unmodifiable(
          order.map((path) => byPath[path]!),
        );
      }
    }
    if (closingId == null) continue;
    if (closingPaths.isEmpty && closingPresented.isEmpty) continue;
    byMessageId[closingId] = TurnFiles(
      produced: closingPaths,
      presented: closingPresented,
    );
  }
  return byMessageId;
}
