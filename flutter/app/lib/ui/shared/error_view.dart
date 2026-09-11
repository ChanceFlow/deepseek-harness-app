/// Full-screen failure surface shared by the routed screens: a localized
/// sentence, an error glyph, and an optional retry action. A screen whose
/// async state fails renders this instead of a raw `error.toString()`, so
/// the reader gets a sentence they can act on rather than a Dart
/// exception dump.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

class LocalizedErrorView extends StatelessWidget {
  const LocalizedErrorView({required this.message, super.key, this.onRetry});

  /// Already-localized human sentence describing the failure.
  final String message;

  /// Retry affordance; null renders the message alone (a failure with no
  /// meaningful retry).
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 40, color: scheme.error),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurface,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(l10n.retry),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: scheme.outlineVariant),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
