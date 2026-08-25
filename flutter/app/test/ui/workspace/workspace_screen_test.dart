/// WorkspaceScreen widget parity tests — the web WorkspaceBrowser port.
library;

import 'package:domain/model/directory.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/ui/theme/theme.dart';
import 'package:app/ui/workspace/workspace_screen.dart';
import 'package:app/ui/workspace/workspace_ui_state.dart';

import '../../l10n_app.dart';

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

const _sessions = <SessionSummary>[
  SessionSummary(
    id: 's1',
    title: 'alpha session',
    blank: false,
    updatedAtEpochMs: 2000,
    cwd: '/tmp/one',
  ),
  SessionSummary(
    id: 's2',
    title: 'beta session',
    blank: false,
    updatedAtEpochMs: 1000,
    cwd: '/tmp/one',
  ),
];

Future<void> _pump(
  WidgetTester tester,
  WorkspaceUiState uiState,
  List<WorkspaceAction> actions, {
  String? selectedSessionId,
  List<String>? openedSessions,
  ThemeData? theme,
}) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  return tester.pumpWidget(
    l10nApp(
      theme: theme,
      home: WorkspaceScreen(
        uiState: uiState,
        onAction: actions.add,
        selectedSessionId: selectedSessionId,
        onSelectSession: openedSessions?.add,
      ),
    ),
  );
}

