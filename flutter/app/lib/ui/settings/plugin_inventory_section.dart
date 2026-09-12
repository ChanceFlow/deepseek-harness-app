/// Read-only plugin inventory for Settings.
///
/// One self-contained section over `pluginInventory/list`: the Cordis
/// Loader's current non-group entries and, when a roster is composed, every
/// agent preset's flattened composition. It writes nothing — enabling,
/// disabling, or configuring a plugin stays on the host.
///
/// Reference behavior:
/// `packages/client/ui-settings-plugin-inventory/src/client/
/// PluginInventorySettingsTab.tsx` renders a two-column card grid with a
/// preset switcher and a scope-grouped catalog. A phone cannot afford two
/// legible columns beside a tag and an id, so this surface adapts instead of
/// copying: one full-width disclosure row per entry, one expansion tile per
/// preset composition, and the reference's flat search result set while a
/// query is active. The searchable unit and tag vocabulary do not move.
library;

import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/plugin_inventory.dart';
import 'package:domain/repository/chat_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import '../shared/state_dot.dart';
import '../state_stream.dart';
import '../theme/theme.dart';
import 'settings_backend_scope.dart';
import 'settings_chrome.dart';

/// Page state for the inventory section.
///
/// The raw read failure never enters this state: the controller records it
/// with the error log and publishes only [failed], so no transport detail can
/// reach the rendered tree.
final class PluginInventoryUiState {
  const PluginInventoryUiState({
    this.isLoading = false,
    this.failed = false,
    this.snapshot,
    this.query = '',
  });

  /// A read is in flight.
  final bool isLoading;

  /// The last read failed; the surface shows its generic failure notice.
  final bool failed;

  /// The last good snapshot, or null while unloaded or after a failure.
  final PluginInventorySnapshot? snapshot;

  /// The current catalog query, lower-cased on write.
  final String query;
}

/// One controller per backend: it reads the inventory on construction and on
/// every retry, and holds the query the surface filters by.
class PluginInventoryController {
  PluginInventoryController(this._repository) {
    unawaited(_refreshNow());
  }

  final ChatRepository _repository;
  final AppStateStream<PluginInventoryUiState> _state =
      AppStateStream<PluginInventoryUiState>(const PluginInventoryUiState());

  bool _isLoading = false;
  bool _failed = false;
  PluginInventorySnapshot? _snapshot;
  String _query = '';

  PluginInventoryUiState get state => _state.value;
  Stream<PluginInventoryUiState> get uiState => _state.stream;

  void dispose() {}

  /// Filters the catalog by module name or entry id; an empty query restores
  /// the grouped catalog.
  void search(String query) {
    final String normalized = query.trim().toLowerCase();
    if (normalized == _query) return;
    _query = normalized;
    _publish();
  }

  /// Re-reads the whole snapshot.
  void refresh() {
    unawaited(_refreshNow());
  }

  Future<void> _refreshNow() async {
    _isLoading = true;
    _failed = false;
    _publish();
    try {
      final PluginInventorySnapshot snapshot = await _repository
          .listPluginInventory();
      _snapshot = snapshot;
      _failed = false;
    } catch (error, stackTrace) {
      // The failure is a fact for diagnostics only; the surface states it
      // without the transport text.
      _snapshot = null;
      _failed = true;
      ErrorLogCollector.instance.captureError(
        error,
        stackTrace: stackTrace,
        context: const <String, Object?>{
          'controller': 'PluginInventoryController',
          'action': 'refresh',
        },
      );
    } finally {
      _isLoading = false;
      _publish();
    }
  }

  void _publish() {
    _state.value = PluginInventoryUiState(
      isLoading: _isLoading,
      failed: _failed,
      snapshot: _snapshot,
      query: _query,
    );
  }
}

/// One controller per backend, disposed with the Settings surface.
final pluginInventoryControllerProvider = Provider.family
    .autoDispose<PluginInventoryController, String>((ref, backendId) {
      final controller = PluginInventoryController(
        ref.watch(chatRepositoryProvider(backendId)),
      );
      ref.onDispose(controller.dispose);
      return controller;
    });

