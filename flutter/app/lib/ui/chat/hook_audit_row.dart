/// Hook-audit row — the transcript seat for one `hook/invoked` + `hook/result`
/// pair.
///
/// The reference marks these events log-only (`packages/hooks/hook-protocol/
/// src/events.ts`: not a `SurfaceEventType`), so the web client renders no
/// row for them at all. This row exists because the failure it explains is
/// otherwise unattributable: a blocking `PreToolUse` deny reaches the
/// transcript as an error tool row, with nothing saying a hook — not the
/// tool, not the host — refused the call.
///
/// Placement is therefore inline in the turn, at the audit's own log
/// position, collapsed to one line and never expanded by default. A ledger
/// seat (the trajectory screen) was rejected: the ledger's flat record row
/// cannot carry the decision/exit/duration facts as separate fields, and a
/// deny's whole value is its adjacency to the tool row it explains.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/hook.dart';
import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// One hook audit, collapsed to its point and verdict.
class HookAuditRow extends StatefulWidget {
  const HookAuditRow({
    required this.audit,
    super.key,
    this.initiallyExpanded = false,
  });

  final HookAudit audit;

  /// Whether the detail panel starts open. False is the default: the
  /// collapsed row already names the verdict a reader scans for.
  final bool initiallyExpanded;

  @override
  State<HookAuditRow> createState() => _HookAuditRowState();
}

class _HookAuditRowState extends State<HookAuditRow> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final audit = widget.audit;
    // `decision` is null exactly while only `hook/invoked` has folded; the
    // row states that rather than guessing a verdict.
    final decision = audit.decision;
    final denied = decision == 'deny';
    final verdictColor = denied ? scheme.error : scheme.onSurfaceVariant;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(kShapeChip),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    Icons.webhook_outlined,
                    size: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      audit.point,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      decision == null
                          ? l10n.hookAuditPending
                          : l10n.hookAuditDecision(decision),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        height: 1.2,
                        fontWeight: denied ? FontWeight.w600 : null,
                        color: verdictColor,
                      ),
                    ),
                  ),
                  if (audit.durationMs case final durationMs?) ...[
                    Text(
                      l10n.hookAuditDurationMs(durationMs),
                      style: theme.textTheme.labelSmall?.copyWith(
                        height: 1.2,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Icon(
                    _expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DetailLine(label: l10n.hookAuditPoint, value: audit.point),
                  _DetailLine(
                    label: l10n.hookAuditDialect,
                    value: hookDialectLabel(audit.dialect, l10n),
                  ),
                  if (audit.matcher case final matcher?)
                    _DetailLine(label: l10n.hookAuditMatcher, value: matcher),
                  _DetailLine(
                    label: l10n.hookAuditDecisionLabel,
                    value: decision == null
                        ? l10n.hookAuditPending
                        : l10n.hookAuditDecision(decision),
                  ),
                  _DetailLine(
                    label: l10n.hookAuditExitCode,
                    value: audit.exitCode?.toString() ?? l10n.hookAuditUnknown,
                  ),
                  _DetailLine(
                    label: l10n.hookAuditStderr,
                    value: audit.stderrSummary ?? l10n.hookAuditNoStderr,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// One label/value line of the expanded audit. The value wraps rather than
/// truncating: a stderr summary is the reader's only window onto why a hook
/// refused.
class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The bridge dialect (`HookDialect`) as a label. The enum is closed and the
/// adapter fails loud on an unknown wire literal, so this switch is
/// exhaustive by construction.
String hookDialectLabel(HookDialect dialect, AppLocalizations l10n) =>
    switch (dialect) {
      HookDialect.claudeCode => l10n.hookDialectClaudeCode,
      HookDialect.codex => l10n.hookDialectCodex,
    };
