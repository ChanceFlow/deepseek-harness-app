/// Empty-state hero — port of the web EmptyHero/HeroShell: fish headline,
/// soft blue glow, and the workspace chip over the blank draft.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/agent_preset.dart';
import 'package:domain/model/workspace.dart';
import 'package:flutter/material.dart';

import 'fish_logo.dart';
import 'preset_seat.dart';

class EmptyHero extends StatelessWidget {
  const EmptyHero({
    super.key,
    required this.workspaces,
    required this.onPickWorkspace,
    this.currentWorkspaceLabel,
    this.presetRoster,
    this.currentPresetId,
    this.onPickPreset,
  });

  final List<WorkspaceSummary> workspaces;
  final void Function(String workspaceId) onPickWorkspace;

  /// Active draft workspace label; null renders the placeholder chip.
  final String? currentWorkspaceLabel;

  /// Agent-preset roster and the id the seat shows; a null roster
  /// (unloaded, or a deployment composing no presets) hides the chip.
  final AgentPresetRoster? presetRoster;
  final String? currentPresetId;

  /// A preset pick's dispatch (stage the next session or switch the
  /// current blank one, per the owner's state).
  final void Function(String presetId)? onPickPreset;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Stack(
      children: [
        // figma 313:14109 — soft brand ellipse behind the headline.
        Positioned.fill(
          child: IgnorePointer(
            child: Align(
              alignment: const Alignment(0, 0.55),
              child: AspectRatio(
                aspectRatio: 1051 / 468,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    // Wide ellipse approximation via a scaled radial fill.
                    shape: BoxShape.rectangle,
                    gradient: RadialGradient(
                      colors: [
                        scheme.primary.withValues(alpha: 0.08),
                        scheme.primary.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // The hero sits low, near the composer it is asking the reader to
        // use: the transcript grows upward from there, so the first
        // message lands where the headline was.
        Align(
          alignment: const Alignment(0, 0.55),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // figma 34:10412 — fish 34×25 leading the headline, gap 10.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FishLogo(size: 34, color: theme.colorScheme.onSurface),
                    const SizedBox(width: 10),
                    Text(
                      l10n.heroHeadline,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        l10n.heroPreview,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Web HeroShell: the preset seat rides beside the workspace
              // picker, same chip family.
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  WorkspaceChip(
                    workspaces: workspaces,
                    label: currentWorkspaceLabel,
                    onPickWorkspace: onPickWorkspace,
                  ),
                  AgentPresetSeat(
                    roster: presetRoster,
                    currentId: currentPresetId,
                    onSelect: onPickPreset ?? (_) {},
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Folder + label + chevron; opens the workspace menu (web WorkspaceChip).
class WorkspaceChip extends StatelessWidget {
  const WorkspaceChip({
    super.key,
    required this.workspaces,
    required this.onPickWorkspace,
    this.label,
  });

  final List<WorkspaceSummary> workspaces;
  final void Function(String workspaceId) onPickWorkspace;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final resolvedLabel = label ?? l10n.heroChooseWorkspace;
    return PopupMenuButton<String>(
      tooltip: l10n.heroChooseWorkspace,
      onSelected: onPickWorkspace,
      itemBuilder: (context) => [
        for (final workspace in workspaces)
          PopupMenuItem(
            value: workspace.workspaceId,
            child: Text('${workspace.title} — ${workspace.path}'),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              label == null
                  ? Icons.folder_outlined
                  : Icons.folder_open_outlined,
              size: 16,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              resolvedLabel,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down,
              size: 12,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
