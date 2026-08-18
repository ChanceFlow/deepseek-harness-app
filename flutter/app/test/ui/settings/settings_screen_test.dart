/// SettingsScreen widget parity tests.
library;

import 'package:domain/model/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/ui/settings/settings_screen.dart';
import 'package:app/ui/settings/settings_ui_state.dart';

const _snapshot = SettingsSnapshot(
  writable: true,
  hasDocument: true,
  namespaces: [
    SettingsNamespace(
      ns: 'llm-deepseek',
      applies: SettingsApplies.live,
      revision: 3,
      hasUserLayer: true,
      secretCount: 1,
    ),
    SettingsNamespace(
      ns: 'shell',
      applies: SettingsApplies.restart,
      revision: 0,
      hasUserLayer: false,
      secretCount: 0,
    ),
  ],
  credentialRefs: ['DEEPSEEK_API_KEY'],
);

const _credentials = [
  CredentialStatus(
    ref: 'DEEPSEEK_API_KEY',
    configured: true,
    source: 'file',
    writable: true,
  ),
];

Future<void> _pump(
  WidgetTester tester,
  SettingsUiState uiState,
  List<SettingsAction> actions,
) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  return tester.pumpWidget(
    MaterialApp(
      home: SettingsScreen(uiState: uiState, onAction: actions.add),
    ),
  );
}

void main() {
  testWidgets('renders snapshot chips, namespaces, credentials',
      (tester) async {
    await _pump(
      tester,
      const SettingsUiState(
        snapshot: _snapshot,
        credentials: _credentials,
      ),
      [],
    );

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('host writable'), findsOneWidget);
    expect(find.text('settings document'), findsOneWidget);
    expect(find.text('llm-deepseek'), findsOneWidget);
    expect(
      find.text(
          'applies: live · revision: 3 · user layer · 1 secrets set'),
      findsOneWidget,
    );
    expect(find.text('shell'), findsOneWidget);
    expect(
      find.text('applies: restart · revision: 0'),
      findsOneWidget,
    );
    expect(find.text('Credentials'), findsOneWidget);
    expect(find.text('DEEPSEEK_API_KEY'), findsOneWidget);
    expect(
      find.text('configured · source: file · writable'),
      findsOneWidget,
    );
    expect(find.text('Replace'), findsOneWidget);
    expect(find.text('Unset'), findsOneWidget);
  });

  testWidgets('error shows the loopback hint', (tester) async {
    await _pump(
      tester,
      const SettingsUiState(errorMessage: 'describe failed'),
      [],
    );
    expect(find.text('describe failed'), findsOneWidget);
    expect(
      find.textContaining('loopback-only'),
      findsOneWidget,
    );
  });

  testWidgets('key patch dialog dispatches UpdateSettingAction',
      (tester) async {
    final actions = <SettingsAction>[];
    await _pump(
      tester,
      const SettingsUiState(snapshot: _snapshot),
      actions,
    );

    await tester.tap(find.text('Edit key').first);
    await tester.pumpAndSettle();

    expect(find.text('Patch llm-deepseek'), findsOneWidget);
    expect(find.text('✓ Key patch'), findsOneWidget);
    expect(find.textContaining('CAS revision 3'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Top-level key'),
      'model',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'JSON value'),
      '"glm-x"',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(
      actions,
      contains(const UpdateSettingAction(
        ns: 'llm-deepseek',
        key: 'model',
        jsonValue: '"glm-x"',
        expectedRevision: 3,
      )),
    );
  });

  testWidgets('replace-section mode dispatches ReplaceSettingAction',
      (tester) async {
    final actions = <SettingsAction>[];
    await _pump(
      tester,
      const SettingsUiState(snapshot: _snapshot),
      actions,
    );

    await tester.tap(find.text('Edit key').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replace section'));
    await tester.pump();
    expect(find.text('✓ Replace section'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(
        TextField,
        'Whole user-layer JSON object',
      ),
      '{ "model": "glm-x" }',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(
      actions,
      contains(const ReplaceSettingAction(
        ns: 'llm-deepseek',
        sectionJson: '{ "model": "glm-x" }',
        expectedRevision: 3,
      )),
    );
  });

  testWidgets('credential set/unset dispatch', (tester) async {
    final actions = <SettingsAction>[];
    await _pump(
      tester,
      const SettingsUiState(
        snapshot: _snapshot,
        credentials: _credentials,
      ),
      actions,
    );

    await tester.tap(find.text('Unset'));
    await tester.pump();
    expect(
        actions, contains(const UnsetCredentialAction('DEEPSEEK_API_KEY')));

    actions.clear();
    await tester.tap(find.text('Replace'));
    await tester.pumpAndSettle();
    expect(find.text('Store DEEPSEEK_API_KEY'), findsOneWidget);

    final secretField = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'secret value',
    );
    await tester.enterText(secretField, 'sk-test');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(
      actions,
      contains(
          const SetCredentialAction('DEEPSEEK_API_KEY', 'sk-test')),
    );
  });

  testWidgets('read-only snapshot hides edit affordances',
      (tester) async {
    await _pump(
      tester,
      const SettingsUiState(
        snapshot: SettingsSnapshot(
          writable: false,
          hasDocument: false,
          namespaces: [
            SettingsNamespace(
              ns: 'shell',
              applies: SettingsApplies.restart,
              revision: 0,
              hasUserLayer: false,
              secretCount: 0,
            ),
          ],
          credentialRefs: [],
        ),
      ),
      [],
    );

    expect(find.text('host read-only'), findsOneWidget);
    expect(find.text('no settings document'), findsOneWidget);
    expect(find.text('Edit key'), findsNothing);
    expect(find.text('Credentials'), findsNothing);
  });
}
