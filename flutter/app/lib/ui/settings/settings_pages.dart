/// The Settings sub-pages the root index opens.
///
/// Each page owns one subject the root can only name: the agent-preset
/// roster, the credential records, the provider directory, the host settings
/// namespaces, the read-only plugin inventory, and About. The pages carry no
/// chrome of their own — [SettingsPageScaffold] and the widgets in
/// `settings_chrome.dart` do — and the ones that write read the live
/// [SettingsChannel] so a write they trigger lands without going back.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/agent_preset.dart';
import 'package:domain/model/settings.dart';
import 'package:flutter/material.dart';

import '../shared/agent_preset_display.dart';
import '../theme/theme.dart';
import 'about_section.dart';
import 'llm_providers.dart';
import 'plugin_inventory_section.dart';
import 'settings_chrome.dart';
import 'settings_ui_state.dart';

/// The credential reference the official DeepSeek route resolves by default.
const String _kDeepSeekCredentialRef = 'DEEPSEEK_API_KEY';

/// `Settings` → Agent presets: the single surface a default preset is chosen
/// on. The root row states the current default and opens this page; no second
/// picker exists beside it.
class SettingsAgentPresetsPage extends StatelessWidget {
  const SettingsAgentPresetsPage({required this.channel, super.key});

  final SettingsChannel channel;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return SettingsLive(
      channel: channel,
      builder:
          (
            BuildContext context,
            SettingsUiState state,
            void Function(SettingsAction) onAction,
          ) {
            final List<AgentPresetEntry> entries =
                state.roster?.entries ?? const <AgentPresetEntry>[];
            final bool writable = state.snapshot?.writable ?? false;
            return SettingsPageScaffold(
              title: l10n.settingsNavAgentPresets,
              children: <Widget>[
                SettingsSectionHeading(
                  title: l10n.settingsNavAgentPresets,
                  intro: l10n.agentPresetsIntro,
                  showTitle: false,
                ),
                if (entries.isEmpty)
                  Text(
                    l10n.presetsFooter,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  )
                else ...<Widget>[
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
                          writable: writable,
                          busy: state.isLoading,
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
              ],
            );
          },
    );
  }
}

/// `Settings` → Credentials: the DeepSeek key card and every other secret
/// reference the host namespaces report.
class SettingsCredentialsPage extends StatelessWidget {
  const SettingsCredentialsPage({required this.channel, super.key});

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
            void Function(SettingsAction) onAction,
          ) => SettingsPageScaffold(
            title: l10n.settingsNavCredentials,
            children: <Widget>[
              SettingsSectionHeading(
                title: l10n.settingsSectionModels,
                intro: l10n.modelsIntro,
                showTitle: false,
              ),
              _CredentialsCard(
                snapshot: state.snapshot,
                credentials: state.credentials,
                credentialError: state.credentialError,
                onAction: onAction,
              ),
            ],
          ),
    );
  }
}

/// `Settings` → Providers: the provider directory, key plane, and discovery.
class SettingsProvidersPage extends StatelessWidget {
  const SettingsProvidersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return SettingsPageScaffold(
      title: l10n.settingsSectionProviders,
      children: const <Widget>[SettingsLlmProvidersSection(showTitle: false)],
    );
  }
}

/// `Settings` → Plugins: the host settings namespaces and their in-place
/// editors.
class SettingsPluginsPage extends StatelessWidget {
  const SettingsPluginsPage({required this.channel, super.key});

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
            void Function(SettingsAction) onAction,
          ) => SettingsPageScaffold(
            title: l10n.settingsNavPlugins,
            children: <Widget>[
              SettingsSectionHeading(
                title: l10n.settingsSectionPlugins,
                intro: l10n.pluginsIntro,
                showTitle: false,
              ),
              _PluginsCard(
                namespaces:
                    state.snapshot?.namespaces ?? const <SettingsNamespace>[],
                writable: state.snapshot?.writable ?? false,
                busy: state.isLoading,
                onAction: onAction,
              ),
            ],
          ),
    );
  }
}

/// `Settings` → Plugin inventory: the read-only Loader catalog and every
/// preset's composition.
class SettingsPluginInventoryPage extends StatelessWidget {
  const SettingsPluginInventoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return SettingsPageScaffold(
      title: l10n.settingsSectionPluginInventory,
      children: const <Widget>[
        SettingsPluginInventorySection(showTitle: false),
      ],
    );
  }
}

/// `Settings` → About: the build's version, the project docs, and the
/// feedback channel.
class SettingsAboutPage extends StatelessWidget {
  const SettingsAboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return SettingsPageScaffold(
      title: l10n.settingsSectionAbout,
      children: const <Widget>[SettingsAboutSection(showTitle: false)],
    );
  }
}

