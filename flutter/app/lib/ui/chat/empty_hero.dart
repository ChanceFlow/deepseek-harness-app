/// Empty-state hero — port of the web EmptyHero/HeroShell: fish headline,
/// soft blue glow, and the workspace chip over the blank draft.
library;

import 'package:domain/model/workspace.dart';
import 'package:flutter/material.dart';

import '../theme/deepsuite_extension.dart';
import 'fish_logo.dart';

/// Web `hero.*` locale strings (English seat).
const String kHeroHeadline = 'Into the Unknown';
const String kHeroPreview = 'Preview';
const String kHeroChooseWorkspace = 'Choose workspace';

class EmptyHero extends StatelessWidget {
  const EmptyHero({
    super.key,
    required this.workspaces,
    required this.onPickWorkspace,
    this.currentWorkspaceLabel,
  });

  final List<WorkspaceSummary> workspaces;
  final void Function(String workspaceId) onPickWorkspace;

  /// Active draft workspace label; null renders the placeholder chip.
  final String? currentWorkspaceLabel;

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    final theme = Theme.of(context);
    return Stack(
      children: [
        // figma 313:14109 — soft blue ellipse behind the headline.
        const Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1051 / 468,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    // Wide ellipse approximation via a scaled radial fill.
                    shape: BoxShape.rectangle,
                    gradient: RadialGradient(
                      colors: [Color(0x146187D8), Color(0x006187D8)],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Center(
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
                      kHeroHeadline,
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
                        color: ds.bgLayer2,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        kHeroPreview,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: ds.labelSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              WorkspaceChip(
                workspaces: workspaces,
                label: currentWorkspaceLabel,
                onPickWorkspace: onPickWorkspace,
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
    final ds = dsOf(context);
    final theme = Theme.of(context);
    final resolvedLabel = label ?? kHeroChooseWorkspace;
    return PopupMenuButton<String>(
      tooltip: kHeroChooseWorkspace,
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
          color: ds.bgLayer1,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: ds.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              label == null
                  ? Icons.folder_outlined
                  : Icons.folder_open_outlined,
              size: 16,
              color: ds.labelSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              resolvedLabel,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: ds.labelSecondary,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down, size: 12, color: ds.labelSecondary),
          ],
        ),
      ),
    );
  }
}
