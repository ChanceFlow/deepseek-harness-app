/// Composer-takeover card for a pending dynamic-Cordis plugin activation
/// request (`cordis/request-run`) — the same seat and card family as
/// [ApprovalPanel]: the composer footprint swaps to an error-tinted card
/// while the host blocks a `cordis_run` / `cordis_define` tool call on a
/// human decision.
///
/// Only rejection is offered, and the card says why: an approval's `ok:true`
/// arm must name the exact Client activation (`pluginRunId`) the answering
/// page created or attached to, and only a browser plugin runtime can
/// produce one. A native client that faked an approval would be lying to the
/// host. A rejection needs no such identity, refuses both halves, and is the
/// answer that releases the blocked tool call.
///
/// A request whose `requiresApproval` is false never mounts this card: the
/// host already started its own half and only needs a browser page to
/// attach the Client half, so there is no pending user decision to show and
/// nothing a Reject would release (`ChatScreen._pendingCordisRequest`).
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/cordis.dart';
import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'chat_ui_state.dart';

class CordisRequestPanel extends StatelessWidget {
  const CordisRequestPanel({
    required this.request,
    required this.onAction,
    super.key,
  });

  final CordisRunRequest request;
  final void Function(ChatAction) onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kShapeDock),
        border: Border.all(color: scheme.errorContainer),
        boxShadow: kM3ShadowElevation1,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tinted full-width header band, the approval card's family.
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
                Expanded(
                  child: Text(
                    l10n.cordisApprovalHeader,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.error,
                    ),
                  ),
                ),
                _ModeChip(mode: request.mode),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    request.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.cordisPurposeLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  Text(request.purpose, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  _DetailLine(
                    label: l10n.cordisPluginIdLabel,
                    value: request.pluginId,
                  ),
                  const SizedBox(height: 4),
                  _DetailLine(
                    label: l10n.cordisPackageIdLabel,
                    value: request.packageId,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.cordisRejectOnlyNotice,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => onAction(RejectCordisRun(request.requestId)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: scheme.error,
                  ),
                  child: Text(l10n.reject),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The activation's lifecycle intent (`run` / `update`) as a compact chip.
class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.mode});

  final CordisRunMode mode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final label = switch (mode) {
      CordisRunMode.run => l10n.cordisModeRun,
      CordisRunMode.update => l10n.cordisModeUpdate,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(kShapeChip),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// One label/value identity row; the value is selectable so a reader can
/// copy a plugin or package id into a report.
class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 84,
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            maxLines: 2,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
