/// WorkspaceScreen widget parity tests.
library;

import 'package:domain/model/directory.dart';
import 'package:domain/model/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';

import 'package:app/ui/workspace/workspace_screen.dart';
import 'package:app/ui/workspace/workspace_ui_state.dart';

const _homeListing = DirectoryListing(
  path: '/home/user',
  home: '/home/user',
  crumbs: <DirectoryEntry>[],
  entries: [
    DirectoryEntry(name: 'Projects', path: '/home/user/Projects', hidden: false),
    DirectoryEntry(name: 'secrets', path: '/home/user/secrets', hidden: true),
  ],
  truncated: false,
);

Finder _hintField(String hint) {
  return find.byWidgetPredicate(
    (widget) =>
        widget is TextField && widget.decoration?.hintText == hint,
  );
}

Finder _labeledField(String label) {
  return find.byWidgetPredicate(
    (widget) =>
        widget is TextField && widget.decoration?.labelText == label,
  );
}

Future<void> _pump(
  WidgetTester tester,
  WorkspaceUiState uiState,
  List<WorkspaceAction> actions,
) {
  return tester.pumpWidget(
    material.MaterialApp(
      home: WorkspaceScreen(uiState: uiState, onAction: actions.add),
    ),
  );
}

void main() {
  testWidgets('renders workspace rows with order-aware Up/Down',
      (tester) async {
    final actions = <WorkspaceAction>[];
    await _pump(
      tester,
      const WorkspaceUiState(
        workspaces: [
          WorkspaceSummary(
            workspaceId: 'w1',
            path: '/tmp/one',
            title: 'one',
            sessionIds: ['s1', 's2'],
          ),
          WorkspaceSummary(
            workspaceId: 'w2',
            path: '/tmp/two',
            title: 'two',
            sessionIds: [],
          ),
        ],
      ),
      actions,
    );

    expect(find.text('Workspaces'), findsOneWidget);
    expect(find.text('one'), findsOneWidget);
    expect(find.text('/tmp/one'), findsOneWidget);
    expect(find.text('sessions: 2'), findsOneWidget);
    expect(find.text('sessions: 0'), findsOneWidget);

    // First row's Up and last row's Down are disabled.
    final ups = find.widgetWithText(OutlinedButton, 'Up');
    expect(
        tester.widget<OutlinedButton>(ups.at(0)).onPressed, isNull);
    expect(
        tester.widget<OutlinedButton>(ups.at(1)).onPressed, isNotNull);
    final downs = find.widgetWithText(OutlinedButton, 'Down');
    expect(
        tester.widget<OutlinedButton>(downs.at(0)).onPressed, isNotNull);
    expect(
        tester.widget<OutlinedButton>(downs.at(1)).onPressed, isNull);

    await tester.tap(downs.at(0));
    await tester.pump();
    expect(actions, contains(const MoveWorkspaceDownAction('w1')));
  });

  testWidgets('create dispatches trimmed path and clears the field',
      (tester) async {
    final actions = <WorkspaceAction>[];
    await _pump(tester, const WorkspaceUiState(), actions);

    final pathField = _labeledField('Existing directory path');
    expect(find.widgetWithText(FilledButton, 'Create').first, findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Create').first)
          .onPressed,
      isNull,
    );

    await tester.enterText(pathField, '/tmp/new-ws');
    await tester.pump();
    await tester.tap(find.text('Create'));
    await tester.pump();
    expect(actions, contains(const CreateWorkspaceAction('/tmp/new-ws')));
    expect(tester.widget<TextField>(pathField).controller?.text, '');
  });

  testWidgets('delete and rename dispatch workspace actions',
      (tester) async {
    final actions = <WorkspaceAction>[];
    await _pump(
      tester,
      const WorkspaceUiState(
        workspaces: [
          WorkspaceSummary(
            workspaceId: 'w1',
            path: '/tmp/one',
            title: 'one',
            sessionIds: [],
          ),
        ],
      ),
      actions,
    );

    await tester.tap(find.text('Delete workspace'));
    await tester.pump();
    expect(actions, contains(const DeleteWorkspaceAction('w1')));

    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(find.text('Rename workspace'), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(TextField),
      ),
      'renamed',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(
        actions, contains(const RenameWorkspaceAction('w1', 'renamed')));
  });

  testWidgets('directory browser navigates, filters hidden, creates folders',
      (tester) async {
    final actions = <WorkspaceAction>[];
    await _pump(
      tester,
      const WorkspaceUiState(
        directoryBrowserOpen: true,
        directoryListing: _homeListing,
      ),
      actions,
    );

    expect(find.text('Choose directory'), findsOneWidget);
    expect(find.text('/home/user'), findsOneWidget);
    expect(find.text('Projects'), findsOneWidget);
    expect(find.text('.secrets'), findsNothing); // hidden by default

    await tester.tap(find.text('Projects'));
    await tester.pump();
    expect(
        actions, contains(const NavigateDirectory('/home/user/Projects')));

    await tester.tap(find.text('Show hidden'));
    await tester.pump();
    expect(find.text('.secrets'), findsOneWidget);
    await tester.tap(find.text('Hide hidden'));
    await tester.pump();
    expect(find.text('.secrets'), findsNothing);

    final folderField = _hintField('New folder name');
    await tester.enterText(folderField, 'sub/dir');
    await tester.pump();
    // Slashes are stripped from folder names.
    expect(tester.widget<TextField>(folderField).controller?.text, 'subdir');
    await tester.tap(find.text('Create folder'));
    await tester.pump();
    expect(
      actions,
      contains(const CreateDirectoryAction('/home/user', 'subdir')),
    );

    await tester.tap(find.text('Use this folder'));
    await tester.pump();
    expect(actions, contains(const CloseDirectoryBrowser()));
    expect(
      tester.widget<TextField>(_labeledField('Existing directory path'))
          .controller
          ?.text,
      '/home/user',
    );
  });

  testWidgets('browser shows loading and failure placeholders',
      (tester) async {
    final actions = <WorkspaceAction>[];
    await _pump(
      tester,
      const WorkspaceUiState(
        directoryBrowserOpen: true,
        directoryLoading: true,
      ),
      actions,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await _pump(
      tester,
      const WorkspaceUiState(directoryBrowserOpen: true),
      actions,
    );
    expect(find.text('Unable to load directory'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(actions, contains(const CloseDirectoryBrowser()));
  });
}
