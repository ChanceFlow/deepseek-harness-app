/// Settings screen — Flutter port of the dsh web settings surface.
///
/// Translates the web settings panel (ui-settings shell plus the
/// ui-settings-general / -models / -plugins sections, ui-agent-preset,
/// and the ui-conversation Enter row) onto a phone-width tab. The
/// panel's content-column rhythm — 16/500 section titles over 14/22
/// rows with 12/18 tertiary descriptions, border-l2 hairlines between
/// rows, 12px-radius cards, capsule controls, 8px-radius inputs — is
/// kept token-for-token (reference packages/client/ui-settings-* module
/// css). The web's two-pane panel (nav rail + content column) collapses
/// to a horizontal capsule nav over an IndexedStack of pages in the
/// web nav's order — General, Models, Plugins, Agent presets — plus
/// mobile-only pages: Backends (the device-local multi-host registry,
/// which stays reachable even when the active host is not) and
/// Credentials; IndexedStack preserves each section's scroll and entry
/// state across switches. General facts render as value rows, the
/// Enter-behavior and agent-preset defaults render as the web's
/// interactive preference rows, presets render as the web's selectable
/// cards (read-only: authoring verbs are loopback-pinned), namespaces
/// disclose in place under Plugins (web PluginCard), the DeepSeek
/// API-key card rides Models, and the credential editor opens as a
/// bottom sheet on the popover surface instead of a side panel.
library;

import 'package:domain/model/agent_preset.dart';
import 'package:domain/model/backend.dart';
import 'package:domain/model/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import '../shared/agent_preset_display.dart';
import '../shared/backend_connection_dot.dart';
import '../theme/deepsuite_extension.dart';
import '../theme/deepsuite_tokens.dart' show DeepSuiteStatic, kDsDuration;
import 'busy_enter_preference.dart';
import 'settings_ui_state.dart';

class SettingsRoute extends ConsumerWidget {
  const SettingsRoute({super.key, this.backendId});

  /// The backend whose HOST settings this surface presents; null uses
  /// the active backend. The Backends section is device-local and always
  /// shows.
  final String? backendId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolved =
        backendId ?? ref.watch(activeBackendIdProvider).value ?? '';
    if (resolved.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final controller = ref.watch(settingsControllerProvider(resolved));
    return StreamBuilder<SettingsUiState>(
      stream: controller.uiState,
      initialData: controller.state,
      builder: (context, snapshot) {
        final uiState = snapshot.data ?? const SettingsUiState();
        return SettingsScreen(uiState: uiState, onAction: controller.onAction);
      },
    );
  }
}

/// Phone-tab settings sections. The web nav order is general 0, models
/// 10, plugins 15, agent-presets 20 (reference ui-settings nav); the
/// mobile-only pages bracket it: Backends first (the device-local
/// registry decides which host every other page even describes, and it
/// stays reachable when that host is not), Credentials last (the web
/// manages secrets inside the Models provider editors).
enum _SettingsSection { backends, general, models, plugins, presets, credentials }

String _sectionLabel(_SettingsSection section) => switch (section) {
  _SettingsSection.backends => 'Backends',
  _SettingsSection.general => 'General',
  _SettingsSection.models => 'Models',
  _SettingsSection.plugins => 'Plugins',
  _SettingsSection.presets => 'Agent presets',
  _SettingsSection.credentials => 'Credentials',
};

/// The credential reference the official DeepSeek route resolves by
/// default (reference packages/llm/llm-deepseek DEFAULT_API_KEY_ENV);
/// the Models page's feasible subset keys off it.
const String _kDeepSeekCredentialRef = 'DEEPSEEK_API_KEY';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.uiState,
    required this.onAction,
  });

  final SettingsUiState uiState;
  final void Function(SettingsAction) onAction;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  _SettingsSection _section = _SettingsSection.general;

  @override
  Widget build(BuildContext context) {
    final uiState = widget.uiState;
    final described = uiState.snapshot;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SettingsHeader(
              onRefresh: () => widget.onAction(const RefreshSettingsAction()),
            ),
            if (uiState.errorMessage case final String error)
              _ErrorBanner(
                message: error,
                onDismiss: () =>
                    widget.onAction(const DismissSettingsError()),
              ),
            // Web surfaces write/refresh state on the controls; the mobile
            // tab keeps one slim activity line above the content column.
            if (described != null && uiState.isLoading)
              LinearProgressIndicator(
                minHeight: 2,
                color: dsOf(context).accent,
                backgroundColor: Colors.transparent,
              ),
            // The nav and the page stack always mount: the Backends page
            // is device-local, so it stays reachable when the active host
            // is unreachable (fixing that host's URL is exactly the flow
            // that must not dead-end).
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SettingsSectionNav(
                    section: _section,
                    onSelect: (next) =>
                        setState(() => _section = next),
                  ),
                  Expanded(
                    child: IndexedStack(
                      index: _section.index,
                      children: [
                        const _BackendsPage(),
                        _HostPageGate(
                          snapshot: described,
                          loading: uiState.isLoading,
                          onOpenBackends: () => setState(
                            () => _section = _SettingsSection.backends,
                          ),
                          page: (host) => _GeneralPage(
                            snapshot: host,
                            roster: uiState.roster,
                            busy: uiState.isLoading,
                            onAction: widget.onAction,
                          ),
                        ),
                        _HostPageGate(
                          snapshot: described,
                          loading: uiState.isLoading,
                          onOpenBackends: () => setState(
                            () => _section = _SettingsSection.backends,
                          ),
                          page: (host) => _ModelsPage(
                            writable: host.writable,
                            credentials: uiState.credentials,
                            onAction: widget.onAction,
                          ),
                        ),
                        _HostPageGate(
                          snapshot: described,
                          loading: uiState.isLoading,
                          onOpenBackends: () => setState(
                            () => _section = _SettingsSection.backends,
                          ),
                          page: (host) => _PluginsPage(
                            snapshot: host,
                            busy: uiState.isLoading,
                            onAction: widget.onAction,
                          ),
                        ),
                        _HostPageGate(
                          snapshot: described,
                          loading: uiState.isLoading,
                          onOpenBackends: () => setState(
                            () => _section = _SettingsSection.backends,
                          ),
                          page: (_) => _AgentPresetsPage(
                            roster: uiState.roster,
                            onAction: widget.onAction,
                          ),
                        ),
                        _HostPageGate(
                          snapshot: described,
                          loading: uiState.isLoading,
                          onOpenBackends: () => setState(
                            () => _section = _SettingsSection.backends,
                          ),
                          page: (_) => _CredentialsPage(
                            credentials: uiState.credentials,
                            credentialError: uiState.credentialError,
                            onAction: widget.onAction,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The panel's section nav (web SettingsRoot `.navList`) collapsed to a
/// horizontal capsule row: one 36px capsule per section on the selector
/// vocabulary, the active one on the module fill.
class _SettingsSectionNav extends StatelessWidget {
  const _SettingsSectionNav({
    required this.section,
    required this.onSelect,
  });

  final _SettingsSection section;
  final ValueChanged<_SettingsSection> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            for (final candidate in _SettingsSection.values) ...[
              if (candidate != _SettingsSection.values.first)
                const SizedBox(width: 8),
              _ModeButton(
                label: _sectionLabel(candidate),
                selected: candidate == section,
                onTap: () => onSelect(candidate),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Web panel header: the nav title 'Settings' (16/500) beside the header
/// action chrome — a circular glyph button on interactive-bg-hover.
class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Settings',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          _CircleAction(
            icon: Icons.refresh,
            tooltip: 'Refresh',
            onTap: onRefresh,
          ),
        ],
      ),
    );
  }
}

/// Web failure presentation plus the transport hint: error ink at 12/18
/// with the loopback reminder underneath and a dismiss control.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Icon(
              Icons.error_outline,
              size: 14,
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'settings/credentials are loopback-only on the host; '
                    'connect via adb reverse',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          _CircleAction(
            icon: Icons.close,
            iconSize: 14,
            tooltip: 'Dismiss',
            onTap: onDismiss,
          ),
        ],
      ),
    );
  }
}

