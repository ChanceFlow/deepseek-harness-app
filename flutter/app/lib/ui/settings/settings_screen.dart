/// Settings tab — an index of one-line rows over pushed sub-pages.
///
/// The root names every subject the app can configure and states the current
/// value where there is one; the subject itself lives one tap away, so no
/// long-form surface competes for the root's pixels. Where a surface belongs:
///
/// - **Pushed page** — anything with content of its own: agent presets,
///   credentials, providers, host settings namespaces, plugin inventory,
///   About, and the ASR and error-log surfaces already built as pages.
/// - **Modal sheet** — a single choice over a short list: interface language,
///   appearance, busy-Enter behavior, and every editor (a credential's value,
///   a host's address). Sheet plumbing is [showSettingsSheet].
/// - **The host sheet** — the registry, the settings scope, and the scoped
///   host's write/document facts, so the host dimension stays one row plus
///   one sheet ([host settings split](../../../../../.agents/notes/implemented/feature/2026-08-24-settings-app-host-split.md)).
library;

import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/agent_preset.dart';
import 'package:domain/model/backend.dart';
import 'package:domain/model/connection_state.dart' as domain;
import 'package:domain/model/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../backends/describe_backend_error.dart';
import '../../di/providers.dart';
import '../shared/agent_preset_display.dart';
import '../shared/backend_connection_dot.dart';
import '../theme/theme.dart';
import 'backend_reachability.dart';
import 'battery_optimization_section.dart';
import 'busy_enter_preference.dart';
import 'locale_preference.dart';
import 'settings_backend_scope.dart';
import 'settings_chrome.dart';
import 'settings_controller.dart';
import 'settings_pages.dart';
import 'settings_ui_state.dart';
import 'theme_preference.dart';

class SettingsRoute extends ConsumerWidget {
  const SettingsRoute({super.key, this.backendId});

  /// The backend whose HOST settings this surface presents; null uses
  /// the settings scope (which follows the active backend until the
  /// user pins one).
  final String? backendId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String resolved =
        backendId ?? ref.watch(settingsBackendScopeProvider);
    if (resolved.isEmpty) {
      if (ref.watch(backendRegistryStateProvider).value == null) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      // The registry loaded with no active backend (every backend is
      // disabled): the host card's manage sheet stays reachable — it
      // lists disabled backends too, and it is the way back.
      return SettingsScreen(
        uiState: const SettingsUiState(),
        onAction: (SettingsAction _) {},
      );
    }
    final SettingsController controller = ref.watch(
      settingsControllerProvider(resolved),
    );
    return StreamBuilder<SettingsUiState>(
      stream: controller.uiState,
      initialData: controller.state,
      builder: (BuildContext context, AsyncSnapshot<SettingsUiState> snapshot) {
        final SettingsUiState uiState =
            snapshot.data ?? const SettingsUiState();
        return SettingsScreen(
          uiState: uiState,
          onAction: controller.onAction,
          uiStateStream: controller.uiState,
        );
      },
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    required this.uiState,
    required this.onAction,
    this.uiStateStream,
    super.key,
  });

  final SettingsUiState uiState;
  final void Function(SettingsAction) onAction;

  /// The controller's stream when the tab is controller-backed. A pushed
  /// sub-page re-renders from it, so a write the page triggers is visible
  /// without going back; a caller holding only a snapshot leaves it null.
  final Stream<SettingsUiState>? uiStateStream;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final SettingsSnapshot? snapshot = uiState.snapshot;
    final SettingsChannel channel = SettingsChannel(
      state: uiState,
      onAction: onAction,
      stream: uiStateStream,
    );

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _SettingsHeader(
              onRefresh: () => onAction(const RefreshSettingsAction()),
            ),
            if (uiState.errorMessage case final String error)
              _ErrorBanner(
                message: error,
                onDismiss: () => onAction(const DismissSettingsError()),
              ),
            if (snapshot != null && uiState.isLoading)
              LinearProgressIndicator(
                minHeight: 2,
                color: scheme.primary,
                backgroundColor: Colors.transparent,
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: <Widget>[
                  _HostSection(uiState: uiState, snapshot: snapshot),
                  const SizedBox(height: 24),
                  const _AppSection(),
                  const SizedBox(height: 24),
                  _ChatSection(channel: channel),
                  const SizedBox(height: 24),
                  _ModelsSection(channel: channel),
                  const SizedBox(height: 24),
                  _PluginsSection(channel: channel),
                  const SizedBox(height: 24),
                  const _AboutSection(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Web panel header: the nav title 'Settings' beside the refresh action chrome.
class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              l10n.destinationSettings,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          SettingsCircleAction(
            icon: Icons.refresh,
            tooltip: l10n.refresh,
            onTap: onRefresh,
          ),
        ],
      ),
    );
  }
}

