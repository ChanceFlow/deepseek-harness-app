/// The host editor: one configured backend's label, base URL, certificate
/// trust and enabled state, plus add and remove.
///
/// A new host dispatches [AddBackend]; an existing one dispatches the four
/// mutations that describe it. Validation mirrors
/// `BackendRegistryController._parseBaseUrl`, so a bad URL is refused here
/// before the registry can fail it a frame later, and the guards on removal
/// mirror the controller's own (the last host and the active host stay).
library;

import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/backend.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../di/providers.dart';
import '../theme/theme.dart';

/// Applies one registry action from the settings surface.
///
/// This is the seam a widget test overrides to record what a save or a remove
/// would dispatch; production resolves the real controller and forwards the
/// action to it.
typedef ShellRegistryDispatch = void Function(BackendAction action);

/// The dispatch seam: production forwards to the registry controller, a test
/// records the action.
final shellRegistryDispatchProvider = Provider<ShellRegistryDispatch>((ref) {
  return (BackendAction action) {
    unawaited(
      ref
          .read(backendRegistryProvider.future)
          .then<void>((registry) => registry.onAction(action))
          .catchError((Object _) {
            // A bare surface has no registry behind it; the next state
            // snapshot is the source of truth anyway.
          }),
    );
  };
});

/// Opens the editor for [host], or a blank one when it is null.
Future<void> showHostEditor(BuildContext context, {BackendConfig? host}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (BuildContext sheetContext) => HostEditorSheet(host: host),
  );
}

/// The editor body: add a host, or edit one already configured.
class HostEditorSheet extends ConsumerStatefulWidget {
  const HostEditorSheet({this.host, super.key});

  /// Null adds a host; non-null edits this host.
  final BackendConfig? host;

  @override
  ConsumerState<HostEditorSheet> createState() => _HostEditorSheetState();
}

class _HostEditorSheetState extends ConsumerState<HostEditorSheet> {
  late final TextEditingController _label;
  late final TextEditingController _url;
  late bool _trust;
  late bool _enabled;

  /// The inline refusal or validation failure; null when the form is clean.
  String? _error;

  @override
  void initState() {
    super.initState();
    final BackendConfig? host = widget.host;
    _label = TextEditingController(text: host?.label ?? '');
    _url = TextEditingController(text: host?.baseUri.toString() ?? '');
    _trust = host?.trustHostCertificate ?? false;
    _enabled = host?.enabled ?? true;
  }

  @override
  void dispose() {
    _label.dispose();
    _url.dispose();
    super.dispose();
  }

  /// The controller's own rule: http or https, with a host.
  Uri? _parseBaseUrl(String raw) {
    final Uri? uri = Uri.tryParse(raw.trim());
    if (uri == null) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    if (uri.host.isEmpty) return null;
    return uri;
  }

  void _clearError() {
    if (_error == null) return;
    setState(() => _error = null);
  }

  void _save() {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final String label = _label.text.trim();
    final String rawUrl = _url.text.trim();
    if (label.isEmpty) {
      setState(() => _error = l10n.backendErrorEmptyLabel);
      return;
    }
    if (_parseBaseUrl(rawUrl) == null) {
      setState(() => _error = l10n.backendErrorInvalidBaseUrl);
      return;
    }

    final ShellRegistryDispatch dispatch = ref.read(
      shellRegistryDispatchProvider,
    );
    final BackendConfig? host = widget.host;
    if (host == null) {
      dispatch(AddBackend(label, rawUrl, trustHostCertificate: _trust));
    } else {
      dispatch(RenameBackend(host.id, label));
      dispatch(UpdateBackendUrl(host.id, rawUrl));
      dispatch(SetBackendTrustHostCertificate(host.id, _trust));
      dispatch(SetBackendEnabled(host.id, _enabled));
    }
    Navigator.of(context).pop();
  }

  Future<void> _remove() async {
    final BackendConfig? host = widget.host;
    if (host == null) return;
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final BackendRegistryState state =
        ref.read(backendRegistryStateProvider).value ??
        const BackendRegistryState();
    // Mirror the controller's order: the last host is refused before the
    // active-host guard, because a one-host registry is necessarily active.
    if (state.backends.length <= 1) {
      setState(() => _error = l10n.cannotRemoveLastBackend);
      return;
    }
    if (state.activeId == host.id) {
      setState(() => _error = l10n.removeActiveBackendFirst);
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(l10n.remove),
        content: Text(host.label),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.remove),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;
    if (!mounted) return;
    ref.read(shellRegistryDispatchProvider)(RemoveBackend(host.id));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final BackendConfig? host = widget.host;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              host == null ? l10n.addBackend : l10n.editBackend,
              style: DshType.l20.style(color: scheme.labelPrimary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _label,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: l10n.backendLabel,
                hintText: l10n.backendLabelHint,
              ),
              onChanged: (String _) => _clearError(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: l10n.backendBaseUrlLabel,
                hintText: l10n.backendBaseUrlHint,
                helperText: l10n.baseUrlValidHint,
              ),
              onChanged: (String _) => _clearError(),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                l10n.backendTrustCertificateTitle,
                style: DshType.s14.style(color: scheme.labelPrimary),
              ),
              subtitle: Text(
                l10n.backendTrustCertificateDescription,
                style: DshType.xxs12.style(color: scheme.labelTertiary),
              ),
              value: _trust,
              onChanged: (bool value) => setState(() => _trust = value),
            ),
            if (host != null)
              Tooltip(
                message: _enabled
                    ? l10n.backendDisableTooltip
                    : l10n.backendEnableTooltip,
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    l10n.automationTasksFilterEnabled,
                    style: DshType.s14.style(color: scheme.labelPrimary),
                  ),
                  subtitle: Text(
                    _enabled
                        ? l10n.backendStatusActive
                        : l10n.backendStatusDisabled,
                    style: DshType.xxs12.style(color: scheme.labelTertiary),
                  ),
                  value: _enabled,
                  onChanged: (bool value) => setState(() => _enabled = value),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: DshType.xs13.style(color: scheme.stateErrorPrimary),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (host != null)
                  TextButton(
                    onPressed: _remove,
                    style: TextButton.styleFrom(
                      foregroundColor: scheme.stateErrorPrimary,
                    ),
                    child: Text(l10n.remove),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: Text(l10n.cancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _save,
                  child: Text(host == null ? l10n.add : l10n.save),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
