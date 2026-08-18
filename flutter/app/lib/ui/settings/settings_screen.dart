/// Settings screen — Flutter port of the legacy SettingsRoute.kt.
library;

import 'package:domain/model/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import 'settings_ui_state.dart';

class SettingsRoute extends ConsumerWidget {
  const SettingsRoute({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(settingsControllerProvider);
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

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.uiState,
    required this.onAction,
  });

  final SettingsUiState uiState;
  final void Function(SettingsAction) onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Settings', style: theme.textTheme.titleLarge),
                  ),
                  OutlinedButton(
                    onPressed: () =>
                        onAction(const RefreshSettingsAction()),
                    child: const Text('Refresh'),
                  ),
                ],
              ),
              if (uiState.errorMessage case final error?) ...[
                Text(
                  error,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
                Text(
                  'settings/credentials are loopback-only on the host; '
                  'connect via adb reverse',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
              switch (uiState.snapshot) {
                null => uiState.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : const SizedBox.shrink(),
                final described => Expanded(
                    child: SnapshotBody(
                      snapshot: described,
                      credentials: uiState.credentials,
                      credentialError: uiState.credentialError,
                      onAction: onAction,
                    ),
                  ),
              },
            ],
          ),
        ),
      ),
    );
  }
}

class SnapshotBody extends StatelessWidget {
  const SnapshotBody({
    super.key,
    required this.snapshot,
    required this.credentials,
    required this.credentialError,
    required this.onAction,
  });

  final SettingsSnapshot snapshot;
  final List<CredentialStatus> credentials;
  final String? credentialError;
  final void Function(SettingsAction) onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 4,
          children: [
            Chip(
              label: Text(
                  snapshot.writable ? 'host writable' : 'host read-only'),
              visualDensity: VisualDensity.compact,
            ),
            Chip(
              label: Text(snapshot.hasDocument
                  ? 'settings document'
                  : 'no settings document'),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView(
            children: [
              for (final namespace in snapshot.namespaces)
                NamespaceRow(
                  key: ValueKey(namespace.ns),
                  namespace: namespace,
                  writable: snapshot.writable,
                  onAction: onAction,
                ),
              if (credentials.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 4),
                  child: Text('Credentials',
                      style: theme.textTheme.titleMedium),
                ),
                for (final credential in credentials)
                  CredentialRow(
                    key: ValueKey(credential.ref),
                    credential: credential,
                    onAction: onAction,
                  ),
              ],
            ],
          ),
        ),
        if (credentialError case final String credError)
          Text(
            'credentials: $credError',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.error),
          ),
      ],
    );
  }
}

class NamespaceRow extends StatefulWidget {
  const NamespaceRow({
    super.key,
    required this.namespace,
    required this.writable,
    required this.onAction,
  });

  final SettingsNamespace namespace;
  final bool writable;
  final void Function(SettingsAction) onAction;

  @override
  State<NamespaceRow> createState() => _NamespaceRowState();
}

class _NamespaceRowState extends State<NamespaceRow> {
  final TextEditingController _keyController = TextEditingController();
  final TextEditingController _valueController = TextEditingController();
  bool _replaceMode = false;

