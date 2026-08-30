/// Model-seat sheet behavior: picking a model from the directory submits
/// that model with the remembered effort for its route when one exists,
/// and with the model's default effort otherwise (web `selectionOf`
/// parity, with the client's remembered effort standing in for the
/// same-route current).
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:app/ui/chat/chat_local_state.dart';
import 'package:app/ui/chat/model_select.dart';
import 'package:domain/model/model_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';

const SessionModels directory = SessionModels(
  current: ModelSelection(provider: 'p', model: 'base'),
  routable: true,
  groups: <ModelProviderGroup>[
    ModelProviderGroup(
      id: 'p',
      name: 'Provider',
      models: <ModelCatalogModel>[
        ModelCatalogModel(
          id: 'base',
          name: 'Base',
          reasoning: ModelReasoning(
            defaultEffort: 'low',
            efforts: <ModelReasoningEffort>[
              ModelReasoningEffort(id: 'low', name: 'Low'),
              ModelReasoningEffort(id: 'high', name: 'High'),
            ],
          ),
        ),
        ModelCatalogModel(
          id: 'fresh',
          name: 'Fresh',
          reasoning: ModelReasoning(
            defaultEffort: 'low',
            efforts: <ModelReasoningEffort>[
              ModelReasoningEffort(id: 'low', name: 'Low'),
              ModelReasoningEffort(id: 'high', name: 'High'),
            ],
          ),
        ),
      ],
    ),
  ],
);

Future<ModelSelection> _pickModel(
  WidgetTester tester,
  ModelSeatPreferences? prefs,
) async {
  final selections = <ModelSelection>[];
  await tester.pumpWidget(
    l10nApp(
      home: Scaffold(
        body: ModelSelect(
          models: directory,
          locked: false,
          onSelect: selections.add,
          onRefresh: () {},
          modelPrefs: prefs,
        ),
      ),
    ),
  );
  await tester.tap(find.byType(IconButton));
  await tester.pumpAndSettle();
  // Root pane: open the model list.
  await tester.tap(find.text('Model').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Base'));
  await tester.pumpAndSettle();
  return selections.single;
}

void main() {
  testWidgets('a remembered effort prefills the model pick', (tester) async {
    final selection = await _pickModel(
      tester,
      const ModelSeatPreferences(
        effortByRoute: <String, String>{'p/base': 'high'},
      ),
    );
    expect(selection.provider, 'p');
    expect(selection.model, 'base');
    expect(selection.reasoningEffort, 'high');
  });

  testWidgets('a route without a remembered effort uses the default', (
    tester,
  ) async {
    final selection = await _pickModel(
      tester,
      const ModelSeatPreferences(effortByRoute: <String, String>{}),
    );
    expect(selection.model, 'base');
    expect(selection.reasoningEffort, 'low');
  });

  testWidgets('no preference store at all uses the default', (tester) async {
    final selection = await _pickModel(tester, null);
    expect(selection.reasoningEffort, 'low');
  });

  testWidgets('a remembered effort for another route does not leak', (
    tester,
  ) async {
    await tester.pumpWidget(
      l10nApp(
        home: Scaffold(
          body: ModelSelect(
            models: directory,
            locked: false,
            onSelect: (_) {},
            onRefresh: () {},
            modelPrefs: const ModelSeatPreferences(
              effortByRoute: <String, String>{'other/fresh': 'high'},
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Model').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fresh'));
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    // The effort row shows the catalog default, not the other route's
    // remembered effort.
    expect(find.text(l10n.providerDefault), findsNothing);
  });

  testWidgets('effort pane lists efforts and selects one', (tester) async {
    final selections = <ModelSelection>[];
    await tester.pumpWidget(
      l10nApp(
        home: Scaffold(
          body: ModelSelect(
            models: directory,
            locked: false,
            onSelect: selections.add,
            onRefresh: () {},
          ),
        ),
      ),
    );
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    // Root pane: tap effort row
    await tester.tap(find.text('Effort'));
    await tester.pumpAndSettle();
    expect(find.text('Low'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);

    await tester.tap(find.text('High'));
    await tester.pumpAndSettle();
    expect(selections.single.reasoningEffort, 'high');
  });

  testWidgets('sheet panes navigate back to root pane', (tester) async {
    await tester.pumpWidget(
      l10nApp(
        home: Scaffold(
          body: ModelSelect(
            models: directory,
            locked: false,
            onSelect: (_) {},
            onRefresh: () {},
          ),
        ),
      ),
    );
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    // Navigate to model pane
    await tester.tap(find.text('Model').last);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);

    // Tap header back
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    // Back at root pane
    expect(find.text('Effort'), findsOneWidget);
  });
}
