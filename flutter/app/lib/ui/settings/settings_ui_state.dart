/// Settings screen UI state and intents — port of SettingsUiState.kt.
library;

import 'package:domain/model/settings.dart';

final class SettingsUiState {
  const SettingsUiState({
    this.snapshot,
    this.credentials = const <CredentialStatus>[],
    this.isLoading = false,
    this.errorMessage,
    this.credentialError,
  });

  final SettingsSnapshot? snapshot;
  final List<CredentialStatus> credentials;
  final bool isLoading;
  final String? errorMessage;

  /// Credential describe is enrichment: its failure never blanks the page.
  final String? credentialError;
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
      other is SetCredentialAction &&
      other.ref == ref &&
      other.value == value;

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
