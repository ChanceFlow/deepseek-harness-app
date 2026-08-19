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
  testWidgets('renders general facts, namespace cards, credential rows', (
    tester,
  ) async {
    await _pump(
      tester,
      const SettingsUiState(snapshot: _snapshot, credentials: _credentials),
      [],
    );

    // Web panel header + the circular refresh action.
    expect(find.text('Settings'), findsOneWidget);
    expect(find.byTooltip('Refresh'), findsOneWidget);

    // General section (web GeneralSection rows).
    expect(find.text('Host writes'), findsOneWidget);
    expect(find.text('Writable'), findsOneWidget);
    expect(find.text('Settings document'), findsOneWidget);
    expect(find.text('Present'), findsOneWidget);

    // Namespace disclosure cards carry the host meta line.
    expect(find.text('llm-deepseek'), findsOneWidget);
    expect(
      find.text('applies: live · revision: 3 · user layer · 1 secrets set'),
      findsOneWidget,
    );
    expect(find.text('shell'), findsOneWidget);
    expect(find.text('applies: restart · revision: 0'), findsOneWidget);

    // Credentials section with the state badge (web SecretField).
    expect(find.text('Credentials'), findsOneWidget);
    expect(find.text('DEEPSEEK_API_KEY'), findsOneWidget);
    expect(find.text('configured · source: file · writable'), findsOneWidget);
    expect(find.text('Configured'), findsOneWidget);
  });

  testWidgets('error shows the loopback hint and dismisses', (tester) async {
    final actions = <SettingsAction>[];
    await _pump(
      tester,
      const SettingsUiState(errorMessage: 'describe failed'),
      actions,
    );
    expect(find.text('describe failed'), findsOneWidget);
    expect(find.textContaining('loopback-only'), findsOneWidget);

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    expect(actions, contains(const DismissSettingsError()));
  });

  testWidgets('key patch form dispatches UpdateSettingAction', (tester) async {
    final actions = <SettingsAction>[];
    await _pump(tester, const SettingsUiState(snapshot: _snapshot), actions);

    // Expanding the namespace card reveals the staged patch form.
    await tester.tap(find.text('llm-deepseek'));
    await tester.pumpAndSettle();

    expect(find.text('Patch key'), findsOneWidget);
    expect(find.text('Replace section'), findsOneWidget);
    expect(find.textContaining('CAS revision 3'), findsOneWidget);

    final keyField = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == null,
    );
    final valueField = find.byWidgetPredicate(
      (w) =>
          w is TextField &&
          w.decoration?.hintText == 'true / 42 / "text" / {…}',
    );
    await tester.enterText(keyField, 'model');
    await tester.enterText(valueField, '"glm-x"');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(
      actions,
      contains(
        const UpdateSettingAction(
          ns: 'llm-deepseek',
          key: 'model',
          jsonValue: '"glm-x"',
          expectedRevision: 3,
        ),
      ),
    );
  });

  testWidgets('replace-section mode dispatches ReplaceSettingAction', (
    tester,
  ) async {
    final actions = <SettingsAction>[];
    await _pump(tester, const SettingsUiState(snapshot: _snapshot), actions);

    await tester.tap(find.text('llm-deepseek'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replace section'));
    await tester.pump();
    expect(find.text('Patch key'), findsOneWidget);

    final replaceField = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == '{ "key": value }',
    );
    await tester.enterText(replaceField, '{ "model": "glm-x" }');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(
      actions,
      contains(
        const ReplaceSettingAction(
          ns: 'llm-deepseek',
          sectionJson: '{ "model": "glm-x" }',
          expectedRevision: 3,
        ),
      ),
    );
  });

  testWidgets('credential sheet set/unset dispatch', (tester) async {
    final actions = <SettingsAction>[];
    await _pump(
      tester,
      const SettingsUiState(snapshot: _snapshot, credentials: _credentials),
      actions,
    );

    // Tapping the credential row opens the editor sheet.
    await tester.tap(find.text('DEEPSEEK_API_KEY'));
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
      contains(const SetCredentialAction('DEEPSEEK_API_KEY', 'sk-test')),
    );

    // The destructive unset rides the same sheet footer.
    actions.clear();
    await tester.tap(find.text('DEEPSEEK_API_KEY'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unset'));
    await tester.pump();
    expect(actions, contains(const UnsetCredentialAction('DEEPSEEK_API_KEY')));
  });

  testWidgets('read-only snapshot hides edit affordances', (tester) async {
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

    expect(find.text('Read-only'), findsOneWidget);
    expect(find.text('None'), findsOneWidget);
    // Expanding a read-only card shows the notice, not the patch form.
    await tester.tap(find.text('shell'));
    await tester.pumpAndSettle();
    expect(find.text('Patch key'), findsNothing);
    expect(find.textContaining('read-only'), findsOneWidget);
    expect(find.text('Credentials'), findsNothing);
  });
}
