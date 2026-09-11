/// File preview sheet — the surface behind a tool row's "Preview" action.
///
/// Reads a text window of a workspace file through the repository seam
/// handed in by the chat surface (`workspaceFiles/read` via
/// [ChatRepository.readWorkspaceFile]) and renders it with the app's
/// existing markdown/code renderer. A bottom sheet is the natural Material 3
/// fit: the action is invoked from an expanded transcript row, so the
/// content opens as a modal surface over the same context instead of a
/// route push that hides the conversation.
///
/// States: loading, read failure (localized, retryable), binary/undecodable
/// (a notice, never a wall of replacement characters), and text — with the
/// host's truncation signal (`eof == false`) surfacing the paged window's
/// line count.
library;

import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/workspace_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/theme.dart';
import 'markdown/markdown_text.dart';

/// Reads a text window of [path] inside [sessionId]'s workspace.
typedef WorkspaceFileReader = Future<WorkspaceFileContent> Function(
  String sessionId,
  String path,
);

/// Opens the preview sheet for [path]. [readFile] is the chat surface's
/// repository seam; the sheet never reaches past it.
Future<void> showFilePreviewSheet(
  BuildContext context, {
  required String sessionId,
  required String path,
  required WorkspaceFileReader readFile,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    sheetAnimationStyle: const AnimationStyle(
      duration: DshMotion.durationMedium,
      curve: DshMotion.curveEmphasized,
      reverseCurve: DshMotion.curveExit,
    ),
    builder: (sheetContext) =>
        FilePreviewSheet(sessionId: sessionId, path: path, readFile: readFile),
  );
}

class FilePreviewSheet extends StatefulWidget {
  const FilePreviewSheet({
    required this.sessionId,
    required this.path,
    required this.readFile,
    super.key,
  });

  final String sessionId;
  final String path;
  final WorkspaceFileReader readFile;

  @override
  State<FilePreviewSheet> createState() => _FilePreviewSheetState();
}

class _FilePreviewSheetState extends State<FilePreviewSheet> {
  WorkspaceFileContent? _content;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final content = await widget.readFile(widget.sessionId, widget.path);
      if (!mounted) return;
      setState(() {
        _content = content;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final content = _content;
    final binary = content != null && _looksBinary(content.text);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(kShapeSheet),
          border: Border.all(color: scheme.outlineVariant),
          boxShadow: kM3ShadowElevation3,
        ),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(context, l10n, copyable: content != null && !binary),
                Divider(height: 1, color: scheme.outlineVariant),
                Flexible(
                  child: _body(context, l10n, binary: binary, content: content),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(
    BuildContext context,
    AppLocalizations l10n, {
    required bool copyable,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Icon(Icons.description_outlined, size: 20, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.previewFile, style: theme.textTheme.titleSmall),
                Text(
                  widget.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontFamily: 'monospace',
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (copyable)
            IconButton(
              tooltip: l10n.copyContent,
              onPressed: _copyContent,
              icon: Icon(Icons.copy_outlined, color: scheme.onSurfaceVariant),
            ),
          IconButton(
            tooltip: l10n.close,
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.close, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context,
    AppLocalizations l10n, {
    required bool binary,
    required WorkspaceFileContent? content,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_failed || content == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.filePreviewFailed,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(l10n.retry),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: scheme.outlineVariant),
              ),
            ),
          ],
        ),
      );
    }
    if (binary) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.data_object, size: 32, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              l10n.filePreviewBinary,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }
    final text = content.text;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The host pages large files: a window that is not the end of the
          // file reports how many lines it returned.
          if (!content.eof)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(kShapeChip),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.unfold_more,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.filePreviewTruncated(content.lines),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (text.trim().isEmpty)
            Text(
              l10n.filePreviewEmpty,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            )
          else
            MarkdownText(text: _renderable(widget.path, text)),
        ],
      ),
    );
  }

  Future<void> _copyContent() async {
    final content = _content;
    if (content == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    await Clipboard.setData(ClipboardData(text: content.text));
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.copiedFeedback),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

/// Text the existing renderer understands: a markdown document passes
/// through, any other file is wrapped in a fenced block so it takes the
/// code surface (monospace, horizontal scroll) instead of being reflowed
/// as prose.
String _renderable(String path, String text) {
  if (_markdownExtensions.any(path.toLowerCase().endsWith)) return text;
  final language = _languageFor(path);
  return '```${language ?? ''}\n$text\n```';
}

/// Binary or undecodable content: a NUL byte, or a run of Unicode
/// replacement characters the JSON text decode produced for bytes that are
/// not valid UTF-8.
bool _looksBinary(String text) {
  if (text.isEmpty) return false;
  final sample = text.length > 4096 ? text.substring(0, 4096) : text;
  var replacement = 0;
  var total = 0;
  for (final rune in sample.runes) {
    total += 1;
    if (rune == 0) return true;
    if (rune == 0xFFFD) replacement += 1;
  }
  return total > 0 && replacement > total * 0.05;
}

const List<String> _markdownExtensions = <String>['.md', '.markdown', '.mdx'];

String? _languageFor(String path) {
  final name = path.split('/').last;
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return null;
  return name.substring(dot + 1).toLowerCase();
}
