/// The subagent page: the pin's `ui-settings-subagent` section — one page over
/// **two** Host namespaces, saved together (`ui-settings-subagent/src/client/
/// index.ts:3-6`; `SUBAGENT_NS = 'subagent'` `:50`).
///
/// The limits card (`subagent-limits-card-controller.ts`) edits `maxDepth`
/// (`minimum: 0`) and `maxActiveSubagents` (`minimum: 1`) (`:14-18`, `:45`), and
/// its parse guard (`:29-37`) **rejects** a non-safe-integer, a below-minimum
/// value and `-0` instead of clamping them: a rejected entry leaves the stored
/// value standing and writes nothing.
///
/// The model-selection card (`subagent-model-selection-card-controller.ts`)
/// edits the second namespace, `subagent-model-selection-settings` (`:9`):
/// `enabled` (bool) and `allowedModels` (`{provider, model}[]`, exact routes
/// stored as the reader's authorization) (`:15-24`). Each stored route is
/// joined with the adapter catalog (`:26-40`), so a route the catalog no longer
/// advertises **still renders**, marked unavailable.
///
/// Persistence follows [ThemePreferenceController]: describe, take each
/// namespace's own `revision` and the document's `writable`, and write with that
/// revision as the CAS fence. A namespace the Host does not publish renders
/// **absent** — never a defaulted value.
library;

import 'dart:async';
import 'dart:convert';

import 'package:app/l10n/app_localizations.dart';
import 'package:app/ui/state_stream.dart';
import 'package:domain/repository/chat_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import 'settings_chrome.dart';

/// The Host namespace carrying the delegation limits (`index.ts:50`).
const String kSubagentLimitsNamespace = 'subagent';

/// The Host namespace carrying the model allowlist (`...-controller.ts:9`).
const String kSubagentModelSelectionNamespace =
    'subagent-model-selection-settings';

/// The limits card's two fields (`subagent-limits-card-controller.ts:45`).
const String kSubagentMaxDepthField = 'maxDepth';
const String kSubagentMaxActiveSubagentsField = 'maxActiveSubagents';

/// The model card's two fields (`subagent-model-selection-card-controller.ts:15-24`).
const String kSubagentEnabledField = 'enabled';
const String kSubagentAllowedModelsField = 'allowedModels';

/// The largest integer the pin accepts (`Number.isSafeInteger`,
/// `subagent-limits-card-controller.ts:33`). Dart integers are wider, so the
/// bound is stated rather than inherited.
const int kSubagentMaxSafeInteger = 9007199254740991;

/// One exact provider/model route, stored or advertised.
@immutable
final class SubagentModelRoute {
  const SubagentModelRoute({
    required this.provider,
    required this.model,
    this.providerName,
    this.modelName,
    this.available = true,
  });

  /// The route's identity, used for lookup only (`...-controller.ts:28-31`).
  static String keyOf(String provider, String model) => '$provider/$model';

  final String provider;
  final String model;
  final String? providerName;
  final String? modelName;

  /// False once the catalog stops advertising this exact route; the row stays.
  final bool available;

  String get key => keyOf(provider, model);
}

/// Parse one limit the way the pin's guard does
/// (`subagent-limits-card-controller.ts:29-37`): a non-integer, a JS
/// unsafe integer, a value below [minimum], and a negative zero are all
/// **rejected** (null) rather than clamped to the bound.
int? parseSubagentLimit(String text, {required int minimum}) {
  final String trimmed = text.trim();
  // `Object.is(value, -0)` — `int.tryParse('-0')` would answer 0, so the
  // literal is what has to be refused.
  if (RegExp(r'^-\s*0+$').hasMatch(trimmed)) return null;
  final int? value = int.tryParse(trimmed);
  if (value == null) return null;
  if (value.abs() > kSubagentMaxSafeInteger) return null;
  if (value < minimum) return null;
  return value;
}

/// What the page renders: the two namespaces' stored values, their revisions,
/// and whether the Host published each at all.
final class SubagentSettingsState {
  const SubagentSettingsState({
    this.maxDepth,
    this.maxActiveSubagents,
    this.enabled = false,
    this.allowedModels = const <SubagentModelRoute>[],
    this.limitsExposed = false,
    this.modelsExposed = false,
    this.writable = false,
    this.limitsRevision,
    this.modelsRevision,
    this.loading = true,
    this.saving = false,
    this.failed = false,
    this.rejectedField,
  });

