/// Tool summary-row model — port of the web `toolRowModel`
/// (`ui-tool/src/client/tool/models/tool-call-model.ts`): variant
/// classification, figma row titles, one-line ARGS-derived summary,
/// expanded-body text, and flattened result output. The result text lives
/// ONLY in the expanded body; the collapsed summary never quotes it.
library;

import 'dart:convert';

import 'package:domain/model/timeline_item.dart';
import 'package:flutter/material.dart' show IconData, Icons;

/// Row variants selected by the generic atomic renderer (web
/// `ToolRowVariant`).
enum ToolRowVariant { search, read, bash, write, edit, code, others }

/// Figma row titles per variant (design literals, not translatable copy).
const Map<ToolRowVariant, String> kVariantTitles = <ToolRowVariant, String>{
  ToolRowVariant.search: 'Search',
  ToolRowVariant.read: 'Read',
  ToolRowVariant.bash: 'Bash',
  ToolRowVariant.write: 'Write',
  ToolRowVariant.edit: 'Edit',
  ToolRowVariant.code: 'Code',
  ToolRowVariant.others: 'Tool call',
};

/// Known tool name → variant (web `TOOL_VARIANTS`).
const Map<String, ToolRowVariant> _toolVariants = <String, ToolRowVariant>{
  'bash': ToolRowVariant.bash,
  // The PowerShell twin is a shell tool: the bash row family with its own
  // title from [_toolTitles], not the generic others row.
  'pwsh': ToolRowVariant.bash,
  'read': ToolRowVariant.read,
  'web_fetch': ToolRowVariant.read,
  'web_search': ToolRowVariant.search,
  'grep': ToolRowVariant.search,
  'glob': ToolRowVariant.search,
  'write': ToolRowVariant.write,
  'edit': ToolRowVariant.edit,
  'run_code': ToolRowVariant.code,
  'cordis_package_inspect': ToolRowVariant.read,
  'cordis_runtime_inspect': ToolRowVariant.read,
  'cordis_run': ToolRowVariant.others,
  'cordis_stop': ToolRowVariant.others,
  'cordis_undefine': ToolRowVariant.others,
};

/// Tool-owned titles that refine a generic row variant without replacing
/// it (web `TOOL_TITLES`).
const Map<String, String> _toolTitles = <String, String>{
  'cordis_package_inspect': 'Inspect',
  'cordis_runtime_inspect': 'Inspect',
  'cordis_run': 'Run Cordis Plugin',
  'cordis_stop': 'Stop Cordis Plugin',
  'cordis_undefine': 'Remove Cordis Plugin',
  'pwsh': 'Pwsh',
};

/// Summary key preference per variant (args-derived; result-derived
/// summaries are a ledger item — web `SUMMARY_KEYS`).
const Map<ToolRowVariant, List<String>> _summaryKeys =
    <ToolRowVariant, List<String>>{
      ToolRowVariant.bash: ['description', 'command'],
      ToolRowVariant.read: ['path', 'file_path', 'url'],
      ToolRowVariant.search: ['query', 'pattern', 'url'],
      ToolRowVariant.write: ['path', 'file_path'],
      ToolRowVariant.edit: ['path', 'file_path'],
      ToolRowVariant.code: ['description'],
      ToolRowVariant.others: [],
    };

/// File path keys only — never `url` (web_fetch lands on the read
/// variant).
const List<String> _filePathKeys = ['path', 'file_path'];

/// File-tool variants whose summary may be an openable path.
const Set<ToolRowVariant> _filePathVariants = <ToolRowVariant>{
  ToolRowVariant.read,
  ToolRowVariant.write,
  ToolRowVariant.edit,
};

/// Classify a wire tool name into its row variant (web `classifyTool`).
ToolRowVariant classifyTool(String toolName) =>
    _toolVariants[toolName] ?? ToolRowVariant.others;

String _firstLine(String text) {
  final newline = text.indexOf('\n');
  return newline == -1 ? text : text.substring(0, newline);
}

Object? _parseArgs(String argsRaw) {
  try {
    return jsonDecode(argsRaw);
  } on FormatException {
    // Non-JSON args (mid-stream truncation): summary/body fall back to
    // the raw string.
    return null;
  }
}

String? _pickString(Map<String, Object?> args, List<String> keys) {
  for (final key in keys) {
    final value = args[key];
    if (value is String && value.isNotEmpty) return value;
  }
  return null;
}

String _deriveSummary(ToolRowVariant variant, String argsRaw) {
  final parsed = _parseArgs(argsRaw);
  if (parsed is! Map<String, Object?>) return _firstLine(argsRaw);
  final args = parsed.cast<String, Object?>();
  final picked = _pickString(args, _summaryKeys[variant]!);
  if (picked != null) return _firstLine(picked);
  for (final value in args.values) {
    if (value is String && value.isNotEmpty) return _firstLine(value);
  }
  return _firstLine(argsRaw);
}

String? _deriveFilePath(ToolRowVariant variant, String argsRaw) {
  if (!_filePathVariants.contains(variant)) return null;
  final parsed = _parseArgs(argsRaw);
  if (parsed is! Map<String, Object?>) return null;
  final picked = _pickString(parsed.cast<String, Object?>(), _filePathKeys);
  return picked == null ? null : _firstLine(picked);
}

