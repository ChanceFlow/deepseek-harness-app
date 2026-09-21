/// Presented-files row — the 交付文件 cards a finished turn closes with.
///
/// The phone counterpart of the reference `Deliverables` presented section
/// (`ui-deliverables/src/client/Deliverables.tsx` plus
/// `PresentedFileCard.tsx`): one card per file a successful `present` call
/// declared, each carrying the file's basename, the model's description (the
/// extension when it wrote none), and one open affordance.
///
/// Two reference affordances are deliberately absent. There is no
/// host-desktop action ("open in default app" / "show in file manager"): that
/// is the reference's `/api/present.open` route, which asks the *host's*
/// desktop to open a path — the same loopback-flavoured promise the
/// produced-file chips already decline, so a card opens the in-app preview
/// instead. And the host-status line ("this Host has no desktop") exists to
/// explain a disabled menu; with no menu there is nothing to explain.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:flutter/material.dart';

import 'produced_files.dart';
import '../theme/theme.dart';

class PresentedFilesRow extends StatefulWidget {
  const PresentedFilesRow({
    required this.files,
    required this.onOpenFile,
    super.key,
  });

  /// Maximum cards rendered before the remainder toggle (reference
  /// `COLLAPSED_PRESENTED_COUNT`).
  static const int collapsedCount = 4;

  /// Declared files in first-seen path order, each path's latest declaration.
  final List<PresentedFile> files;

  /// Opens one declared path; the chat surface passes its preview seam.
  final void Function(String path) onOpenFile;

  @override
  State<PresentedFilesRow> createState() => _PresentedFilesRowState();
}

class _PresentedFilesRowState extends State<PresentedFilesRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.files.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final collapsible = widget.files.length > PresentedFilesRow.collapsedCount;
    final shown = collapsible && !_expanded
        ? widget.files.take(PresentedFilesRow.collapsedCount).toList()
        : widget.files;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.presentedFilesLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          for (final file in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _PresentedFileCard(
                file: file,
                onOpen: () => widget.onOpenFile(file.path),
              ),
            ),
          if (collapsible)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                ),
                iconAlignment: IconAlignment.end,
                label: Text(
                  _expanded
                      ? l10n.presentedFilesCollapse
                      : l10n.presentedFilesAll(widget.files.length),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One declared file: a file-type seat, the name over its description, and a
/// trailing open seat. The whole card is tappable, which is the phone's
/// equivalent of the reference's full-card preview overlay.
class _PresentedFileCard extends StatelessWidget {
  const _PresentedFileCard({required this.file, required this.onOpen});

  final PresentedFile file;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final name = producedFileBasename(file.path);
    final description = file.description?.trim();
    final subtitle = description == null || description.isEmpty
        ? _extensionLabel(name, l10n)
        : description;
    return Material(
      color: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kShapeCard),
        side: BorderSide(color: scheme.outlineVariant, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onOpen,
        leading: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(kShapeChip),
            border: Border.all(color: scheme.outlineVariant, width: 0.5),
          ),
          child: Icon(
            Icons.description_outlined,
            size: 20,
            color: scheme.onSurfaceVariant,
          ),
        ),
        title: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        trailing: Tooltip(
          message: l10n.presentedFilesOpenName(file.path),
          child: TextButton(
            onPressed: onOpen,
            child: Text(l10n.presentedFilesOpen),
          ),
        ),
      ),
    );
  }

  /// The reference's fallback line: the uppercased extension, or the bare
  /// word for a file with none.
  String _extensionLabel(String name, AppLocalizations l10n) {
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return l10n.presentedFilesFile;
    return name.substring(dot + 1).toUpperCase();
  }
}