/// The Settings mount point: the Loader entries and the agent-preset
/// compositions.
///
/// Self-contained: it watches its own controller for the scoped backend, so
/// a host mounts it as one child of the Settings list.
class SettingsPluginInventorySection extends ConsumerWidget {
  const SettingsPluginInventorySection({this.showTitle = true, super.key});

  /// False on the Plugin inventory page, whose app bar already names it.
  final bool showTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String backendId = ref.watch(settingsBackendScopeProvider);
    if (backendId.isEmpty) return const SizedBox.shrink();
    final PluginInventoryController controller = ref.watch(
      pluginInventoryControllerProvider(backendId),
    );
    return StreamBuilder<PluginInventoryUiState>(
      stream: controller.uiState,
      initialData: controller.state,
      builder:
          (BuildContext context, AsyncSnapshot<PluginInventoryUiState> snap) {
            final PluginInventoryUiState state = snap.data ?? controller.state;
            return _PluginInventoryCard(
              state: state,
              controller: controller,
              showTitle: showTitle,
            );
          },
    );
  }
}

/// Enablement one catalog row can report, after the failed phase wins.
enum _Enablement { enabled, disabled, conditional, failed }

/// One rendered catalog row: an entry or a preset composition row flattened
/// into the same tag/subtitle vocabulary.
final class _CatalogItem {
  const _CatalogItem({
    required this.moduleName,
    required this.entryId,
    required this.enablement,
    required this.phase,
    this.condition,
    this.scopeLabel,
  });

  final String moduleName;
  final String? entryId;
  final _Enablement enablement;
  final PluginFiberPhase? phase;
  final String? condition;

  /// The preset a search result came from; null for a global entry.
  final String? scopeLabel;

  /// Whether this row matches a lower-cased query over module name / id.
  bool matches(String normalizedQuery) {
    if (normalizedQuery.isEmpty) return true;
    if (moduleName.toLowerCase().contains(normalizedQuery)) return true;
    final String? id = entryId;
    return id != null && id.toLowerCase().contains(normalizedQuery);
  }
}

/// Compact a module specifier without guessing whether its Loader id was
/// generated (web `moduleShortName`).
String _moduleShortName(String moduleName) {
  final int slash = moduleName.indexOf('/');
  final String unscoped = moduleName.startsWith('@') && slash >= 0
      ? moduleName.substring(slash + 1)
      : moduleName;
  return unscoped
      .replaceFirst(RegExp('^cordis:'), '')
      .replaceFirst(RegExp('^cordis-plugin-'), '')
      .replaceFirst(RegExp('^dsh-(?:host-|client-)?'), '');
}

/// Display an entry identity without the composition-only `include:` marker
/// (web `entrySubtitle`); the query and tooltip keep the complete id.
String _entrySubtitle(String entryId) => entryId.startsWith('include:')
    ? entryId.substring('include:'.length)
    : entryId;

String _presetDisplayName(AgentPresetPluginGroup preset) {
  final String? name = preset.name;
  return name == null || name.isEmpty ? preset.id : name;
}

_Enablement _entryEnablement(PluginInventoryEntry entry) {
  if (entry.fiberPhase == PluginFiberPhase.failed) return _Enablement.failed;
  return entry.enabled ? _Enablement.enabled : _Enablement.disabled;
}

_Enablement _rowEnablement(AgentPresetPluginRow row) {
  if (row.fiberPhase == PluginFiberPhase.failed) return _Enablement.failed;
  return switch (row.enabled) {
    PresetRowEnablement.enabled => _Enablement.enabled,
    PresetRowEnablement.disabled => _Enablement.disabled,
    PresetRowEnablement.conditional => _Enablement.conditional,
  };
}

_CatalogItem _entryItem(PluginInventoryEntry entry) => _CatalogItem(
  moduleName: entry.moduleName,
  entryId: entry.entryId,
  enablement: _entryEnablement(entry),
  phase: entry.fiberPhase,
);

_CatalogItem _presetItem(
  AgentPresetPluginGroup preset,
  AgentPresetPluginRow row,
) => _CatalogItem(
  moduleName: row.moduleName,
  entryId: row.entryId,
  enablement: _rowEnablement(row),
  phase: row.fiberPhase,
  condition: row.condition,
  scopeLabel: _presetDisplayName(preset),
);

