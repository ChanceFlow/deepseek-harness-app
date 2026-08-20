/// Settings screen controller — port of the legacy SettingsViewModel.
///
/// Read-mostly settings/credentials overview plus the agent-preset
/// default write. The host pins the settings and credential verbs to
/// loopback connections, so a remote source surfaces the transport error
/// instead of a page; writes re-describe on success.
library;

import 'dart:async';
import 'dart:convert';

import 'package:domain/model/agent_preset.dart';
import 'package:domain/model/settings.dart';
import 'package:domain/repository/chat_repository.dart';

import '../state_stream.dart';
import 'settings_ui_state.dart';

/// The settings namespace the host resolves the default agent preset
/// from at session creation (web `AGENT_PRESET_SETTINGS_NS`).
const String kAgentPresetSettingsNs = 'agent-presets';

/// The namespace field carrying the default preset id.
const String kAgentPresetDefaultField = 'default';

class SettingsController {
  SettingsController(this._repository) {
    _refresh();
  }

  final ChatRepository _repository;
  final AppStateStream<SettingsUiState> _state =
      AppStateStream<SettingsUiState>(const SettingsUiState(isLoading: true));

  SettingsSnapshot? _snapshot;
  List<CredentialStatus> _credentials = const <CredentialStatus>[];
  AgentPresetRoster? _roster;
  bool _isLoading = false;
  String? _errorMessage;
  String? _credentialError;

  SettingsUiState get state => _state.value;
  Stream<SettingsUiState> get uiState => _state.stream;

  void dispose() {}

  void _publish() {
    _state.value = SettingsUiState(
      snapshot: _snapshot,
      credentials: _credentials,
      isLoading: _isLoading,
      errorMessage: _errorMessage,
      credentialError: _credentialError,
      roster: _roster,
    );
  }

  void onAction(SettingsAction action) {
    switch (action) {
      case RefreshSettingsAction():
        _refresh();
      case DismissSettingsError():
        _errorMessage = null;
        _publish();
      case SetCredentialAction():
        _writeCredential(action.ref, action.value);
      case UnsetCredentialAction():
        _clearCredential(action.ref);
      case UpdateSettingAction():
        _updateSetting(action);
      case ReplaceSettingAction():
        _replaceSetting(action);
      case SelectAgentPresetDefaultAction():
        _selectAgentPresetDefault(action.presetId);
    }
  }

  /// One-key namespace patch with the described revision as CAS guard.
  void _updateSetting(UpdateSettingAction action) {
    if (action.key.trim().isEmpty || action.jsonValue.trim().isEmpty) return;
    unawaited(() async {
      _isLoading = true;
      _publish();
      try {
        final updated = await _runCatchingForUi(
          () => _repository.updateSetting(
            action.ns,
            action.key.trim(),
            action.jsonValue.trim(),
            expectedRevision: action.expectedRevision,
          ),
        );
        if (updated != null) await _refreshNow();
      } finally {
        _isLoading = false;
        _publish();
      }
    }());
  }

  /// Whole-section replacement of one namespace's user layer.
  void _replaceSetting(ReplaceSettingAction action) {
    if (action.sectionJson.trim().isEmpty) return;
    unawaited(() async {
      _isLoading = true;
      _publish();
      try {
        final updated = await _runCatchingForUi(
          () => _repository.replaceSetting(
            action.ns,
            action.sectionJson.trim(),
            expectedRevision: action.expectedRevision,
          ),
        );
        if (updated != null) await _refreshNow();
      } finally {
        _isLoading = false;
        _publish();
      }
    }());
  }

  /// Persists one preset as the default for sessions created later
  /// (web `writeDefaultPreset`): a one-key patch of the
  /// `agent-presets` namespace's `default` field, CAS-guarded by the
  /// revision the last describe reported for that namespace. Running
  /// sessions keep the composition they were created with.
  void _selectAgentPresetDefault(String presetId) {
    if (presetId.isEmpty) return;
    unawaited(() async {
      _isLoading = true;
      _publish();
      try {
        final revision = _snapshot?.namespaces
            .where((ns) => ns.ns == kAgentPresetSettingsNs)
            .firstOrNull
            ?.revision;
        final updated = await _runCatchingForUi(
          () => _repository.updateSetting(
            kAgentPresetSettingsNs,
            kAgentPresetDefaultField,
            jsonEncode(presetId),
            expectedRevision: revision,
          ),
        );
        if (updated != null) await _refreshNow();
      } finally {
        _isLoading = false;
        _publish();
      }
    }());
  }

  /// Writes are loopback-gated; both paths re-describe after a success.
  void _writeCredential(String ref, String value) {
    if (value.isEmpty) return;
    unawaited(() async {
      _isLoading = true;
      _publish();
      try {
        // Future<void> resolves to null, so success is tracked explicitly
        // (the Kotlin Unit return was non-null).
        var ok = false;
        await _runCatchingForUi(() async {
          await _repository.setCredential(ref, value);
          ok = true;
        });
        if (ok) await _refreshNow();
      } finally {
        _isLoading = false;
        _publish();
      }
    }());
  }

  void _clearCredential(String ref) {
    unawaited(() async {
      _isLoading = true;
      _publish();
      try {
        var ok = false;
        await _runCatchingForUi(() async {
          await _repository.unsetCredential(ref);
          ok = true;
        });
        if (ok) await _refreshNow();
      } finally {
        _isLoading = false;
        _publish();
      }
    }());
  }

  void _refresh() {
    unawaited(_refreshNow());
  }

  Future<void> _refreshNow() async {
    _isLoading = true;
    _publish();
    final described = await _runCatchingForUi(_repository.describeSettings);
    if (described != null) {
      _snapshot = described;
      await _loadCredentials(described.credentialRefs);
      await _loadRoster();
    }
    _isLoading = false;
    _publish();
  }

  /// The roster rides the describe refresh: the presets section and the
  /// General picker need the settings snapshot (writability, the
  /// `agent-presets` revision) to act on it. A failure keeps the last
  /// good roster and surfaces through the error banner.
  Future<void> _loadRoster() async {
    final roster = await _runCatchingForUi(_repository.listAgentPresets);
    if (roster != null) _roster = roster;
  }

  Future<void> _loadCredentials(List<String> refs) async {
    _credentialError = null;
    try {
      _credentials = await _repository.describeCredentials(refs);
    } catch (error) {
      _credentials = const <CredentialStatus>[];
      _credentialError = error.toString();
    }
  }

  Future<T?> _runCatchingForUi<T>(Future<T> Function() block) async {
    try {
      _errorMessage = null;
      _publish();
      return await block();
    } catch (error) {
      _errorMessage = error.toString();
      _publish();
      return null;
    }
  }
}