/// Backends page — the device-local multi-host registry (no web peer:
/// the web client is compiled against one host). One row per configured
/// backend with its LIVE connection dot; tapping a non-active row
/// makes it the backend the chat surface presents. The edit sheet owns
/// add/rename/repoint/remove with the registry's guards surfaced
/// inline.
class _BackendsPage extends ConsumerWidget {
  const _BackendsPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watching the keep-alive here pins every configured backend's
    // connection while this page exists (the dots read live phases).
    ref.watch(allBackendConnectionsProvider);
    final registry = ref.watch(backendRegistryStateProvider);
    return registry.when(
      loading: () =>
          const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text(error.toString())),
      data: (state) => _BackendsList(state: state, ref: ref),
    );
  }
}

class _BackendsList extends StatelessWidget {
  const _BackendsList({required this.state, required this.ref});

  final BackendRegistryState state;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const _SectionHeader(
          title: 'Backends',
          intro: 'Host endpoints this device keeps connected — every '
              'configured backend stays live; the active one drives Chat '
              'and these host-settings pages.',
        ),
        // The registry's last refusal or persist failure (guards fail
        // loud on the state); the next successful mutation clears it.
        if (state.errorMessage case final String message)
          _RegistryErrorLine(message: message),
        ..._divided(
          ds,
          [
            for (final backend in state.backends)
              _BackendRow(
                backend: backend,
                active: backend.id == state.activeId,
                onAction: (action) => _dispatchBackendAction(ref, action),
                onEdit: () => _openBackendSheet(
                  context,
                  ref,
                  backend,
                  removeBlockedReason: _removeBlockedReason(state, backend),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        // Web empty-column convention: the trailing affordance is a
        // capsule on the selector vocabulary.
        Center(
          child: OutlinedButton(
            onPressed: () => _openBackendSheet(context, ref, null),
            style: _outlineCapsule(context),
            child: const Text('Add backend'),
          ),
        ),
      ],
    );
  }
}

/// Why a backend cannot be removed right now (the registry's guards,
/// mirrored as visible UI instead of a dead button); null = removable.
String? _removeBlockedReason(
  BackendRegistryState state,
  BackendConfig backend,
) {
  if (backend.id == state.activeId) {
    return 'Switch away before removing the active backend.';
  }
  if (state.backends.length <= 1) {
    return 'The last backend cannot be removed.';
  }
  return null;
}

void _dispatchBackendAction(WidgetRef ref, BackendAction action) {
  ref
      .read(backendRegistryProvider.future)
      .then((controller) => controller.onAction(action));
}

/// The add/edit sheet on the settings menu-surface idiom (credential
/// editor): menu fill, 12px radius, popover hairline, lv3 shadow.
Future<void> _openBackendSheet(
  BuildContext context,
  WidgetRef ref,
  BackendConfig? backend, {
  String? removeBlockedReason,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final insets = MediaQuery.of(sheetContext).viewInsets.bottom;
      return Padding(
        padding: EdgeInsets.fromLTRB(8, 0, 8, 8 + insets),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: dsOf(sheetContext).menu,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: dsOf(sheetContext).borderInverted),
            boxShadow: kDsShadowLv3,
          ),
          child: _BackendSheet(
            backend: backend,
            removeBlockedReason: backend == null ? null : removeBlockedReason,
            onSave: (label, baseUrl) {
              if (backend == null) {
                _dispatchBackendAction(
                  ref,
                  AddBackend(label, baseUrl),
                );
                return;
              }
              if (label != backend.label) {
                _dispatchBackendAction(
                  ref,
                  RenameBackend(backend.id, label),
                );
              }
              if (baseUrl != backend.baseUri.toString()) {
                _dispatchBackendAction(
                  ref,
                  UpdateBackendUrl(backend.id, baseUrl),
                );
              }
            },
            onRemove: backend == null || removeBlockedReason != null
                ? null
                : () => _dispatchBackendAction(
                    ref,
                    RemoveBackend(backend.id),
                  ),
          ),
        ),
      );
    },
  );
}