/// The credential card: one DeepSeek entry plus every other referenced secret.
class _CredentialsCard extends StatelessWidget {
  const _CredentialsCard({
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
    final String? error = credentialError;

    return SettingsSectionCard(
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
        if (deepSeek != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: _DeepSeekCard(credential: deepSeek, onAction: onAction),
          ),
        if (otherCredentials.isNotEmpty) ...<Widget>[
          if (deepSeek != null) const SettingsCardDivider(),
          for (int i = 0; i < otherCredentials.length; i++) ...<Widget>[
            if (i > 0) const SettingsCardDivider(),
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
        if (error != null) ...<Widget>[
          const SettingsCardDivider(),
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
        const SettingsCardDivider(),
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
    );
  }
}

/// The DeepSeek key seat: one tap opens the credential editor sheet.
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
      duration: DshMotion.durationShort,
      curve: DshMotion.curveStandard,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(kShapeCard),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(kShapeCard),
          hoverColor: scheme.surfaceContainerHighest,
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
                SettingsStatusDot(
                  color: credential.configured ? scheme.success : scheme.error,
                ),
                const SizedBox(width: 6),
                SettingsBadge(
                  label: credential.configured
                      ? l10n.stateConfigured
                      : l10n.stateNotSet,
                  tone: credential.configured
                      ? SettingsBadgeTone.primary
                      : SettingsBadgeTone.neutral,
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
      ),
    );
  }

  Future<void> _openSheet(BuildContext context) {
    return showSettingsSheet<void>(
      context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) =>
          _CredentialSheet(credential: credential, onAction: onAction),
    );
  }
}

/// One secret reference the host namespaces report: identity, state, and the
/// editor behind it.
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
              SettingsBadge(
                label: credential.configured
                    ? l10n.stateConfigured
                    : l10n.stateNotSet,
                tone: credential.configured
                    ? SettingsBadgeTone.primary
                    : SettingsBadgeTone.neutral,
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

  Future<void> _openSheet(BuildContext context) {
    return showSettingsSheet<void>(
      context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) =>
          _CredentialSheet(credential: credential, onAction: onAction),
    );
  }
}

/// The credential editor sheet: store a value, or clear the stored one.
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
    return Column(
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
            SettingsBadge(
              label: credential.configured
                  ? l10n.stateConfigured
                  : l10n.stateNotSet,
              tone: credential.configured
                  ? SettingsBadgeTone.primary
                  : SettingsBadgeTone.neutral,
            ),
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
                style: settingsDangerCapsule(context),
                child: Text(l10n.unset),
              ),
            const Spacer(),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: settingsOutlineCapsule(context),
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
                  style: settingsFilledCapsule(context),
                  child: Text(l10n.save),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildEditor(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SettingsFieldLabel(l10n.secretValueLabel),
        const SizedBox(height: 6),
        TextField(
          controller: _valueController,
          autofocus: true,
          obscureText: true,
          decoration: settingsInputDecoration(
            context,
            hint: l10n.secretValueHint,
          ),
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

/// The host settings namespaces, each an in-place JSON editor.
class _PluginsCard extends StatelessWidget {
  const _PluginsCard({
    required this.namespaces,
    required this.writable,
    required this.busy,
    required this.onAction,
  });

  final List<SettingsNamespace> namespaces;
  final bool writable;
  final bool busy;
  final void Function(SettingsAction) onAction;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return SettingsSectionCard(
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
            if (i > 0) const SettingsCardDivider(),
            _NamespaceCard(
              key: ValueKey<String>(namespaces[i].ns),
              namespace: namespaces[i],
              writable: writable,
              busy: busy,
              onAction: onAction,
            ),
          ],
      ],
    );
  }
}

/// One namespace disclosure: the metadata line, then a key patch or a whole
/// user-layer replacement.
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
                    duration: DshMotion.durationShort,
                    curve: DshMotion.curveStandard,
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
              SettingsModeButton(
                label: l10n.patchKey,
                selected: !_replaceMode,
                onTap: () => setState(() => _replaceMode = false),
              ),
              SettingsModeButton(
                label: l10n.replaceSection,
                selected: _replaceMode,
                onTap: () => setState(() => _replaceMode = true),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!_replaceMode) ...<Widget>[
            SettingsFieldLabel(l10n.topLevelKey),
            const SizedBox(height: 6),
            TextField(
              controller: _keyController,
              decoration: settingsInputDecoration(context),
              onChanged: (String _) => setState(() {}),
            ),
            const SizedBox(height: 12),
          ],
          SettingsFieldLabel(
            _replaceMode ? l10n.wholeUserLayerJson : l10n.jsonValue,
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _valueController,
            decoration: settingsInputDecoration(
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
                style: settingsOutlineCapsule(context),
                child: Text(l10n.discard),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _canSave && !widget.busy ? _save : null,
                style: settingsFilledCapsule(context),
                child: Text(l10n.save),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One preset the roster offers: identity, badges, description, and the
/// default-selection verb.
class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.entry,
    required this.writable,
    required this.busy,
    required this.onAction,
    super.key,
  });

  final AgentPresetEntry entry;
  final bool writable;
  final bool busy;
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
      duration: DshMotion.durationShort,
      curve: DshMotion.curveStandard,
      decoration: BoxDecoration(
        color: active ? scheme.surfaceContainerHigh : scheme.surfaceContainer,
        border: Border.all(
          color: broken
              ? scheme.error
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
          onTap: broken || active || !writable || busy
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
                      color: scheme.error,
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

/// One preset's standing: a filled failure badge, an outlined label, or the
/// inverted in-use mark.
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
      background = scheme.error;
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
        borderRadius: BorderRadius.circular(kShapePill),
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
