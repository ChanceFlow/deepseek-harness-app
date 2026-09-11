/// Produced-files row — the chip lane a finished turn closes with.
///
/// The phone counterpart of the reference `ProducedFiles`
/// (`ui-deliverables/src/client/ProducedFiles.tsx`): a short label and up to
/// six file chips, then a localized "+N files" overflow. Each chip shows the
/// basename (the full path rides the tooltip) and opens the path with the
/// in-app preview sheet — `host.openPath` is a loopback-privileged verb, so
/// a directly-connected phone can list the paths but cannot ask the host's
/// desktop to open them.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import 'produced_files.dart';

class ProducedFilesRow extends StatelessWidget {
  const ProducedFilesRow({
    required this.paths,
    required this.onOpenFile,
    super.key,
  });

  /// Maximum chips rendered before the remainder counter (reference
  /// `SHOWN_LIMIT`).
  static const int shownLimit = 6;

  /// Produced paths in first-seen order, already deduped per turn.
  final List<String> paths;

  /// Opens one produced path; the chat surface passes its preview seam.
  final void Function(String path) onOpenFile;

  @override
  Widget build(BuildContext context) {
    if (paths.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final shown = paths.take(shownLimit).toList(growable: false);
    final remainder = paths.length - shown.length;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.producedFilesLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              for (final path in shown)
                Tooltip(
                  message: l10n.producedFilesOpen(path),
                  child: ActionChip(
                    avatar: Icon(
                      Icons.insert_drive_file_outlined,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                    label: Text(producedFileBasename(path)),
                    labelStyle: theme.textTheme.labelMedium,
                    backgroundColor: scheme.surfaceContainerHigh,
                    side: BorderSide(color: scheme.outlineVariant),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onPressed: () => onOpenFile(path),
                  ),
                ),
              if (remainder > 0)
                Text(
                  l10n.producedFilesMore(remainder),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