StateDotState _phaseDotState(PluginFiberPhase phase) => switch (phase) {
  PluginFiberPhase.pending => StateDotState.disabled,
  PluginFiberPhase.loading => StateDotState.ongoing,
  PluginFiberPhase.active => StateDotState.done,
  PluginFiberPhase.failed => StateDotState.error,
  PluginFiberPhase.unloading => StateDotState.ongoing,
};

String _phaseLabel(AppLocalizations l10n, PluginFiberPhase phase) =>
    switch (phase) {
      PluginFiberPhase.pending => l10n.pluginInventoryPhasePending,
      PluginFiberPhase.loading => l10n.pluginInventoryPhaseLoading,
      PluginFiberPhase.active => l10n.pluginInventoryPhaseActive,
      PluginFiberPhase.failed => l10n.pluginInventoryPhaseFailed,
      PluginFiberPhase.unloading => l10n.pluginInventoryPhaseUnloading,
    };

String _enablementLabel(AppLocalizations l10n, _Enablement enablement) =>
    switch (enablement) {
      _Enablement.enabled => l10n.pluginInventoryEnabledTag,
      _Enablement.disabled => l10n.pluginInventoryDisabledTag,
      _Enablement.conditional => l10n.pluginInventoryConditionalTag,
      _Enablement.failed => l10n.pluginInventoryFailedTag,
    };

/// The section card: heading, the read-only notice, the search field, then
/// loading / failure / empty / no-match / catalog.
class _PluginInventoryCard extends StatelessWidget {
  const _PluginInventoryCard({
    required this.state,
    required this.controller,
    required this.showTitle,
  });

  final PluginInventoryUiState state;
  final PluginInventoryController controller;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SettingsSectionHeading(
          title: l10n.settingsSectionPluginInventory,
          intro: l10n.pluginInventoryIntro,
          showTitle: showTitle,
        ),
        SettingsSectionCard(
          children: <Widget>[
            // The one fact the surface owes every reader: it cannot write.
            _CardNotice(l10n.pluginInventoryReadOnlyNotice),
            const SettingsCardDivider(),
            if (state.snapshot != null) ...<Widget>[
              _SearchField(controller: controller, l10n: l10n),
              const SettingsCardDivider(),
            ],
            ..._body(l10n),
          ],
        ),
      ],
    );
  }

  List<Widget> _body(AppLocalizations l10n) {
    if (state.failed) {
      return <Widget>[_FailureNotice(l10n: l10n, onRetry: controller.refresh)];
    }
    final PluginInventorySnapshot? snapshot = state.snapshot;
    if (snapshot == null) {
      return <Widget>[_LoadingNotice(l10n: l10n)];
    }
    if (snapshot.entries.isEmpty && snapshot.agentPresets.isEmpty) {
      return <Widget>[_CardNotice(l10n.pluginInventoryEmpty)];
    }
    if (state.query.isNotEmpty) {
      final List<_CatalogItem> matches = <_CatalogItem>[
        for (final _CatalogItem item in _allItems(snapshot))
          if (item.matches(state.query)) item,
      ];
      if (matches.isEmpty) {
        return <Widget>[_CardNotice(l10n.pluginInventoryNoMatch)];
      }
      return <Widget>[
        for (final _CatalogItem item in matches) _PluginTile(item: item),
      ];
    }
    return _grouped(snapshot, l10n);
  }

  List<_CatalogItem> _allItems(PluginInventorySnapshot snapshot) =>
      <_CatalogItem>[
        for (final PluginInventoryEntry entry in snapshot.entries)
          _entryItem(entry),
        for (final AgentPresetPluginGroup preset in snapshot.agentPresets)
          for (final AgentPresetPluginRow row in preset.rows)
            _presetItem(preset, row),
      ];

  List<Widget> _grouped(
    PluginInventorySnapshot snapshot,
    AppLocalizations l10n,
  ) {
    final List<AgentPresetPluginGroup> presets = snapshot.agentPresets;
    final List<Widget> groups = <Widget>[];
    if (presets.isNotEmpty) {
      groups.add(
        _GroupTile(
          title: l10n.pluginInventoryPresetGroupTitle,
          subtitle: l10n.pluginInventoryPresetGroupIntro,
          // The reference opens the preset plane by default; the global
          // plane waits behind its own disclosure.
          initiallyExpanded: true,
          children: <Widget>[
            for (final AgentPresetPluginGroup preset in presets)
              _PresetTile(preset: preset),
          ],
        ),
      );
    }
    if (snapshot.entries.isNotEmpty) {
      final int failedCount = snapshot.entries
          .where(
            (PluginInventoryEntry entry) =>
                entry.fiberPhase == PluginFiberPhase.failed,
          )
          .length;
      groups.add(
        _GroupTile(
          title: l10n.pluginInventoryGlobalGroupTitle,
          subtitle: l10n.pluginInventoryGlobalGroupIntro,
          count: l10n.pluginInventoryPluginCount(snapshot.entries.length),
          failedCount: failedCount == 0
              ? null
              : l10n.pluginInventoryFailedCount(failedCount),
          initiallyExpanded: presets.isEmpty,
          children: <Widget>[
            for (final PluginInventoryEntry entry in snapshot.entries)
              _PluginTile(item: _entryItem(entry)),
          ],
        ),
      );
    }
    return groups;
  }
}