  final int? maxDepth;
  final int? maxActiveSubagents;
  final bool enabled;
  final List<SubagentModelRoute> allowedModels;
  final bool limitsExposed;
  final bool modelsExposed;
  final bool writable;
  final int? limitsRevision;
  final int? modelsRevision;
  final bool loading;
  final bool saving;
  final bool failed;

  /// The field whose last entry was refused, for the page's one message.
  final String? rejectedField;

  SubagentSettingsState copyWith({
    int? maxDepth,
    int? maxActiveSubagents,
    bool? enabled,
    List<SubagentModelRoute>? allowedModels,
    bool? limitsExposed,
    bool? modelsExposed,
    bool? writable,
    int? limitsRevision,
    int? modelsRevision,
    bool? loading,
    bool? saving,
    bool? failed,
    String? rejectedField,
    bool clearRejected = false,
  }) => SubagentSettingsState(
    maxDepth: maxDepth ?? this.maxDepth,
    maxActiveSubagents: maxActiveSubagents ?? this.maxActiveSubagents,
    enabled: enabled ?? this.enabled,
    allowedModels: allowedModels ?? this.allowedModels,
    limitsExposed: limitsExposed ?? this.limitsExposed,
    modelsExposed: modelsExposed ?? this.modelsExposed,
    writable: writable ?? this.writable,
    limitsRevision: limitsRevision ?? this.limitsRevision,
    modelsRevision: modelsRevision ?? this.modelsRevision,
    loading: loading ?? this.loading,
    saving: saving ?? this.saving,
    failed: failed ?? this.failed,
    rejectedField: clearRejected ? null : (rejectedField ?? this.rejectedField),
  );
}

/// UDF controller over both namespaces: one describe fills both cards, and
/// [save] writes every field that differs from what the Host last reported,
/// each with its own namespace's revision as the fence.
class SubagentSettingsController {
  SubagentSettingsController(this._repository, {this.catalog = const []}) {
    unawaited(refresh());
  }

  final ChatRepository _repository;

  /// The adapter catalog the stored routes are joined against. Empty means the
  /// surface has no catalog to compare with, so no stored route is called
  /// unavailable on no evidence.
  final List<SubagentModelRoute> catalog;

  final AppStateStream<SubagentSettingsState> _state =
      AppStateStream<SubagentSettingsState>(const SubagentSettingsState());

  /// What the Host last reported, so [save] writes only real changes.
  SubagentSettingsState _described = const SubagentSettingsState();

  SubagentSettingsState get state => _state.value;
  Stream<SubagentSettingsState> get uiState => _state.stream;

  void dispose() {
    unawaited(_state.close());
  }

  /// Re-describe the document and adopt both namespaces.
  Future<void> refresh() async {
    try {
      final snapshot = await _repository.describeSettings();
      final limits = snapshot.namespaces
          .where((entry) => entry.ns == kSubagentLimitsNamespace)
          .firstOrNull;
      final models = snapshot.namespaces
          .where((entry) => entry.ns == kSubagentModelSelectionNamespace)
          .firstOrNull;
      final limitsValue = limits?.value;
      final modelsValue = models?.value;
      final next = SubagentSettingsState(
        maxDepth: _intOf(limitsValue, kSubagentMaxDepthField),
        maxActiveSubagents: _intOf(
          limitsValue,
          kSubagentMaxActiveSubagentsField,
        ),
        enabled:
            modelsValue is Map && modelsValue[kSubagentEnabledField] == true,
        allowedModels: _routesOf(modelsValue),
        limitsExposed: limitsValue is Map,
        modelsExposed: modelsValue is Map,
        writable: snapshot.writable,
        limitsRevision: limits?.revision,
        modelsRevision: models?.revision,
      );
      _described = next;
      _state.value = next;
    } catch (error) {
      _state.value = _state.value.copyWith(loading: false, failed: true);
      ErrorLogCollector.instance.addBreadcrumb(
        'Subagent describe failed: $error',
        level: 'warning',
      );
    }
  }

  static int? _intOf(Object? value, String field) {
    if (value is! Map) return null;
    final Object? stored = value[field];
    return stored is num ? stored.toInt() : null;
  }

