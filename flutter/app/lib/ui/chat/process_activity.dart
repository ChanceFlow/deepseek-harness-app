/// Work categories and live detail for the transcript's process disclosure.
///
/// Port of the reference chat grouping's own module
/// (`reference/deepseek-harness/packages/client/ui-chat/src/client/
/// conversation-nodes/process-activity.ts`): a process group ranks its work by
/// category, and while it runs it names the one thing happening now.
///
/// Two reference facts are reproduced exactly rather than approximated:
/// the category table's order and membership, and the live-detail rule (its
/// argument-key priority, whitespace collapse, and 160-**grapheme** cap).
library;

import 'dart:convert';

import 'package:app/l10n/app_localizations.dart';
import 'package:characters/characters.dart';
import 'package:domain/model/timeline_item.dart';

/// One category of work a process group can report.
///
/// [thinking] is not a tool category: it is what a group with no tool call
/// shows, so it participates in labels but never in the ranked counts.
enum ProcessActivity {
  thinking,
  read,
  readImage,
  search,
  write,
  edit,
  commands,
  code,
  webSearch,
  webFetch,
  subagents,
  plan,
  questions,
  tools,
}

/// The reference's tool-name table, in its own probe order.
ProcessActivity processActivityOf(String name) {
  if (name == 'read') return ProcessActivity.read;
  if (name == 'read_image') return ProcessActivity.readImage;
  if (name == 'grep' || name == 'glob' || name.endsWith('_inspect')) {
    return ProcessActivity.search;
  }
  if (name == 'write') return ProcessActivity.write;
  if (name == 'edit' || name == 'apply_patch') return ProcessActivity.edit;
  if (const <String>{
        'bash',
        'pwsh',
        'exec_command',
        'write_stdin',
      }.contains(name) ||
      name.startsWith('terminal_')) {
    return ProcessActivity.commands;
  }
  if (name == 'run_code') return ProcessActivity.code;
  if (name == 'web_search') return ProcessActivity.webSearch;
  if (name == 'web_fetch') return ProcessActivity.webFetch;
  if (name == 'subagent' || name.startsWith('subagent_')) {
    return ProcessActivity.subagents;
  }
  if (const <String>{
    'todo_write',
    'create_goal',
    'update_goal',
    'get_goal',
  }.contains(name)) {
    return ProcessActivity.plan;
  }
  if (name == 'ask_user_question' || name == 'request_user_input') {
    return ProcessActivity.questions;
  }
  return ProcessActivity.tools;
}

/// Whether a tool name creates or forks a subagent (the reference's
/// `isSubagentDelegationTool`): the shipped `subagent` name and its
/// `subagent_`-prefixed variants. The control tools use other names
/// (`send_message`, `list_agents`), so they count as ordinary work.
bool isSubagentDelegationTool(String name) =>
    name == 'subagent' || name.startsWith('subagent_');

/// One category's call count inside a group.
final class ProcessActivityCount {
  const ProcessActivityCount(this.kind, this.count);

  final ProcessActivity kind;
  final int count;
}

/// A group's ranked work plus whatever it is doing right now.
final class ProcessActivitySummary {
  const ProcessActivitySummary({
    required this.counts,
    this.running,
    this.runningDetail = '',
    this.preparing = false,
  });

  /// Categories by call count, most first; equal counts keep first-appearance
  /// order.
  final List<ProcessActivityCount> counts;

  /// The category of the latest still-running call; null once nothing runs.
  final ProcessActivity? running;

  /// One line describing the running work (or, with no running call, the
  /// newest reasoning paragraph); empty when neither exists.
  final String runningDetail;

  /// Whether the latest running call's arguments are not usable yet, which is
  /// the reference's `phase: 'preparing'`.
  final bool preparing;
}

/// Grapheme cap on one live detail line, matching the reference.
const int liveToolDetailMaxChars = 160;

/// The reference's argument-key priority for a live detail line.
const List<String> _liveDetailKeys = <String>[
  'title',
  'description',
  'objective',
  'task',
  'task_name',
  'name',
  'question',
  'questions',
  'prompt',
  'message',
  'command',
  'cmd',
  'queries',
  'query',
  'pattern',
  'url',
  'uri',
  'file_path',
  'path',
  'target',
  'action',
  'status',
];

Object? _parseArgs(String argsRaw) {
  if (argsRaw.isEmpty) return null;
  try {
    return jsonDecode(argsRaw);
  } on FormatException {
    return null;
  }
}

/// Collapse [value] to one bounded line: a string is taken as-is, a list of
/// strings is comma-joined, and anything else has no readable detail.
String normalizeLiveToolDetail(Object? value) {
  final String text;
  if (value is String) {
    text = value;
  } else if (value is List<Object?> && value.every((item) => item is String)) {
    text = value.cast<String>().join(', ');
  } else {
    text = '';
  }
  final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  final chars = normalized.characters;
  return chars.length <= liveToolDetailMaxChars
      ? normalized
      : '${chars.take(liveToolDetailMaxChars - 1).toString().trimRight()}…';
}

