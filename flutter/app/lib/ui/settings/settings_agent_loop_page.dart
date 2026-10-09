/// The agent loop page: the pin's `ui-settings-agent-loop` section, which the
/// Host section carries as one card with one field.
///
/// The namespace is `agent-loop` (`reference/.../ui-settings-agent-loop/src/
/// client/agent-loop-card-controller.ts:15`) and the only field is
/// `maxParallelToolCalls` — "upper bound on parallel-safe tool calls in flight
/// per step" (`:19-22`, declared `:25`/`:45`). The composed `agents` array is
/// deliberately not part of this section (`:17-18`), so no roster is rendered
/// here.
///
/// Persistence follows [ThemePreferenceController]: describe the host document,
/// take the namespace's own `revision` and the document's `writable` flag, and
/// write with that revision as the CAS fence. A namespace the host does not
/// publish renders **absent** — never a defaulted number, because a cap the
/// reader never set is not a value we may invent.
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

/// The namespace the Host document carries this page's field in.
const String kAgentLoopNamespace = 'agent-loop';

/// The one field this section edits.
const String kMaxParallelToolCallsField = 'maxParallelToolCalls';

/// What the page renders: the stored cap, the namespace's revision, and whether
/// the host published the namespace at all.
final class AgentLoopState {
  const AgentLoopState({
    this.maxParallelToolCalls,
    this.exposed = false,
    this.writable = false,
    this.revision,
    this.loading = true,
    this.saving = false,
    this.failed = false,
  });

  /// The stored cap, or null when the field is absent or unreadable.
  final int? maxParallelToolCalls;

  /// Whether the host document carries the `agent-loop` namespace at all.
  final bool exposed;

  final bool writable;
  final int? revision;
  final bool loading;
  final bool saving;
  final bool failed;

  AgentLoopState copyWith({
    int? maxParallelToolCalls,
    bool? exposed,
    bool? writable,
    int? revision,
    bool? loading,
    bool? saving,
    bool? failed,
  }) => AgentLoopState(
    maxParallelToolCalls: maxParallelToolCalls ?? this.maxParallelToolCalls,
    exposed: exposed ?? this.exposed,
    writable: writable ?? this.writable,
    revision: revision ?? this.revision,
    loading: loading ?? this.loading,
    saving: saving ?? this.saving,
    failed: failed ?? this.failed,
  );
}

/// UDF controller over the host `agent-loop` namespace: reads on construction,
/// publishes every change, writes with the described revision as the fence.
class AgentLoopController {
  AgentLoopController(this._repository) {
    unawaited(refresh());
  }

  final ChatRepository _repository;
  final AppStateStream<AgentLoopState> _state = AppStateStream<AgentLoopState>(
    const AgentLoopState(),
  );

  AgentLoopState get state => _state.value;
  Stream<AgentLoopState> get uiState => _state.stream;

  void dispose() {
    unawaited(_state.close());
  }

  /// Re-describe the document and adopt what the host reports.
  Future<void> refresh() async {
    _state.value = _state.value.copyWith(loading: true, failed: false);
    try {
      final snapshot = await _repository.describeSettings();
      final namespace = snapshot.namespaces
          .where((entry) => entry.ns == kAgentLoopNamespace)
          .firstOrNull;
      final value = namespace?.value;
      final exposed =
          value is Map && value.containsKey(kMaxParallelToolCallsField);
      final stored = exposed ? value[kMaxParallelToolCallsField] : null;
      _state.value = AgentLoopState(
        maxParallelToolCalls: stored is num ? stored.toInt() : null,
        exposed: exposed,
        writable: snapshot.writable,
        revision: namespace?.revision,
        // The describe settled: without this the page keeps its loading state
        // and renders the field for a namespace the host never published.
        loading: false,
      );
    } catch (error) {
      _state.value = _state.value.copyWith(loading: false, failed: true);
      ErrorLogCollector.instance.addBreadcrumb(
        'Agent loop describe failed: $error',
        level: 'warning',
      );
    }
  }

  /// Persist one cap. The field updates optimistically and reverts when the
  /// host refuses the write.
  Future<void> setMaxParallelToolCalls(int value) async {
    final before = _state.value;
    if (value == before.maxParallelToolCalls || before.saving) return;
    _state.value = before.copyWith(
      maxParallelToolCalls: value,
      saving: true,
      failed: false,
    );
    try {
      await _repository.updateSetting(
        kAgentLoopNamespace,
        kMaxParallelToolCallsField,
        jsonEncode(value),
        expectedRevision: before.revision,
      );
      await refresh();
    } catch (error) {
      _state.value = before.copyWith(failed: true, saving: false);
      ErrorLogCollector.instance.addBreadcrumb(
        'Agent loop write failed: $error',
        level: 'warning',
      );
    }
  }
}

/// The agent loop card: one row, one number.
class SettingsAgentLoopPage extends ConsumerStatefulWidget {
  const SettingsAgentLoopPage({required this.backendId, super.key});

  /// The backend whose Host document carries this page's namespace; the route
  /// that pushes the page resolves it the way its sibling pages do.
  final String backendId;

  @override
  ConsumerState<SettingsAgentLoopPage> createState() =>
      _SettingsAgentLoopPageState();
}

class _SettingsAgentLoopPageState extends ConsumerState<SettingsAgentLoopPage> {
  AgentLoopController? _controller;
  final TextEditingController _field = TextEditingController();

  @override
  void initState() {
    super.initState();
    _bind();
    _field.addListener(_onChanged);
  }

  void _bind() {
    _controller = AgentLoopController(
      ref.read(chatRepositoryProvider(widget.backendId)),
    );
    _controller!.uiState.listen((AgentLoopState state) {
      if (!mounted) return;
      final int? value = state.maxParallelToolCalls;
      final String text = value?.toString() ?? '';
      if (_field.text != text && !_fieldFocus.hasFocus) _field.text = text;
      setState(() {});
    });
  }

  final FocusNode _fieldFocus = FocusNode();

  void _onChanged() {
    final int? parsed = int.tryParse(_field.text.trim());
    if (parsed != null) unawaited(_controller?.setMaxParallelToolCalls(parsed));
  }

  @override
  void dispose() {
    _field.removeListener(_onChanged);
    _field.dispose();
    _fieldFocus.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final AgentLoopState state = _controller?.state ?? const AgentLoopState();
    return SettingsPageScaffold(
      title: l10n.settingsAgentLoopTitle,
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  l10n.settingsAgentLoopTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(l10n.settingsAgentLoopDescription),
                const SizedBox(height: 12),
                // An unpublished namespace renders absent: there is no stored
                // cap to show, and inventing one would report a value the host
                // never held.
                if (!state.loading && !state.exposed)
                  Text(
                    l10n.settingsAgentLoopUnpublished,
                    style: Theme.of(context).textTheme.bodyMedium,
                  )
                else
                  TextField(
                    controller: _field,
                    focusNode: _fieldFocus,
                    enabled: state.writable && !state.saving,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: l10n.settingsAgentLoopMaxParallel,
                      helperText: state.failed
                          ? l10n.settingsAgentLoopSaveFailed
                          : null,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
