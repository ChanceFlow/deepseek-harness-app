/// `@` mention composer source — the phone port of the reference web client's
/// unified `@` reference source
/// (`reference/deepseek-harness/packages/client/ui-reference/src/client/index.ts`),
/// backed by `fileReferences/list`.
///
/// The token grammar is a faithful mirror of the shared browser-safe grammar
/// (`reference/deepseek-harness/packages/context/file-reference/src/grammar.ts`)
/// so the text a reader accepts is the text the host and the web client read:
/// an unquoted `@path` token, or `@"path with spaces` while the quote is open.
/// Directory candidates keep the token open for the next level, exactly the
/// web drill; a file candidate completes the mention and takes a separating
/// space.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:app/ui/theme/theme.dart';
import 'package:domain/model/file_reference.dart';
import 'package:flutter/material.dart';

import 'chat_ui_state.dart';

/// One live `@` token ending at the caret.
final class ActiveFileReferenceToken {
  const ActiveFileReferenceToken({
    required this.prefix,
    required this.query,
    required this.quoted,
  });

  /// The complete token text replaced when the reader accepts a candidate:
  /// `@` or `@"` plus the query.
  final String prefix;

  /// The path text after `@` or `@"`.
  final String query;

  /// Whether the reader opened a quoted path.
  final bool quoted;

  /// Offset of the token's first character for a caret at [cursor].
  int startAt(int cursor) => cursor - prefix.length;
}

final RegExp _quotedToken = RegExp(r'(?:^|\s)(@"([^"]*))$');
final RegExp _plainToken = RegExp(r'(?:^|\s)(@([^\s]*))$');
final RegExp _draftUnsafe = RegExp(r'[\u0000-\u001f\u007f-\u009f"]');
final RegExp _whitespace = RegExp(r'\s');

/// Extract the `@path` or `@"path with spaces` token ending at [cursor].
///
/// An `@` inside another token, such as an email address, is not a completion
/// trigger. Returns null outside an `@` token.
ActiveFileReferenceToken? activeFileReferenceToken(String text, int cursor) {
  final clamped = cursor.clamp(0, text.length);
  final before = text.substring(0, clamped);
  final quoted = _quotedToken.firstMatch(before);
  final quotedPrefix = quoted?.group(1);
  final quotedQuery = quoted?.group(2);
  if (quotedPrefix != null && quotedQuery != null) {
    return ActiveFileReferenceToken(
      prefix: quotedPrefix,
      query: quotedQuery,
      quoted: true,
    );
  }
  final plain = _plainToken.firstMatch(before);
  final plainPrefix = plain?.group(1);
  final plainQuery = plain?.group(2);
  if (plainPrefix == null || plainQuery == null) return null;
  return ActiveFileReferenceToken(
    prefix: plainPrefix,
    query: plainQuery,
    quoted: false,
  );
}

/// Format one candidate as prompt text, or null for a path the grammar cannot
/// represent safely.
///
/// A directory mention ends in `/`; when it needs quoting the quote stays open
/// so completion can descend another level.
String? fileReferenceMention(
  FileReferenceCandidate candidate, {
  bool preserveQuote = false,
}) {
  final path = candidate.kind == FileReferenceKind.directory
      ? '${candidate.path}/'
      : candidate.path;
  if (_draftUnsafe.hasMatch(path)) return null;
  final quoted = preserveQuote || _whitespace.hasMatch(path);
  if (!quoted) return '@$path';
  if (candidate.kind == FileReferenceKind.directory) return '@"$path';
  return '@"$path"';
}

/// The draft after accepting [candidate] over [token].
///
/// A file completes the mention and takes a separating space unless the draft
/// already has one next; a directory leaves the token open so the menu shows
/// the level just entered. Returns null when the mention is unrepresentable.
({String text, int caret})? applyFileReferencePick({
  required String draft,
  required int cursor,
  required ActiveFileReferenceToken token,
  required FileReferenceCandidate candidate,
}) {
  final mention = fileReferenceMention(candidate, preserveQuote: token.quoted);
  if (mention == null) return null;
  final start = token.startAt(cursor.clamp(0, draft.length));
  final end = cursor.clamp(0, draft.length);
  final tail = end < draft.length ? draft[end] : '';
  final complete = candidate.kind == FileReferenceKind.file;
  final separator = complete && !_whitespace.hasMatch(tail) ? ' ' : '';
  final inserted = '$mention$separator';
  return (
    text: draft.replaceRange(start, end, inserted),
    caret: start + inserted.length,
  );
}

/// The `@` candidate menu: the file-reference rows the composer shows above
/// the draft band while a token is live.
///
/// [picker] is the controller's last resolved query. Only a holder whose
/// query equals the live [token] renders, so a slower answer to an earlier
/// prefix never stands under newer text.
class FileReferenceCandidates extends StatelessWidget {
  const FileReferenceCandidates({
    required this.token,
    required this.picker,
    required this.enabled,
    required this.onPick,
    super.key,
  });

  /// The live `@` token at the caret, or null when the draft has none.
  final ActiveFileReferenceToken? token;

  /// The controller's last resolved `@` query, or null while none resolved.
  final FileReferencePickerState? picker;

  final bool enabled;
  final void Function(FileReferenceCandidate candidate) onPick;

  @override
  Widget build(BuildContext context) {
    final live = token;
    final resolved = picker;
    if (!enabled || live == null || resolved == null) {
      return const SizedBox.shrink();
    }
    if (resolved.query != live.query) return const SizedBox.shrink();
    final rows = <FileReferenceCandidate>[
      for (final candidate in resolved.candidates)
        if (fileReferenceMention(candidate, preserveQuote: live.quoted) != null)
          candidate,
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxHeight: 220),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(kShapeMenuSheet),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(4),
          children: [
            // Web parity: the reference menu labels the file group because a
            // combined `@` source also offers sessions (there: "Files &
            // folders"). This source offers files only, so the label names
            // the one group rather than a section boundary.
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
              child: Text(
                l10n.fileReferenceSectionTitle,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            for (final candidate in rows)
              _FileReferenceRow(
                candidate: candidate,
                onTap: () => onPick(candidate),
              ),
          ],
        ),
      ),
    );
  }
}

/// One candidate row: the selector form the composer's other menus use
/// (36px icon tile, bold label, secondary detail).
class _FileReferenceRow extends StatelessWidget {
  const _FileReferenceRow({required this.candidate, required this.onTap});

  final FileReferenceCandidate candidate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final path = candidate.path;
    final slash = path.lastIndexOf('/');
    final name = slash < 0 ? path : path.substring(slash + 1);
    final parent = slash < 0 ? '' : path.substring(0, slash);
    final directory = candidate.kind == FileReferenceKind.directory;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(kShapeChip),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(kShapeChip),
                ),
                child: Icon(
                  directory
                      ? Icons.folder_outlined
                      : Icons.description_outlined,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      directory ? '$name/' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                        color: scheme.onSurface,
                      ),
                    ),
                    // The location is the parent alone; a workspace-root
                    // entry has no parent to name.
                    if (parent.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        parent,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
