/// One Host settings namespace as the plugin pages the pin serves.
///
/// The reference serves two pages of this shape from the Plugins page: the
/// shell executor's namespace in both its platform bindings
/// (`ui-settings-shell/src/client/index.ts:47-52`: `bash-sandbox` off Windows,
/// `pwsh-sandbox` on it) and the DeepSeek web-search provider's
/// (`ui-settings-web-search/src/client/index.ts:48-59`:
/// `web-search-deepseek`). Both are a staged form over one settings namespace:
/// the rows render the effective value — the user's override over the composed
/// default — a field the user overrode carries an `overridden` mark beside a
/// `reset` verb, an empty field saves as a reset, and nothing is written until
/// Save (`ui-settings-shell/README.md` "Use this package",
/// `shell-card-controller.ts:39-55`).
///
/// Writes ride the host's user-settings document through the same
/// `settings/{describe,mutate}` pair and the same CAS guard the other settings
/// rows use (`theme_preference.dart`), so a stale page cannot overwrite a
/// change it never saw. The namespace this client's describe does not carry is
/// not served: the page renders the pin's own `unavailable` copy rather than
/// defaulting a value the Host never published.
library;

import 'dart:async';
import 'dart:convert';

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/settings.dart';
import 'package:domain/repository/chat_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../logging/error_log_collector.dart';
import '../state_stream.dart';
import 'settings_chrome.dart';

/// One editable row on a namespace page: the field key the Host's schema
/// declares, the copy above it, and whether the value is a number.
final class HostNamespaceField {
  const HostNamespaceField({
    required this.key,
    required this.label,
    required this.hint,
    this.numeric = false,
  });

  final String key;
  final String label;
  final String hint;

  /// A numeric field: text that is not a number blocks the save
  /// (`settingsNumberField`, `shell-card-controller.ts:45`).
  final bool numeric;
}

/// The one secret a namespace page writes through the credentials domain
/// instead of the settings document (`WebSearchCard.tsx:31-44`): its literal
/// never rides a response, so the page learns only whether one is configured.
final class HostNamespaceSecret {
  const HostNamespaceSecret({
    required this.label,
    required this.hint,
    required this.configuredLabel,
    required this.unsetLabel,
  });

  final String label;
  final String hint;
  final String configuredLabel;
  final String unsetLabel;
}

/// What one namespace page renders.
final class HostNamespaceState {
  const HostNamespaceState({
    this.loading = false,
    this.saving = false,
    this.failed = false,
    this.namespace,
    this.writable = false,
    this.revision,
    this.value = const <String, Object?>{},
    this.user = const <String, Object?>{},
    this.credentialRef,
    this.credentialConfigured = false,
    this.credentialWritable = true,
  });

  final bool loading;
  final bool saving;
  final bool failed;

  /// The served namespace this page bound, or null when the Host serves none
  /// of the candidates: the page is then not configurable.
  final String? namespace;

  /// Whether the settings document accepts writes at all.
  final bool writable;

  /// The CAS revision the last describe reported for [namespace].
  final int? revision;

  /// The effective value: schema defaults, then the composition base, then the
  /// user layer (the Host's redacted resolved view).
  final Map<String, Object?> value;

  /// The raw user section: a key present here is user-overridden.
  final Map<String, Object?> user;

  /// The credential reference the page watches, when it has one.
  final String? credentialRef;
  final bool credentialConfigured;
  final bool credentialWritable;

  bool get served => namespace != null;

  /// Whether the user layer carries [key]: the row marks it and offers the
  /// reset (`SettingsFormModel.field().overridden`).
  bool overridden(String key) => user.containsKey(key);

  /// The effective value of [key], or null when the Host publishes none.
  Object? effective(String key) => value[key];

  HostNamespaceState copyWith({
    bool? loading,
    bool? saving,
    bool? failed,
    String? namespace,
    bool? writable,
    int? revision,
    Map<String, Object?>? value,
    Map<String, Object?>? user,
    String? credentialRef,
    bool? credentialConfigured,
    bool? credentialWritable,
  }) {
    return HostNamespaceState(
      loading: loading ?? this.loading,
      saving: saving ?? this.saving,
      failed: failed ?? this.failed,
      namespace: namespace ?? this.namespace,
      writable: writable ?? this.writable,
      revision: revision ?? this.revision,
      value: value ?? this.value,
      user: user ?? this.user,
      credentialRef: credentialRef ?? this.credentialRef,
      credentialConfigured: credentialConfigured ?? this.credentialConfigured,
      credentialWritable: credentialWritable ?? this.credentialWritable,
    );
  }
}