/// One backend row: live connection dot, label over `host:port`, the
/// Active badge on the presented backend, and the edit affordance.
/// Tapping a non-active row selects it (the registry guards the rest).
class _BackendRow extends StatelessWidget {
  const _BackendRow({
    required this.backend,
    required this.active,
    required this.onAction,
    required this.onEdit,
  });

  final BackendConfig backend;
  final bool active;

  final void Function(BackendAction action) onAction;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ds = dsOf(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        hoverColor: ds.interactiveBgHover,
        onTap: active ? null : () => onAction(SelectBackend(backend.id)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              BackendConnectionDot(backendId: backend.id),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(backend.label, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 4),
                    Text(
                      '${backend.baseUri.host}:${backend.baseUri.port}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ds.labelTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (active)
                const _StateBadge(configured: true, label: 'Active')
              else
                const _StateBadge(configured: false, label: 'Standby'),
              const SizedBox(width: 4),
              _CircleAction(
                icon: Icons.edit_outlined,
                iconSize: 16,
                tooltip: 'Edit backend',
                onTap: onEdit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Registry refusal line: error ink at 12/18 with the outline glyph,
/// matching the transport error banner's vocabulary (no dismiss — the
/// next successful mutation clears it).
class _RegistryErrorLine extends StatelessWidget {
  const _RegistryErrorLine({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Icon(
              Icons.error_outline,
              size: 14,
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Host-settings page gate: the page renders from a snapshot; before
/// the first snapshot the surface is the loading state, and after a
/// failed load it states the unreachable host and routes to Backends
/// (repointing the host is the fix for exactly this dead end).
class _HostPageGate extends StatelessWidget {
  const _HostPageGate({
    required this.snapshot,
    required this.loading,
    required this.onOpenBackends,
    required this.page,
  });

  final SettingsSnapshot? snapshot;
  final bool loading;
  final VoidCallback onOpenBackends;
  final Widget Function(SettingsSnapshot) page;

  @override
  Widget build(BuildContext context) {
    final described = snapshot;
    if (described != null) return page(described);
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final theme = Theme.of(context);
    final ds = dsOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 24,
              color: ds.labelTertiary,
            ),
            const SizedBox(height: 12),
            Text(
              'Host settings unavailable',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'The active backend did not answer. Repoint or switch it '
              'from the Backends page.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: ds.labelTertiary,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onOpenBackends,
              style: _filledCapsule(context),
              child: const Text('Backends'),
            ),
          ],
        ),
      ),
    );
  }
}

/// General page (web GeneralSection): the preference rows — busy-Enter
/// (web EnterBehaviorRow) and the agent-preset default (web
/// AgentPresetRow) — over the connection-fact rows.
class _GeneralPage extends StatelessWidget {
  const _GeneralPage({
    required this.snapshot,
    required this.roster,
    required this.busy,
    required this.onAction,
  });

  final SettingsSnapshot snapshot;
  final AgentPresetRoster? roster;
  final bool busy;
  final void Function(SettingsAction) onAction;

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    final rows = <Widget>[
      const _EnterBehaviorRow(),
      // Web rule: the row exists only when the deployment composes at
      // least one preset — an empty roster has nothing to choose between.
      if (roster?.entries.isNotEmpty ?? false)
        _AgentPresetRow(
          roster: roster!,
          writable: snapshot.writable,
          busy: busy,
          onAction: onAction,
        ),
      _GeneralRow(
        title: 'Host writes',
        description:
            'Whether the host accepts settings and credential writes.',
        value: snapshot.writable ? 'Writable' : 'Read-only',
        tone: snapshot.writable ? _FactTone.positive : _FactTone.warning,
      ),
      _GeneralRow(
        title: 'Settings document',
        description:
            'Whether a user settings document backs the '
            'namespaces.',
        value: snapshot.hasDocument ? 'Present' : 'None',
        tone: snapshot.hasDocument ? _FactTone.positive : _FactTone.neutral,
      ),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const _SectionHeader(
          title: 'General',
          intro: 'New-session defaults and the host settings plane.',
        ),
        ..._divided(ds, rows),
      ],
    );
  }
}

/// The healthy presets a picker may offer (web `presetOptions`): a
/// broken preset cannot compose a session, so offering it would only
/// defer that discovery to a failed session start.
List<AgentPresetEntry> _pickerOptions(AgentPresetRoster? roster) =>
    roster?.entries.where((entry) => entry.broken == null).toList() ??
    const <AgentPresetEntry>[];

/// Busy-Enter preference row (web EnterBehaviorRow): a Queue/Steer
/// capsule selector persisted to the shared LocalStateStore. The row
/// renders with the queue default while the store loads or refuses to
/// load — the preference is device-local and never fails a page.
class _EnterBehaviorRow extends ConsumerWidget {
  const _EnterBehaviorRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ds = dsOf(context);
    final theme = Theme.of(context);
    final controller = ref.watch(busyEnterPreferenceProvider).value;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Enter behavior while busy', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text(
            'Applies only while an agent is running.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: ds.labelTertiary,
            ),
          ),
          const SizedBox(height: 10),
          if (controller == null)
            _enterBehaviorCapsules(
              context,
              BusyEnterBehavior.queue,
              null,
            )
          else
            StreamBuilder<BusyEnterBehavior>(
              stream: controller.uiState,
              initialData: controller.state,
              builder: (context, snapshot) => _enterBehaviorCapsules(
                context,
                snapshot.data ?? BusyEnterBehavior.queue,
                controller.select,
              ),
            ),
        ],
      ),
    );
  }

  Widget _enterBehaviorCapsules(
    BuildContext context,
    BusyEnterBehavior current,
    ValueChanged<BusyEnterBehavior>? onSelect,
  ) {
    return Wrap(
      spacing: 8,
      children: [
        for (final option in BusyEnterBehavior.values)
          _ModeButton(
            label: switch (option) {
              BusyEnterBehavior.queue => 'Queue',
              BusyEnterBehavior.steer => 'Steer',
            },
            selected: option == current,
            onTap: onSelect == null ? null : () => onSelect(option),
          ),
      ],
    );
  }
}

