/// WorkspaceScreen widget parity tests — the web WorkspaceBrowser port.
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
  crumbs: [DirectoryEntry(name: 'chance', path: '/home/user', hidden: false)],
  entries: [
    DirectoryEntry(
      name: 'Projects',
      path: '/home/user/Projects',
      hidden: false,
    ),
    DirectoryEntry(name: 'secrets', path: '/home/user/secrets', hidden: true),
  ],
  truncated: false,
);

const _twoWorkspaces = [
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
];

Future<void> _pump(
  WidgetTester tester,
  WorkspaceUiState uiState,
  List<WorkspaceAction> actions,
) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  return tester.pumpWidget(
    material.MaterialApp(
      home: WorkspaceScreen(uiState: uiState, onAction: actions.add),
    ),
  );
}

void main() {
  testWidgets('rows expand to details; new-session + menu verbs dispatch', (
    tester,
  ) async {
    final actions = <WorkspaceAction>[];
    await _pump(
      tester,
      const WorkspaceUiState(workspaces: _twoWorkspaces),
      actions,
    );

    // Section header: the web chrome pair (search + add-workspace).
    expect(find.text('Workspaces'), findsOneWidget);
    expect(find.byTooltip('Search'), findsOneWidget);
    expect(find.byTooltip('Add workspace'), findsOneWidget);
    expect(find.text('one'), findsOneWidget);
    expect(find.text('two'), findsOneWidget);

    // Expanding a row reveals the path and session count (web hover-card).
    await tester.tap(find.text('one'));
    await tester.pump();
    expect(find.text('/tmp/one'), findsOneWidget);
    expect(find.text('2 sessions'), findsOneWidget);

    // The row's + starts a session in that workspace (web rowActions).
    await tester.tap(find.byTooltip('New session in one'));
    await tester.pump();
    expect(actions, contains(const StartSessionInWorkspace('w1')));

    // The ⋮ sheet carries the order verbs; first row cannot move up.
    await tester.tap(find.byTooltip('Workspace actions for one'));
    await tester.pumpAndSettle();
    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Delete workspace'), findsOneWidget);
    expect(find.text('Move up'), findsOneWidget);
    expect(find.text('Move down'), findsOneWidget);

    await tester.tap(find.text('Move down'));
    await tester.pumpAndSettle();
    expect(actions, contains(const MoveWorkspaceDownAction('w1')));
  });

  testWidgets('search capsule filters workspaces client-side', (tester) async {
    await _pump(tester, const WorkspaceUiState(workspaces: _twoWorkspaces), []);

    await tester.tap(find.byTooltip('Search'));
    await tester.pump();
    final field = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'Search workspaces...',
    );
    await tester.enterText(field, 'two');
    await tester.pump();
    expect(find.text('one'), findsNothing);
    // The surviving row (the query echo in the capsule matches too).
    expect(find.text('two'), findsWidgets);
  });

  testWidgets('add-workspace opens the directory browser', (tester) async {
    final actions = <WorkspaceAction>[];
    await _pump(tester, const WorkspaceUiState(), actions);

    await tester.tap(find.byTooltip('Add workspace'));
    await tester.pump();
    expect(actions, contains(const OpenDirectoryBrowser()));
  });

  testWidgets('rename dialog guards duplicates and dispatches', (tester) async {
    final actions = <WorkspaceAction>[];
    await _pump(
      tester,
      const WorkspaceUiState(workspaces: _twoWorkspaces),
      actions,
    );

    await tester.tap(find.byTooltip('Workspace actions for one'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(find.text('Rename workspace'), findsOneWidget);

    // A duplicate title blocks the save with the conflict notice.
    await tester.enterText(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(TextField),
      ),
      'two',
    );
    await tester.pump();
    expect(find.textContaining('already exists'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Rename'))
          .onPressed,
      isNull,
    );

    await tester.enterText(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(TextField),
      ),
      'renamed',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();
    expect(actions, contains(const RenameWorkspaceAction('w1', 'renamed')));
  });

  testWidgets('delete confirmation dispatches with the web copy', (
    tester,
  ) async {
    final actions = <WorkspaceAction>[];
    await _pump(
      tester,
      const WorkspaceUiState(workspaces: _twoWorkspaces),
      actions,
    );

    await tester.tap(find.byTooltip('Workspace actions for one'));
    await tester.pumpAndSettle();
    // The sheet row (menu) and the dialog confirm share the label; the
    // dialog is reached only through the sheet.
    await tester.tap(find.text('Delete workspace').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('appear under Ungrouped'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete workspace'));
    await tester.pumpAndSettle();
    expect(actions, contains(const DeleteWorkspaceAction('w1')));
  });

  testWidgets('directory browser navigates, filters hidden, creates folders', (
    tester,
  ) async {
    final actions = <WorkspaceAction>[];
    await _pump(
      tester,
      const WorkspaceUiState(
        directoryBrowserOpen: true,
        directoryListing: _homeListing,
      ),
      actions,
    );

    // Sheet title and the Home-collapsed crumb trail.
    expect(find.text('Select Workspace Directory'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Projects'), findsOneWidget);
    expect(find.text('secrets'), findsNothing); // hidden by default

    await tester.tap(find.text('Projects'));
    await tester.pump();
    expect(actions, contains(const NavigateDirectory('/home/user/Projects')));

    await tester.tap(find.text('Show hidden files'));
    await tester.pump();
    // Hidden entries carry the dot prefix (web hidden-file display).
    expect(find.text('.secrets'), findsOneWidget);
    await tester.tap(find.text('Show hidden files'));
    await tester.pump();
    expect(find.text('.secrets'), findsNothing);

    // New-folder dialog sanitizes slashes out of the name.
    await tester.tap(find.text('New folder'));
    await tester.pumpAndSettle();
    final folderField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'Untitled folder',
    );
    await tester.enterText(folderField, 'sub/dir');
    await tester.pump();
    expect(tester.widget<TextField>(folderField).controller?.text, 'subdir');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();
    expect(
      actions,
      contains(const CreateDirectoryAction('/home/user', 'subdir')),
    );

    // Open adopts the browsed folder directly as a workspace.
    await tester.tap(find.text('Open'));
    await tester.pump();
    expect(actions, contains(const CreateWorkspaceAction('/home/user')));
    expect(actions, contains(const CloseDirectoryBrowser()));
  });

  testWidgets('browser shows loading and failure placeholders', (tester) async {
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
