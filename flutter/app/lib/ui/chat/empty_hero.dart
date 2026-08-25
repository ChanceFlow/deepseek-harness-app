/// Empty-state hero — port of the web EmptyHero/HeroShell: fish headline,
/// soft blue glow, and the workspace chip over the blank draft.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/agent_preset.dart';
import 'package:domain/model/workspace.dart';
import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'fish_logo.dart';
import 'preset_seat.dart';

class EmptyHero extends StatelessWidget {
  const EmptyHero({
    required this.workspaces,
    required this.onPickWorkspace,
    super.key,
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
    required this.workspaces,
    required this.onPickWorkspace,
    super.key,
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
    return Tooltip(
      message: l10n.heroChooseWorkspace,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _open(context),
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
                  color: label == null
                      ? scheme.onSurfaceVariant
                      : scheme.primary,
                ),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: Text(
                    resolvedLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
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
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final scheme = Theme.of(sheetContext).colorScheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: scheme.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outlineVariant),
              boxShadow: kM3ShadowElevation3,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 440),
              child: _WorkspaceSheet(
                workspaces: workspaces,
                currentLabel: label,
                onPickWorkspace: (workspaceId) {
                  Navigator.of(sheetContext).pop();
                  onPickWorkspace(workspaceId);
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WorkspaceSheet extends StatelessWidget {
  const _WorkspaceSheet({
    required this.workspaces,
    required this.currentLabel,
    required this.onPickWorkspace,
  });

  final List<WorkspaceSummary> workspaces;
  final String? currentLabel;
  final void Function(String workspaceId) onPickWorkspace;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.folder_outlined, size: 16, color: scheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    l10n.heroChooseWorkspace,
                    style: theme.textTheme.titleSmall,
                  ),
                ],
              ),
              if (workspaces.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${workspaces.length}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (workspaces.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.folder_off_outlined,
                    size: 32,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.noWorkspacesRegistered,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.noWorkspacesRegisteredBody,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: workspaces.length,
              itemBuilder: (context, index) {
                final workspace = workspaces[index];
                final isSelected = currentLabel == workspace.title;
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => onPickWorkspace(workspace.workspaceId),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? scheme.primaryContainer
                                  : scheme.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              isSelected
                                  ? Icons.folder_open_rounded
                                  : Icons.folder_outlined,
                              size: 18,
                              color: isSelected
                                  ? scheme.onPrimaryContainer
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  workspace.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13.5,
                                    color: scheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  workspace.path,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 11.5,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            Icon(
                              Icons.check_circle_rounded,
                              size: 18,
                              color: scheme.primary,
                            )
                          else if (workspace.sessionIds.isNotEmpty)
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
                                '${workspace.sessionIds.length}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontSize: 10,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