/// Opens one Settings sub-page on the root navigator, so the system back
/// gesture and the app-bar back button both return to the index.
void _pushSettingsPage(BuildContext context, Widget page) {
  unawaited(
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (BuildContext _) => page)),
  );
}

/// SECTION 1: the scoped host — its identity, the host sheet behind it, and
/// the battery exemption that keeps the connection alive with the screen off.
class _HostSection extends ConsumerWidget {
  const _HostSection({required this.uiState, required this.snapshot});

  final SettingsUiState uiState;
  final SettingsSnapshot? snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final SettingsSnapshot? snapshot = this.snapshot;

    final String scopedId = ref.watch(settingsBackendScopeProvider);
    final BackendRegistryState? registry = ref
        .watch(backendRegistryStateProvider)
        .value;
    final BackendConfig? backend = registry?.backends
        .where((BackendConfig b) => b.id == scopedId)
        .firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SettingsSectionHeading(title: l10n.settingsSectionHost),
        if (backend == null && uiState.isLoading)
          const SettingsSectionCard(
            children: <Widget>[
              Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
          )
        else if (snapshot == null && !uiState.isLoading)
          SettingsSectionCard(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(
                          Icons.cloud_off_outlined,
                          size: 20,
                          color: scheme.error,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          l10n.hostSettingsUnavailable,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: scheme.error,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.hostSettingsUnavailableBody,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: () => _openHostSheet(context, ref, snapshot),
                      style: settingsFilledCapsule(context),
                      child: Text(l10n.settingsCategoryHost),
                    ),
                  ],
                ),
              ),
            ],
          )
        else if (backend != null)
          SettingsSectionCard(
            children: <Widget>[
              _HostHeaderTile(
                backend: backend,
                scopedId: scopedId,
                activeId: registry?.activeId,
                onManage: () => _openHostSheet(context, ref, snapshot),
              ),
            ],
          ),
        // The battery-optimization exemption is device-local and independent
        // of host settings, so it keeps its own card and stays visible even
        // while the host describe is loading or unavailable.
        const SizedBox(height: 12),
        const SettingsSectionCard(
          children: <Widget>[SettingsBatteryOptimizationRow()],
        ),
      ],
    );
  }
}

/// Host header tile showing the active scoped host with live connection dot.
class _HostHeaderTile extends ConsumerWidget {
  const _HostHeaderTile({
    required this.backend,
    required this.scopedId,
    required this.activeId,
    required this.onManage,
  });

