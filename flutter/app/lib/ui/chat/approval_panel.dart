/// Approval card → detail: the dock keeps one line, the request opens a sheet.
///
/// The reference renders the approval as a composer-seat takeover
/// (`ui-approval/src/client/index.ts:91` registers `ApprovalPanel` on
/// `conversation.composer`), so the seat stays ours too. What changes is where
/// the request's body lives: the card is one line — "Waiting for approval", the
/// justification's first line, and Allow once — and the paired command, the
/// privileged-tool line and the two seats open on a large decision sheet, with
/// Reject and Allow once pinned at its bottom. A command can be a page long and
/// the dock sits above the navigation bar, so the block belongs on its own
/// surface rather than in the composer seat.
library;

import 'dart:convert';

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'card_detail.dart';
import 'chat_ui_state.dart';

/// Extract the shell command from an approval's paired running call
/// (bash-family args carry `command`); null hides the line.
/// Port of web `commandOf(call: RunningToolCall | undefined)`.
String? commandOf(TimelineToolCall? call) {
  if (call == null) return null;
  final raw = call.arguments;
  if (raw == null || raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map && decoded['command'] is String) {
      final cmd = decoded['command'] as String;
      return cmd.isNotEmpty ? cmd : null;
    }
  } catch (_) {
    // Unparseable model args: the panel still renders, just without the command line.
    return null;
  }
  return null;
}

/// The approval's one-line card: the wait, the justification's first line, and
/// the primary answer. Tapping it opens the request's own surface.
class ApprovalRow extends StatelessWidget {
  const ApprovalRow({
    required this.request,
    required this.onAction,
    this.command,
    super.key,
  });

  final TimelineApprovalRequest request;
  final String? command;
  final void Function(ChatAction) onAction;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final reason = request.reason ?? l10n.approveToolFallback(request.toolName);
    return CardDetailRow(
      icon: Icons.shield_outlined,
      title: l10n.waitingForApproval,
      summary: _firstLine(reason),
      trailing: FilledButton(
        onPressed: () => onAction(
          RespondApproval(
            requestId: request.requestId,
            approvalId: request.approvalId,
            allowed: true,
          ),
        ),
        style: FilledButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: Text(l10n.allowOnce),
      ),
      onOpen: () => showCardDetailSheet<void>(
        context,
        builder: (sheetContext) => ApprovalDecisionSheet(
          request: request,
          command: command,
          onAction: onAction,
        ),
      ),
    );
  }
}

/// The approval's detail surface: the whole justification and the paired
/// command above, the two answers pinned at the bottom of the sheet.
class ApprovalDecisionSheet extends StatelessWidget {
  const ApprovalDecisionSheet({
    required this.request,
    required this.onAction,
    this.command,
    super.key,
  });

  final TimelineApprovalRequest request;
  final String? command;
  final void Function(ChatAction) onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final commandText = command;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // The wait's own strip, on the failure tone the request wears: the
          // sheet's body is the request, and the reader has to see at a glance
          // that this is the decision blocking the session.
          Container(
            color: scheme.errorContainer,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Row(
              children: <Widget>[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: scheme.error,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.waitingForApproval,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    request.reason ??
                        l10n.approveToolFallback(request.toolName),
                    style: theme.textTheme.bodyMedium,
                  ),
                  Text(
                    l10n.toolRequestsPrivileged(request.toolName),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (commandText != null && commandText.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SelectableText(
                      commandText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFamily: kCodeFontFamily,
                        fontFamilyFallback: kCodeFontFamilyFallback,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          CardDetailActionBar(
            actions: <Widget>[
              OutlinedButton(
                onPressed: () {
                  onAction(
                    RespondApproval(
                      requestId: request.requestId,
                      approvalId: request.approvalId,
                      allowed: false,
                    ),
                  );
                  Navigator.of(context).pop();
                },
                child: Text(l10n.reject),
              ),
              FilledButton(
                onPressed: () {
                  onAction(
                    RespondApproval(
                      requestId: request.requestId,
                      approvalId: request.approvalId,
                      allowed: true,
                    ),
                  );
                  Navigator.of(context).pop();
                },
                child: Text(l10n.allowOnce),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The row's one summary line: the first non-empty line of [text].
String _firstLine(String text) {
  for (final line in text.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isNotEmpty) return trimmed;
  }
  return text.trim();
}
