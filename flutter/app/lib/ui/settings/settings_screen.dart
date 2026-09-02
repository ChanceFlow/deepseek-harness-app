/// Settings screen — Modern grouped section cards layout for DSH Mobile.
///
/// Organized into distinct functional sections on a unified scrolling surface:
/// 1. **Host & Connection** — Identity, live connection status, endpoint,
///    write status, settings document status, and host management entry.
/// 2. **App Preferences** — Device-local preferences (interface language).
/// 3. **Chat & Agent** — Busy-Enter behavior, default preset picker, and
///    the full preset roster cards.
/// 4. **Models & Credentials** — DeepSeek API key and host secret references.
/// 5. **Plugins & Advanced** — Host settings namespaces with in-place editors.
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
import 'busy_enter_preference.dart';
import 'locale_preference.dart';
import 'settings_backend_scope.dart';
import 'settings_controller.dart';
import 'settings_ui_state.dart';

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
        return SettingsScreen(uiState: uiState, onAction: controller.onAction);
      },
    );
  }
}

/// The credential reference the official DeepSeek route resolves by default.
const String _kDeepSeekCredentialRef = 'DEEPSEEK_API_KEY';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    required this.uiState,
    required this.onAction,
    super.key,
  });

  final SettingsUiState uiState;
  final void Function(SettingsAction) onAction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final SettingsSnapshot? snapshot = uiState.snapshot;

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
                  // 1. Host & Connection section
                  _HostSection(
                    uiState: uiState,
                    snapshot: snapshot,
                    onAction: onAction,
                  ),
                  const SizedBox(height: 24),

                  // 2. App Preferences section
                  const _AppPreferencesSection(),
                  const SizedBox(height: 24),

                  // 3. Chat & Agent section
                  _ChatAgentSection(
                    snapshot: snapshot,
                    roster: uiState.roster,
                    busy: uiState.isLoading,
                    onAction: onAction,
                  ),
                  const SizedBox(height: 24),

                  // 4. Models & Credentials section
                  _ModelsCredentialsSection(
                    snapshot: snapshot,
                    credentials: uiState.credentials,
                    credentialError: uiState.credentialError,
                    onAction: onAction,
                  ),
                  const SizedBox(height: 24),

                  // 5. Plugins & Advanced section
                  _PluginsAdvancedSection(
                    snapshot: snapshot,
                    busy: uiState.isLoading,
                    onAction: onAction,
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
          _CircleAction(
            icon: Icons.refresh,
            tooltip: l10n.refresh,
            onTap: onRefresh,
          ),
        ],
      ),
    );
  }
}

/// Unified section heading with optional subtitle.
class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, this.intro});

  final String title;
  final String? intro;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (intro != null) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              intro!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Standard grouped container card for setting items.
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(kShapeCard),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

/// Thin hairline divider between items inside a section card.
class _CardDivider extends StatelessWidget {
  const _CardDivider();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Divider(height: 1, thickness: 1, color: scheme.outlineVariant);
  }
}

/// SECTION 1: Host & Connection section.
class _HostSection extends ConsumerWidget {
  const _HostSection({
    required this.uiState,
    required this.snapshot,
    required this.onAction,
  });

  final SettingsUiState uiState;
  final SettingsSnapshot? snapshot;
  final void Function(SettingsAction) onAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

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
        _SectionHeading(title: l10n.settingsSectionHost),
        if (backend == null && uiState.isLoading)
          const _SectionCard(
            children: <Widget>[
              Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
          )
        else if (snapshot == null && !uiState.isLoading)
          _SectionCard(
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
                      onPressed: () => _openHostSheet(context, ref),
                      style: _filledCapsule(context),
                      child: Text(l10n.settingsCategoryHost),
                    ),
                  ],
                ),
              ),
            ],
          )
        else ...<Widget>[
          _SectionCard(
            children: <Widget>[
              if (backend != null) ...<Widget>[
                _HostHeaderTile(
                  backend: backend,
                  scopedId: scopedId,
                  activeId: registry?.activeId,
                  onManage: () => _openHostSheet(context, ref),
                ),
                const _CardDivider(),
              ],
              if (snapshot != null) ...<Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _GeneralRow(
                    title: l10n.hostWritesLabel,
                    description: l10n.hostWritesDescription,
                    value: snapshot!.writable
                        ? l10n.writableValue
                        : l10n.readOnlyValue,
                    tone: snapshot!.writable
                        ? _FactTone.positive
                        : _FactTone.warning,
                  ),
                ),
                const _CardDivider(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _GeneralRow(
                    title: l10n.settingsDocumentLabel,
                    description: l10n.settingsDocumentDescription,
                    value: snapshot!.hasDocument
                        ? l10n.presentValue
                        : l10n.noneValue,
                    tone: snapshot!.hasDocument
                        ? _FactTone.positive
                        : _FactTone.neutral,
                  ),
                ),
              ],
            ],
          ),
        ],
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
                _StateBadge(configured: true, label: l10n.backendStatusActive),
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

