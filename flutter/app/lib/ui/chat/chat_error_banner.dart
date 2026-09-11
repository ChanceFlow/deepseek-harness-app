/// Inline chat failure strip — the localized sentence plus the retry and
/// dismiss actions the controller already exposes ([RetrySessions] and
/// [DismissError]).
///
/// [describeChatError] turns the controller's machine error into a sentence
/// a reader can act on: the one failure class the controller names
/// (`SESSION_ALREADY_OWNED`) keeps its specific copy, every other failure
/// reads the generic localized headline with the raw host detail kept as a
/// secondary line instead of the whole message.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// Localized headline plus the optional raw host detail.
typedef ChatErrorCopy = ({String message, String? detail});

/// Maps a controller `errorMessage` to user-facing copy.
ChatErrorCopy describeChatError(AppLocalizations l10n, String error) {
  if (error == 'SESSION_ALREADY_OWNED' ||
      error.contains('session-persistence/already-owned') ||
      error.contains('SessionAlreadyOwned')) {
    return (message: l10n.sessionAlreadyOwnedError, detail: null);
  }
  final detail = error.trim();
  return (
    message: l10n.chatActionFailed,
    detail: detail.isEmpty ? null : detail,
  );
}

class ChatErrorBanner extends StatelessWidget {
  const ChatErrorBanner({
    required this.message,
    super.key,
    this.detail,
    this.onRetry,
    this.onDismiss,
  });

  /// Localized headline sentence.
  final String message;

  /// Raw host detail; null when the headline says everything.
  final String? detail;

  /// Retry affordance; null where retrying the action is not meaningful.
  final VoidCallback? onRetry;

  /// Dispatches the controller's dismiss action; null where the failure is
  /// not the app's to clear — an Agent-level failure clears when the session
  /// accepts a new prompt, so the strip carries no close affordance.
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(kShapeCard),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onErrorContainer,
                  ),
                ),
                if (detail case final detail?)
                  Text(
                    detail,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontFamily: 'monospace',
                      color: scheme.onErrorContainer,
                    ),
                  ),
              ],
            ),
          ),
          if (onRetry case final retry?)
            TextButton(
              onPressed: retry,
              style: TextButton.styleFrom(
                foregroundColor: scheme.onErrorContainer,
                visualDensity: VisualDensity.compact,
              ),
              child: Text(l10n.retry),
            ),
          if (onDismiss case final dismiss?)
            IconButton(
              tooltip: l10n.dismiss,
              visualDensity: VisualDensity.compact,
              onPressed: dismiss,
              icon: Icon(Icons.close, size: 18, color: scheme.onErrorContainer),
            ),
        ],
      ),
    );
  }
}