/// Agent-preset default row (web AgentPresetRow): the current default's
/// display name trailing, a menu-surface picker listing the healthy
/// roster. The control is disabled while the host reports read-only
/// (the write would be refused); the row itself does not exist when the
/// deployment composes no presets.
class _AgentPresetRow extends StatelessWidget {
  const _AgentPresetRow({
    required this.roster,
    required this.writable,
    required this.busy,
    required this.onAction,
  });

  final AgentPresetRoster roster;
  final bool writable;
  final bool busy;
  final void Function(SettingsAction) onAction;

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    final theme = Theme.of(context);
    final options = _pickerOptions(roster);
    // A roster can mark nothing default; the picker still has to show
    // something, so the label falls back to the first entry (web rule).
    final current = roster.defaultEntry ?? roster.entries.first;
    final enabled = writable && !busy && options.isNotEmpty;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        hoverColor: ds.interactiveBgHover,
        onTap: enabled ? () => _openPicker(context, options) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Agent preset', style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Applies to sessions you start from now on. '
                      'Running sessions keep the preset they began with.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ds.labelTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                agentPresetDisplayName(current),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: ds.labelSecondary,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 20, color: ds.labelTertiary),
            ],
          ),
        ),
      ),
    );
  }

  /// Mobile picker for the web PresetMenu: the menu-surface sheet
  /// (MenuDropdown family, as the credential editor) listing one row
  /// per healthy preset, the current default checked.
  Future<void> _openPicker(
    BuildContext context,
    List<AgentPresetEntry> options,
  ) {
    final currentId = (roster.defaultEntry ?? roster.entries.first).id;
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final ds = dsOf(sheetContext);
        final theme = Theme.of(sheetContext);
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: ds.menu,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: ds.borderInverted),
              boxShadow: kDsShadowLv3,
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Agent preset', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  for (final option in options)
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        hoverColor: ds.interactiveBgHover,
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          onAction(SelectAgentPresetDefaultAction(option.id));
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  agentPresetDisplayName(option),
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                              if (option.id == currentId)
                                Icon(
                                  Icons.check,
                                  size: 16,
                                  color: ds.accent,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Agent-presets page (web AgentPresetSection): the roster as grouped
/// selectable cards — Built-in and Custom (web groups). Read-only
/// beyond the default switch: the copy, delete, and compose-viewer
/// verbs ride loopback-pinned RPCs a mobile client cannot reach, so
/// authoring stays on the host and the page says so. An empty or
/// unloaded roster renders nothing but that footnote (web rule: a
/// deployment that composes no presets has nothing to manage).
class _AgentPresetsPage extends StatelessWidget {
  const _AgentPresetsPage({
    required this.roster,
    required this.onAction,
  });

  final AgentPresetRoster? roster;
  final void Function(SettingsAction) onAction;

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    final theme = Theme.of(context);
    final entries = roster?.entries ?? const <AgentPresetEntry>[];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (entries.isNotEmpty) ...[
          const _SectionHeader(
            title: 'Agent presets',
            intro:
                'A preset is the plugin composition one session\'s agent '
                'runs — its tools, prompt, and capabilities.',
          ),
          for (final (trust, heading) in [
            (AgentPresetTrust.system, 'Built-in'),
            (AgentPresetTrust.user, 'Custom'),
          ])
            if (entries.any((entry) => entry.trust == trust)) ...[
              Text(
                heading.toUpperCase(),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: ds.labelTertiary,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 8),
              for (final entry in entries.where(
                (entry) => entry.trust == trust,
              )) ...[
                _PresetCard(
                  key: ValueKey(entry.id),
                  entry: entry,
                  onAction: onAction,
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 8),
            ],
        ],
        Text(
          'Presets are authored on the host: copy, edit, and delete them '
          'from the desktop settings.',
          style: theme.textTheme.bodySmall?.copyWith(color: ds.labelTertiary),
        ),
      ],
    );
  }
}

/// One preset card (web `.card`): the card body IS the control —
/// tapping a healthy non-default card makes it the default. The
/// default reads selected (layer-2 fill, primary border — web
/// `cardActive`), not merely badged; a broken preset carries the error
/// border, the 'Failed to load' badge, and the discovery reason, with
/// its body disabled.
class _PresetCard extends StatelessWidget {
  const _PresetCard({
    super.key,
    required this.entry,
    required this.onAction,
  });