  List<SubagentModelRoute> _routesOf(Object? value) {
    if (value is! Map) return const <SubagentModelRoute>[];
    final Object? stored = value[kSubagentAllowedModelsField];
    if (stored is! List) return const <SubagentModelRoute>[];
    return <SubagentModelRoute>[
      for (final Object? entry in stored)
        if (entry is Map &&
            entry['provider'] is String &&
            entry['model'] is String)
          _joined(entry['provider']! as String, entry['model']! as String),
    ];
  }

  SubagentModelRoute _joined(String provider, String model) {
    final advertised = catalog
        .where(
          (route) => route.key == SubagentModelRoute.keyOf(provider, model),
        )
        .firstOrNull;
    if (catalog.isEmpty) {
      return SubagentModelRoute(provider: provider, model: model);
    }
    return SubagentModelRoute(
      provider: provider,
      model: model,
      providerName: advertised?.providerName,
      modelName: advertised?.modelName,
      available: advertised != null,
    );
  }

  /// Draft one limit. A refused entry changes nothing and is reported, rather
  /// than clamped to the bound (`subagent-limits-card-controller.ts:29-37`).
  bool setMaxDepth(String text) => _setLimit(
    text,
    field: kSubagentMaxDepthField,
    minimum: 0,
    apply: (value) => _state.value = _state.value.copyWith(
      maxDepth: value,
      clearRejected: true,
    ),
  );

  /// Draft the other limit (`minimum: 1`).
  bool setMaxActiveSubagents(String text) => _setLimit(
    text,
    field: kSubagentMaxActiveSubagentsField,
    minimum: 1,
    apply: (value) => _state.value = _state.value.copyWith(
      maxActiveSubagents: value,
      clearRejected: true,
    ),
  );

  bool _setLimit(
    String text, {
    required String field,
    required int minimum,
    required void Function(int value) apply,
  }) {
    final int? value = parseSubagentLimit(text, minimum: minimum);
    if (value == null) {
      _state.value = _state.value.copyWith(rejectedField: field);
      return false;
    }
    apply(value);
    return true;
  }

  void setEnabled(bool enabled) {
    _state.value = _state.value.copyWith(enabled: enabled, clearRejected: true);
  }

  /// Authorize or revoke one exact route.
  void setRouteSelected(SubagentModelRoute route, bool selected) {
    final current = _state.value.allowedModels;
    final next = <SubagentModelRoute>[
      for (final SubagentModelRoute entry in current)
        if (entry.key != route.key) entry,
      if (selected) route,
    ];
    _state.value = _state.value.copyWith(
      allowedModels: next,
      clearRejected: true,
    );
  }

  /// Write every field that differs from the described one, each under its own
  /// namespace's revision. Nothing dirty means nothing written.
  Future<void> save() async {
    final before = _state.value;
    if (before.saving) return;
    _state.value = before.copyWith(saving: true, failed: false);
    try {
      if (before.limitsExposed) {
        if (before.maxDepth != _described.maxDepth && before.maxDepth != null) {
          await _write(
            kSubagentLimitsNamespace,
            kSubagentMaxDepthField,
            before.maxDepth,
            before.limitsRevision,
          );
        }
        if (before.maxActiveSubagents != _described.maxActiveSubagents &&
            before.maxActiveSubagents != null) {
          await _write(
            kSubagentLimitsNamespace,
            kSubagentMaxActiveSubagentsField,
            before.maxActiveSubagents,
            before.limitsRevision,
          );
        }
      }
      if (before.modelsExposed) {
        if (before.enabled != _described.enabled) {
          await _write(
            kSubagentModelSelectionNamespace,
            kSubagentEnabledField,
            before.enabled,
            before.modelsRevision,
          );
        }
        if (!_sameRoutes(before.allowedModels, _described.allowedModels)) {
          await _write(
            kSubagentModelSelectionNamespace,
            kSubagentAllowedModelsField,
            <Map<String, String>>[
              for (final SubagentModelRoute route in before.allowedModels)
                <String, String>{
                  'provider': route.provider,
                  'model': route.model,
                },
            ],
            before.modelsRevision,
          );
        }
      }
      await refresh();
    } catch (error) {
      _state.value = _state.value.copyWith(saving: false, failed: true);
      ErrorLogCollector.instance.addBreadcrumb(
        'Subagent write failed: $error',
        level: 'warning',
      );
    }
  }

