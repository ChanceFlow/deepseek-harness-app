/// The stop-and-archive confirmation: the reference's answer to a Host that
/// refused to archive a session still running work.
///
/// The dialog owns its own in-flight and error state (the reference's form
/// does the same), asks the Host through [onConfirm], and reports a durable
/// archive through [onArchived] so the app root raises the notice. Escape,
/// the barrier, and the back gesture are ignored while the call is in
/// flight: the Host may already be stopping work, and closing the dialog
/// would hide that.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/session_archive.dart';
import 'package:flutter/material.dart';

import '../../notifications/session_notice.dart';

/// One family's line in the confirmation: its count and the names of the
/// items that will stop (the raw family key for a family this program did not
/// compile).
String sessionActivityLine(AppLocalizations l10n, SessionActivityEntry entry) {
  final names = entry.items
      .map((item) => item.displayName)
      .join(l10n.archiveConfirmListSeparator);
  return switch (entry.kind) {
    SessionActivityKind.turn => l10n.archiveConfirmTurn,
    SessionActivityKind.subagent => l10n.archiveConfirmSubagents(
      entry.items.length,
      names,
    ),
    SessionActivityKind.job => l10n.archiveConfirmJobs(
      entry.items.length,
      names,
    ),
    SessionActivityKind.schedule => l10n.archiveConfirmSchedules(
      entry.items.length,
      names,
    ),
    SessionActivityKind.other => l10n.archiveConfirmOther(
      entry.items.length,
      entry.rawKind,
    ),
  };
}

/// The confirmation for one [SessionArchiveRequest].
class SessionArchiveConfirmDialog extends StatefulWidget {
  const SessionArchiveConfirmDialog({
    required this.request,
    required this.onConfirm,
    required this.onArchived,
    super.key,
  });

  /// What the Host refused and the work it named.
  final SessionArchiveRequest request;

  /// Asks the Host to stop [SessionArchiveRequest.sessionId]'s running work
  /// and archive it; resolves once the archive is durable.
  final Future<void> Function() onConfirm;

  /// Called after [onConfirm] resolves, before the dialog closes.
  final VoidCallback onArchived;

  @override
  State<SessionArchiveConfirmDialog> createState() =>
      _SessionArchiveConfirmDialogState();
}

class _SessionArchiveConfirmDialogState
    extends State<SessionArchiveConfirmDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onConfirm();
      if (!mounted) return;
      widget.onArchived();
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(l10n.archiveConfirmTitle),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(l10n.archiveConfirmBody(widget.request.displayTitle)),
              const SizedBox(height: 16),
              Text(
                l10n.archiveConfirmActivity,
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              for (final entry in widget.request.activity)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(sessionActivityLine(l10n, entry)),
                ),
              if (_busy) ...<Widget>[
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(l10n.archiveConfirmPending)),
                  ],
                ),
              ],
              if (_error case final String message) ...<Widget>[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(message, style: TextStyle(color: scheme.error)),
                ),
              ],
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: _busy ? null : _confirm,
            child: Text(l10n.archiveConfirmAction),
          ),
        ],
      ),
    );
  }
}