  final BackendConfig backend;
  final String scopedId;
  final String? activeId;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final domain.ConnectionState? connection = ref
        .watch(backendConnectionStateProvider(backend.id))
        .value;
    final String version = connection?.hostDescription?.version ?? '';
    final String endpoint = '${backend.baseUri.host}:${backend.baseUri.port}';
    final String subtitle = version.isEmpty
        ? endpoint
        : '$endpoint · ${l10n.backendVersion(version)}';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onManage,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: <Widget>[
              BackendConnectionDot(
                backendId: scopedId,
                enabled: backend.enabled,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      backend.label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (backend.id == activeId) ...<Widget>[
                const SizedBox(width: 8),
                SettingsBadge(
                  label: l10n.backendStatusActive,
                  tone: SettingsBadgeTone.primary,
                ),
              ],
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// SECTION 2: device-local preferences, each one choice deep.
class _AppSection extends StatelessWidget {
  const _AppSection();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SettingsSectionHeading(
          title: l10n.settingsSectionApp,
          intro: l10n.appSettingsIntro,
        ),
        const SettingsSectionCard(
          children: <Widget>[
            _LanguageRow(),
            SettingsCardDivider(),
            SettingsAppearanceEntryRow(),
            SettingsCardDivider(),
            _AsrModelsEntryRow(),
            SettingsCardDivider(),
            _ErrorLogsEntryRow(),
          ],
        ),
      ],
    );
  }
}

/// SECTION 3: how a session starts and behaves — the busy-Enter behavior and
/// the default agent preset.
class _ChatSection extends StatelessWidget {
  const _ChatSection({required this.channel});

  final SettingsChannel channel;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SettingsSectionHeading(
          title: l10n.settingsSectionChat,
          intro: l10n.generalIntro,
        ),
        SettingsSectionCard(
          children: <Widget>[
            const _EnterBehaviorEntryRow(),
            const SettingsCardDivider(),
            _AgentPresetEntryRow(channel: channel),
          ],
        ),
      ],
    );
  }
}

/// SECTION 4: the credential records and the provider directory behind them.
class _ModelsSection extends StatelessWidget {
  const _ModelsSection({required this.channel});

  final SettingsChannel channel;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SettingsSectionHeading(title: l10n.settingsSectionModels),
        SettingsSectionCard(
          children: <Widget>[
            SettingsNavRow(
              title: l10n.settingsNavCredentials,
              leading: const Icon(Icons.key_outlined),
              onTap: () => _pushSettingsPage(
                context,
                SettingsCredentialsPage(channel: channel),
              ),
            ),
            const SettingsCardDivider(),
            SettingsNavRow(
              title: l10n.settingsSectionProviders,
              leading: const Icon(Icons.hub_outlined),
              onTap: () =>
                  _pushSettingsPage(context, const SettingsProvidersPage()),
            ),
          ],
        ),
      ],
    );
  }
}

/// SECTION 5: the host settings namespaces and the read-only plugin roster.
class _PluginsSection extends StatelessWidget {
  const _PluginsSection({required this.channel});