/// The catalog query, filtered client-side over module name and entry id.
class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.l10n});

  final PluginInventoryController controller;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: TextField(
        onChanged: controller.search,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          isDense: true,
          hintText: l10n.pluginInventorySearchHint,
          prefixIcon: Icon(Icons.search, color: scheme.onSurfaceVariant),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(kShapeChip),
            borderSide: BorderSide(color: scheme.outlineVariant),
          ),
        ),
      ),
    );
  }
}

/// An [ExpansionTile] that builds its body only while open.
///
/// The framework tile keeps its collapsed children mounted and offstage, so a
/// 160-entry global plane would build every row's facts at Settings mount.
/// This wrapper gates the body on the tile's own expansion signal and leaves
/// the tile component in charge of the row, chevron, and animation.
class _Disclosure extends StatefulWidget {
  const _Disclosure({
    required this.title,
    required this.children,
    this.subtitle,
    this.leading,
    this.initiallyExpanded = false,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final List<Widget> children;
  final bool initiallyExpanded;

  @override
  State<_Disclosure> createState() => _DisclosureState();
}

class _DisclosureState extends State<_Disclosure> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      shape: const Border(),
      collapsedShape: const Border(),
      initiallyExpanded: widget.initiallyExpanded,
      leading: widget.leading,
      title: widget.title,
      subtitle: widget.subtitle,
      onExpansionChanged: (bool expanded) {
        setState(() => _expanded = expanded);
      },
      children: _expanded ? widget.children : const <Widget>[],
    );
  }
}

/// One scope group ("Session plugins" / "Global plugins").
class _GroupTile extends StatelessWidget {
  const _GroupTile({
    required this.title,
    required this.subtitle,
    required this.initiallyExpanded,
    required this.children,
    this.count,
    this.failedCount,
  });

  final String title;
  final String subtitle;
  final bool initiallyExpanded;
  final List<Widget> children;
  final String? count;
  final String? failedCount;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return _Disclosure(
      initiallyExpanded: initiallyExpanded,
      title: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: <Widget>[
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (count != null)
            Text(
              count!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          if (failedCount != null)
            Text(
              failedCount!,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
        ],
      ),
      children: children,
    );
  }
}

/// One agent preset's composition: identity, trust, and its plugin rows.
class _PresetTile extends StatelessWidget {
  const _PresetTile({required this.preset});

