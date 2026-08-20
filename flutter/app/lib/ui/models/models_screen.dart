/// Models screen — Flutter port of the legacy ModelsRoute.kt.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/model_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import 'models_ui_state.dart';

class ModelsRoute extends ConsumerWidget {
  const ModelsRoute({super.key, this.backendId});

  /// The backend this surface presents; null uses the active backend.
  final String? backendId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolved =
        backendId ?? ref.watch(activeBackendIdProvider).value ?? '';
    if (resolved.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final controller = ref.watch(modelsControllerProvider(resolved));
    return StreamBuilder<ModelsUiState>(
      stream: controller.uiState,
      initialData: controller.state,
      builder: (context, snapshot) {
        final uiState = snapshot.data ?? const ModelsUiState();
        return ModelsScreen(uiState: uiState, onAction: controller.onAction);
      },
    );
  }
}

class ModelsScreen extends StatelessWidget {
  const ModelsScreen({
    super.key,
    required this.uiState,
    required this.onAction,
  });

  final ModelsUiState uiState;
  final void Function(ModelsAction) onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.modelsTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (uiState.errorMessage case final error?)
                Text(error, style: TextStyle(color: theme.colorScheme.error)),
              Text(l10n.sessionLabel, style: theme.textTheme.labelLarge),
              Expanded(
                flex: 35,
                child: ListView(
                  children: [
                    for (final session in uiState.sessions)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: session.id == uiState.selectedSessionId
                              ? null
                              : () => onAction(SelectModelsSession(session.id)),
                          child: Text(session.displayTitle),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(l10n.providersLabel, style: theme.textTheme.labelLarge),
              Expanded(
                flex: 65,
                child: ListView(
                  children: [
                    for (final group
                        in uiState.models?.groups ??
                            const <ModelProviderGroup>[]) ...[
                      Text(group.name, style: theme.textTheme.titleSmall),
                      for (final model in group.models)
                        _ModelRow(
                          group: group,
                          model: model,
                          selected: uiState.selected,
                          onAction: onAction,
                        ),
                    ],
                    for (final failure
                        in uiState.models?.failures ??
                            const <ModelCatalogFailure>[])
                      Text(
                        '${failure.name}: ${failure.message}',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({
    required this.group,
    required this.model,
    required this.selected,
    required this.onAction,
  });

  final ModelProviderGroup group;
  final ModelCatalogModel model;
  final ModelSelection? selected;
  final void Function(ModelsAction) onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final isCurrent =
        selected?.provider == group.id && selected?.model == model.id;
    final defaultEffort = model.reasoning?.defaultEffort;
    final selectedEffort = isCurrent
        ? selected?.reasoningEffort ?? defaultEffort
        : defaultEffort;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isCurrent)
          FilledButton(
            onPressed: () =>
                onAction(SelectModelAction(group.id, model.id, selectedEffort)),
            child: Text(l10n.modelCurrent(model.name)),
          )
        else
          OutlinedButton(
            onPressed: () =>
                onAction(SelectModelAction(group.id, model.id, selectedEffort)),
            child: Text(model.name),
          ),
        if (model.description case final String description?)
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 2),
            child: Text(description, style: theme.textTheme.bodySmall),
          ),
        if (isCurrent &&
            (model.reasoning?.efforts ?? const <ModelReasoningEffort>[])
                .isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.reasoningEffortLabel, style: theme.textTheme.labelMedium),
                for (final effort in model.reasoning!.efforts)
                  _effortChip(
                    context,
                    effort: effort,
                    selectedEffortId: selected?.reasoningEffort,
                    defaultEffort: defaultEffort,
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _effortChip(
    BuildContext context, {
    required ModelReasoningEffort effort,
    required String? selectedEffortId,
    required String? defaultEffort,
  }) {
    final effortSelected =
        selectedEffortId == effort.id ||
        (selectedEffortId == null && defaultEffort == effort.id);
    return effortSelected
        ? FilledButton(
            onPressed: () =>
                onAction(SelectModelAction(group.id, model.id, effort.id)),
            child: Text(effort.name),
          )
        : OutlinedButton(
            onPressed: () =>
                onAction(SelectModelAction(group.id, model.id, effort.id)),
            child: Text(effort.name),
          );
  }
}
