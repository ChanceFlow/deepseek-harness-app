/// `Settings` → Default permission preset.
///
/// Two permission facts live on two surfaces and are easy to confuse:
///
/// * the *current session's* preset is the composer's access chip, which
///   submits `/permission <preset>` (web `ui-permission-presets`
///   `choose`), and
/// * the *deployment default* a new session starts from is this page. It
///   reads the composed table from `permissionPresets/catalog` and the
///   effective value from the settings namespace `permission`, and patches
///   only `defaultPreset` with the described revision as CAS guard — the same
///   write the reference settings row performs
///   (`ui-permission-presets/src/client/settings-store.ts`).
///
/// The row offers `defaultOptions`, not `options`: a host may compose a
/// preset that is switchable per session but not acceptable as a default.
library;

import 'dart:async';
import 'dart:convert';

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/permission_select.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import '../chat/permission_select.dart';
import 'settings_backend_scope.dart';
import 'settings_ui_state.dart';
import 'settings_chrome.dart';

/// The settings namespace carrying the effective default preset.
const String kPermissionSettingsNamespace = 'permission';

/// The key this page patches inside that namespace.
const String kPermissionDefaultKey = 'defaultPreset';

class SettingsPermissionDefaultsPage extends ConsumerStatefulWidget {
  const SettingsPermissionDefaultsPage({required this.channel, super.key});

  final SettingsChannel channel;

  @override
  ConsumerState<SettingsPermissionDefaultsPage> createState() =>
      _SettingsPermissionDefaultsPageState();
}

class _SettingsPermissionDefaultsPageState
    extends ConsumerState<SettingsPermissionDefaultsPage> {
  PermissionPresetCatalog? _catalog;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final backendId = ref.read(settingsBackendScopeProvider);
    if (backendId.isEmpty) {
      setState(() {
        _loading = false;
        _failed = true;
      });
      return;
    }
    try {
      final catalog = await ref
          .read(chatRepositoryProvider(backendId))
          .loadPermissionPresetCatalog();
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      // A host that composes no permission service answers with an error
      // rather than an empty table; the page says so instead of offering a
      // choice that cannot land.
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SettingsLive(
      channel: widget.channel,
      builder: (context, state, onAction) {
        final catalog = _catalog;
        final namespace = state.snapshot?.namespaces
            .where((item) => item.ns == kPermissionSettingsNamespace)
            .firstOrNull;
        final value = namespace?.value;
        final current =
            (value is Map<String, Object?>
                ? value[kPermissionDefaultKey] as String?
                : null) ??
            catalog?.defaultPreset;
        final writable = state.snapshot?.writable ?? false;
        return SettingsPageScaffold(
          title: l10n.settingsNavPermissionDefaults,
          children: <Widget>[
            SettingsSectionHeading(
              title: l10n.settingsNavPermissionDefaults,
              intro: l10n.permissionDefaultsIntro,
              showTitle: false,
            ),
            if (_failed)
              SettingsSectionCard(
                children: <Widget>[
                  _Notice(text: l10n.permissionDefaultsUnavailable),
                ],
              )
            else if (_loading || catalog == null || state.isLoading)
              SettingsSectionCard(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: <Widget>[
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Text(l10n.permissionDefaultsLoading),
                      ],
                    ),
                  ),
                ],
              )
            else
              SettingsSectionCard(
                children: <Widget>[
                  RadioGroup<String>(
                    // A read-only document shows no selection and the tap
                    // lands nowhere; the notice below says why. A write is
                    // one top-level key patch guarded by the described
                    // revision (web settings-store `write`).
                    groupValue: writable ? current : null,
                    onChanged: (value) {
                      if (!writable || value == null) return;
                      onAction(
                        UpdateSettingAction(
                          ns: kPermissionSettingsNamespace,
                          key: kPermissionDefaultKey,
                          jsonValue: jsonEncode(value),
                          expectedRevision: namespace?.revision,
                        ),
                      );
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        for (
                          var i = 0;
                          i < catalog.defaultOptions.length;
                          i++
                        ) ...<Widget>[
                          if (i > 0) const SettingsCardDivider(),
                          _PresetRow(option: catalog.defaultOptions[i]),
                        ],
                      ],
                    ),
                  ),
                  if (!writable) ...<Widget>[
                    const SettingsCardDivider(),
                    _Notice(text: l10n.permissionDefaultsReadOnly),
                  ],
                ],
              ),
          ],
        );
      },
    );
  }
}

/// One selectable default: the preset's own label and sentence, and the
/// radio mark the reader picks. The ancestor [RadioGroup] owns the group
/// value and change routing; the tile carries only its own value.
class _PresetRow extends StatelessWidget {
  const _PresetRow({required this.option});

  final PermissionPresetOption option;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final description = option.description;
    return RadioListTile<String>(
      value: option.value,
      controlAffinity: ListTileControlAffinity.trailing,
      title: Row(
        children: <Widget>[
          Icon(
            permissionGlyph(option.value),
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(permissionOptionLabel(option, l10n))),
        ],
      ),
      subtitle: description == null || description.trim().isEmpty
          ? null
          : Text(
              description,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