  final AgentPresetEntry entry;
  final void Function(SettingsAction) onAction;

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    final theme = Theme.of(context);
    final broken = entry.broken != null;
    final active = entry.isDefault;
    // Web rule: the card offers the full description on hover when the
    // 4-line clamp cut it; an unpublished description says so.
    final description = agentPresetDisplayDescription(entry) ??
        'No description.';
    return AnimatedContainer(
      duration: kDsDuration,
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: active ? ds.bgLayer2 : ds.bgLayer3,
        border: Border.all(
          color: broken
              ? theme.colorScheme.error
              : active
              ? theme.colorScheme.onSurface
              : ds.borderL2,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          hoverColor: ds.interactiveBgHover,
          onTap: broken || active
              ? null
              : () => onAction(SelectAgentPresetDefaultAction(entry.id)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        agentPresetDisplayName(entry),
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    if (broken) ...[
                      const SizedBox(width: 8),
                      const _PresetBadge(
                        label: 'Failed to load',
                        filled: true,
                      ),
                    ],
                    if (entry.trust == AgentPresetTrust.user) ...[
                      const SizedBox(width: 8),
                      const _PresetBadge(label: 'Custom'),
                    ],
                    if (active) ...[
                      const SizedBox(width: 8),
                      const Spacer(),
                      const _PresetBadge(label: 'In use', inverted: true),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Tooltip(
                  message: description,
                  child: Text(
                    description,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ds.labelSecondary,
                    ),
                  ),
                ),
                if (broken) ...[
                  const SizedBox(height: 6),
                  Text(
                    // The discovery-reported reason, verbatim: it names
                    // the file and the fix.
                    entry.broken!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  entry.id,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: ds.labelCaption,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Web `.badge`/`.brokenBadge`/`.inUse`: a 999px pill at 11/17 w500 —
/// hairline outline with tertiary ink for the trust mark, the error
/// fill with layer-3 ink when broken, and the label-primary fill with
/// layer-3 ink for the in-use mark.
class _PresetBadge extends StatelessWidget {
  const _PresetBadge({
    required this.label,
    this.filled = false,
    this.inverted = false,
  });

  final String label;
  final bool filled;
  final bool inverted;

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    final theme = Theme.of(context);
    final Color background;
    final Color foreground;
    if (filled) {
      background = theme.colorScheme.error;
      foreground = ds.bgLayer3;
    } else if (inverted) {
      background = theme.colorScheme.onSurface;
      foreground = ds.bgLayer3;
    } else {
      background = Colors.transparent;
      foreground = ds.labelTertiary;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: filled || inverted ? null : Border.all(color: ds.borderL2),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: foreground),
      ),
    );
  }
}

/// Plugins page (web PluginsSettingsSection): the host settings
/// namespaces as in-place disclosure cards (the mobile analog of the
/// web configurable-plugins tab — one PluginCard per namespace).
class _PluginsPage extends StatelessWidget {
  const _PluginsPage({
    required this.snapshot,
    required this.busy,
    required this.onAction,
  });

  final SettingsSnapshot snapshot;
  final bool busy;
  final void Function(SettingsAction) onAction;

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const _SectionHeader(
          title: 'Plugins',
          intro:
              'Configure and inspect the plugins installed in this '
              'deployment.',
        ),
        if (snapshot.namespaces.isEmpty)
          Text(
            'This deployment exposes no plugin settings.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: ds.labelTertiary,
            ),
          ),
        for (var i = 0; i < snapshot.namespaces.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _NamespaceCard(
            key: ValueKey(snapshot.namespaces[i].ns),
            namespace: snapshot.namespaces[i],
            writable: snapshot.writable,
            busy: busy,
            onAction: onAction,
          ),
        ],
      ],
    );
  }
}

/// Models page (web ModelsSection), scoped to what the mobile adapter
/// covers: the official DeepSeek route's API-key card (credential
/// describe + set/unset — the same editor sheet as the Credentials
/// page). The web's provider-directory joins, schema-driven profile
/// editors, and custom-provider CRUD ride RPCs the adapter does not
/// expose, so they stay on the host and the page says so.
class _ModelsPage extends StatelessWidget {
  const _ModelsPage({
    required this.writable,
    required this.credentials,
    required this.onAction,
  });

  final bool writable;
  final List<CredentialStatus> credentials;
  final void Function(SettingsAction) onAction;

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    final theme = Theme.of(context);
    final deepSeek = credentials
        .where((credential) => credential.ref == _kDeepSeekCredentialRef)
        .firstOrNull;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const _SectionHeader(
          title: 'Models',
          intro:
              'Enter your API keys to use models from the following '
              'providers.',
        ),
        if (!writable)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'The settings document is read-only in this deployment.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: ds.labelTertiary,
              ),
            ),
          ),
        if (deepSeek != null) ...[
          _DeepSeekCard(credential: deepSeek, onAction: onAction),
          const SizedBox(height: 12),
        ],
        Text(
          'Custom providers are managed on the host: this client covers '
          'the DeepSeek API key only.',
          style: theme.textTheme.bodySmall?.copyWith(color: ds.labelTertiary),
        ),
      ],
    );
  }
}

/// The official DeepSeek route's row (web ModelsSection `.rowCard`):
/// provider name over the API-key state, the configured/missing dot
/// and badge trailing, opening the credential editor sheet.
class _DeepSeekCard extends StatelessWidget {
  const _DeepSeekCard({required this.credential, required this.onAction});

  final CredentialStatus credential;
  final void Function(SettingsAction) onAction;

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: kDsDuration,
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: ds.bgLayer3,
        border: Border.all(color: ds.borderL2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          hoverColor: ds.interactiveBgHover,
          onTap: () => _openSheet(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('DeepSeek', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Text(
                        credential.configured
                            ? 'API key configured'
                            : 'API key missing',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: ds.labelTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _StatusDot(
                  color: credential.configured
                      ? DeepSuiteStatic.green500
                      : ds.warnPrimary,
                ),
                const SizedBox(width: 6),
                _StateBadge(configured: credential.configured),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, size: 20, color: ds.labelTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The same editor sheet the Credentials page opens: write-only
  /// secret field, capsule footer with the destructive unset.
  Future<void> _openSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final insets = MediaQuery.of(sheetContext).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(8, 0, 8, 8 + insets),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: dsOf(sheetContext).menu,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: dsOf(sheetContext).borderInverted),
              boxShadow: kDsShadowLv3,
            ),
            child: _CredentialSheet(
              credential: credential,
              onAction: onAction,
            ),
          ),
        );
      },
    );
  }
}

/// Credentials page: the secret references the host namespaces name,
/// each opening the editor sheet. The web manages these inside the
/// Models provider editors; the phone keeps them addressable directly.
class _CredentialsPage extends StatelessWidget {
  const _CredentialsPage({
    required this.credentials,
    required this.credentialError,
    required this.onAction,
  });

  final List<CredentialStatus> credentials;
  final String? credentialError;
  final void Function(SettingsAction) onAction;

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    final theme = Theme.of(context);
    final tertiary = theme.textTheme.bodySmall?.copyWith(
      color: ds.labelTertiary,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const _SectionHeader(
          title: 'Credentials',
          intro: 'Secret references named by the host namespaces.',
        ),
        if (credentialError case final String error) ...[
          Text('Credential state unavailable: $error', style: tertiary),
          if (credentials.isNotEmpty) const SizedBox(height: 8),
        ],
        if (credentials.isEmpty)
          Text('No credentials referenced.', style: tertiary)
        else
          ..._divided(
            ds,
            [
              for (final credential in credentials)
                _CredentialRow(
                  key: ValueKey(credential.ref),
                  credential: credential,
                  onAction: onAction,
                ),
            ],
          ),
      ],
    );
  }
}