  final SettingsChannel channel;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SettingsSectionHeading(
          title: l10n.settingsSectionPlugins,
          intro: l10n.pluginsIntro,
        ),
        SettingsSectionCard(
          children: <Widget>[
            SettingsNavRow(
              title: l10n.settingsNavPluginSettings,
              leading: const Icon(Icons.extension_outlined),
              onTap: () => _pushSettingsPage(
                context,
                SettingsPluginsPage(channel: channel),
              ),
            ),
            const SettingsCardDivider(),
            SettingsNavRow(
              title: l10n.settingsSectionPluginInventory,
              leading: const Icon(Icons.widgets_outlined),
              onTap: () => _pushSettingsPage(
                context,
                const SettingsPluginInventoryPage(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// SECTION 6: About. The row names itself; no heading repeats it.
class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return SettingsSectionCard(
      children: <Widget>[
        SettingsNavRow(
          title: l10n.settingsSectionAbout,
          leading: const Icon(Icons.info_outline),
          onTap: () => _pushSettingsPage(context, const SettingsAboutPage()),
        ),
      ],
    );
  }
}

/// Language preference row: the interface language, chosen in a sheet so the
/// three options cost the index one line instead of three capsules.
class _LanguageRow extends ConsumerWidget {
  const _LanguageRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final LocalePreferenceController? controller = ref
        .watch(localePreferenceProvider)
        .value;
    if (controller == null) {
      return SettingsNavRow(
        title: l10n.languageLabel,
        leading: const Icon(Icons.language_outlined),
        enabled: false,
        onTap: () {},
      );
    }
    return StreamBuilder<AppLocalePreference>(
      stream: controller.uiState,
      initialData: controller.state,
      builder:
          (BuildContext context, AsyncSnapshot<AppLocalePreference> snapshot) {
            final AppLocalePreference current =
                snapshot.data ?? AppLocalePreference.system;
            return SettingsNavRow(
              title: l10n.languageLabel,
              leading: const Icon(Icons.language_outlined),
              value: _languageLabel(l10n, current),
              onTap: () => _choose(context, controller, current),
            );
          },
    );
  }

  Future<void> _choose(
    BuildContext context,
    LocalePreferenceController controller,
    AppLocalePreference current,
  ) async {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final AppLocalePreference? picked =
        await showSettingsChoiceSheet<AppLocalePreference>(
          context,
          title: l10n.languageLabel,
          description: l10n.languageDescription,
          current: current,
          choices: <SettingsChoice<AppLocalePreference>>[
            for (final AppLocalePreference option in AppLocalePreference.values)
              SettingsChoice<AppLocalePreference>(
                value: option,
                label: _languageLabel(l10n, option),
              ),
          ],
        );
    if (picked != null) await controller.select(picked);
  }
}

String _languageLabel(AppLocalizations l10n, AppLocalePreference option) =>
    switch (option) {
      AppLocalePreference.system => l10n.languageOptionSystem,
      AppLocalePreference.zh => l10n.languageOptionZh,
      AppLocalePreference.en => l10n.languageOptionEn,
    };

/// ASR models entry row navigating to on-device speech recognition management.
class _AsrModelsEntryRow extends ConsumerWidget {
  const _AsrModelsEntryRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final AsrModelsUiState asrState =
        ref.watch(asrModelsUiStateProvider).value ?? const AsrModelsUiState();
    return SettingsNavRow(
      title: l10n.asrModelsTitle,
      leading: const Icon(Icons.mic_none_outlined),
      trailing: SettingsBadge(
        label: l10n.asrInstalledCount(
          asrState.installedCount,
          asrState.totalCount > 0 ? asrState.totalCount : 4,
        ),
        tone: asrState.installedCount > 0
            ? SettingsBadgeTone.primary
            : SettingsBadgeTone.neutral,
      ),
      onTap: () => _pushSettingsPage(context, const AsrModelsRoute()),
    );
  }
}

/// Error logs entry row navigating to error log viewing and copying.
class _ErrorLogsEntryRow extends ConsumerWidget {
  const _ErrorLogsEntryRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ErrorLogsUiState errorState =
        ref.watch(errorLogsUiStateProvider).value ?? const ErrorLogsUiState();
    final bool failed = errorState.fatalCount > 0 || errorState.errorCount > 0;
    return SettingsNavRow(
      title: l10n.errorLogsTitle,
      leading: const Icon(Icons.bug_report_outlined),
      trailing: SettingsBadge(
        label: l10n.errorLogsCountBadge(errorState.totalCount),
        tone: failed ? SettingsBadgeTone.error : SettingsBadgeTone.neutral,
      ),
      onTap: () => _pushSettingsPage(context, const ErrorLogsRoute()),
    );
  }
}

/// The busy-Enter behavior row: the current mode in words, chosen in a sheet.
class _EnterBehaviorEntryRow extends ConsumerWidget {
  const _EnterBehaviorEntryRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final BusyEnterPreferenceController? controller = ref
        .watch(busyEnterPreferenceProvider)
        .value;
    if (controller == null) {
      return SettingsNavRow(
        title: l10n.busyPreferenceLabel,
        leading: const Icon(Icons.keyboard_return),
        enabled: false,
        onTap: () {},
      );
    }
    return StreamBuilder<BusyEnterBehavior>(
      stream: controller.uiState,
      initialData: controller.state,
      builder:
          (BuildContext context, AsyncSnapshot<BusyEnterBehavior> snapshot) {
            final BusyEnterBehavior current =
                snapshot.data ?? BusyEnterBehavior.queue;
            return SettingsNavRow(
              title: l10n.busyPreferenceLabel,
              leading: const Icon(Icons.keyboard_return),
              value: _busyBehaviorLabel(l10n, current),
              onTap: () => _choose(context, controller, current),
            );
          },
    );
  }

