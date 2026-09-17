/// The Workspaces tab's directory browser is a page-modal: its sheet docks
/// at the screen's bottom edge under one page-wide scrim. A section's own
/// Stack sizes to its browsing region, and a sheet docked there was
/// clipped against that region's edge — its title and its footer controls
/// fell outside the section.
library;

import 'package:app/di/providers.dart';
import 'package:app/ui/chat/chat_ui_state.dart';
import 'package:app/ui/workspace/workspace_screen.dart';
import 'package:domain/model/backend.dart';
import 'package:domain/model/directory.dart';
import 'package:domain/model/workspace.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';
import '../chat/session_search_test.dart';

final _backend = BackendConfig(
  id: 'b1',
  label: 'Laptop',
  baseUri: Uri.parse('http://10.0.2.2:3080'),
);

const _workspace = WorkspaceSummary(
  workspaceId: 'w1',
  path: '/home/user',
  title: 'home',
  sessionIds: ['s1'],
);

const _listing = DirectoryListing(
  path: '/home/user',
  home: '/home/user',
  crumbs: [DirectoryEntry(name: 'chance', path: '/home/user', hidden: false)],
  entries: [
    DirectoryEntry(
      name: 'Projects',
      path: '/home/user/Projects',
      hidden: false,
    ),
  ],
  truncated: false,
);

/// The domain seam: a repository double, so the real controller and the
/// real screen run (wire decoding is the adapter's own suite).
class _FakeWorkspaceRepository extends SearchTestFakeRepository {
  _FakeWorkspaceRepository() : super(initialWorkspaces: const [_workspace]);

  @override
  Future<DirectoryListing> listDirectory(String? path) async => _listing;
}

void main() {
  testWidgets('the directory browser docks at the screen, not the section', (
    tester,
  ) async {
    // A short phone: the sheet is taller than one backend's browsing
    // region, which is the case the section-local Stack clipped.
    tester.view.physicalSize = const Size(720, 1688);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _FakeWorkspaceRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatRepositoryProvider('b1').overrideWithValue(repository),
          // The aggregate reads the active backend's selection only; the
          // chat controller behind it is not this surface's subject.
          chatUiStateProvider('b1')
              .overrideWithValue(const AsyncData<ChatUiState>(ChatUiState())),
        ],
        child: l10nApp(
          home: WorkspaceAggregateScreen(
            backends: [_backend],
            activeId: 'b1',
            onAction: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The header's add control opens the browser (the section dispatches
    // straight to its own workspace controller).
    expect(find.byType(DirectoryBrowserDialog), findsNothing);
    await tester.tap(find.byTooltip('Add workspace'));
    await tester.pumpAndSettle();
    expect(find.byType(DirectoryBrowserDialog), findsOneWidget);

    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final sheet = tester.getRect(find.byType(DirectoryBrowserDialog));
    // Docked at the bottom edge and wholly on screen: the whole sheet is
    // the reader's, its title included.
    expect(sheet.bottom, lessThanOrEqualTo(screen.height));
    expect(sheet.top, greaterThanOrEqualTo(0));
    expect(
      sheet.bottom,
      greaterThan(screen.height - 40),
      reason: 'the sheet docks at the bottom of the screen',
    );
    expect(
      find.text('Select Workspace Directory').hitTestable(),
      findsOneWidget,
    );
    // The footer's controls stay reachable — they are the flow's verbs.
    expect(find.text('New folder').hitTestable(), findsOneWidget);
    expect(find.text('Open').hitTestable(), findsOneWidget);

    // The scrim spans the page, not one section: a tap above the sheet
    // still closes the browser.
    final scrim = tester.getRect(
      find.byWidgetPredicate(
        (widget) =>
            widget is ColoredBox && widget.color.a > 0 && widget.color.a < 1,
      ),
    );
    expect(scrim.top, 0);
    expect(scrim.width, screen.width);
  });
}
