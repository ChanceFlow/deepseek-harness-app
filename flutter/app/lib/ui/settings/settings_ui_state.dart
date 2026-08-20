/// Settings screen UI state and intents — port of SettingsUiState.kt,
/// extended for the sectioned panel (agent-preset roster).
library;

import 'package:domain/model/agent_preset.dart';
import 'package:domain/model/settings.dart';

final class SettingsUiState {
  const SettingsUiState({
    this.snapshot,
    this.credentials = const <CredentialStatus>[],
    this.isLoading = false,
    this.errorMessage,
    this.credentialError,
    this.roster,
  });

  final SettingsSnapshot? snapshot;
  final List<CredentialStatus> credentials;
  final bool isLoading;
  final String? errorMessage;

  /// Credential describe is enrichment: its failure never blanks the page.
  final String? credentialError;

  /// Agent-preset roster (web `agentPreset.list`); null while unloaded or
  /// after a load failure — the presets section and the General picker
  /// render nothing rather than an empty roster.
  final AgentPresetRoster? roster;
}

sealed class SettingsAction {
  const SettingsAction();
}

final class RefreshSettingsAction extends SettingsAction {
  const RefreshSettingsAction();

  @override
  bool operator ==(Object other) => other is RefreshSettingsAction;

  @override
  int get hashCode => 'refresh-settings'.hashCode;
}

final class DismissSettingsError extends SettingsAction {
  const DismissSettingsError();

  @override
  bool operator ==(Object other) => other is DismissSettingsError;

  @override
  int get hashCode => 'dismiss-settings-error'.hashCode;
}

final class SetCredentialAction extends SettingsAction {
  const SetCredentialAction(this.ref, this.value);

  final String ref;
  final String value;

  @override
  bool operator ==(Object other) =>
      other is SetCredentialAction && other.ref == ref && other.value == value;

  @override
  int get hashCode => Object.hash(ref, value);
}

final class UnsetCredentialAction extends SettingsAction {
  const UnsetCredentialAction(this.ref);

  final String ref;

  @override
  bool operator ==(Object other) =>
      other is UnsetCredentialAction && other.ref == ref;

  @override
  int get hashCode => ref.hashCode;
}

final class UpdateSettingAction extends SettingsAction {
  const UpdateSettingAction({
    required this.ns,
    required this.key,
    required this.jsonValue,
    required this.expectedRevision,
  });

  final String ns;
  final String key;
  final String jsonValue;
  final int? expectedRevision;

  @override
  bool operator ==(Object other) =>
      other is UpdateSettingAction &&
      other.ns == ns &&
      other.key == key &&
      other.jsonValue == jsonValue &&
      other.expectedRevision == expectedRevision;

  @override
  int get hashCode => Object.hash(ns, key, jsonValue, expectedRevision);
}

final class ReplaceSettingAction extends SettingsAction {
  const ReplaceSettingAction({
    required this.ns,
    required this.sectionJson,
    required this.expectedRevision,
  });

  final String ns;
  final String sectionJson;
  final int? expectedRevision;

  @override
  bool operator ==(Object other) =>
      other is ReplaceSettingAction &&
      other.ns == ns &&
      other.sectionJson == sectionJson &&
      other.expectedRevision == expectedRevision;

  @override
  int get hashCode => Object.hash(ns, sectionJson, expectedRevision);
}

/// Make one preset the default for sessions created later (web
/// `writeDefaultPreset`): the `agent-presets` settings namespace's
/// `default` field. The controller resolves the CAS revision from the
/// last describe.
final class SelectAgentPresetDefaultAction extends SettingsAction {
  const SelectAgentPresetDefaultAction(this.presetId);

  final String presetId;

  @override
  bool operator ==(Object other) =>
      other is SelectAgentPresetDefaultAction && other.presetId == presetId;

  @override
  int get hashCode => presetId.hashCode;
}