  Future<void> _choose(
    BuildContext context,
    BusyEnterPreferenceController controller,
    BusyEnterBehavior current,
  ) async {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final BusyEnterBehavior? picked =
        await showSettingsChoiceSheet<BusyEnterBehavior>(
          context,
          title: l10n.busyPreferenceLabel,
          description: l10n.busyPreferenceDescription,
          current: current,
          choices: <SettingsChoice<BusyEnterBehavior>>[
            for (final BusyEnterBehavior option in BusyEnterBehavior.values)
              SettingsChoice<BusyEnterBehavior>(
                value: option,
                label: _busyBehaviorLabel(l10n, option),
              ),
          ],
        );
    if (picked != null) await controller.select(picked);
  }
}

String _busyBehaviorLabel(AppLocalizations l10n, BusyEnterBehavior option) =>
    switch (option) {
      BusyEnterBehavior.queue => l10n.busyBehaviorQueue,
      BusyEnterBehavior.steer => l10n.busyBehaviorSteer,
    };

/// The default agent preset: one row stating the current default, opening the
/// one page that selects it. There is no second picker beside it.
class _AgentPresetEntryRow extends StatelessWidget {
  const _AgentPresetEntryRow({required this.channel});

  final SettingsChannel channel;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return SettingsLive(
      channel: channel,
      builder:
          (
            BuildContext context,
            SettingsUiState state,
            void Function(SettingsAction) _,
          ) {
            final AgentPresetRoster? roster = state.roster;
            final AgentPresetEntry? current = _pickerOptions(roster)
                .firstOrNull;
            final AgentPresetEntry? shown = roster?.defaultEntry ?? current;
            return SettingsNavRow(
              title: l10n.agentPresetPreferenceLabel,
              leading: const Icon(Icons.smart_toy_outlined),
              value: shown == null ? null : agentPresetDisplayName(shown, l10n),
              // Always navigable: an unloaded or empty roster is a page that
              // states it, never a dead row.
              onTap: () => _pushSettingsPage(
                context,
                SettingsAgentPresetsPage(channel: channel),
              ),
            );
          },
    );
  }
}

/// The presets a session can actually be started with: a broken one stays
/// listed on the roster page (its directory still owns the id) but is never
/// offered as the default (web `presetOptions`).
List<AgentPresetEntry> _pickerOptions(AgentPresetRoster? roster) =>
    roster?.entries
        .where((AgentPresetEntry entry) => entry.broken == null)
        .toList() ??
    const <AgentPresetEntry>[];

/// The host sheet: the settings scope, the registry, and the scoped host's
/// own facts. It is the whole host dimension — no page repeats it.
Future<void> _openHostSheet(
  BuildContext context,
  WidgetRef ref,
  SettingsSnapshot? snapshot,
) {
  return showSettingsSheet<void>(
    context,
    builder: (BuildContext sheetContext) => _HostSheet(snapshot: snapshot),
  );
}

class _HostSheet extends ConsumerWidget {
  const _HostSheet({required this.snapshot});