/// UDF controller over one served namespace (the first of [namespaces] the
/// Host's describe carries): reads on construction, publishes every change,
/// and writes the staged form with the described revision as the CAS guard.
class HostNamespaceController {
  HostNamespaceController(
    this._repository,
    this.namespaces, {
    this.credentialRefField,
    this.defaultCredentialRef,
  }) {
    unawaited(refresh());
  }

  final ChatRepository _repository;

  /// The namespace ids this page binds, in the Host's binding order (the shell
  /// page binds the one executor the base bundle composed).
  final List<String> namespaces;

  /// Field naming the credential reference, when the page has a secret
  /// (`web-search-card-controller.ts:186-190`: `apiKeyEnv`, else the provider
  /// default).
  final String? credentialRefField;

  /// The provider's default credential reference.
  final String? defaultCredentialRef;

  final AppStateStream<HostNamespaceState> _state =
      AppStateStream<HostNamespaceState>(const HostNamespaceState());

  HostNamespaceState get state => _state.value;
  Stream<HostNamespaceState> get uiState => _state.stream;

  void dispose() {
    unawaited(_state.close());
  }

  /// Re-describe the candidate namespaces and adopt what the Host reports.
  Future<void> refresh() async {
    _state.value = _state.value.copyWith(loading: true, failed: false);
    try {
      final snapshot = await _repository.describeSettings();
      final namespace = snapshot.namespaces
          .where((entry) => namespaces.contains(entry.ns))
          .firstOrNull;
      final Map<String, Object?> value = _asMap(namespace?.value);
      final Map<String, Object?> user = _asMap(namespace?.user);
      final credential = await _readCredential(value);
      _state.value = HostNamespaceState(
        namespace: namespace?.ns,
        writable: snapshot.writable,
        revision: namespace?.revision,
        value: value,
        user: user,
        credentialRef: credential?.ref,
        credentialConfigured: credential?.configured ?? false,
        credentialWritable: credential?.writable ?? true,
      );
    } catch (error, stackTrace) {
      _state.value = _state.value.copyWith(loading: false, failed: true);
      ErrorLogCollector.instance.captureError(
        error,
        stackTrace: stackTrace,
        context: <String, Object?>{
          'controller': 'HostNamespaceController',
          'namespaces': namespaces,
        },
      );
    }
  }

  /// Write the staged form: every path op in one CAS-guarded mutate, then the
  /// staged key through the credentials domain, then a fresh describe. A blank
  /// key draft keeps the stored one (`WebSearchCard.tsx:31-44`).
  Future<void> save(List<SettingPathOp> ops, {String? credentialValue}) async {
    final HostNamespaceState before = _state.value;
    final String? ns = before.namespace;
    if (before.saving || ns == null) return;
    _state.value = before.copyWith(saving: true, failed: false);
    var accepted = true;
    try {
      if (ops.isNotEmpty) {
        await _repository.mutateSetting(
          ns,
          ops,
          expectedRevision: before.revision,
        );
      }
      final String? ref = before.credentialRef;
      if (credentialValue != null &&
          credentialValue.isNotEmpty &&
          ref != null) {
        await _repository.setCredential(ref, credentialValue);
      }
    } catch (error, stackTrace) {
      accepted = false;
      ErrorLogCollector.instance.captureError(
        error,
        stackTrace: stackTrace,
        context: <String, Object?>{
          'controller': 'HostNamespaceController',
          'action': 'save',
          'ns': ns,
        },
      );
    }
    await refresh();
    _state.value = _state.value.copyWith(saving: false, failed: !accepted);
  }

  /// Reset one field to the deployment default: the Host's unset op, staged by
  /// the page and written with the rest of the form on Save.
  static SettingPathOp resetOp(String key) =>
      SettingPathOp(op: 'unset', path: <String>[key]);

  /// Address the credential the namespace names, when this page has a secret.
  /// A credential read is enrichment: its failure leaves the control usable and
  /// the Host is what refuses a write.
  Future<CredentialStatus?> _readCredential(Map<String, Object?> value) async {
    final String? field = credentialRefField;
    final String? fallback = defaultCredentialRef;
    if (field == null || fallback == null) return null;
    final Object? declared = value[field];
    final String ref = declared is String && declared.isNotEmpty
        ? declared
        : fallback;
    try {
      final statuses = await _repository.describeCredentials(<String>[ref]);
      return statuses.where((status) => status.ref == ref).firstOrNull ??
          CredentialStatus(ref: ref, configured: false, writable: true);
    } catch (error) {
      ErrorLogCollector.instance.addBreadcrumb(
        'Credential describe failed for $ref: $error',
        level: 'warning',
      );
      return CredentialStatus(ref: ref, configured: false, writable: true);
    }
  }