/// SECTION 2: App Preferences section (Language & ASR Models).
class _AppPreferencesSection extends StatelessWidget {
  const _AppPreferencesSection();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _SectionHeading(
          title: l10n.settingsSectionApp,
          intro: l10n.appSettingsIntro,
        ),
        const _SectionCard(
          children: <Widget>[
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: _LanguageRow(),
            ),
            _CardDivider(),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: _AsrModelsEntryRow(),
            ),
          ],
        ),
      ],
    );
  }
}

/// SECTION 3: Chat & Agent section (Busy-Enter + Agent Presets).
class _ChatAgentSection extends StatelessWidget {
  const _ChatAgentSection({
    required this.snapshot,
    required this.roster,
    required this.busy,
    required this.onAction,
  });

  final SettingsSnapshot? snapshot;
  final AgentPresetRoster? roster;
  final bool busy;
  final void Function(SettingsAction) onAction;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final List<AgentPresetEntry> entries =
        roster?.entries ?? const <AgentPresetEntry>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _SectionHeading(
          title: l10n.settingsSectionChat,
          intro: l10n.generalIntro,
        ),
        _SectionCard(
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: _EnterBehaviorRow(),
            ),
            if (entries.isNotEmpty) ...<Widget>[
              const _CardDivider(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _AgentPresetRow(
                  roster: roster!,
                  writable: snapshot?.writable ?? false,
                  busy: busy,
                  onAction: onAction,
                ),
              ),
              const _CardDivider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      l10n.settingsNavAgentPresets,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.agentPresetsIntro,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final (AgentPresetTrust trust, String heading)
                        in <(AgentPresetTrust, String)>[
                          (AgentPresetTrust.system, l10n.presetGroupBuiltIn),
                          (AgentPresetTrust.user, l10n.presetGroupCustom),
                        ])
                      if (entries.any(
                        (AgentPresetEntry entry) => entry.trust == trust,
                      )) ...<Widget>[
                        Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 8),
                          child: Text(
                            heading,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                        for (final AgentPresetEntry entry in entries.where(
                          (AgentPresetEntry e) => e.trust == trust,
                        )) ...<Widget>[
                          _PresetCard(
                            key: ValueKey<String>(entry.id),
                            entry: entry,
                            onAction: onAction,
                          ),
                          const SizedBox(height: 8),
                        ],
                      ],
                    const SizedBox(height: 4),
                    Text(
                      l10n.presetsFooter,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (roster != null) ...<Widget>[
              const _CardDivider(),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  l10n.presetsFooter,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// SECTION 4: Models & Credentials section.
class _ModelsCredentialsSection extends StatelessWidget {
  const _ModelsCredentialsSection({
    required this.snapshot,
    required this.credentials,
    required this.credentialError,
    required this.onAction,
  });

  final SettingsSnapshot? snapshot;
  final List<CredentialStatus> credentials;
  final String? credentialError;
  final void Function(SettingsAction) onAction;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final CredentialStatus? deepSeek = credentials
        .where((CredentialStatus c) => c.ref == _kDeepSeekCredentialRef)
        .firstOrNull;
    final List<CredentialStatus> otherCredentials = credentials
        .where((CredentialStatus c) => c.ref != _kDeepSeekCredentialRef)
        .toList();
    final bool writable = snapshot?.writable ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _SectionHeading(
          title: l10n.settingsSectionModels,
          intro: l10n.modelsIntro,
        ),
        _SectionCard(
          children: <Widget>[
            if (snapshot != null && !writable)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  l10n.settingsReadOnlyNotice,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (deepSeek != null) ...<Widget>[
              Padding(
                padding: const EdgeInsets.all(12),
                child: _DeepSeekCard(credential: deepSeek, onAction: onAction),
              ),
            ],
            if (otherCredentials.isNotEmpty) ...<Widget>[
              if (deepSeek != null) const _CardDivider(),
              for (int i = 0; i < otherCredentials.length; i++) ...<Widget>[
                if (i > 0) const _CardDivider(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _CredentialRow(
                    key: ValueKey<String>(otherCredentials[i].ref),
                    credential: otherCredentials[i],
                    onAction: onAction,
                  ),
                ),
              ],
            ],
            if (credentialError case final String error) ...<Widget>[
              const _CardDivider(),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  l10n.credentialStateUnavailable(error),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            if (credentials.isEmpty) ...<Widget>[
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  l10n.noCredentialsReferenced,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            const _CardDivider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Text(
                l10n.modelsFooter,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// SECTION 5: Plugins & Advanced section.
class _PluginsAdvancedSection extends StatelessWidget {
  const _PluginsAdvancedSection({
    required this.snapshot,
    required this.busy,
    required this.onAction,
  });

  final SettingsSnapshot? snapshot;
  final bool busy;
  final void Function(SettingsAction) onAction;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final List<SettingsNamespace> namespaces =
        snapshot?.namespaces ?? const <SettingsNamespace>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _SectionHeading(
          title: l10n.settingsSectionPlugins,
          intro: l10n.pluginsIntro,
        ),
        _SectionCard(
          children: <Widget>[
            if (namespaces.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  l10n.noPluginSettings,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              for (int i = 0; i < namespaces.length; i++) ...<Widget>[
                if (i > 0) const _CardDivider(),
                _NamespaceCard(
                  key: ValueKey<String>(namespaces[i].ns),
                  namespace: namespaces[i],
                  writable: snapshot?.writable ?? false,
                  busy: busy,
                  onAction: onAction,
                ),
              ],
          ],
        ),
      ],
    );
  }
}

/// Language preference row: the interface language as a capsule selector.
class _LanguageRow extends ConsumerWidget {
  const _LanguageRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final LocalePreferenceController? controller = ref
        .watch(localePreferenceProvider)
        .value;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.languageLabel,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.languageDescription,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          if (controller == null)
            _languageCapsules(context, AppLocalePreference.system, null)
          else
            StreamBuilder<AppLocalePreference>(
              stream: controller.uiState,
              initialData: controller.state,
              builder:
                  (
                    BuildContext context,
                    AsyncSnapshot<AppLocalePreference> snapshot,
                  ) => _languageCapsules(
                    context,
                    snapshot.data ?? AppLocalePreference.system,
                    controller.select,
                  ),
            ),
        ],
      ),
    );
  }

  Widget _languageCapsules(
    BuildContext context,
    AppLocalePreference current,
    ValueChanged<AppLocalePreference>? onSelect,
  ) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return Wrap(
      spacing: 8,
      children: <Widget>[
        for (final AppLocalePreference option in AppLocalePreference.values)
          _ModeButton(
            label: switch (option) {
              AppLocalePreference.system => l10n.languageOptionSystem,
              AppLocalePreference.zh => l10n.languageOptionZh,
              AppLocalePreference.en => l10n.languageOptionEn,
            },
            selected: option == current,
            onTap: onSelect == null ? null : () => onSelect(option),
          ),
      ],
    );
  }
}

/// ASR models entry row navigating to on-device speech recognition management.
class _AsrModelsEntryRow extends ConsumerWidget {
  const _AsrModelsEntryRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final AsrModelsUiState asrState =
        ref.watch(asrModelsUiStateProvider).value ?? const AsrModelsUiState();

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (BuildContext _) => const AsrModelsRoute(),
          ),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    l10n.asrModelsTitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.asrModelsDescription,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: asrState.installedCount > 0
                    ? scheme.primaryContainer
                    : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                l10n.asrInstalledCount(
                  asrState.installedCount,
                  asrState.totalCount > 0 ? asrState.totalCount : 4,
                ),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: asrState.installedCount > 0
                      ? scheme.onPrimaryContainer
                      : scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 20, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// The host sheet: managing hosts, switching active, pinning scope.
Future<void> _openHostSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (BuildContext sheetContext) {
      final ColorScheme scheme = Theme.of(sheetContext).colorScheme;
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(kShapeSheet),
            border: Border.all(color: scheme.outlineVariant),
            boxShadow: kM3ShadowElevation3,
          ),
          child: const SafeArea(top: false, child: _HostSheet()),
        ),
      );
    },
  );
}