/// The first `question` of a `questions` argument array, or empty.
String _questionDetail(Object? value) {
  if (value is! List<Object?>) return '';
  for (final item in value) {
    if (item is! Map) continue;
    final detail = normalizeLiveToolDetail(item['question']);
    if (detail.isNotEmpty) return detail;
  }
  return '';
}

/// One live line for a running tool call: its first readable argument from the
/// reference's key priority, falling back to the call's own name.
String liveToolDetail(String name, String argsRaw) {
  final args = _parseArgs(argsRaw);
  if (args is! Map) return normalizeLiveToolDetail(name);
  for (final key in _liveDetailKeys) {
    if (!args.containsKey(key)) continue;
    final value = args[key];
    final detail = key == 'questions'
        ? _questionDetail(value)
        : normalizeLiveToolDetail(value);
    if (detail.isNotEmpty) return detail;
  }
  return normalizeLiveToolDetail(name);
}

/// The newest non-empty paragraph of a reasoning block, stripped of its
/// emphasis markers and bounded like a tool detail — the reference's fallback
/// when a group runs but no tool call is in flight.
String latestReasoningDetail(String? reasoning) {
  if (reasoning == null) return '';
  final paragraphs = reasoning.split(RegExp(r'\r?\n[\t ]*\r?\n'));
  for (var index = paragraphs.length - 1; index >= 0; index--) {
    final detail = normalizeLiveToolDetail(
      paragraphs[index].replaceAll('**', ''),
    );
    if (detail.isNotEmpty) return detail;
  }
  return '';
}

/// Whether a call's arguments are still unusable, which the reference reports
/// as the `preparing` phase.
///
/// The reference learns this from a process-local `preparing` frame; this
/// client folds tool calls from the durable log, where `arguments` is required,
/// so the same condition is read off the payload: absent or not yet parseable.
bool _isPreparing(TimelineToolCall call) {
  final raw = call.arguments;
  return raw == null || _parseArgs(raw) == null;
}

/// Rank the work of one process group.
///
/// Every call in the tree counts once (nested dispatches included, deduped by
/// call id), the latest still-running call supplies [ProcessActivitySummary.running],
/// and [reasoningDetail] supplies the detail when nothing runs.
ProcessActivitySummary deriveProcessActivity(
  List<TimelineToolCall> roots, {
  String Function()? reasoningDetail,
}) {
  final counts = <ProcessActivity, int>{};
  final order = <ProcessActivity>[];
  final seen = <String>{};
  ProcessActivity? running;
  var runningDetail = '';
  var preparing = false;
  var runningTime = -1;

  void visit(TimelineToolCall call) {
    if (!seen.add(call.id)) return;
    final kind = processActivityOf(call.name);
    if (!counts.containsKey(kind)) order.add(kind);
    if (call.status == ToolRunStatus.running) {
      final time = call.startedAtEpochMs ?? 0;
      if (time >= runningTime) {
        running = kind;
        preparing = _isPreparing(call);
        runningDetail = preparing
            ? (kind == ProcessActivity.tools ? call.name : '')
            : liveToolDetail(call.name, call.arguments ?? '');
        runningTime = time;
      }
    }
    counts[kind] = (counts[kind] ?? 0) + 1;
    for (final child in call.children) {
      visit(child);
    }
  }

  for (final root in roots) {
    visit(root);
  }
  if (running == null) {
    runningDetail = reasoningDetail?.call() ?? '';
  }
  // The reference sorts by count with a stable sort, so equal counts keep the
  // order the categories first appeared. Dart's sort is not stable, so the
  // first-appearance index is the explicit tiebreak.
  final firstSeen = <ProcessActivity, int>{
    for (var index = 0; index < order.length; index++) order[index]: index,
  };
  final sorted =
      order.map((kind) => ProcessActivityCount(kind, counts[kind]!)).toList()
        ..sort((a, b) {
          final byCount = b.count.compareTo(a.count);
          return byCount != 0
              ? byCount
              : firstSeen[a.kind]!.compareTo(firstSeen[b.kind]!);
        });
  return ProcessActivitySummary(
    counts: List<ProcessActivityCount>.unmodifiable(sorted),
    running: running,
    runningDetail: runningDetail,
    preparing: preparing,
  );
}

