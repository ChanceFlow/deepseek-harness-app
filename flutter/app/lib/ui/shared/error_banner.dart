/// Inline failure strip — a localized sentence, the raw host detail as a
/// secondary monospace line, and the actions the owning controller can offer
/// (retry and/or dismiss).
///
/// The strip states a failure a surface holds; who owns it decides the
/// actions. A controller's failed action passes both, an Agent-level failure
/// the host reported passes none: that failure clears when the session
/// accepts a new prompt, so a close button would hide a fact that is still
/// true on the host.
///
/// [kShapeCard] and the `errorContainer` / `onErrorContainer` role pair are
/// the whole look; a caller places it, so the strip keeps no margin.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../theme/theme.dart';

class ErrorBanner extends StatelessWidget {
  const ErrorBanner({
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

  /// Dismiss affordance; null where the failure is not the app's to clear.
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