  static Map<String, Object?> _asMap(Object? value) =>
      value is Map ? value.cast<String, Object?>() : const <String, Object?>{};
}

/// The staged form over one namespace: the rows, the per-field override mark
/// and reset, the secret when the page has one, and the Save that writes them.
///
/// Drafts live here, not in the controller: nothing reaches the Host until
/// Save, and leaving the page drops what was typed
/// (`ui-settings-shell/README.md` "Use this package").
class HostNamespaceFormCard extends StatefulWidget {
  const HostNamespaceFormCard({
    required this.controller,
    required this.fields,
    this.secret,
    super.key,
  });

  final HostNamespaceController controller;
  final List<HostNamespaceField> fields;

  /// The one credential row, for a page whose key is not in the document.
  final HostNamespaceSecret? secret;

  @override
  State<HostNamespaceFormCard> createState() => _HostNamespaceFormCardState();
}

class _HostNamespaceFormCardState extends State<HostNamespaceFormCard> {
  final Map<String, TextEditingController> _fields =
      <String, TextEditingController>{};
  final TextEditingController _secret = TextEditingController();

  /// Field keys the reader touched: their draft is what Save writes, even when
  /// it is empty — an empty draft is the reset.
  final Set<String> _touched = <String>{};

  HostNamespaceState _state = const HostNamespaceState();
  StreamSubscription<HostNamespaceState>? _subscription;

  @override
  void initState() {
    super.initState();
    for (final HostNamespaceField field in widget.fields) {
      _fields[field.key] = TextEditingController();
    }
    _state = widget.controller.state;
    _adopt();
    _subscription = widget.controller.uiState.listen((
      HostNamespaceState state,
    ) {
      if (!mounted) return;
      setState(() {
        _state = state;
        // A describe landing under an untouched form refreshes the shown
        // values; a draft the reader typed stands until they save or
        // discard it.
        if (_touched.isEmpty) _adopt();
      });
    });
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    for (final TextEditingController controller in _fields.values) {
      controller.dispose();
    }
    _secret.dispose();
    super.dispose();
  }

  /// Show the effective values the Host just published.
  void _adopt() {
    for (final HostNamespaceField field in widget.fields) {
      _fields[field.key]?.text = _formatValue(_state.effective(field.key));
    }
  }

  static String _formatValue(Object? value) => switch (value) {
    null => '',
    final num number => number.toString(),
    final String text => text,
    _ => jsonEncode(value),
  };

  bool _invalid(HostNamespaceField field) {
    if (!field.numeric) return false;
    final String draft = _fields[field.key]?.text.trim() ?? '';
    return draft.isNotEmpty && num.tryParse(draft) == null;
  }

  bool get _anyInvalid => widget.fields.any(_invalid);

  bool get _dirty => _touched.isNotEmpty || _secret.text.isNotEmpty;

  bool get _canSave =>
      _state.served &&
      _state.writable &&
      !_state.saving &&
      _dirty &&
      !_anyInvalid;

  void _resetField(HostNamespaceField field) {
    setState(() {
      _fields[field.key]?.text = '';
      _touched.add(field.key);
    });
  }

  void _discard() {
    setState(() {
      _touched.clear();
      _secret.clear();
      _adopt();
    });
  }