  @override
  void dispose() {
    _keyController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  Future<void> _openEditor() {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text('Patch ${widget.namespace.ns}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  OutlinedButton(
                    onPressed: () =>
                        setDialogState(() => _replaceMode = false),
                    child: Text(
                        !_replaceMode ? '✓ Key patch' : 'Key patch'),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: OutlinedButton(
                      onPressed: () =>
                          setDialogState(() => _replaceMode = true),
                      child: Text(_replaceMode
                          ? '✓ Replace section'
                          : 'Replace section'),
                    ),
                  ),
                ],
              ),
              if (_replaceMode)
                TextField(
                  controller: _valueController,
                  decoration: const InputDecoration(
                    labelText: 'Whole user-layer JSON object',
                    hintText: '{ "key": value }',
                    isDense: true,
                  ),
                  onChanged: (_) => setDialogState(() {}),
                )
              else ...[
                TextField(
                  controller: _keyController,
                  decoration: const InputDecoration(
                    labelText: 'Top-level key',
                    isDense: true,
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
                TextField(
                  controller: _valueController,
                  decoration: const InputDecoration(
                    labelText: 'JSON value',
                    hintText: 'true / 42 / "text" / {…}',
                    isDense: true,
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
              ],
              Text(
                'CAS revision ${widget.namespace.revision}; '
                'host validates against the schema',
                style: Theme.of(dialogContext)
                    .textTheme
                    .bodySmall
                    ?.copyWith(
                      color: Theme.of(dialogContext)
                          .colorScheme
                          .onSurfaceVariant,
                    ),
              ),
            ],
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: _replaceMode
                  ? _valueController.text.trim().isNotEmpty
                      ? () {
                          widget.onAction(ReplaceSettingAction(
                            ns: widget.namespace.ns,
                            sectionJson: _valueController.text,
                            expectedRevision: widget.namespace.revision,
                          ));
                          Navigator.of(dialogContext).pop();
                        }
                      : null
                  : _keyController.text.trim().isNotEmpty &&
                          _valueController.text.trim().isNotEmpty
                      ? () {
                          widget.onAction(UpdateSettingAction(
                            ns: widget.namespace.ns,
                            key: _keyController.text,
                            jsonValue: _valueController.text,
                            expectedRevision: widget.namespace.revision,
                          ));
                          Navigator.of(dialogContext).pop();
                        }
                      : null,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final namespace = widget.namespace;
    final theme = Theme.of(context);
    final meta = [
      'applies: ${namespace.applies.name}',
      'revision: ${namespace.revision}',
      if (namespace.hasUserLayer) 'user layer',
      if (namespace.secretCount > 0) '${namespace.secretCount} secrets set',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(namespace.ns, style: theme.textTheme.titleSmall),
          Text(meta, style: theme.textTheme.bodySmall),
          if (widget.writable)
            OutlinedButton(
              onPressed: () => _openEditor(),
              child: const Text('Edit key'),
            ),
        ],
      ),
    );
  }
}

class CredentialRow extends StatefulWidget {
  const CredentialRow({
    super.key,
    required this.credential,
    required this.onAction,
  });

  final CredentialStatus credential;
  final void Function(SettingsAction) onAction;

  @override
  State<CredentialRow> createState() => _CredentialRowState();
}

class _CredentialRowState extends State<CredentialRow> {
  final TextEditingController _valueController = TextEditingController();

  @override
  void dispose() {
    _valueController.dispose();
    super.dispose();
  }

  Future<void> _openEditor() {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Store ${widget.credential.ref}'),
        content: TextField(
          controller: _valueController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'secret value',
            isDense: true,
          ),
          onChanged: (_) => (dialogContext as Element).markNeedsBuild(),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ListenableBuilder(
            listenable: _valueController,
            builder: (dialogContext, _) => FilledButton(
              onPressed: _valueController.text.trim().isNotEmpty
                  ? () {
                      widget.onAction(SetCredentialAction(
                        widget.credential.ref,
                        _valueController.text.trim(),
                      ));
                      _valueController.clear();
                      Navigator.of(dialogContext).pop();
                    }
                  : null,
              child: const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final credential = widget.credential;
    final theme = Theme.of(context);
    final meta = [
      credential.configured ? 'configured' : 'not configured',
      if (credential.source case final String source) 'source: $source',
      credential.writable ? 'writable' : 'read-only',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(credential.ref, style: theme.textTheme.titleSmall),
          Text(meta, style: theme.textTheme.bodySmall),
          if (credential.writable)
            Wrap(
              children: [
                OutlinedButton(
                  onPressed: _openEditor,
                  child: Text(
                      credential.configured ? 'Replace' : 'Set value'),
                ),
                if (credential.configured)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: OutlinedButton(
                      onPressed: () => widget.onAction(
                          UnsetCredentialAction(credential.ref)),
                      child: const Text('Unset'),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