String? _deriveBody(ToolRowVariant variant, String argsRaw) {
  if (argsRaw.isEmpty) return null;
  final parsed = _parseArgs(argsRaw);
  if (parsed == null) return argsRaw;
  // The code row's expanded body IS the program, not the args JSON
  // envelope around it.
  if (variant == ToolRowVariant.code && parsed is Map<String, Object?>) {
    final code = parsed['code'];
    if (code is String && code.isNotEmpty) return code;
  }
  const encoder = JsonEncoder.withIndent('  ');
  try {
    return encoder.convert(parsed);
  } on JsonUnsupportedObjectError {
    return argsRaw;
  }
}

/// Everything the row renders, derived once per call (web
/// `ToolRowModel`).
final class ToolRowModel {
  const ToolRowModel({
    required this.variant,
    required this.title,
    required this.summary,
    required this.state,
    this.filePath,
    this.body,
    this.output,
    this.errorSummary,
    this.leading,
    this.summarySuffix,
  });

  final ToolRowVariant variant;
  final String title;

  /// Collapsed one-line summary; ARGS-derived — the settled result text
  /// never reaches this slot.
  final String summary;

  /// Filesystem path from args when the row is a file tool.
  final String? filePath;

  /// Expanded-body input text (pretty args); null = no input section.
  final String? body;

  /// Flattened result text; null while running or when the result carries
  /// no text.
  final String? output;

  /// First line of the result text on an error row; null otherwise.
  final String? errorSummary;

  /// Row-specific leading glyph (the todo checklist); null = the shared
  /// variant chrome.
  final IconData? leading;

  /// Non-shrinking summary suffix (the todo parallel-active count) riding
  /// beside the truncatable text.
  final String? summarySuffix;

  final ToolRowState state;
}

/// Row state semantic (web `ToolRowState`).
enum ToolRowState { running, ok, error }

/// todo_write plan summary — port of `plan-summary.ts`: counts plus the
/// first `in_progress` content and the parallel-active remainder.
({int done, int total, String? activeContent, int activeExtra}) _planSummary(
  List<Map<String, Object?>> todos,
) {
  final active = todos
      .where((item) => item['status'] == 'in_progress')
      .toList();
  final first = active.isEmpty ? null : active.first['content'];
  final String? named = first is String && first.trim().isNotEmpty
      ? first
      : null;
  return (
    done: todos.where((item) => item['status'] == 'completed').length,
    total: todos.length,
    activeContent: named,
    activeExtra: named == null ? 0 : active.length - 1,
  );
}

/// Derive the full row model from one timeline tool call (web
/// `toolRowModel`).
ToolRowModel deriveToolRowModel(TimelineToolCall call) {
  final variant = classifyTool(call.name);
  final argsRaw = call.arguments ?? '';
  final base = argsRaw.isEmpty ? call.id : _deriveSummary(variant, argsRaw);
  final toolTitle = _toolTitles[call.name];
  // Others keeps the static "Tool call" title (figma literal); the real
  // tool name rides the mutable summary slot unless the tool owns a
  // specific title.
  var summary =
      variant == ToolRowVariant.others &&
          call.name.isNotEmpty &&
          toolTitle == null
      ? '${call.name} · $base'
      : base;
  var title = toolTitle ?? kVariantTitles[variant]!;
  String? summarySuffix;
  IconData? leading;
  // todo_write carries a product row (web todo-row.tsx): the checklist
  // glyph, a dedicated title, and the plan summary from the args.
  if (call.name == 'todo_write') {
    title = 'Update to-do list';
    leading = Icons.checklist;
    final parsed = _parseArgs(argsRaw);
    final todosRaw = parsed is Map<String, Object?> ? parsed['todos'] : null;
    if (todosRaw is List &&
        todosRaw.every((item) => item is Map<String, Object?>)) {
      final todos = todosRaw.cast<Map<String, Object?>>();
      final plan = _planSummary(todos);
      final head = '${plan.done}/${plan.total} completed';
      summary = plan.activeContent == null
          ? head
          : '$head · ${plan.activeContent}';
      summarySuffix = plan.activeExtra > 0 ? '+${plan.activeExtra}' : null;
    }
  }
  final output = call.status == ToolRunStatus.running
      ? null
      : (call.result == null || call.result!.isEmpty ? null : call.result);
  final state = switch (call.status) {
    ToolRunStatus.running => ToolRowState.running,
    ToolRunStatus.completed => ToolRowState.ok,
    ToolRunStatus.failed => ToolRowState.error,
  };
  final errorSummary = state == ToolRowState.error && output != null
      ? _firstLine(output)
      : null;
  return ToolRowModel(
    variant: variant,
    title: title,
    summary: summary,
    filePath: _deriveFilePath(variant, argsRaw),
    body: _deriveBody(variant, argsRaw),
    output: output,
    errorSummary: errorSummary,
    leading: leading,
    summarySuffix: summarySuffix,
    state: state,
  );
}