  final SettingsSnapshot? snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(allBackendConnectionsProvider);
    final BackendRegistryState? registry = ref
        .watch(backendRegistryStateProvider)
        .value;
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final String scopedId = ref.watch(settingsBackendScopeProvider);
    final bool pinned = ref
        .watch(settingsBackendScopeProvider.notifier)
        .isPinned;
    if (registry == null) return const SizedBox.shrink();
    final SettingsSnapshot? facts = snapshot;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.settingsScopeTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            l10n.settingsScopeHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          if (registry.errorMessage case final String message)
            _RegistryErrorLine(message: describeBackendError(l10n, message)),
          if (pinned && registry.backends.length > 1)
            _HostSheetRow(
              leading: Icon(
                Icons.autorenew,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
              title: l10n.settingsScopeFollowActive,
              subtitle: null,
              active: false,
              selected: false,
              onTap: () {
                Navigator.of(context).pop();
                ref.read(settingsBackendScopeProvider.notifier).followActive();
              },
            ),
          for (final BackendConfig backend in registry.backends)
            _HostSheetRow(
              backendId: backend.id,
              title: backend.label,
              subtitle: '${backend.baseUri.host}:${backend.baseUri.port}',
              active: backend.id == registry.activeId,
              selected: backend.id == scopedId,
              enabled: backend.enabled,
              // Tapping pins the settings scope; the scope only ever
              // describes a connected host, so a disabled row's tap
              // does nothing (the switch is its control).
              onTap: backend.enabled
                  ? () {
                      Navigator.of(context).pop();
                      ref
                          .read(settingsBackendScopeProvider.notifier)
                          .select(backend.id);
                    }
                  : null,
              onToggleEnabled: () => _dispatchBackendAction(
                ref,
                SetBackendEnabled(backend.id, !backend.enabled),
              ),
              onEdit: () => _openBackendSheet(
                context,
                ref,
                backend,
                removeBlockedReason: _removeBlockedReason(
                  registry,
                  backend,
                  l10n,
                ),
              ),
            ),
          const SizedBox(height: 4),
          Center(
            child: OutlinedButton(
              onPressed: () => _openBackendSheet(context, ref, null),
              style: settingsOutlineCapsule(context),
              child: Text(l10n.addBackend),
            ),
          ),
          // The scoped host's own settings plane: the facts the root used to
          // carry, stated where the scope is chosen.
          if (facts != null) ...<Widget>[
            const SizedBox(height: 12),
            Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
            const SizedBox(height: 8),
            Text(
              l10n.settingsScopeFactsTitle,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            SettingsFactRow(
              title: l10n.hostWritesLabel,
              description: l10n.hostWritesDescription,
              value: facts.writable ? l10n.writableValue : l10n.readOnlyValue,
              tone: facts.writable
                  ? SettingsFactTone.positive
                  : SettingsFactTone.warning,
            ),
            SettingsFactRow(
              title: l10n.settingsDocumentLabel,
              description: l10n.settingsDocumentDescription,
              value: facts.hasDocument ? l10n.presentValue : l10n.noneValue,
              tone: facts.hasDocument
                  ? SettingsFactTone.positive
                  : SettingsFactTone.neutral,
            ),
          ],
        ],
      ),
    );
  }
}

class _HostSheetRow extends ConsumerWidget {
  const _HostSheetRow({
    required this.title,
    required this.subtitle,
    required this.active,
    required this.selected,
    required this.onTap,
    this.backendId,
    this.onEdit,
    this.onToggleEnabled,
    this.enabled = true,
    this.leading,
  });

  final String? backendId;
  final Widget? leading;
  final String title;
  final String? subtitle;
  final bool active;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;

