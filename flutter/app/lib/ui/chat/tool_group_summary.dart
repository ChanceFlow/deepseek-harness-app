/// Semantic tool-call aggregation model for timeline action chips.
///
/// Groups a batch of consecutive tool calls into clean, human-readable
/// activity summaries (e.g. "Explored 3 files, 2 searches", "Ran 3 commands")
/// matching Cursor Composer / Windsurf Cascade timeline design.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/timeline_item.dart';

import 'tool_row_model.dart';

/// Semantic summary representation of a grouped set of tool calls.
final class ToolGroupSummary {
  const ToolGroupSummary({
    required this.title,
    required this.subtitle,
    required this.semanticTitle,
    required this.toolBreakdown,
    required this.filesExplored,
    required this.searches,
    required this.modifications,
    required this.commands,
    required this.totalCalls,
    required this.runningCalls,
    required this.failedCalls,
    this.activeAction,
  });

  /// Primary label displayed on the action chip.
  final String title;

  /// Secondary detail (e.g. active action while running, or breakdown when expanded).
  final String subtitle;

  /// High-level semantic summary (e.g. "Explored 3 files, 2 searches").
  final String semanticTitle;

  /// Granular per-tool breakdown (e.g. "bash 1 · edit 1 · read 1").
  final String toolBreakdown;

  /// Number of files explored or inspected.
  final int filesExplored;

  /// Number of search operations.
  final int searches;

  /// Number of file modifications (creates/edits).
  final int modifications;

  /// Number of shell commands executed.
  final int commands;

  /// Total count of tool calls in this group.
  final int totalCalls;

  /// Count of currently running tool calls.
  final int runningCalls;

  /// Count of failed tool calls.
  final int failedCalls;

  /// Active action description for in-flight execution.
  final String? activeAction;

  /// Whether any tool call in this group is currently in progress.
  bool get isRunning => runningCalls > 0;

  /// Whether any tool call in this group encountered an error.
  bool get hasFailed => failedCalls > 0;
}

/// Computes a semantic [ToolGroupSummary] from a list of [calls] and localized strings.
ToolGroupSummary deriveToolGroupSummary(
  List<TimelineToolCall> calls,
  AppLocalizations l10n,
) {
  final isZh = l10n.localeName.startsWith('zh');

  var failed = 0;
  var running = 0;
  var filesExplored = 0;
  var searches = 0;
  var modifications = 0;
  var commands = 0;

  final countByName = <String, int>{};

  for (final call in calls) {
    countByName[call.name] = (countByName[call.name] ?? 0) + 1;
    if (call.status == ToolRunStatus.failed) failed++;
    if (call.status == ToolRunStatus.running) running++;

    final variant = classifyTool(call.name);
    switch (variant) {
      case ToolRowVariant.read:
        filesExplored++;
      case ToolRowVariant.search:
        searches++;
      case ToolRowVariant.write:
      case ToolRowVariant.edit:
        modifications++;
      case ToolRowVariant.bash:
        commands++;
      case ToolRowVariant.code:
      case ToolRowVariant.others:
        // Other tools participate in breakdown and total count.
        break;
    }
  }

  // Sorted per-tool breakdown (e.g. "bash 1 · edit 1 · read 1").
  final names = countByName.keys.toList()..sort();
  final toolBreakdown = names
      .map((name) => '$name ${countByName[name]}')
      .join(' · ');

  // Compute settled semantic title.
  final String semanticTitle;
  if (filesExplored > 0 &&
      searches > 0 &&
      modifications == 0 &&
      commands == 0) {
    semanticTitle = l10n.exploredFilesAndSearches(filesExplored, searches);
  } else if (filesExplored > 0 &&
      searches == 0 &&
      modifications == 0 &&
      commands == 0) {
    semanticTitle = l10n.exploredFiles(filesExplored);
  } else if (searches > 0 &&
      filesExplored == 0 &&
      modifications == 0 &&
      commands == 0) {
    semanticTitle = l10n.searchedCount(searches);
  } else if (modifications > 0 &&
      filesExplored == 0 &&
      searches == 0 &&
      commands == 0) {
    semanticTitle = l10n.modifiedFiles(modifications);
  } else if (commands > 0 &&
      filesExplored == 0 &&
      searches == 0 &&
      modifications == 0) {
    semanticTitle = l10n.ranCommands(commands);
  } else {
    // Mixed category: build composite of active categories.
    final parts = <String>[];
    if (filesExplored > 0) parts.add(l10n.exploredFiles(filesExplored));
    if (searches > 0) parts.add(l10n.searchedCount(searches));
    if (modifications > 0) parts.add(l10n.modifiedFiles(modifications));
    if (commands > 0) parts.add(l10n.ranCommands(commands));

    if (parts.length == 2) {
      semanticTitle = isZh ? parts.join('，') : parts.join(', ');
    } else {
      semanticTitle = l10n.toolGroupOperations(calls.length);
    }
  }

  // Compute in-flight running information.
  final runningCall = calls
      .where((c) => c.status == ToolRunStatus.running)
      .firstOrNull;

  String? activeAction;
  String title;
  String subtitle;

  if (runningCall != null) {
    final runningModel = deriveToolRowModel(runningCall, l10n);
    final actionVerb = switch (runningCall.name) {
      'read' => isZh ? '正在读取' : 'Reading',
      'write' => isZh ? '正在写入' : 'Writing',
      'edit' => isZh ? '正在编辑' : 'Editing',
      'bash' => isZh ? '正在运行 bash' : 'Running bash',
      'pwsh' => isZh ? '正在运行 pwsh' : 'Running pwsh',
      'grep' || 'glob' => isZh ? '正在搜索' : 'Searching',
      _ =>
        isZh ? '正在执行 ${runningModel.title}' : 'Running ${runningModel.title}',
    };
    final target = runningModel.summary.isNotEmpty
        ? runningModel.summary
        : runningModel.title;
    activeAction = '$actionVerb: $target';

    title = calls.length > 1
        ? l10n.toolWorkingSteps(calls.length)
        : (isZh ? '执行中' : 'Working');
    subtitle = activeAction;
  } else {
    title = semanticTitle;
    subtitle = toolBreakdown.isNotEmpty
        ? toolBreakdown
        : (isZh ? '完成' : 'Done');
  }

  return ToolGroupSummary(
    title: title,
    subtitle: subtitle,
    semanticTitle: semanticTitle,
    toolBreakdown: toolBreakdown,
    filesExplored: filesExplored,
    searches: searches,
    modifications: modifications,
    commands: commands,
    totalCalls: calls.length,
    runningCalls: running,
    failedCalls: failed,
    activeAction: activeAction,
  );
}
