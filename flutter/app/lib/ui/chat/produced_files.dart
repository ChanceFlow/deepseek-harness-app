/// Produced-file derivation — the phone port of the reference turn
/// deliverables fold (`ui-deliverables/src/client/turn-deliverables.ts`
/// `mutationPath` and `producedForClosing`).
///
/// The vocabulary comes from successful first-party mutation tool calls,
/// never from the closing prose: a `write`, `edit`, or mutating
/// `str_replace_editor` call whose result settled successfully contributes
/// its path. Reads, deletes, unsupported tools, malformed arguments, and
/// failed results contribute nothing. Paths keep first-seen order and appear
/// once per turn, so a file written and then edited in the same turn is one
/// entry.
///
/// [producedMutationPath] is the per-call extraction; [TurnFiles] owns the
/// turn walk, the closing-message snapshot, and the pairing with the files a
/// `present` call declared.
library;

import 'dart:convert';

import 'package:domain/model/timeline_item.dart';

import 'turn_files.dart';

/// The basename of a `/`- or `\`-separated path; the whole string when it
/// carries no separator.
String producedFileBasename(String path) {
  final slash = path.lastIndexOf('/');
  final backslash = path.lastIndexOf(r'\');
  final cut = slash > backslash ? slash : backslash;
  return cut < 0 ? path : path.substring(cut + 1);
}

/// The path one settled mutation call produced; null when the call is not a
/// successful first-party mutation.
///
/// The argument checks mirror the reference's per-tool validation: `write`
/// needs a string `content`, `edit` needs a real replacement (non-empty
/// `old_string`, differing `new_string`, boolean-or-absent `replace_all`),
/// and `str_replace_editor` needs a complete mutating command.
String? producedMutationPath(TimelineToolCall call) {
  if (call.status != ToolRunStatus.completed || call.isError) return null;
  final argsRaw = call.arguments;
  if (argsRaw == null || argsRaw.isEmpty) return null;
  final Object? parsed;
  try {
    parsed = jsonDecode(argsRaw);
  } on FormatException {
    // Truncated or non-JSON arguments (a mid-stream call): no path.
    return null;
  }
  if (parsed is! Map<String, Object?>) return null;
  final args = parsed.cast<String, Object?>();
  return switch (call.name) {
    'write' => args['content'] is String ? _pathValue(args['file_path']) : null,
    'edit' => _validEditArgs(args) ? _pathValue(args['file_path']) : null,
    'str_replace_editor' => _editorMutationPath(args),
    _ => null,
  };
}

/// A non-blank path preserves the exact spelling supplied to the tool.
String? _pathValue(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;

/// The replacement fields an `edit` execution requires.
bool _validEditArgs(Map<String, Object?> args) {
  final oldString = args['old_string'];
  final newString = args['new_string'];
  final replaceAll = args['replace_all'];
  return oldString is String &&
      oldString.isNotEmpty &&
      newString is String &&
      oldString != newString &&
      (replaceAll == null || replaceAll is bool);
}

/// A path only from a complete mutating editor command.
String? _editorMutationPath(Map<String, Object?> args) {
  final path = _pathValue(args['path']);
  if (path == null) return null;
  final command = args['command'];
  if (command == 'create') {
    return args['file_text'] is String ? path : null;
  }
  if (command == 'str_replace') {
    final oldStr = args['old_str'];
    final newStr = args['new_str'];
    return oldStr is String &&
            oldStr.isNotEmpty &&
            (newStr == null || newStr is String)
        ? path
        : null;
  }
  if (command == 'insert') {
    final insertLine = args['insert_line'];
    return insertLine is int && insertLine >= 0 && args['new_str'] is String
        ? path
        : null;
  }
  return null;
}

/// Produced paths per closing assistant message id, in transcript order.
///
/// The turn walk and the closing-message snapshot live in [TurnFiles], whose
/// fold reads this module's [producedMutationPath] beside the presented-file
/// facts; this reader projects just the produced half.
Map<String, List<String>> producedFilesByClosingMessage(
  List<TimelineItem> items, {
  required bool latestTurnClosed,
}) => <String, List<String>>{
  for (final entry in turnFilesByClosingMessage(
    items,
    latestTurnClosed: latestTurnClosed,
  ).entries)
    if (entry.value.produced.isNotEmpty) entry.key: entry.value.produced,
};