/// The live label for one activity (the reference's `message.stepProcess.*`
/// and `message.stepProcess.prepare.*`).
String liveActivityLabel(
  ProcessActivity activity,
  AppLocalizations l10n, {
  bool preparing = false,
}) {
  if (!preparing) {
    return switch (activity) {
      ProcessActivity.thinking => l10n.stepProcessThinking,
      ProcessActivity.read => l10n.stepProcessRead,
      ProcessActivity.readImage => l10n.stepProcessReadImage,
      ProcessActivity.search => l10n.stepProcessSearch,
      ProcessActivity.write => l10n.stepProcessWrite,
      ProcessActivity.edit => l10n.stepProcessEdit,
      ProcessActivity.commands => l10n.stepProcessCommands,
      ProcessActivity.code => l10n.stepProcessCode,
      ProcessActivity.webSearch => l10n.stepProcessWebSearch,
      ProcessActivity.webFetch => l10n.stepProcessWebFetch,
      ProcessActivity.subagents => l10n.stepProcessSubagents,
      ProcessActivity.plan => l10n.stepProcessPlan,
      ProcessActivity.questions => l10n.stepProcessQuestions,
      ProcessActivity.tools => l10n.stepProcessTools,
    };
  }
  return switch (activity) {
    // A group that has not named a tool yet prepares to call one.
    ProcessActivity.thinking => l10n.stepProcessPrepareTools,
    ProcessActivity.read => l10n.stepProcessPrepareRead,
    ProcessActivity.readImage => l10n.stepProcessPrepareReadImage,
    ProcessActivity.search => l10n.stepProcessPrepareSearch,
    ProcessActivity.write => l10n.stepProcessPrepareWrite,
    ProcessActivity.edit => l10n.stepProcessPrepareEdit,
    ProcessActivity.commands => l10n.stepProcessPrepareCommands,
    ProcessActivity.code => l10n.stepProcessPrepareCode,
    ProcessActivity.webSearch => l10n.stepProcessPrepareWebSearch,
    ProcessActivity.webFetch => l10n.stepProcessPrepareWebFetch,
    ProcessActivity.subagents => l10n.stepProcessPrepareSubagents,
    ProcessActivity.plan => l10n.stepProcessPreparePlan,
    ProcessActivity.questions => l10n.stepProcessPrepareQuestions,
    ProcessActivity.tools => l10n.stepProcessPrepareTools,
  };
}

/// The settled label for one activity (the reference's
/// `message.stepProcess.done.*`).
String doneActivityLabel(ProcessActivity activity, AppLocalizations l10n) =>
    switch (activity) {
      ProcessActivity.thinking => l10n.stepProcessDoneThinking,
      ProcessActivity.read => l10n.stepProcessDoneRead,
      ProcessActivity.readImage => l10n.stepProcessDoneReadImage,
      ProcessActivity.search => l10n.stepProcessDoneSearch,
      ProcessActivity.write => l10n.stepProcessDoneWrite,
      ProcessActivity.edit => l10n.stepProcessDoneEdit,
      ProcessActivity.commands => l10n.stepProcessDoneCommands,
      ProcessActivity.code => l10n.stepProcessDoneCode,
      ProcessActivity.webSearch => l10n.stepProcessDoneWebSearch,
      ProcessActivity.webFetch => l10n.stepProcessDoneWebFetch,
      ProcessActivity.subagents => l10n.stepProcessDoneSubagents,
      ProcessActivity.plan => l10n.stepProcessDonePlan,
      ProcessActivity.questions => l10n.stepProcessDoneQuestions,
      ProcessActivity.tools => l10n.stepProcessDoneTools,
    };

/// A closed group's disclosure title: its top three categories without counts
/// (the reference's `processTitle`).
///
/// Two categories join through `stepProcessJoinTwo` — sharing a prefix when
/// both carry it (the Chinese `已`) — and three or more through
/// `stepProcessComma`, with `stepProcessMore` marking a fourth category the
/// title dropped.
String processTitle(ProcessActivitySummary summary, AppLocalizations l10n) {
  final labels = summary.counts
      .take(3)
      .map((count) => doneActivityLabel(count.kind, l10n))
      .toList(growable: false);
  if (labels.isEmpty) return doneActivityLabel(ProcessActivity.thinking, l10n);
  final first = labels.first;
  if (labels.length == 1) return first;
  if (labels.length == 2) {
    final second = labels[1];
    final prefix = l10n.stepProcessSharedPrefix;
    final shared =
        prefix.isNotEmpty &&
        first.startsWith(prefix) &&
        second.startsWith(prefix);
    return l10n.stepProcessJoinTwo(
      first,
      _continuation(shared ? second.substring(prefix.length) : second),
    );
  }
  final title = <String>[
    first,
    ...labels.skip(1).map(_continuation),
  ].join(l10n.stepProcessComma);
  return summary.counts.length > 3 ? l10n.stepProcessMore(title) : title;
}

/// The reference lowercases only the first character of a continued label, so
/// a joined English title reads as one sentence.
String _continuation(String label) =>
    label.isEmpty ? label : label[0].toLowerCase() + label.substring(1);
