/// Composer-takeover approval panel — port of the web ApprovalPanel
/// (draft approval.png): the InputBar footprint swaps to an error-tinted
/// card with a "Waiting for approval" strip, the justification headline,
/// and right-aligned Reject / Allow once actions.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'chat_ui_state.dart';

class ApprovalPanel extends StatelessWidget {
  const ApprovalPanel({
    super.key,
    required this.request,
    required this.onAction,
  });

  final TimelineApprovalRequest request;
  final void Function(ChatAction) onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.errorContainer),
        boxShadow: kM3ShadowElevation1,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tinted full-width header band.
          Container(
            width: double.infinity,
            color: scheme.errorContainer,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: scheme.error,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.waitingForApproval,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.error,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => onAction(
                    RespondApproval(
                      requestId: request.requestId,
                      approvalId: request.approvalId,
                      allowed: false,
                    ),
                  ),
                  child: Text(l10n.reject),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => onAction(
                    RespondApproval(
                      requestId: request.requestId,
                      approvalId: request.approvalId,
                      allowed: true,
                    ),
                  ),
                  child: Text(l10n.allowOnce),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
