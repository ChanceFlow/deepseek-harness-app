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
import 'card_detail.dart';

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

/// One declared file, as the card → detail pattern's one-line row: the file's
/// own seat, its name, the model's description under it, and the open chip that
/// hands the content to the preview surface.
///
/// The reference's `PresentedFileCard` keeps a full-body card because its
/// sidebar is the thing that opens; on a phone the row is the card, and the
/// file's content belongs to the surface the chip opens —
/// [showFilePreviewSheet], whose own header records why it is a sheet rather
/// than a route ("the content opens as a modal surface over the same context
/// instead of a route push that hides the conversation"). The sheet is owned by
/// the modal-surface pass and is not edited here.
class _PresentedFileCard extends StatelessWidget {
  const _PresentedFileCard({required this.file, required this.onOpen});

  final PresentedFile file;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final name = producedFileBasename(file.path);
    final description = file.description?.trim();
    final summary = description == null || description.isEmpty
        ? _extensionLabel(name, l10n)
        : description;
    return CardDetailRow(
      icon: Icons.description_outlined,
      title: name,
      summary: summary,
      openLabel: l10n.presentedFilesOpen,
      semanticLabel: l10n.presentedFilesOpenName(file.path),
      onOpen: onOpen,
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