void main() {
  testWidgets('groups expand to session rows; verbs dispatch', (tester) async {
    final actions = <WorkspaceAction>[];
    await _pump(
      tester,
      const WorkspaceUiState(workspaces: _twoWorkspaces, sessions: _sessions),
      actions,
    );

    // Section header: the web chrome pair (search + add-workspace).
    expect(find.text('Workspaces'), findsOneWidget);
    expect(find.byTooltip('Search'), findsOneWidget);
    expect(find.byTooltip('Add workspace'), findsOneWidget);
    expect(find.text('one'), findsOneWidget);
    expect(find.text('two'), findsOneWidget);

    // Expanding a group reveals its session rows (web session tree).
    await tester.tap(find.text('one'));
    await tester.pump();
    expect(find.text('alpha session'), findsOneWidget);
    expect(find.text('beta session'), findsOneWidget);

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

  testWidgets('search dispatches the session query and renders results', (
    tester,
  ) async {
    final actions = <WorkspaceAction>[];
    await _pump(
      tester,
      const WorkspaceUiState(
        workspaces: _twoWorkspaces,
        sessions: _sessions,
        searchResults: [SessionSearchResult(sessionId: 's2', snippet: 'hit')],
      ),
      actions,
    );

    await tester.tap(find.byTooltip('Search'));
    await tester.pump();
    final field = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'Search workspaces...',
    );
    await tester.enterText(field, 'beta');
    await tester.pump();
    expect(actions, contains(const SearchSessionsAction('beta')));

    // The flat result list replaces the tree: the matched session row
    // carries its workspace context ('one') in the meta line, while the
    // other group header and the unmatched session row are gone.
    expect(find.text('beta session'), findsOneWidget);
    expect(find.text('alpha session'), findsNothing);
    expect(find.text('two'), findsNothing);
    // Clearing the query clears the search and restores the tree.
    await tester.enterText(field, '');
    await tester.pump();
    expect(actions, contains(const SearchSessionsAction('')));
    expect(find.text('one'), findsOneWidget);
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

  testWidgets('long-press a session row opens the verbs sheet and archives', (
    tester,
  ) async {
    final actions = <WorkspaceAction>[];
    await _pump(
      tester,
      const WorkspaceUiState(workspaces: _twoWorkspaces, sessions: _sessions),
      actions,
    );

    // Expand the group to reveal the session rows, then long-press one.
    await tester.tap(find.text('one'));
    await tester.pump();
    await tester.longPress(find.text('alpha session'));
    await tester.pumpAndSettle();
    expect(find.text('Archive session'), findsOneWidget);

    // The long-press verb commits without a dialog (web archive
    // semantics).
    await tester.tap(find.text('Archive session'));
    await tester.pumpAndSettle();
    expect(actions, contains(const ArchiveSessionAction('s1')));
  });

  testWidgets('session rows carry an always-visible verbs seat on the tab', (
    tester,
  ) async {
    final actions = <WorkspaceAction>[];
    await _pump(
      tester,
      const WorkspaceUiState(workspaces: _twoWorkspaces, sessions: _sessions),
      actions,
    );

    // Expand the group to reveal the session rows; each non-blank row
    // carries an always-visible ellipsis seat (the Workspaces touch
    // idiom), which opens the same verbs sheet as the long-press.
    await tester.tap(find.text('one'));
    await tester.pump();
    expect(find.byTooltip('Session actions for alpha session'), findsOneWidget);
    expect(find.byTooltip('Session actions for beta session'), findsOneWidget);

    await tester.tap(find.byTooltip('Session actions for alpha session'));
    await tester.pumpAndSettle();
    expect(find.text('Rename session'), findsOneWidget);
    expect(find.text('Fork session'), findsOneWidget);
    expect(find.text('Archive session'), findsOneWidget);

    await tester.tap(find.text('Archive session'));
    await tester.pumpAndSettle();
    expect(actions, contains(const ArchiveSessionAction('s1')));
  });

  testWidgets('long-press fork dispatches and rename opens the dialog', (
    tester,
  ) async {
    final actions = <WorkspaceAction>[];
    await _pump(
      tester,
      const WorkspaceUiState(workspaces: _twoWorkspaces, sessions: _sessions),
      actions,
    );

    await tester.tap(find.text('one'));
    await tester.pump();
    await tester.longPress(find.text('alpha session'));
    await tester.pumpAndSettle();
    expect(find.text('Fork session'), findsOneWidget);
    expect(find.text('Rename session'), findsOneWidget);

    await tester.tap(find.text('Fork session'));
    await tester.pumpAndSettle();
    expect(actions, contains(const ForkSessionAction('s1')));

    // Rename opens the session dialog; saving dispatches.
    await tester.longPress(find.text('alpha session'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename session'));
    await tester.pumpAndSettle();
    expect(find.text('Rename session'), findsWidgets);
    await tester.enterText(find.byType(TextField).last, 'renamed session');
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();
    expect(
      actions,
      contains(const RenameSessionAction('s1', 'renamed session')),
    );
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

  testWidgets('directory browser scrim rides the theme scrim role', (
    tester,
  ) async {
    final actions = <WorkspaceAction>[];
    // Pump under both brightnesses: a hardcoded color passes one mode and
    // fails the other; the scrim role reads back equal in each.
    for (final theme in [DshTheme.light(), DshTheme.dark()]) {
      await _pump(
        tester,
        const WorkspaceUiState(
          directoryBrowserOpen: true,
          directoryListing: _homeListing,
        ),
        actions,
        theme: theme,
      );
      await tester.pumpAndSettle();

      final scheme = Theme.of(
        tester.element(find.text('Select Workspace Directory')),
      ).colorScheme;
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is ColoredBox &&
              widget.color == scheme.scrim.withValues(alpha: 0.54),
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets('session rows select through and highlight', (tester) async {
    final opened = <String>[];
    await _pump(
      tester,
      const WorkspaceUiState(workspaces: _twoWorkspaces, sessions: _sessions),
      [],
      selectedSessionId: 's1',
      openedSessions: opened,
    );

    // The current session's group is force-expanded (sidebar rule) and
    // its row carries the selected treatment — a re-tap is a no-op.
    expect(find.text('alpha session'), findsOneWidget);
    await tester.tap(find.text('beta session'));
    await tester.pump();
    expect(opened, ['s2']);
    // The selected row does not re-select.
    await tester.tap(find.text('alpha session'));
    await tester.pump();
    expect(opened, ['s2']);
  });

  testWidgets('groups over the limit fold behind the overflow control', (
    tester,
  ) async {
    final many = <SessionSummary>[
      for (var i = 1; i <= 7; i++)
        SessionSummary(
          id: 's$i',
          title: 'session $i',
          blank: false,
          updatedAtEpochMs: 1000 * i,
          cwd: '/tmp/one',
        ),
    ];
    final workspace = WorkspaceSummary(
      workspaceId: 'w1',
      path: '/tmp/one',
      title: 'one',
      sessionIds: [for (var i = 1; i <= 7; i++) 's$i'],
    );
    await _pump(
      tester,
      WorkspaceUiState(workspaces: [workspace], sessions: many),
      [],
      selectedSessionId: 's1',
    );

    // The collapsed limit leaves five rows plus the overflow control.
    expect(find.text('session 7'), findsNothing);
    expect(find.text('Show all 7'), findsOneWidget);
    await tester.tap(find.text('Show all 7'));
    await tester.pump();
    expect(find.text('session 7'), findsOneWidget);
    expect(find.text('Show less'), findsOneWidget);
  });

  testWidgets('sessions outside every workspace trail in Ungrouped', (
    tester,
  ) async {
    final sessions = <SessionSummary>[
      const SessionSummary(
        id: 'loose',
        title: 'loose session',
        blank: false,
        updatedAtEpochMs: 3000,
        cwd: '/elsewhere',
      ),
      ..._sessions,
    ];
    await _pump(
      tester,
      WorkspaceUiState(workspaces: _twoWorkspaces, sessions: sessions),
      [],
      selectedSessionId: 's1',
    );

    expect(find.text('Ungrouped'), findsOneWidget);
    // The ungrouped bucket folds by default; expanding reveals the row.
    expect(find.text('loose session'), findsNothing);
    await tester.tap(find.text('Ungrouped'));
    await tester.pump();
    expect(find.text('loose session'), findsOneWidget);
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