  Future<void> _save() async {
    final ops = <SettingPathOp>[];
    for (final HostNamespaceField field in widget.fields) {
      if (!_touched.contains(field.key) || _invalid(field)) continue;
      final String draft = _fields[field.key]?.text.trim() ?? '';
      if (draft.isEmpty) {
        // An empty field saves as a reset (`ui-settings-shell/README.md`).
        if (_state.overridden(field.key)) {
          ops.add(HostNamespaceController.resetOp(field.key));
        }
        continue;
      }
      final Object value = field.numeric ? num.parse(draft) : draft;
      ops.add(
        SettingPathOp(
          op: 'set',
          path: <String>[field.key],
          jsonValue: jsonEncode(value),
        ),
      );
    }
    final String key = _secret.text;
    setState(() {
      _touched.clear();
      _secret.clear();
    });
    await widget.controller.save(
      ops,
      credentialValue: key.isEmpty ? null : key,
    );
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    if (!_state.served) {
      return SettingsSectionCard(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              l10n.settingsFormUnavailable,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (!_state.writable)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              l10n.settingsFormReadOnly,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        SettingsSectionCard(
          children: <Widget>[
            // The pin's key row leads the card, then its two settings rows
            // (`WebSearchCard.tsx:31-69`).
            if (widget.secret
                case final HostNamespaceSecret secret) ...<Widget>[
              _secretField(context, secret),
              if (widget.fields.isNotEmpty) const SettingsCardDivider(),
            ],
            for (var i = 0; i < widget.fields.length; i++) ...<Widget>[
              if (i > 0) const SettingsCardDivider(),
              _field(context, widget.fields[i]),
            ],
          ],
        ),
        if (_state.failed) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            l10n.settingsFormSaveFailed,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            OutlinedButton(
              onPressed: _dirty && !_state.saving ? _discard : null,
              style: settingsOutlineCapsule(context),
              child: Text(l10n.discard),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _canSave ? () => unawaited(_save()) : null,
              style: settingsFilledCapsule(context),
              child: Text(_state.saving ? l10n.settingsFormSaving : l10n.save),
            ),
          ],
        ),
      ],
    );
  }

  Widget _field(BuildContext context, HostNamespaceField field) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final bool overridden = _state.overridden(field.key);
    final bool enabled = _state.writable && !_state.saving;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SettingsFieldLabel(field.label),
          const SizedBox(height: 6),
          TextField(
            key: ValueKey<String>('host-namespace-field-${field.key}'),
            controller: _fields[field.key],
            enabled: enabled,
            keyboardType: field.numeric ? TextInputType.number : null,
            inputFormatters: field.numeric
                ? <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ]
                : null,
            decoration: settingsInputDecoration(context, hint: field.hint),
            onChanged: (String _) => setState(() => _touched.add(field.key)),
          ),
          if (_invalid(field)) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              l10n.settingsFormInvalidNumber,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ],
          if (overridden) ...<Widget>[
            const SizedBox(height: 6),
            // A wrap, not a row: the mark and the reset verb share the line
            // while the card is wide enough and take one each when it is not,
            // instead of pushing the verb off the card.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: <Widget>[
                SettingsBadge(
                  label: l10n.settingsFormOverridden,
                  tone: SettingsBadgeTone.primary,
                ),
                TextButton(
                  onPressed: enabled ? () => _resetField(field) : null,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: theme.textTheme.bodySmall,
                  ),
                  child: Text(l10n.settingsFormReset),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _secretField(BuildContext context, HostNamespaceSecret secret) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    // The credentials domain is its own store with its own refusal: a key stays
    // writable while the settings document is read-only, and a key the process
    // environment supplies disables only this control
    // (`WebSearchCard.tsx:35-39`).
    final bool enabled = _state.credentialWritable && !_state.saving;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SettingsFieldLabel(secret.label),
          const SizedBox(height: 6),
          TextField(
            key: const ValueKey<String>('host-namespace-secret'),
            controller: _secret,
            enabled: enabled,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: settingsInputDecoration(context, hint: secret.hint),
            onChanged: (String _) => setState(() {}),
          ),
          const SizedBox(height: 6),
          Text(
            _state.credentialConfigured
                ? secret.configuredLabel
                : secret.unsetLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// The index row one namespace page hangs off.
///
/// The reference registers each card through `whileServed` and withdraws it
/// when the Host stops serving the namespace
/// (`ui-settings-shell/src/client/index.ts:50-52`); the row does the same, and
/// states the pin's own `unavailable` copy while it binds none, so it never
/// offers a form that cannot land.
class HostNamespaceEntryRow extends StatelessWidget {
  const HostNamespaceEntryRow({
    required this.controller,
    required this.title,
    required this.leading,
    required this.onOpen,
    super.key,
  });

  final HostNamespaceController controller;
  final String title;
  final Widget leading;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return StreamBuilder<HostNamespaceState>(
      stream: controller.uiState,
      initialData: controller.state,
      builder:
          (BuildContext context, AsyncSnapshot<HostNamespaceState> snapshot) {
            final HostNamespaceState state = snapshot.data ?? controller.state;
            if (state.loading && !state.served) {
              return SettingsNavRow(
                title: title,
                leading: leading,
                enabled: false,
                onTap: () {},
              );
            }
            if (!state.served) {
              return SettingsNavRow(
                title: title,
                leading: leading,
                value: l10n.settingsFormUnavailable,
                enabled: false,
                onTap: () {},
              );
            }
            return SettingsNavRow(
              title: title,
              leading: leading,
              onTap: onOpen,
            );
          },
    );
  }
}