  /// The enable/disable switch verb; null on rows that manage no backend
  /// (the follow-active entry).
  final VoidCallback? onToggleEnabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final String? backendId = this.backendId;
    // The version reads the live connection; a disabled backend has
    // none, and its state is told by the disabled badge instead.
    final String version = backendId == null || !enabled
        ? ''
        : ref
                  .watch(backendConnectionStateProvider(backendId))
                  .value
                  ?.hostDescription
                  ?.version ??
              '';
    final String? formattedSubtitle = subtitle == null
        ? null
        : (version.isEmpty
              ? subtitle!
              : '$subtitle · ${l10n.backendVersion(version)}');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(kShapeChip),
        hoverColor: scheme.surfaceContainerHigh,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: <Widget>[
              if (leading != null)
                leading!
              else if (backendId != null)
                BackendConnectionDot(backendId: backendId, enabled: enabled)
              else
                const SizedBox(width: 8),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: theme.textTheme.bodyMedium),
                    if (formattedSubtitle != null) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        formattedSubtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (active) ...<Widget>[
                const SizedBox(width: 8),
                SettingsBadge(
                  label: l10n.backendStatusActive,
                  tone: SettingsBadgeTone.primary,
                ),
              ],
              if (!enabled) ...<Widget>[
                const SizedBox(width: 8),
                SettingsBadge(label: l10n.backendStatusDisabled),
              ],
              if (selected) ...<Widget>[
                const SizedBox(width: 8),
                Icon(Icons.check, size: 18, color: scheme.primary),
              ],
              if (onToggleEnabled != null) ...<Widget>[
                const SizedBox(width: 4),
                Tooltip(
                  message: enabled
                      ? l10n.backendDisableTooltip
                      : l10n.backendEnableTooltip,
                  child: Switch(
                    value: enabled,
                    onChanged: (bool _) => onToggleEnabled!(),
                  ),
                ),
              ],
              if (onEdit != null) ...<Widget>[
                const SizedBox(width: 4),
                SettingsCircleAction(
                  icon: Icons.edit_outlined,
                  iconSize: 16,
                  tooltip: l10n.editBackend,
                  onTap: onEdit!,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
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
                children: <Widget>[
                  Text(
                    message,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.settingsLoopbackHint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SettingsCircleAction(
            icon: Icons.close,
            iconSize: 14,
            tooltip: l10n.dismiss,
            onTap: onDismiss,
          ),
        ],
      ),
    );
  }
}

String? _removeBlockedReason(
  BackendRegistryState state,
  BackendConfig backend,
  AppLocalizations l10n,
) {
  if (backend.id == state.activeId) {
    return l10n.removeActiveBackendFirst;
  }
  if (state.backends.length <= 1) {
    return l10n.cannotRemoveLastBackend;
  }
  return null;
}

void _dispatchBackendAction(WidgetRef ref, BackendAction action) {
  unawaited(
    ref
        .read(backendRegistryProvider.future)
        .then(
          (BackendRegistryController controller) => controller.onAction(action),
        ),
  );
}

Future<void> _openBackendSheet(
  BuildContext context,
  WidgetRef ref,
  BackendConfig? backend, {
  String? removeBlockedReason,
}) {
  return showSettingsSheet<void>(
    context,
    isScrollControlled: true,
    builder: (BuildContext sheetContext) => _BackendSheet(
      backend: backend,
      removeBlockedReason: backend == null ? null : removeBlockedReason,
      onSave: (String label, String baseUrl, bool trustHostCertificate) {
        if (backend == null) {
          _dispatchBackendAction(
            ref,
            AddBackend(
              label,
              baseUrl,
              trustHostCertificate: trustHostCertificate,
            ),
          );
          return;
        }
        if (label != backend.label) {
          _dispatchBackendAction(ref, RenameBackend(backend.id, label));
        }
        if (baseUrl != backend.baseUri.toString()) {
          _dispatchBackendAction(ref, UpdateBackendUrl(backend.id, baseUrl));
        }
        if (trustHostCertificate != backend.trustHostCertificate) {
          _dispatchBackendAction(
            ref,
            SetBackendTrustHostCertificate(backend.id, trustHostCertificate),
          );
        }
      },
      onRemove: backend == null || removeBlockedReason != null
          ? null
          : () => _dispatchBackendAction(ref, RemoveBackend(backend.id)),
      onSetChatHost:
          backend != null &&
              backend.enabled &&
              backend.id !=
                  ref.read(backendRegistryStateProvider).value?.activeId
          ? () {
              _dispatchBackendAction(ref, SelectBackend(backend.id));
              Navigator.of(sheetContext).pop();
            }
          : null,
    ),
  );
}

