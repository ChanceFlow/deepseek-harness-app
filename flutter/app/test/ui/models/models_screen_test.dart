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
  List<ModelsAction> actions, {
  Size physicalSize = const Size(800, 1600),
  double devicePixelRatio = 1.0,
}) {
  tester.view.physicalSize = physicalSize;
  tester.view.devicePixelRatio = devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  return tester.pumpWidget(
    l10nApp(
      home: ModelsScreen(uiState: uiState, onAction: actions.add),
    ),
  );
}

/// A catalog with more rows than any phone or tablet viewport shows:
/// five groups of six models.
const _longCatalog = SessionModels(
  current: ModelSelection(provider: 'p0', model: 'm0-0'),
  routable: true,
  groups: [
    ModelProviderGroup(
      id: 'p0',
      name: 'Provider Zero',
      models: [
        ModelCatalogModel(id: 'm0-0', name: 'Model 0-0'),
        ModelCatalogModel(id: 'm0-1', name: 'Model 0-1'),
        ModelCatalogModel(id: 'm0-2', name: 'Model 0-2'),
        ModelCatalogModel(id: 'm0-3', name: 'Model 0-3'),
        ModelCatalogModel(id: 'm0-4', name: 'Model 0-4'),
        ModelCatalogModel(id: 'm0-5', name: 'Model 0-5'),
      ],
    ),
    ModelProviderGroup(
      id: 'p1',
      name: 'Provider One',
      models: [
        ModelCatalogModel(id: 'm1-0', name: 'Model 1-0'),
        ModelCatalogModel(id: 'm1-1', name: 'Model 1-1'),
        ModelCatalogModel(id: 'm1-2', name: 'Model 1-2'),
        ModelCatalogModel(id: 'm1-3', name: 'Model 1-3'),
        ModelCatalogModel(id: 'm1-4', name: 'Model 1-4'),
        ModelCatalogModel(id: 'm1-5', name: 'Model 1-5'),
      ],
    ),
    ModelProviderGroup(
      id: 'p2',
      name: 'Provider Two',
      models: [
        ModelCatalogModel(id: 'm2-0', name: 'Model 2-0'),
        ModelCatalogModel(id: 'm2-1', name: 'Model 2-1'),
        ModelCatalogModel(id: 'm2-2', name: 'Model 2-2'),
        ModelCatalogModel(id: 'm2-3', name: 'Model 2-3'),
        ModelCatalogModel(id: 'm2-4', name: 'Model 2-4'),
        ModelCatalogModel(id: 'm2-5', name: 'Model 2-5'),
      ],
    ),
    ModelProviderGroup(
      id: 'p3',
      name: 'Provider Three',
      models: [
        ModelCatalogModel(id: 'm3-0', name: 'Model 3-0'),
        ModelCatalogModel(id: 'm3-1', name: 'Model 3-1'),
        ModelCatalogModel(id: 'm3-2', name: 'Model 3-2'),
        ModelCatalogModel(id: 'm3-3', name: 'Model 3-3'),
        ModelCatalogModel(id: 'm3-4', name: 'Model 3-4'),
        ModelCatalogModel(id: 'm3-5', name: 'Model 3-5'),
      ],
    ),
    ModelProviderGroup(
      id: 'p4',
      name: 'Provider Four',
      models: [
        ModelCatalogModel(id: 'm4-0', name: 'Model 4-0'),
        ModelCatalogModel(id: 'm4-1', name: 'Model 4-1'),
        ModelCatalogModel(id: 'm4-2', name: 'Model 4-2'),
        ModelCatalogModel(id: 'm4-3', name: 'Model 4-3'),
        ModelCatalogModel(id: 'm4-4', name: 'Model 4-4'),
        ModelCatalogModel(id: 'm4-5', name: 'Model 4-5'),
      ],
    ),
  ],
  failures: [],
);

const _phoneUiState = ModelsUiState(
  sessions: [
    SessionSummary(id: 's0', title: 'Session zero', blank: false),
    SessionSummary(id: 's1', title: 'Session one', blank: false),
  ],
  selectedSessionId: 's0',
  models: _longCatalog,
);

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

  testWidgets('the page is one scrolling viewport at phone size', (
    tester,
  ) async {
    // 360x844dp — the reported device: 720x1688 physical at dpr 2.
    await _pump(
      tester,
      _phoneUiState,
      [],
      physicalSize: const Size(720, 1688),
      devicePixelRatio: 2.0,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // A single scroll view owns the page: the old two-pane split gave the
    // Scaffold's one primary scroll controller to two sibling ListViews
    // ('ScrollController attached to multiple scroll views').
    expect(find.byType(ListView), findsOneWidget);
    expect(
      tester.widget<Scrollable>(find.byType(Scrollable)).controller!.positions,
      hasLength(1),
    );

    // The tail of the catalog starts offscreen. The first swipe begins on
    // the session picker — the region that used to be a pinned, dead third
    // of the screen — and already scrolls the page.
    expect(find.text('Model 4-5'), findsNothing);
    await tester.drag(find.text('Session zero'), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Scrollable>(find.byType(Scrollable)).controller!.offset,
      greaterThan(0),
    );

    // More page drags bring the tail into view.
    await tester.dragUntilVisible(
      find.text('Model 4-5'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    expect(find.text('Model 4-5'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the page scrolls at tablet size without overflow', (
    tester,
  ) async {
    // 800x1280dp tablet portrait.
    await _pump(
      tester,
      _phoneUiState,
      [],
      physicalSize: const Size(1600, 2560),
      devicePixelRatio: 2.0,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(ListView), findsOneWidget);

    expect(find.text('Model 4-5'), findsNothing);
    await tester.dragUntilVisible(
      find.text('Model 4-5'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    expect(find.text('Model 4-5'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('taps still dispatch after the page is scrolled', (tester) async {
    final actions = <ModelsAction>[];
    await _pump(
      tester,
      _phoneUiState,
      actions,
      physicalSize: const Size(720, 1688),
      devicePixelRatio: 2.0,
    );
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('Model 1-3'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.tap(find.text('Model 1-3'));
    await tester.pump();
    expect(actions, contains(const SelectModelAction('p1', 'm1-3')));
  });
}