/// Web section heading block (ModelsSection `.title`/`.intro`): a 16/500
/// title over a 14/22 tertiary intro line.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.intro});

  final String title;
  final String intro;

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            intro,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ds.labelTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Web GeneralSection: border-l2 hairline separators between rows, with
/// the trailing separator stripped on the column's last row.
List<Widget> _divided(DeepSuiteColors ds, List<Widget> rows) => [
  for (var i = 0; i < rows.length; i++)
    if (i < rows.length - 1)
      DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: ds.borderL2)),
        ),
        child: rows[i],
      )
    else
      rows[i],
];

/// Web General row (LanguageRow/EnterBehaviorRow `.row`, figma
/// Setting-Cell): a 14/22 title over a 12/18 tertiary description with
/// the current value trailing, at 16px vertical padding.
class _GeneralRow extends StatelessWidget {
  const _GeneralRow({
    required this.title,
    required this.description,
    required this.value,
    required this.tone,
  });

  final String title;
  final String description;
  final String value;
  final _FactTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ds = dsOf(context);
    final (dotColor, textColor) = _toneColors(ds, tone);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ds.labelTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _StatusDot(color: dotColor),
          const SizedBox(width: 6),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(color: textColor),
          ),
        ],
      ),
    );
  }
}

/// Row-value tones carried by the trailing dot (web credential-dot
/// vocabulary: success, warn, and the unobserved neutral gray).
enum _FactTone { positive, warning, neutral }

/// Dot and text colors for one row-value tone.
(Color, Color) _toneColors(DeepSuiteColors ds, _FactTone tone) =>
    switch (tone) {
      _FactTone.positive => (DeepSuiteStatic.green500, ds.labelSecondary),
      _FactTone.warning => (ds.warnPrimary, ds.warnLabel),
      _FactTone.neutral => (ds.labelCaption, ds.labelTertiary),
    };

/// Web ModelsSection `.credentialDot`: an 8px solid state dot.
class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// Web PluginCard: a 12px-radius bordered card on the layer-3 fill whose
/// header (name over tertiary description, rotating chevron) discloses
/// the edit form in place; the open card lifts to the layer-2 fill.
/// Read-only namespaces disclose only the warn notice.
class _NamespaceCard extends StatefulWidget {
  const _NamespaceCard({
    super.key,
    required this.namespace,
    required this.writable,
    required this.busy,
    required this.onAction,
  });

  final SettingsNamespace namespace;
  final bool writable;
  final bool busy;
  final void Function(SettingsAction) onAction;

  @override
  State<_NamespaceCard> createState() => _NamespaceCardState();
}

class _NamespaceCardState extends State<_NamespaceCard> {
  final TextEditingController _keyController = TextEditingController();
  final TextEditingController _valueController = TextEditingController();
  bool _open = false;
  bool _replaceMode = false;

  @override
  void dispose() {
    _keyController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  bool get _canSave => _replaceMode
      ? _valueController.text.trim().isNotEmpty
      : _keyController.text.trim().isNotEmpty &&
            _valueController.text.trim().isNotEmpty;

  void _save() {
    final namespace = widget.namespace;
    widget.onAction(
      _replaceMode
          ? ReplaceSettingAction(
              ns: namespace.ns,
              sectionJson: _valueController.text,
              expectedRevision: namespace.revision,
            )
          : UpdateSettingAction(
              ns: namespace.ns,
              key: _keyController.text,
              jsonValue: _valueController.text,
              expectedRevision: namespace.revision,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    final theme = Theme.of(context);
    final namespace = widget.namespace;
    return AnimatedContainer(
      duration: kDsDuration,
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: _open ? ds.bgLayer2 : ds.bgLayer3,
        border: Border.all(color: ds.borderL2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(12),
              hoverColor: ds.interactiveBgHover,
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(namespace.ns, style: theme.textTheme.titleSmall),
                          const SizedBox(height: 4),
                          Text(
                            _namespaceMeta(namespace),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: ds.labelTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: _open ? 0.5 : 0,
                      duration: kDsDuration,
                      curve: Curves.easeInOut,
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        size: 20,
                        color: ds.labelTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_open) _buildBody(context),
          ],
        ),
      ),
    );
  }

  /// Web PluginCard `.body`: inset hairline top border over either the
  /// read-only notice or the staged edit form and its footer.
  Widget _buildBody(BuildContext context) {
    final ds = dsOf(context);
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: ds.borderL2)),
      ),
      child: widget.writable
          ? _buildEditor(context)
          : Padding(
              padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
              child: Text(
                'Host is read-only on this connection; '
                'namespace edits are unavailable.',
                style: theme.textTheme.bodySmall?.copyWith(color: ds.warnLabel),
              ),
            ),
    );
  }

  /// The staged patch form: mode capsules (web selector vocabulary), the
  /// bordered 8px-radius inputs, the CAS caption, and the footer controls.
  Widget _buildEditor(BuildContext context) {
    final ds = dsOf(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ModeButton(
                label: 'Patch key',
                selected: !_replaceMode,
                onTap: () => setState(() => _replaceMode = false),
              ),
              _ModeButton(
                label: 'Replace section',
                selected: _replaceMode,
                onTap: () => setState(() => _replaceMode = true),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!_replaceMode) ...[
            const _FieldLabel('Top-level key'),
            const SizedBox(height: 6),
            TextField(
              controller: _keyController,
              decoration: _dsInputDecoration(context),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
          ],
          _FieldLabel(
            _replaceMode ? 'Whole user-layer JSON object' : 'JSON value',
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _valueController,
            decoration: _dsInputDecoration(
              context,
              hint: _replaceMode
                  ? '{ "key": value }'
                  : 'true / 42 / "text" / {…}',
            ),
            maxLines: _replaceMode ? 4 : 1,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Text(
            'CAS revision ${widget.namespace.revision}; '
            'host validates against the schema',
            style: theme.textTheme.bodySmall?.copyWith(color: ds.labelTertiary),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                onPressed: () {
                  _keyController.clear();
                  _valueController.clear();
                  setState(() {});
                },
                style: _outlineCapsule(context),
                child: const Text('Discard'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _canSave && !widget.busy ? _save : null,
                style: _filledCapsule(context),
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Web segmented choice on the selector vocabulary: a 36px capsule on the
/// module fill when selected, hairline outline when not; the padding
/// around it keeps the touch target at 44px. A null [onTap] renders the
/// capsule disabled (settings-nav and mode capsules never use it; the
/// busy-Enter fallback does while its store is unavailable).
class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.selected,
    this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        hoverColor: ds.interactiveBgHover,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? ds.specificSelector : null,
              borderRadius: BorderRadius.circular(18),
              border: selected ? null : Border.all(color: ds.borderL2),
            ),
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: selected
                    ? theme.colorScheme.onSurface
                    : ds.labelSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Web ModelsSection `.fieldLabel`: a 12/18 w500 label-secondary field
/// label.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelMedium
          ?.copyWith(color: dsOf(context).labelSecondary),
    );
  }
}

/// Web input vocabulary (fields.module.css `.input`, ModelsSection
/// `.input`): an 8px-radius bordered field on the layer-1 fill with the
/// brand-blue focus ring.
InputDecoration _dsInputDecoration(BuildContext context, {String? hint}) {
  final ds = dsOf(context);
  final theme = Theme.of(context);
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: BorderSide(color: ds.borderL2),
  );
  return InputDecoration(
    hintText: hint,
    hintStyle: theme.textTheme.bodyMedium?.copyWith(color: ds.labelTertiary),
    filled: true,
    fillColor: ds.bgLayer1,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
    enabledBorder: border,
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: ds.accent),
    ),
  );
}

