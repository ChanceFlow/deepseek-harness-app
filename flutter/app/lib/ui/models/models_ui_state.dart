/// Models screen UI state and intents — port of ModelsUiState.kt.
library;

import 'package:domain/model/model_catalog.dart';
import 'package:domain/model/session.dart';

final class ModelsUiState {
  const ModelsUiState({
    this.sessions = const <SessionSummary>[],
    this.selectedSessionId,
    this.models,
    this.selected,
    this.isLoading = false,
    this.errorMessage,
  });

  final List<SessionSummary> sessions;
  final String? selectedSessionId;
  final SessionModels? models;
  final ModelSelection? selected;
  final bool isLoading;
  final String? errorMessage;
}

sealed class ModelsAction {
  const ModelsAction();
}

final class SelectModelsSession extends ModelsAction {
  const SelectModelsSession(this.sessionId);

  final String sessionId;

  @override
  bool operator ==(Object other) =>
      other is SelectModelsSession && other.sessionId == sessionId;

  @override
  int get hashCode => sessionId.hashCode;
}

final class SelectModelAction extends ModelsAction {
  const SelectModelAction(this.provider, this.model, [this.reasoningEffort]);

  final String provider;
  final String model;
  final String? reasoningEffort;

  @override
  bool operator ==(Object other) =>
      other is SelectModelAction &&
      other.provider == provider &&
      other.model == model &&
      other.reasoningEffort == reasoningEffort;

  @override
  int get hashCode => Object.hash(provider, model, reasoningEffort);
}

final class RefreshModelsAction extends ModelsAction {
  const RefreshModelsAction();

  @override
  bool operator ==(Object other) => other is RefreshModelsAction;

  @override
  int get hashCode => 'refresh-models'.hashCode;
}

final class DismissModelsError extends ModelsAction {
  const DismissModelsError();

  @override
  bool operator ==(Object other) => other is DismissModelsError;

  @override
  int get hashCode => 'dismiss-models-error'.hashCode;
}