  Future<void> _write(String ns, String field, Object? value, int? revision) =>
      _repository.updateSetting(
        ns,
        field,
        jsonEncode(value),
        expectedRevision: revision,
      );

  static bool _sameRoutes(
    List<SubagentModelRoute> a,
    List<SubagentModelRoute> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].key != b[i].key) return false;
    }
    return true;
  }
}

/// The page: the limits card and the model-selection card, saved together.
class SettingsSubagentPage extends ConsumerStatefulWidget {
  const SettingsSubagentPage({required this.backendId, super.key});

  final String backendId;

  @override
  ConsumerState<SettingsSubagentPage> createState() =>
      _SettingsSubagentPageState();
}

class _SettingsSubagentPageState extends ConsumerState<SettingsSubagentPage> {
  SubagentSettingsController? _controller;
  final TextEditingController _depth = TextEditingController();
  final TextEditingController _active = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = SubagentSettingsController(
      ref.read(chatRepositoryProvider(widget.backendId)),
    );
    _controller!.uiState.listen((SubagentSettingsState state) {
      if (!mounted) return;
      if (_depth.text != '${state.maxDepth ?? ''}') {
        _depth.text = state.maxDepth?.toString() ?? '';
      }
      if (_active.text != '${state.maxActiveSubagents ?? ''}') {
        _active.text = state.maxActiveSubagents?.toString() ?? '';
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    _depth.dispose();
    _active.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final SubagentSettingsController controller = _controller!;
    final SubagentSettingsState state = controller.state;
    return SettingsPageScaffold(
      title: l10n.settingsSubagentTitle,
      children: <Widget>[
        if (state.limitsExposed)
          SettingsSectionCard(
            children: <Widget>[
              _NumberRow(
                label: l10n.settingsSubagentMaxDepth,
                controller: _depth,
                onChanged: controller.setMaxDepth,
                rejected: state.rejectedField == kSubagentMaxDepthField
                    ? l10n.settingsSubagentLimitRejected
                    : null,
              ),
              const SettingsCardDivider(),
              _NumberRow(
                label: l10n.settingsSubagentMaxActive,
                controller: _active,
                onChanged: controller.setMaxActiveSubagents,
                rejected:
                    state.rejectedField == kSubagentMaxActiveSubagentsField
                    ? l10n.settingsSubagentLimitRejected
                    : null,
              ),
            ],
          ),
        if (state.modelsExposed) ...<Widget>[
          const SizedBox(height: 12),
          SettingsSectionCard(
            children: <Widget>[
              SwitchListTile(
                title: Text(l10n.settingsSubagentModelSelection),
                subtitle: Text(l10n.settingsSubagentModelSelectionBody),
                value: state.enabled,
                onChanged: state.writable ? controller.setEnabled : null,
              ),
              for (final SubagentModelRoute route in state.allowedModels) ...[
                const SettingsCardDivider(),
                CheckboxListTile(
                  title: Text(
                    route.modelName ??
                        '${route.providerName ?? route.provider} / ${route.model}',
                  ),
                  subtitle: Text(
                    route.available
                        ? route.key
                        : '${route.key} · ${l10n.settingsSubagentUnavailable}',
                  ),
                  value: true,
                  onChanged: state.writable
                      ? (bool? selected) => controller.setRouteSelected(
                          route,
                          selected ?? false,
                        )
                      : null,
                ),
              ],
            ],
          ),
        ],
        if (state.failed) ...<Widget>[
          const SizedBox(height: 8),
          Text(l10n.settingsSubagentSaveFailed),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: state.saving ? null : controller.save,
          child: Text(l10n.settingsSubagentSave),
        ),
      ],
    );
  }
}

/// One labelled number field with its own refusal message.
class _NumberRow extends StatelessWidget {
  const _NumberRow({
    required this.label,
    required this.controller,
    required this.onChanged,
    this.rejected,
  });

  final String label;
  final TextEditingController controller;
  final bool Function(String text) onChanged;
  final String? rejected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label, errorText: rejected),
        onChanged: onChanged,
      ),
    );
  }
}