/// Web capsule controls (ModelsSection `.primaryButton`/
/// `.secondaryButton`): 36px visual height at an 18px radius; Material's
/// padded tap target keeps the touch area at 48px. The filled variant
/// rides the label-primary polarity pair (dark ink over light ink).
ButtonStyle _filledCapsule(BuildContext context) {
  return FilledButton.styleFrom(
    minimumSize: const Size(64, 36),
    padding: const EdgeInsets.symmetric(horizontal: 14),
    shape: const StadiumBorder(),
    textStyle: Theme.of(context).textTheme.bodyMedium,
  );
}

ButtonStyle _outlineCapsule(BuildContext context) {
  final ds = dsOf(context);
  return OutlinedButton.styleFrom(
    minimumSize: const Size(64, 36),
    padding: const EdgeInsets.symmetric(horizontal: 14),
    shape: const StadiumBorder(),
    foregroundColor: ds.labelSecondary,
    side: BorderSide(color: ds.borderL2),
    textStyle: Theme.of(context).textTheme.bodyMedium,
  );
}

ButtonStyle _dangerCapsule(BuildContext context) {
  return TextButton.styleFrom(
    minimumSize: const Size(64, 36),
    padding: const EdgeInsets.symmetric(horizontal: 14),
    shape: const StadiumBorder(),
    foregroundColor: Theme.of(context).colorScheme.error,
    textStyle: Theme.of(context).textTheme.bodyMedium,
  );
}

/// Web General row carrying the SecretField state badge: a 14/22 label
/// over a 12/18 tertiary meta line, with the configured badge and a
/// disclosure chevron; tapping opens the editor sheet.
class _CredentialRow extends StatelessWidget {
  const _CredentialRow({
    super.key,
    required this.credential,
    required this.onAction,
  });

  final CredentialStatus credential;
  final void Function(SettingsAction) onAction;

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        hoverColor: ds.interactiveBgHover,
        onTap: () => _openSheet(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(credential.ref, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 4),
                    Text(
                      _credentialMeta(credential),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ds.labelTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StateBadge(configured: credential.configured),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 20, color: ds.labelTertiary),
            ],
          ),
        ),
      ),
    );
  }

  /// Mobile sub-page for the web SecretField editor: the menu-surface
  /// sheet (MenuDropdown family, as the model selector) — menu fill,
  /// 12px radius, popover hairline, lv3 shadow — carrying the write-only
  /// secret field and the capsule footer with the destructive unset.
  Future<void> _openSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final insets = MediaQuery.of(sheetContext).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(8, 0, 8, 8 + insets),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: dsOf(sheetContext).menu,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: dsOf(sheetContext).borderInverted),
              boxShadow: kDsShadowLv3,
            ),
            child: _CredentialSheet(credential: credential, onAction: onAction),
          ),
        );
      },
    );
  }
}

/// Web SecretField state badge (fields.module.css `.badge`/`.badgeMuted`):
/// a 999px pill at 11/17 w500 — module fill with label-secondary ink when
/// configured, borderless label-tertiary when not. Backends rows reuse
/// the pill for the Active/Standby marker.
class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.configured, this.label});

  final bool configured;

  /// Overrides the default Configured/Not-set copy (the Backends rows
  /// say Active/Standby on the same pill geometry).
  final String? label;

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: configured ? ds.specificSelector : null,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label ?? (configured ? 'Configured' : 'Not set'),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: configured ? ds.labelSecondary : ds.labelTertiary,
        ),
      ),
    );
  }
}

/// The credential editor sheet body: title row with the state badge, the
/// meta line, the write-only secret field (blank draft writes nothing),
/// and the footer controls. Read-only references show the warn notice.
class _CredentialSheet extends StatefulWidget {
  const _CredentialSheet({required this.credential, required this.onAction});

  final CredentialStatus credential;
  final void Function(SettingsAction) onAction;

  @override
  State<_CredentialSheet> createState() => _CredentialSheetState();
}

class _CredentialSheetState extends State<_CredentialSheet> {
  final TextEditingController _valueController = TextEditingController();

