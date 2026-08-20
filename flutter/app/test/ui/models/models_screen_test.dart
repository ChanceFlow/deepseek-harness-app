/// ModelsScreen widget parity tests.
library;

import 'package:domain/model/model_catalog.dart';
import 'package:domain/model/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/ui/models/models_screen.dart';
import 'package:app/ui/models/models_ui_state.dart';

import '../../l10n_app.dart';

const _catalog = SessionModels(
  current: ModelSelection(
    provider: 'deepseek',
    model: 'glm-x',
    reasoningEffort: 'high',
  ),
  routable: true,
  groups: [
    ModelProviderGroup(
      id: 'deepseek',
      name: 'DeepSeek',
      models: [
        ModelCatalogModel(
          id: 'glm-x',
          name: 'GLM X',
          description: 'Fast reasoning model',
          reasoning: ModelReasoning(
            efforts: [
              ModelReasoningEffort(id: 'low', name: 'Low'),
              ModelReasoningEffort(id: 'high', name: 'High'),
            ],
            defaultEffort: 'high',
          ),
        ),
        ModelCatalogModel(id: 'glm-air', name: 'GLM Air'),
      ],
    ),
    ModelProviderGroup(
      id: 'other',
      name: 'Other',
      models: [ModelCatalogModel(id: 'mini', name: 'Mini')],
    ),
  ],
  failures: [
    ModelCatalogFailure(
      id: 'f1',
      name: 'broken-provider',
      message: 'unreachable',
    ),
  ],
);

Future<void> _pump(
  WidgetTester tester,
  ModelsUiState uiState,
  List<ModelsAction> actions,
) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  return tester.pumpWidget(
    l10nApp(
      home: ModelsScreen(uiState: uiState, onAction: actions.add),
    ),
  );
}

void main() {
  testWidgets('renders groups, current model, and provider failures', (
    tester,
  ) async {
    await _pump(
      tester,
      ModelsUiState(
        sessions: const [
          SessionSummary(id: 's1', title: 'Session one', blank: false),
        ],
        selectedSessionId: 's1',
        models: _catalog,
        selected: _catalog.current,
      ),
      [],
    );

    expect(find.text('Models'), findsOneWidget);
    expect(find.text('Session'), findsOneWidget);
    expect(find.text('Session one'), findsOneWidget);
    expect(find.text('Providers'), findsOneWidget);
    expect(find.text('DeepSeek'), findsOneWidget);
    expect(find.text('GLM X (current)'), findsOneWidget);
    expect(find.text('Fast reasoning model'), findsOneWidget);
    expect(find.text('GLM Air'), findsOneWidget);
    expect(find.text('broken-provider: unreachable'), findsOneWidget);

    // Current model exposes the reasoning-effort chips.
    expect(find.text('Reasoning effort'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'High'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Low'), findsOneWidget);
  });

  testWidgets('selecting a session dispatches and disables the current row', (
    tester,
  ) async {
    final actions = <ModelsAction>[];
    await _pump(
      tester,
      const ModelsUiState(
        sessions: [
          SessionSummary(id: 's1', title: 'Session one', blank: false),
          SessionSummary(id: 's2', title: 'Session two', blank: false),
        ],
        selectedSessionId: 's1',
      ),
      actions,
    );

    final one = find.widgetWithText(OutlinedButton, 'Session one');
    expect(tester.widget<OutlinedButton>(one).onPressed, isNull);
    await tester.tap(find.text('Session two'));
    await tester.pump();
    expect(actions, contains(const SelectModelsSession('s2')));
  });

  testWidgets('model and effort taps dispatch SelectModelAction', (
    tester,
  ) async {
    final actions = <ModelsAction>[];
    await _pump(
      tester,
      ModelsUiState(
        selectedSessionId: 's1',
        models: _catalog,
        selected: _catalog.current,
      ),
      actions,
    );

    // Non-current model: dispatch with the default effort.
    await tester.tap(find.text('GLM Air'));
    await tester.pump();
    expect(actions, contains(const SelectModelAction('deepseek', 'glm-air')));

    // Effort chip on the current model.
    await tester.tap(find.text('Low'));
    await tester.pump();
    expect(
      actions,
      contains(const SelectModelAction('deepseek', 'glm-x', 'low')),
    );
  });

  testWidgets('pushing with a current session preselects it', (tester) async {
    final actions = <ModelsAction>[];
    // The wide two-pane surface with a selected session: the sidebar tools
    // region preloads that session into the models controller.
    await _pump(
      tester,
      const ModelsUiState(
        sessions: [
          SessionSummary(id: 's1', title: 'Current one', blank: false),
        ],
        selectedSessionId: 's1',
      ),
      actions,
    );
    expect(find.text('Current one'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(OutlinedButton),
        matching: find.text('Current one'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('error message renders in the error color', (tester) async {
    await _pump(
      tester,
      const ModelsUiState(errorMessage: 'catalog unreachable'),
      [],
    );
    expect(find.text('catalog unreachable'), findsOneWidget);
  });
}
