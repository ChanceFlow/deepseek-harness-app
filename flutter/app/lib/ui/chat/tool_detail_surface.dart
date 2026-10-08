/// The tool row's whole payload as a full-screen surface.
///
/// A tool row's transcript line is one line and its expanded body is a bounded
/// peek — 280px of the diff or the output, scrolled inside the card — because
/// the transcript is what the reader is reading. The whole payload is
/// content-shaped, so it opens one surface deeper: the app bar names the tool,
/// the diff or the input/output sections scroll on their own, and the row's
/// actions (preview the edited file, copy the payload) are pinned in the bottom
/// bar. The peek and this surface draw the same [DiffLineList], so a diff can
/// never read one way in the transcript and another here.
///
/// The reference draws the same pair (`ToolRow.module.css` `.ioCard` for the
/// inline body, `ui-sidebar-documentpreview` for the file itself); a phone has
/// no side pane, so the file's own view stays the preview sheet its host
/// documents, and this surface carries the call's payload.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'card_detail.dart';
import 'diff_line_list.dart';
import 'tool_row_model.dart' show EditDiffModel;
import '../theme/theme.dart';

/// Opens [args]'s payload one surface deeper.
///
/// [onPreviewFile] is the chat surface's own preview seam; null drops the seat,
/// the way the row's action bar does.
Future<void> showToolDetail(
  BuildContext context, {
  required ToolDetailArgs args,
  void Function(String path, {EditDiffModel? diff})? onPreviewFile,
}) => pushCardDetail<void>(
  context,
  name: 'card-detail:tool',
  args: args,
  builder: (context) =>
      ToolDetailSurface(args: args, onPreviewFile: onPreviewFile),
);

/// The tool call's full payload.
class ToolDetailSurface extends StatelessWidget {
  const ToolDetailSurface({required this.args, this.onPreviewFile, super.key});

  final ToolDetailArgs args;
  final void Function(String path, {EditDiffModel? diff})? onPreviewFile;

  /// Everything the payload holds, in the order the row renders it — what the
  /// copy seat puts on the clipboard.
  String get _payload => <String>[
    if (args.diff case final diff?) diffPlainText(diff),
    if (args.input case final input?) input,
    if (args.output case final output?) output,
  ].join('\n\n');

  Future<void> _copy(BuildContext context, AppLocalizations l10n) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: _payload));
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.copiedTooltip),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final path = args.path;
    final preview = onPreviewFile;
    return CardDetailScaffold(
      title: args.title,
      subtitle: path,
      actions: <Widget>[
        if (path != null && preview != null)
          OutlinedButton.icon(
            onPressed: () => preview(path, diff: args.diff),
            icon: const Icon(Icons.visibility_outlined, size: 14),
            label: Text(l10n.previewFile),
          ),
        FilledButton.icon(
          onPressed: () => _copy(context, l10n),
          icon: const Icon(Icons.copy_outlined, size: 14),
          label: Text(l10n.copyTooltip),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (args.diff case final diff?)
            _Section(
              label: l10n.diffLabel,
              child: DiffLineList(diff: diff),
            ),
          if (args.input case final input?)
            _Section(
              label: l10n.inputLabel,
              child: _CodeText(text: input),
            ),
          if (args.output case final output?)
            _Section(
              label: l10n.outputLabel,
              child: _CodeText(text: output, failed: args.failed),
            ),
        ],
      ),
    );
  }
}

/// One labelled section: the row's own gutter label beside the payload.
class _Section extends StatelessWidget {
  const _Section({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 44,
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.labelDimmed,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// A payload body in the app's code face.
class _CodeText extends StatelessWidget {
  const _CodeText({required this.text, this.failed = false});

  final String text;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SelectableText(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: failed ? scheme.stateErrorPrimary : scheme.labelSecondary,
        fontFamily: kCodeFontFamily,
        fontFamilyFallback: kCodeFontFamilyFallback,
      ),
    );
  }
}