  @override
  void dispose() {
    _valueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    final theme = Theme.of(context);
    final credential = widget.credential;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Store ${credential.ref}',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              _StateBadge(configured: credential.configured),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _credentialMeta(credential),
            style: theme.textTheme.bodySmall?.copyWith(color: ds.labelTertiary),
          ),
          const SizedBox(height: 12),
          if (credential.writable)
            _buildEditor(context)
          else
            Text(
              'Read-only on this connection; the stored value cannot be '
              'changed from this client.',
              style: theme.textTheme.bodySmall?.copyWith(color: ds.warnLabel),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (credential.configured && credential.writable)
                TextButton(
                  onPressed: () {
                    widget.onAction(UnsetCredentialAction(credential.ref));
                    Navigator.of(context).pop();
                  },
                  style: _dangerCapsule(context),
                  child: const Text('Unset'),
                ),
              const Spacer(),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: _outlineCapsule(context),
                child: const Text('Cancel'),
              ),
              if (credential.writable) ...[
                const SizedBox(width: 8),
                ListenableBuilder(
                  listenable: _valueController,
                  builder: (context, _) => FilledButton(
                    onPressed: _valueController.text.trim().isNotEmpty
                        ? () {
                            widget.onAction(
                              SetCredentialAction(
                                credential.ref,
                                _valueController.text.trim(),
                              ),
                            );
                            Navigator.of(context).pop();
                          }
                        : null,
                    style: _filledCapsule(context),
                    child: const Text('Save'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEditor(BuildContext context) {
    final ds = dsOf(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel('Secret value'),
        const SizedBox(height: 6),
        TextField(
          controller: _valueController,
          autofocus: true,
          obscureText: true,
          decoration: _dsInputDecoration(context, hint: 'secret value'),
        ),
        const SizedBox(height: 8),
        Text(
          'Stored on the host; the value never rides a response.',
          style: theme.textTheme.bodySmall?.copyWith(color: ds.labelTertiary),
        ),
      ],
    );
  }
}

/// The backend add/edit sheet body: label + base-URL fields with the
/// registry's validation mirrored as immediate inline feedback (the
/// controller remains the authority — it re-checks on dispatch), plus
/// the destructive remove with its guard stated, never a dead control.
class _BackendSheet extends StatefulWidget {
  const _BackendSheet({
    required this.backend,
    required this.onSave,
    this.onRemove,
    this.removeBlockedReason,
  });

  /// Null = add mode (no remove control).
  final BackendConfig? backend;

  /// Fires with the trimmed label and the raw base URL when the drafts
  /// validate; the caller maps it onto Add/Rename/UpdateUrl.
  final void Function(String label, String baseUrl) onSave;

  /// Only passed when the registry would accept the removal; otherwise
  /// [removeBlockedReason] states why the control is absent.
  final VoidCallback? onRemove;

  /// The registry's refusal for removing this backend right now (null
  /// = removable; unused in add mode).
  final String? removeBlockedReason;

  @override
  State<_BackendSheet> createState() => _BackendSheetState();
}

class _BackendSheetState extends State<_BackendSheet> {
  late final TextEditingController _labelController;
  late final TextEditingController _urlController;

  @override
  void initState() {
    super.initState();
    final backend = widget.backend;
    _labelController = TextEditingController(text: backend?.label ?? '');
    _urlController = TextEditingController(
      text: backend?.baseUri.toString() ?? 'http://',
    );
  }

  @override
  void dispose() {
    _labelController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  /// The registry's URL rule (http/https scheme, non-empty host).
  bool _validUrl(String raw) {
    final uri = Uri.tryParse(raw.trim());
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  bool get _canSave =>
      _labelController.text.trim().isNotEmpty && _validUrl(_urlController.text);

  @override
  Widget build(BuildContext context) {
    final ds = dsOf(context);
    final theme = Theme.of(context);
    final editing = widget.backend != null;
    final urlValid = _validUrl(_urlController.text);
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            editing ? 'Edit backend' : 'Add backend',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          const _FieldLabel('Label'),
          const SizedBox(height: 6),
          TextField(
            controller: _labelController,
            autofocus: !editing,
            decoration: _dsInputDecoration(
              context,
              hint: 'Laptop host, build box, …',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          const _FieldLabel('Base URL'),
          const SizedBox(height: 6),
          TextField(
            controller: _urlController,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: _dsInputDecoration(
              context,
              hint: 'http://10.0.2.2:3080',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Text(
            urlValid
                ? 'RPC and event paths derive from this base.'
                : 'http or https with a host, e.g. http://10.0.2.2:3080',
            style: theme.textTheme.bodySmall?.copyWith(
              color: urlValid ? ds.labelTertiary : theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Add mode has nothing to remove; a blocked removal states
              // why instead of rendering a dead destructive control.
              if (editing)
                Expanded(
                  child: widget.onRemove != null
                      ? Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: widget.onRemove,
                            style: _dangerCapsule(context),
                            child: const Text('Remove'),
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Text(
                            widget.removeBlockedReason ?? '',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: ds.labelTertiary,
                            ),
                          ),
                        ),
                )
              else
                const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: _outlineCapsule(context),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _canSave
                    ? () {
                        widget.onSave(
                          _labelController.text.trim(),
                          _urlController.text.trim(),
                        );
                        Navigator.of(context).pop();
                      }
                    : null,
                style: _filledCapsule(context),
                child: Text(editing ? 'Save' : 'Add'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Web header action chrome (SettingsRoot `.close`): a circular glyph
/// button whose hover fills interactive-bg-hover; padded to the 44px
/// touch area.
class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.iconSize = 18,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          hoverColor: dsOf(context).interactiveBgHover,
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              icon,
              size: iconSize,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// Summary columns mirrored from the settings.describe wire view.
String _namespaceMeta(SettingsNamespace namespace) => [
  'applies: ${namespace.applies.name}',
  'revision: ${namespace.revision}',
  if (namespace.hasUserLayer) 'user layer',
  if (namespace.secretCount > 0) '${namespace.secretCount} secrets set',
].join(' · ');

String _credentialMeta(CredentialStatus credential) => [
  credential.configured ? 'configured' : 'not configured',
  if (credential.source case final String source) 'source: $source',
  credential.writable ? 'writable' : 'read-only',
].join(' · ');
