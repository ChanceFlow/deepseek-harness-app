/// Settings screen — Flutter port of the dsh web settings surface.
///
/// Translates the web settings panel (ui-settings shell plus the
/// ui-settings-general / -plugins / -models sections) onto a phone-width
/// tab: the panel's content-column rhythm — 16/500 section titles over
/// 14/22 rows with 12/18 tertiary descriptions, border-l2 hairlines
/// between rows, 12px-radius cards, capsule controls, 8px-radius inputs —
/// kept token-for-token (reference packages/client/ui-settings-* module
/// css). The web's two-pane panel collapses to one column: general facts
/// render as value rows, namespaces disclose in place (web PluginCard),
/// and the credential editor opens as a bottom sheet on the popover
/// surface instead of a side panel.
library;

import 'package:domain/model/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import '../theme/deepsuite_extension.dart';
import '../theme/deepsuite_tokens.dart' show DeepSuiteStatic, kDsDuration;
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
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SettingsHeader(
              onRefresh: () => onAction(const RefreshSettingsAction()),
            ),
            if (uiState.errorMessage case final String error)
              _ErrorBanner(
                message: error,
                onDismiss: () => onAction(const DismissSettingsError()),
              ),
            // Web surfaces write/refresh state on the controls; the mobile
            // tab keeps one slim activity line above the content column.
            if (uiState.snapshot != null && uiState.isLoading)
              LinearProgressIndicator(
                minHeight: 2,
                color: dsOf(context).accent,
                backgroundColor: Colors.transparent,
              ),
            switch (uiState.snapshot) {
              null => Expanded(
                child: Center(
                  child: uiState.isLoading
                      ? const CircularProgressIndicator()
                      : const SizedBox.shrink(),
                ),
              ),
              final described => Expanded(
                child: _SettingsBody(
                  snapshot: described,
                  credentials: uiState.credentials,
                  credentialError: uiState.credentialError,
                  busy: uiState.isLoading,
                  onAction: onAction,
                ),
              ),
            },
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

/// The web panel's content column (`.options`), stacked as one mobile
/// list: General facts, namespace disclosure cards, credential rows.
class _SettingsBody extends StatelessWidget {
  const _SettingsBody({
    required this.snapshot,
    required this.credentials,
    required this.credentialError,
    required this.busy,
    required this.onAction,
  });

  final SettingsSnapshot snapshot;
  final List<CredentialStatus> credentials;
  final String? credentialError;
  final bool busy;
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
          title: 'General',
          intro: 'Connection facts for the host settings plane.',
        ),
        ..._divided(ds, [
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
        ]),
        const SizedBox(height: 28),
        const _SectionHeader(
          title: 'Namespaces',
          intro: 'Host settings namespaces; values stay on the host.',
        ),
        if (snapshot.namespaces.isEmpty)
          Text('No namespaces reported.', style: tertiary),
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
        if (credentials.isNotEmpty || credentialError != null) ...[
          const SizedBox(height: 28),
          const _SectionHeader(
            title: 'Credentials',
            intro: 'Secret references named by the host namespaces.',
          ),
          if (credentialError case final String error) ...[
            Text('Credential state unavailable: $error', style: tertiary),
            if (credentials.isNotEmpty) const SizedBox(height: 8),
          ],
          if (credentials.isNotEmpty)
            ..._divided(ds, [
              for (final credential in credentials)
                _CredentialRow(
                  key: ValueKey(credential.ref),
                  credential: credential,
                  onAction: onAction,
                ),
            ]),
        ],
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
/// around it keeps the touch target at 44px.
class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

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
/// configured, borderless label-tertiary when not.
class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.configured});

  final bool configured;

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
        configured ? 'Configured' : 'Not set',
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