class _HostSheet extends ConsumerWidget {
  const _HostSheet();

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
    return Column(
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
            // describes a connected host, so a disabled row's tap does
            // nothing (the switch is its control).
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
            style: _outlineCapsule(context),
            child: Text(l10n.addBackend),
          ),
        ),
      ],
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
        borderRadius: BorderRadius.circular(8),
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
                _StateBadge(configured: true, label: l10n.backendStatusActive),
              ],
              if (!enabled) ...<Widget>[
                const SizedBox(width: 8),
                _StateBadge(
                  configured: false,
                  label: l10n.backendStatusDisabled,
                ),
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
                _CircleAction(
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
          _CircleAction(
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
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext sheetContext) {
      final double insets = MediaQuery.of(sheetContext).viewInsets.bottom;
      final ColorScheme scheme = Theme.of(sheetContext).colorScheme;
      return Padding(
        padding: EdgeInsets.fromLTRB(8, 0, 8, 8 + insets),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(kShapeSheet),
            border: Border.all(color: scheme.outlineVariant),
            boxShadow: kM3ShadowElevation3,
          ),
          child: _BackendSheet(
            backend: backend,
            removeBlockedReason: backend == null ? null : removeBlockedReason,
            onSave: (String label, String baseUrl) {
              if (backend == null) {
                _dispatchBackendAction(ref, AddBackend(label, baseUrl));
                return;
              }
              if (label != backend.label) {
                _dispatchBackendAction(ref, RenameBackend(backend.id, label));
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
        ),
      );
    },
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

List<AgentPresetEntry> _pickerOptions(AgentPresetRoster? roster) =>
    roster?.entries
        .where((AgentPresetEntry entry) => entry.broken == null)
        .toList() ??
    const <AgentPresetEntry>[];

class _EnterBehaviorRow extends ConsumerWidget {
  const _EnterBehaviorRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final BusyEnterPreferenceController? controller = ref
        .watch(busyEnterPreferenceProvider)
        .value;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.busyPreferenceLabel,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.busyPreferenceDescription,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          if (controller == null)
            _enterBehaviorCapsules(context, BusyEnterBehavior.queue, null)
          else
            StreamBuilder<BusyEnterBehavior>(
              stream: controller.uiState,
              initialData: controller.state,
              builder:
                  (
                    BuildContext context,
                    AsyncSnapshot<BusyEnterBehavior> snapshot,
                  ) => _enterBehaviorCapsules(
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
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return Wrap(
      spacing: 8,
      children: <Widget>[
        for (final BusyEnterBehavior option in BusyEnterBehavior.values)
          _ModeButton(
            label: switch (option) {
              BusyEnterBehavior.queue => l10n.busyBehaviorQueue,
              BusyEnterBehavior.steer => l10n.busyBehaviorSteer,
            },
            selected: option == current,
            onTap: onSelect == null ? null : () => onSelect(option),
          ),
      ],
    );
  }
}

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
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final List<AgentPresetEntry> options = _pickerOptions(roster);
    final AgentPresetEntry current =
        roster.defaultEntry ?? roster.entries.first;
    final bool enabled = writable && !busy && options.isNotEmpty;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? () => _openPicker(context, options) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      l10n.agentPresetLabel,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.agentPresetPreferenceDescription,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                agentPresetDisplayName(current, l10n),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 4),
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

  Future<void> _openPicker(
    BuildContext context,
    List<AgentPresetEntry> options,
  ) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final String currentId = (roster.defaultEntry ?? roster.entries.first).id;
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        final ColorScheme scheme = Theme.of(sheetContext).colorScheme;
        final ThemeData theme = Theme.of(sheetContext);
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainer,
              borderRadius: BorderRadius.circular(kShapeSheet),
              border: Border.all(color: scheme.outlineVariant),
              boxShadow: kM3ShadowElevation3,
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    l10n.agentPresetLabel,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  for (final AgentPresetEntry option in options)
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        hoverColor: scheme.surfaceContainerHigh,
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          onAction(SelectAgentPresetDefaultAction(option.id));
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  agentPresetDisplayName(option, l10n),
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                              if (option.id == currentId)
                                Icon(
                                  Icons.check,
                                  size: 16,
                                  color: scheme.primary,
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

class _PresetCard extends StatelessWidget {
  const _PresetCard({required this.entry, required this.onAction, super.key});

  final AgentPresetEntry entry;
  final void Function(SettingsAction) onAction;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final bool broken = entry.broken != null;
    final bool active = entry.isDefault;
    final String description =
        agentPresetDisplayDescription(entry, l10n) ?? l10n.noDescription;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: active
            ? scheme.surfaceContainerHigh
            : scheme.surfaceContainerHighest,
        border: Border.all(
          color: broken
              ? theme.colorScheme.error
              : active
              ? scheme.primary
              : scheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(kShapeCard),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(kShapeCard),
          hoverColor: scheme.surfaceContainerHigh,
          onTap: broken || active
              ? null
              : () => onAction(SelectAgentPresetDefaultAction(entry.id)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        agentPresetDisplayName(entry, l10n),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (broken) ...<Widget>[
                      const SizedBox(width: 8),
                      _PresetBadge(label: l10n.presetBrokenBadge, filled: true),
                    ],
                    if (entry.trust == AgentPresetTrust.user) ...<Widget>[
                      const SizedBox(width: 8),
                      _PresetBadge(label: l10n.presetGroupCustom),
                    ],
                    if (active) ...<Widget>[
                      const SizedBox(width: 8),
                      const Spacer(),
                      _PresetBadge(
                        label: l10n.presetInUseBadge,
                        inverted: true,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Tooltip(
                  message: description,
                  child: Text(
                    description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (broken) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
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
                    color: scheme.outline,
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
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final ThemeData theme = Theme.of(context);
    final Color background;
    final Color foreground;
    if (filled) {
      background = theme.colorScheme.error;
      foreground = scheme.surfaceContainerHighest;
    } else if (inverted) {
      background = scheme.primary;
      foreground = scheme.onPrimary;
    } else {
      background = Colors.transparent;
      foreground = scheme.onSurfaceVariant;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: filled || inverted
            ? null
            : Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: foreground),
      ),
    );
  }
}

class _DeepSeekCard extends StatelessWidget {
  const _DeepSeekCard({required this.credential, required this.onAction});

  final CredentialStatus credential;
  final void Function(SettingsAction) onAction;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(kShapeCard),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(kShapeCard),
          hoverColor: scheme.surfaceContainerHigh,
          onTap: () => _openSheet(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'DeepSeek',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        credential.configured
                            ? l10n.apiKeyConfigured
                            : l10n.apiKeyMissing,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _StatusDot(
                  color: credential.configured ? scheme.success : scheme.error,
                ),
                const SizedBox(width: 6),
                _StateBadge(configured: credential.configured),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        final double insets = MediaQuery.of(sheetContext).viewInsets.bottom;
        final ColorScheme scheme = Theme.of(sheetContext).colorScheme;
        return Padding(
          padding: EdgeInsets.fromLTRB(8, 0, 8, 8 + insets),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainer,
              borderRadius: BorderRadius.circular(kShapeSheet),
              border: Border.all(color: scheme.outlineVariant),
              boxShadow: kM3ShadowElevation3,
            ),
            child: _CredentialSheet(credential: credential, onAction: onAction),
          ),
        );
      },
    );
  }
}

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
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final (Color dotColor, Color textColor) = _toneColors(scheme, tone);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
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

enum _FactTone { positive, warning, neutral }

(Color, Color) _toneColors(ColorScheme scheme, _FactTone tone) =>
    switch (tone) {
      _FactTone.positive => (scheme.success, scheme.onSurfaceVariant),
      _FactTone.warning => (scheme.error, scheme.onErrorContainer),
      _FactTone.neutral => (scheme.outline, scheme.onSurfaceVariant),
    };

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

class _NamespaceCard extends StatefulWidget {
  const _NamespaceCard({
    required this.namespace,
    required this.writable,
    required this.busy,
    required this.onAction,
    super.key,
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
    final SettingsNamespace namespace = widget.namespace;
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
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final SettingsNamespace namespace = widget.namespace;
    return Material(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          namespace.ns,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _namespaceMeta(namespace, l10n),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_open) _buildBody(context),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: widget.writable
          ? _buildEditor(context)
          : Padding(
              padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
              child: Text(
                l10n.namespaceReadOnlyHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onErrorContainer,
                ),
              ),
            ),
    );
  }

  Widget _buildEditor(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _ModeButton(
                label: l10n.patchKey,
                selected: !_replaceMode,
                onTap: () => setState(() => _replaceMode = false),
              ),
              _ModeButton(
                label: l10n.replaceSection,
                selected: _replaceMode,
                onTap: () => setState(() => _replaceMode = true),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!_replaceMode) ...<Widget>[
            _FieldLabel(l10n.topLevelKey),
            const SizedBox(height: 6),
            TextField(
              controller: _keyController,
              decoration: _dsInputDecoration(context),
              onChanged: (String _) => setState(() {}),
            ),
            const SizedBox(height: 12),
          ],
          _FieldLabel(_replaceMode ? l10n.wholeUserLayerJson : l10n.jsonValue),
          const SizedBox(height: 6),
          TextField(
            controller: _valueController,
            decoration: _dsInputDecoration(
              context,
              hint: _replaceMode
                  ? l10n.jsonKeyValueExampleHint
                  : l10n.jsonValueExampleHint,
            ),
            maxLines: _replaceMode ? 4 : 1,
            onChanged: (String _) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.casRevisionLine(widget.namespace.revision),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              OutlinedButton(
                onPressed: () {
                  _keyController.clear();
                  _valueController.clear();
                  setState(() {});
                },
                style: _outlineCapsule(context),
                child: Text(l10n.discard),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _canSave && !widget.busy ? _save : null,
                style: _filledCapsule(context),
                child: Text(l10n.save),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({required this.label, required this.selected, this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final ThemeData theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        hoverColor: scheme.surfaceContainerHigh,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? scheme.primaryContainer : null,
              borderRadius: BorderRadius.circular(18),
              border: selected
                  ? null
                  : Border.all(color: scheme.outlineVariant),
            ),
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: selected
                    ? theme.colorScheme.onSurface
                    : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Text(
      label,
      style: Theme.of(context).textTheme.labelMedium
          ?.copyWith(color: scheme.onSurfaceVariant),
    );
  }
}

InputDecoration _dsInputDecoration(BuildContext context, {String? hint}) {
  final ThemeData theme = Theme.of(context);
  final ColorScheme scheme = theme.colorScheme;
  final OutlineInputBorder border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: BorderSide(color: scheme.outlineVariant),
  );
  return InputDecoration(
    hintText: hint,
    hintStyle: theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    ),
    filled: true,
    fillColor: scheme.surfaceContainerLow,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
    enabledBorder: border,
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: scheme.primary),
    ),
  );
}

ButtonStyle _filledCapsule(BuildContext context) {
  return FilledButton.styleFrom(
    minimumSize: const Size(64, 36),
    padding: const EdgeInsets.symmetric(horizontal: 14),
    shape: const StadiumBorder(),
    textStyle: Theme.of(context).textTheme.bodyMedium,
  );
}

ButtonStyle _outlineCapsule(BuildContext context) {
  final ColorScheme scheme = Theme.of(context).colorScheme;
  return OutlinedButton.styleFrom(
    minimumSize: const Size(64, 36),
    padding: const EdgeInsets.symmetric(horizontal: 14),
    shape: const StadiumBorder(),
    foregroundColor: scheme.onSurfaceVariant,
    side: BorderSide(color: scheme.outlineVariant),
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

class _CredentialRow extends StatelessWidget {
  const _CredentialRow({
    required this.credential,
    required this.onAction,
    super.key,
  });

  final CredentialStatus credential;
  final void Function(SettingsAction) onAction;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openSheet(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      credential.ref,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _credentialMeta(credential, l10n),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StateBadge(configured: credential.configured),
              const SizedBox(width: 4),
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

  Future<void> _openSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        final double insets = MediaQuery.of(sheetContext).viewInsets.bottom;
        final ColorScheme scheme = Theme.of(sheetContext).colorScheme;
        return Padding(
          padding: EdgeInsets.fromLTRB(8, 0, 8, 8 + insets),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainer,
              borderRadius: BorderRadius.circular(kShapeSheet),
              border: Border.all(color: scheme.outlineVariant),
              boxShadow: kM3ShadowElevation3,
            ),
            child: _CredentialSheet(credential: credential, onAction: onAction),
          ),
        );
      },
    );
  }
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.configured, this.label});

  final bool configured;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: configured ? scheme.primaryContainer : null,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label ?? (configured ? l10n.stateConfigured : l10n.stateNotSet),
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }
}

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
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final CredentialStatus credential = widget.credential;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  l10n.storeCredentialTitle(credential.ref),
                  style: theme.textTheme.titleMedium,
                ),
              ),
              _StateBadge(configured: credential.configured),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _credentialMeta(credential, l10n),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          if (credential.writable)
            _buildEditor(context)
          else
            Text(
              l10n.credentialReadOnlyHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onErrorContainer,
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              if (credential.configured && credential.writable)
                TextButton(
                  onPressed: () {
                    widget.onAction(UnsetCredentialAction(credential.ref));
                    Navigator.of(context).pop();
                  },
                  style: _dangerCapsule(context),
                  child: Text(l10n.unset),
                ),
              const Spacer(),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: _outlineCapsule(context),
                child: Text(l10n.cancel),
              ),
              if (credential.writable) ...<Widget>[
                const SizedBox(width: 8),
                ListenableBuilder(
                  listenable: _valueController,
                  builder: (BuildContext context, Widget? _) => FilledButton(
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
                    child: Text(l10n.save),
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
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _FieldLabel(l10n.secretValueLabel),
        const SizedBox(height: 6),
        TextField(
          controller: _valueController,
          autofocus: true,
          obscureText: true,
          decoration: _dsInputDecoration(context, hint: l10n.secretValueHint),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.secretValueHintLine,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
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
  final void Function(String label, String baseUrl) onSave;
  final VoidCallback? onRemove;
  final String? removeBlockedReason;
  final VoidCallback? onSetChatHost;

  @override
  State<_BackendSheet> createState() => _BackendSheetState();
}

class _BackendSheetState extends State<_BackendSheet> {
  late final TextEditingController _labelController;
  late final TextEditingController _urlController;

  @override
  void initState() {
    super.initState();
    final BackendConfig? backend = widget.backend;
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

  bool _validUrl(String raw) {
    final Uri? uri = Uri.tryParse(raw.trim());
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  bool get _canSave =>
      _labelController.text.trim().isNotEmpty && _validUrl(_urlController.text);

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final bool editing = widget.backend != null;
    final bool urlValid = _validUrl(_urlController.text);
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            editing ? l10n.editBackend : l10n.addBackend,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          _FieldLabel(l10n.backendLabel),
          const SizedBox(height: 6),
          TextField(
            controller: _labelController,
            autofocus: !editing,
            decoration: _dsInputDecoration(
              context,
              hint: l10n.backendLabelHint,
            ),
            onChanged: (String _) => setState(() {}),
          ),
          const SizedBox(height: 12),
          _FieldLabel(l10n.backendBaseUrlLabel),
          const SizedBox(height: 6),
          TextField(
            controller: _urlController,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: _dsInputDecoration(
              context,
              hint: l10n.backendBaseUrlHint,
            ),
            onChanged: (String _) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Text(
            urlValid ? l10n.baseUrlDerivationHint : l10n.baseUrlValidHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: urlValid
                  ? scheme.onSurfaceVariant
                  : theme.colorScheme.error,
            ),
          ),
          if (widget.onSetChatHost != null) ...<Widget>[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: widget.onSetChatHost,
                style: _outlineCapsule(context),
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
                            style: _dangerCapsule(context),
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
                style: _outlineCapsule(context),
                child: Text(l10n.cancel),
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
                child: Text(editing ? l10n.save : l10n.add),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

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
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          hoverColor: scheme.surfaceContainerHigh,
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

String _namespaceMeta(SettingsNamespace namespace, AppLocalizations l10n) =>
    <String>[
      l10n.namespaceMetaApplies(namespace.applies.name),
      l10n.namespaceMetaRevision(namespace.revision),
      if (namespace.hasUserLayer) l10n.userLayerLabel,
      if (namespace.secretCount > 0)
        l10n.secretsSetCount(namespace.secretCount),
    ].join(' · ');

String _credentialMeta(CredentialStatus credential, AppLocalizations l10n) =>
    <String>[
      credential.configured
          ? l10n.credentialMetaConfigured
          : l10n.credentialMetaNotConfigured,
      if (credential.source case final String source)
        l10n.credentialMetaSource(source),
      credential.writable
          ? l10n.credentialMetaWritable
          : l10n.credentialMetaReadOnly,
    ].join(' · ');