class _RegistryErrorLine extends StatelessWidget {
  const _RegistryErrorLine({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
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

class _BackendSheet extends StatefulWidget {
  const _BackendSheet({
    required this.backend,
    required this.onSave,
    this.onRemove,
    this.removeBlockedReason,
    this.onSetChatHost,
  });

  final BackendConfig? backend;
  final void Function(String label, String baseUrl, bool trustHostCertificate)
  onSave;
  final VoidCallback? onRemove;
  final String? removeBlockedReason;
  final VoidCallback? onSetChatHost;

  @override
  State<_BackendSheet> createState() => _BackendSheetState();
}

class _BackendSheetState extends State<_BackendSheet> {
  late final TextEditingController _labelController;
  late final TextEditingController _urlController;
  late bool _trustHostCertificate;

  @override
  void initState() {
    super.initState();
    final BackendConfig? backend = widget.backend;
    _labelController = TextEditingController(text: backend?.label ?? '');
    _urlController = TextEditingController(
      text: backend?.baseUri.toString() ?? 'http://',
    );
    _trustHostCertificate = backend?.trustHostCertificate ?? false;
  }

  @override
  void dispose() {
    _labelController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  bool _validUrl(String raw) {
    final Uri? uri = Uri.tryParse(raw.trim());
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  bool get _canSave =>
      _labelController.text.trim().isNotEmpty && _validUrl(_urlController.text);

  /// The typed base URL once it is valid; null while the text is not (the
  /// reachability check stays disabled).
  Uri? get _parsedUrl {
    final String raw = _urlController.text.trim();
    return _validUrl(raw) ? Uri.parse(raw) : null;
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final bool editing = widget.backend != null;
    final bool urlValid = _validUrl(_urlController.text);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          editing ? l10n.editBackend : l10n.addBackend,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        SettingsFieldLabel(l10n.backendLabel),
        const SizedBox(height: 6),
        TextField(
          controller: _labelController,
          autofocus: !editing,
          decoration: settingsInputDecoration(
            context,
            hint: l10n.backendLabelHint,
          ),
          onChanged: (String _) => setState(() {}),
        ),
        const SizedBox(height: 12),
        SettingsFieldLabel(l10n.backendBaseUrlLabel),
        const SizedBox(height: 6),
        TextField(
          controller: _urlController,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: settingsInputDecoration(
            context,
            hint: l10n.backendBaseUrlHint,
          ),
          onChanged: (String _) => setState(() {}),
        ),
        const SizedBox(height: 8),
        Text(
          urlValid ? l10n.baseUrlDerivationHint : l10n.baseUrlValidHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: urlValid ? scheme.onSurfaceVariant : scheme.error,
          ),
        ),
        const SizedBox(height: 8),
        // The sheet's ink host stays a Material of its own, so the tile's
        // splash paints on the sheet surface rather than under it.
        Material(
          color: Colors.transparent,
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _trustHostCertificate,
            onChanged: (bool value) =>
                setState(() => _trustHostCertificate = value),
            title: Text(
              l10n.backendTrustCertificateTitle,
              style: theme.textTheme.bodyMedium,
            ),
            subtitle: Text(
              l10n.backendTrustCertificateDescription,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Runs on the explicit tap only; saving is never gated by it (a
        // host can be offline while it is configured).
        BackendReachabilityCheck(
          baseUri: _parsedUrl,
          trustHostCertificate: _trustHostCertificate,
        ),
        if (widget.onSetChatHost != null) ...<Widget>[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: widget.onSetChatHost,
              style: settingsOutlineCapsule(context),
              child: Text(l10n.setChatHost),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            if (editing)
              Expanded(
                child: widget.onRemove != null
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: widget.onRemove,
                          style: settingsDangerCapsule(context),
                          child: Text(l10n.remove),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Text(
                          widget.removeBlockedReason ?? '',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
              )
            else
              const Spacer(),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: settingsOutlineCapsule(context),
              child: Text(l10n.cancel),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _canSave
                  ? () {
                      widget.onSave(
                        _labelController.text.trim(),
                        _urlController.text.trim(),
                        _trustHostCertificate,
                      );
                      Navigator.of(context).pop();
                    }
                  : null,
              style: settingsFilledCapsule(context),
              child: Text(editing ? l10n.save : l10n.add),
            ),
          ],
        ),
      ],
    );
  }
}
