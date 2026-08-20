/// Agent-preset seat — mobile port of the web AgentPresetSeat hero chip
/// (ui-agent-preset AgentPresetSeat.tsx): a chip beside the workspace
/// picker that stages the NEXT session's preset, plus the read-only
/// header label naming the preset THIS session runs. Broken presets are
/// never offered (they cannot compose a session); the deployment
/// default backs the staged choice until one is picked.
library;

import 'package:domain/model/agent_preset.dart';
import 'package:domain/model/session.dart';
import 'package:flutter/material.dart';

import '../shared/agent_preset_display.dart';
import '../theme/deepsuite_extension.dart'
    show dsOf, kDsShadowLv3;
import '../theme/deepsuite_tokens.dart' show kFontFamilyMonospace;

/// The roster a picker may offer: every entry that can compose a
/// session (broken ones cannot — offering one would only defer the
/// failure to the session start).
List<AgentPresetEntry> selectablePresets(AgentPresetRoster roster) =>
    roster.entries.where((entry) => entry.broken == null).toList();

/// Display label for one preset id against [roster]; the raw id when the
/// roster carries no such entry.
String presetIdLabel(AgentPresetRoster? roster, String presetId) {
  for (final entry in roster?.entries ?? const <AgentPresetEntry>[]) {
    if (entry.id == presetId) return agentPresetDisplayName(entry);
  }
  return presetId;
}

/// The chip's resolved preset id (web seat precedence): the staged pick
/// first, then the composition a blank selected session already
/// carries, then the deployment default.
String? stagedPresetId({
  required AgentPresetRoster? roster,
  required String? staged,
  required SessionSummary? selectedSession,
}) {
  return staged ??
      (selectedSession?.blank == true ? selectedSession?.agentPreset : null) ??
      roster?.defaultEntry?.id;
}

/// The hero chip. Renders nothing while the roster is missing or empty
/// (the deployment composes no presets — nothing to choose between).
class AgentPresetSeat extends StatelessWidget {
  const AgentPresetSeat({
    super.key,
    required this.roster,
    required this.currentId,
    required this.onSelect,
  });

  final AgentPresetRoster? roster;

  /// The preset id the chip shows (see [stagedPresetId]).
  final String? currentId;

  /// A pick's dispatch: stages the next session's preset or switches
  /// the current blank session's, per the caller's state.
  final void Function(String presetId) onSelect;

  @override
  Widget build(BuildContext context) {
    final options = selectablePresets(roster ?? const AgentPresetRoster());
    final current = currentId;
    if (roster == null || options.isEmpty || current == null) {
      return const SizedBox.shrink();
    }
    final ds = dsOf(context);
    final theme = Theme.of(context);
    return Tooltip(
      message: 'Agent preset for the session you are about to start',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _open(context, options),
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
                  Icons.smart_toy_outlined,
                  size: 16,
                  color: ds.labelSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  presetIdLabel(roster, current),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: ds.labelSecondary,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.keyboard_arrow_down,
                  size: 12,
                  color: ds.labelSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, List<AgentPresetEntry> options) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // Menu-surface sheet (ModelSelect vocabulary): menu fill, 12px
      // radius, lv3 elevation, 4px inner padding.
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: dsOf(sheetContext).menu,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: dsOf(sheetContext).borderInverted),
            boxShadow: kDsShadowLv3,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 440),
            child: _PresetSheet(
              options: options,
              currentId: currentId,
              onSelect: (presetId) {
                Navigator.of(sheetContext).pop();
                onSelect(presetId);
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// The roster picker: display name + description per row, the default
/// marked, the current one checked.
class _PresetSheet extends StatelessWidget {
  const _PresetSheet({
    required this.options,
    required this.currentId,
    required this.onSelect,
  });

  final List<AgentPresetEntry> options;
  final String? currentId;
  final void Function(String presetId) onSelect;

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
          child: Text('Agent preset', style: theme.textTheme.titleSmall),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final option in options)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => onSelect(option.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        agentPresetDisplayName(option),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              fontSize: 13,
                                              color:
                                                  theme.colorScheme.onSurface,
                                            ),
                                      ),
                                    ),
                                    if (option.isDefault) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 1,
                                        ),
                                        decoration: BoxDecoration(
                                          color: ds.bgLayer2,
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Text(
                                          'Default',
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                color: ds.labelSecondary,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                if (agentPresetDisplayDescription(option)
                                    case final String description)
                                  Text(
                                    description,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontSize: 12,
                                      color: ds.labelTertiary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (option.id == currentId)
                            Icon(
                              Icons.check,
                              size: 16,
                              color: theme.colorScheme.onSurface,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Read-only session-header label (web's third surface): the preset
/// THIS session runs, resolved against the roster — a control there
/// would promise a switch the host refuses for a started session.
/// Hidden while the session names no preset or the roster is unloaded.
class AgentPresetHeaderLabel extends StatelessWidget {
  const AgentPresetHeaderLabel({
    super.key,
    required this.session,
    required this.roster,
  });

  final SessionSummary? session;
  final AgentPresetRoster? roster;

  @override
  Widget build(BuildContext context) {
    final presetId = session?.agentPreset;
    // An empty roster means the deployment composes no presets — every
    // preset surface stays hidden.
    final entries = roster?.entries;
    if (presetId == null || entries == null || entries.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: dsOf(context).bgLayer2,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        presetIdLabel(roster, presetId),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontFamily: kFontFamilyMonospace,
        ),
      ),
    );
  }
}
