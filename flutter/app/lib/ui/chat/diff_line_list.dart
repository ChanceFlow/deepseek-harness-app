/// One edit's unified diff as the coloured line list.
///
/// The row's bounded peek and the full-screen detail surface draw the same
/// thing, so a diff can never read one way in the transcript and another on the
/// surface it opens. The line colours are the app's roles: a deletion on
/// `error`/`errorContainer`, an insertion on `primary`/`primaryContainer`, an
/// unchanged line on the plain surface — the same pairing the reference's diff
/// view uses.
library;

import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'tool_row_model.dart' show DiffLineKind, EditDiffModel;

/// The diff's source lines with their `+`/`-`/space prefixes — what the copy
/// seats put on the clipboard.
String diffPlainText(EditDiffModel diff) => [
  for (final line in diff.lines)
    '${switch (line.kind) {
      DiffLineKind.delete => '-',
      DiffLineKind.insert => '+',
      DiffLineKind.equal => ' ',
    }} ${line.text}',
].join('\n');

/// The lines themselves, horizontally scrollable so a long line is readable
/// rather than wrapped mid-token.
class DiffLineList extends StatelessWidget {
  const DiffLineList({required this.diff, super.key});

  final EditDiffModel diff;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final line in diff.lines)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
              decoration: BoxDecoration(
                color: switch (line.kind) {
                  DiffLineKind.delete => scheme.errorContainer.withValues(
                    alpha: 0.35,
                  ),
                  DiffLineKind.insert => scheme.primaryContainer.withValues(
                    alpha: 0.35,
                  ),
                  DiffLineKind.equal => Colors.transparent,
                },
                borderRadius: BorderRadius.circular(kShapeChip),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SizedBox(
                    width: 16,
                    child: Text(
                      switch (line.kind) {
                        DiffLineKind.delete => '-',
                        DiffLineKind.insert => '+',
                        DiffLineKind.equal => ' ',
                      },
                      style: TextStyle(
                        fontFamily: kCodeFontFamily,
                        fontFamilyFallback: kCodeFontFamilyFallback,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: switch (line.kind) {
                          DiffLineKind.delete => scheme.error,
                          DiffLineKind.insert => scheme.primary,
                          DiffLineKind.equal => scheme.onSurfaceVariant,
                        },
                      ),
                    ),
                  ),
                  Text(
                    line.text,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: kCodeFontFamily,
                      fontFamilyFallback: kCodeFontFamilyFallback,
                      color: scheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