  final AgentPresetPluginGroup preset;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String? broken = preset.broken;
    return _Disclosure(
      initiallyExpanded: preset.isDefault,
      title: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              _presetDisplayName(preset),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurface,
              ),
            ),
          ),
          if (preset.isDefault) ...<Widget>[
            const SizedBox(width: 8),
            _Chip(
              label: l10n.pluginInventoryDefaultBadge,
              foreground: scheme.onPrimaryContainer,
              background: scheme.primaryContainer,
            ),
          ],
        ],
      ),
      subtitle: Text(
        <String>[
          preset.trust == 'system'
              ? l10n.presetGroupBuiltIn
              : l10n.presetGroupCustom,
          l10n.pluginInventoryPluginCount(preset.rows.length),
        ].join(' · '),
        style: theme.textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      children: <Widget>[
        if (broken != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              '${l10n.pluginInventoryPresetBrokenLabel}: $broken',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ),
        for (final AgentPresetPluginRow row in preset.rows)
          _PluginTile(item: _presetItem(preset, row)),
      ],
    );
  }
}

/// One catalog row: short module name, enablement tag, the entry id as a
/// secondary detail, and the phase/condition facts behind a disclosure.
class _PluginTile extends StatelessWidget {
  const _PluginTile({required this.item});

  final _CatalogItem item;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String? entryId = item.entryId;
    final String? scopeLabel = item.scopeLabel;
    final String? displayId = entryId == null ? null : _entrySubtitle(entryId);
    final String subtitle = <String>[
      if (scopeLabel != null) scopeLabel,
      if (displayId != null) displayId,
    ].join(' · ');
    final PluginFiberPhase? phase = item.phase;
    // `active` is the settled healthy phase: a dot for it would only repeat
    // the enabled tag. Every other live phase earns the collapsed marker,
    // and `failed` already carries the error-colored tag.
    final PluginFiberPhase? markedPhase =
        phase != null && phase != PluginFiberPhase.active ? phase : null;
    final Widget subtitleText = Text(
      subtitle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(
        color: scheme.onSurfaceVariant,
        fontFamily: 'monospace',
      ),
    );
    return _Disclosure(
      leading: markedPhase == null
          ? null
          : StateDot(state: _phaseDotState(markedPhase), size: 8),
      title: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              _moduleShortName(item.moduleName),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _Chip(
            label: _enablementLabel(l10n, item.enablement),
            foreground: _enablementColor(scheme, item.enablement),
          ),
        ],
      ),
      subtitle: subtitle.isEmpty
          ? null
          : entryId == null
          ? subtitleText
          : Tooltip(message: entryId, child: subtitleText),
      children: <Widget>[
        _DetailFact(
          label: l10n.pluginInventoryModuleLabel,
          value: item.moduleName,
          monospace: true,
        ),
        if (phase != null)
          _DetailFact(
            label: l10n.pluginInventoryStatusLabel,
            value: _phaseLabel(l10n, phase),
          ),
        if (item.condition != null)
          _DetailFact(
            label: l10n.pluginInventoryConditionLabel,
            value: item.condition!,
            monospace: true,
          ),
      ],
    );
  }
}

Color _enablementColor(ColorScheme scheme, _Enablement enablement) =>
    switch (enablement) {
      _Enablement.enabled => scheme.success,
      _Enablement.disabled => scheme.onSurfaceVariant,
      _Enablement.conditional => scheme.warning,
      _Enablement.failed => scheme.error,
    };

/// One labeled fact inside an expanded row.
class _DetailFact extends StatelessWidget {
  const _DetailFact({
    required this.label,
    required this.value,
    this.monospace = false,
  });

  final String label;
  final String value;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurface,
                fontFamily: monospace ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The enablement tag: the one datum a collapsed row must state.
class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.foreground, this.background});

  final String label;
  final Color foreground;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background ?? foreground.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(kShapeChip),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: foreground),
      ),
    );
  }
}

/// The read in flight: a hairline bar and the state's name.
class _LoadingNotice extends StatelessWidget {
  const _LoadingNotice({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const LinearProgressIndicator(
            minHeight: 2,
            backgroundColor: Colors.transparent,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.pluginInventoryLoading,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// The generic failure state: a localized message and Retry, never the
/// transport's own text.
class _FailureNotice extends StatelessWidget {
  const _FailureNotice({required this.l10n, required this.onRetry});

  final AppLocalizations l10n;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              l10n.pluginInventoryLoadFailed,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton(onPressed: onRetry, child: Text(l10n.retry)),
        ],
      ),
    );
  }
}

class _CardNotice extends StatelessWidget {
  const _CardNotice(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Text(
        message,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
