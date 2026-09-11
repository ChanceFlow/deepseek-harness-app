/// Session-log download header action — the phone stand-in for the
/// reference web client's "Session log" header capsule: one compact seat
/// that streams the open session's ZIP through the platform save path and
/// reports where it landed.
///
/// It renders nothing without a selected session or without an export seam
/// (the deployment composed none), turns into a spinner while the archive
/// streams, and announces the settled outcome through a snack bar — a
/// success names the location the platform wrote to, a failure is the
/// localized line (the cause itself is recorded in the error log).
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:app/ui/chat/chat_ui_state.dart';
import 'package:flutter/material.dart';

class SessionLogExportAction extends StatefulWidget {
  const SessionLogExportAction({
    required this.uiState,
    required this.onAction,
    super.key,
  });

  final ChatUiState uiState;
  final void Function(ChatAction) onAction;

  @override
  State<SessionLogExportAction> createState() => _SessionLogExportActionState();
}

class _SessionLogExportActionState extends State<SessionLogExportAction> {
  /// The export state this seat has already announced, so an unrelated
  /// rebuild of a settled export never re-fires the snack bar.
  SessionLogExportState? _announced;

  @override
  void initState() {
    super.initState();
    _announced = widget.uiState.sessionLogExport;
  }

  @override
  void didUpdateWidget(covariant SessionLogExportAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    final export = widget.uiState.sessionLogExport;
    if (export == null || export == _announced) return;
    _announced = export;
    if (export.phase == SessionLogExportPhase.exporting) return;
    // A snack bar cannot be shown during build; the settled state arrives
    // through one, so it waits for the frame to finish.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _announce(export);
    });
  }

  @override
  Widget build(BuildContext context) {
    final sessionId = widget.uiState.selectedSessionId;
    if (sessionId == null || !widget.uiState.canExportSessionLog) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context)!;
    if (widget.uiState.sessionLogExport?.phase ==
        SessionLogExportPhase.exporting) {
      final scheme = Theme.of(context).colorScheme;
      return SizedBox(
        width: 40,
        height: 40,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: scheme.primary,
            ),
          ),
        ),
      );
    }
    return IconButton(
      tooltip: l10n.sessionLogExportTooltip,
      onPressed: () => widget.onAction(ExportSessionLog(sessionId)),
      visualDensity: VisualDensity.compact,
      iconSize: 20,
      icon: const Icon(Icons.save_alt),
    );
  }

  void _announce(SessionLogExportState export) {
    final l10n = AppLocalizations.of(context)!;
    final location = export.location;
    final String? message = switch (export.phase) {
      SessionLogExportPhase.exporting => null,
      SessionLogExportPhase.saved =>
        location == null
            ? l10n.sessionLogExportFailed
            : l10n.sessionLogExportSaved(location),
      SessionLogExportPhase.failed => l10n.sessionLogExportFailed,
    };
    if (message == null) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
