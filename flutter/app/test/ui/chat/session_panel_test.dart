/// SessionPanel widget tests — the browsing toggles' persistence
/// through the local state store and the destination selection's
/// restore (driven through the provider; the bottom tab bar owns the
/// Settings entry on mobile, so the panel carries no trigger).
///
/// Real disk IO never completes inside a testWidgets fake-async zone,
/// so persistence asserts the store's synchronous cache (the write
/// path the panel contracts with) and restores a fresh widget instance
/// from that same store; the store's own disk round-trip belongs to
/// the store's test suite. Toggles schedule the store's debounce
/// timer, so every test that writes pumps fake time past the debounce
/// window before ending (a pending timer fails the test invariant).
library;

import 'dart:io';

import 'package:domain/model/session.dart';
import 'package:domain/model/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/local_state/local_state_providers.dart';
import 'package:app/local_state/local_state_store.dart';
import 'package:app/ui/chat/session_panel.dart';
import 'package:app/ui/root/app_destination.dart';
import 'package:app/ui/shared/session_tree.dart';
import 'package:app/ui/theme/theme.dart';

import '../../l10n_app.dart';

/// Two workspace groups: `proj` with seven sessions (the selected
/// session rides the group, and the run is long enough to carry the
/// overflow control past the collapsed session limit) and `other`
/// with one — the foldable group that is NOT current.
const _workspaces = <WorkspaceSummary>[
  WorkspaceSummary(
    workspaceId: 'w1',
    path: '/tmp/proj',
    title: 'proj',
    sessionIds: <String>['s1', 's2', 's3', 's4', 's5', 's6', 's7'],
  ),
  WorkspaceSummary(
    workspaceId: 'w2',
    path: '/tmp/other',
    title: 'other',
    sessionIds: <String>['o1'],
  ),
];

final _sessions = <SessionSummary>[
  for (var i = 1; i <= 7; i++)
    SessionSummary(
      id: 's$i',
      title: 'session $i',
      blank: false,
      updatedAtEpochMs: 1000 * i,
      cwd: '/tmp/proj',
    ),
  const SessionSummary(
    id: 'o1',
    title: 'other session',
    blank: false,
    updatedAtEpochMs: 8000,
    cwd: '/tmp/other',
  ),
];

/// The store's debounce window (kLocalStateFlushDelay, 500ms) plus a
/// step; tests pump past it to retire the write timer before the test
/// invariant checks for pending timers.
const Duration _debounceWindow = Duration(milliseconds: 600);

/// A fresh temp-file-backed store (empty cache: every read returns the
/// pre-cache default, matching the app's pre-load window).
LocalStateStore _store() {
  final dir = Directory.systemTemp.createTempSync('session_panel_state');
  addTearDown(() => dir.deleteSync(recursive: true));
  return LocalStateStore(File('${dir.path}/local_state.json'));
}

/// Pumps the real panel with the chat screen's standard callbacks and
/// returns the container so tests can read provider state. The store
/// override defaults to a fresh temp-file-backed store; [theme] pumps a
/// specific brightness for role read-backs.
Future<ProviderContainer> _pumpPanel(
  WidgetTester tester, {
  bool inDrawer = false,
  LocalStateStore? store,
  String selectedSessionId = 's1',
  ThemeData? theme,
}) async {
  // Phone-scale logical surface so the tree rows and the foot lay out
  // naturally.
  tester.view.physicalSize = const Size(800, 1280);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final effectiveStore = store ?? _store();
  final container = ProviderContainer(
    overrides: [
      localStateStoreProvider.overrideWith((ref) async => effectiveStore),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: l10nApp(
        theme: theme,
        home: Scaffold(
          body: SessionPanel(
            inDrawer: inDrawer,
            sessions: _sessions,
            workspaces: _workspaces,
            searchResults: const <SessionSearchResult>[],
            selectedSessionId: selectedSessionId,
            onSelectSession: (_) {},
            onCreateSession: (_) {},
            onSearchSessions: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets(
    'the continuation hint dissolves the list edge, never overlays it',
    (tester) async {
      await _pumpPanel(tester);
      // The web `.fade` rides as EdgeFade: a dstIn ShaderMask wrapping the
      // tree, so the rows dissolve into the surface instead of sliding
      // under a translucent band (the accent bleed this replaced).
      expect(
        find.ancestor(
          of: find.byType(ListView),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is ShaderMask && widget.blendMode == BlendMode.dstIn,
          ),
        ),
        findsWidgets,
      );
    },
  );

  testWidgets('the destination selection restores from the store', (
    tester,
  ) async {
    final store = _store();
    final container = await _pumpPanel(tester, store: store);

    // The bottom tab bar owns Settings on mobile; drive the provider
    // the way the tab bar does.
    container
        .read(appDestinationProvider.notifier)
        .select(AppDestination.settings);
    await tester.pumpAndSettle();
    expect(container.read(appDestinationProvider), AppDestination.settings);
    await tester.pump(_debounceWindow);

    // A fresh container over the same store: Chat while the provider
    // is still resolving, the persisted destination once it lands.
    final container2 = ProviderContainer(
      overrides: [localStateStoreProvider.overrideWith((ref) async => store)],
    );
    addTearDown(container2.dispose);
    expect(container2.read(appDestinationProvider), AppDestination.chat);
    await container2.read(localStateStoreProvider.future);
    await tester.pump();
    expect(container2.read(appDestinationProvider), AppDestination.settings);
  });

  testWidgets(
    'the active session\'s group never folds; other overrides persist',
    (tester) async {
      final store = _store();

      // The current group (holds the selected session) is expanded, and
      // tapping its header is a no-op — collapsing it would hide the
      // active session behind a hunt. No override is written. The
      // selected session rides the group's top (priority order), so it
      // is the visible anchor.
      await _pumpPanel(tester, store: store);
      expect(find.text('session 1'), findsOneWidget);
      await tester.tap(find.text('proj'));
      await tester.pumpAndSettle();
      expect(find.text('session 1'), findsOneWidget);
      expect(store.read('sidebar.groupOverrides'), isNull);

      // A non-current group starts folded (default); the toggle expands
      // it and the override writes through to the store's cache.
      expect(find.text('other session'), findsNothing);
      await tester.tap(find.text('other'));
      await tester.pumpAndSettle();
      expect(find.text('other session'), findsOneWidget);
      expect(store.read('sidebar.groupOverrides'), <String, bool>{'w2': true});
      // Folding it back writes the collapse override.
      await tester.tap(find.text('other'));
      await tester.pumpAndSettle();
      expect(find.text('other session'), findsNothing);
      expect(store.read('sidebar.groupOverrides'), <String, bool>{'w2': false});
      await tester.pump(_debounceWindow);

      // A fresh panel instance seeded from the same store keeps the
      // non-current group collapsed while the current group stays open.
      await _pumpPanel(tester, store: store);
      expect(find.text('session 1'), findsOneWidget);
      expect(find.text('other session'), findsNothing);
    },
  );

  testWidgets('the active session rides its group\'s top', (tester) async {
    await _pumpPanel(tester, selectedSessionId: 's3');

    // The selected session pins above every other member (priority
    // order: selected first, then recency): 'session 3' renders above
    // 'session 7', the newest non-selected session.
    expect(find.text('session 3'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('session 3')).dy,
      lessThan(tester.getTopLeft(find.text('session 7')).dy),
    );
  });

  testWidgets('a pinned active session stays visible past the overflow limit', (
    tester,
  ) async {
    // 'session 6' would sit below the collapsed limit of 5 by recency
    // (newest-first: 7,6,5,4,3...), but selection pins it to the head:
    // no hunt, no Show-all expansion needed. The tail behind the limit
    // still folds ('session 1' is the oldest, below the fold).
    await _pumpPanel(tester, selectedSessionId: 's6');
    expect(find.text('session 6'), findsOneWidget);
    expect(find.text('session 1'), findsNothing);
    expect(find.text('Show all 7'), findsOneWidget);
  });

  testWidgets('an overflow expansion writes through and restores', (
    tester,
  ) async {
    final store = _store();

    // First instance: expand the group's overflow run past the
    // collapsed session limit. With priority order (all idle, recency
    // tiebreak) the newest five are visible and the oldest ('session 3'
    // at 3000ms) hides behind the fold until expanded.
    await _pumpPanel(tester, store: store);
    expect(find.text('Show all 7'), findsOneWidget);
    expect(find.text('session 3'), findsNothing);
    await tester.tap(find.text('Show all 7'));
    await tester.pumpAndSettle();
    expect(find.text('Show less'), findsOneWidget);
    expect(find.text('session 3'), findsOneWidget);
    // The expansion wrote through to the store's cache.
    expect(store.read('sidebar.overflowExpanded'), <String>['w1']);
    await tester.pump(_debounceWindow);

    // A fresh panel instance seeded from the same store restores it.
    await _pumpPanel(tester, store: store);
    expect(find.text('session 3'), findsOneWidget);
    expect(find.text('Show less'), findsOneWidget);
  });

  testWidgets('the search seat is an M3 SearchBar with the capsule flow', (
    tester,
  ) async {
    final queries = <String>[];
    tester.view.physicalSize = const Size(800, 1280);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(
      overrides: [
        localStateStoreProvider.overrideWith((ref) async => _store()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: l10nApp(
          home: Scaffold(
            body: SessionPanel(
              inDrawer: false,
              sessions: _sessions,
              workspaces: _workspaces,
              searchResults: const <SessionSearchResult>[],
              selectedSessionId: 's1',
              onSelectSession: (_) {},
              onCreateSession: (_) {},
              onSearchSessions: queries.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Hidden until the header toggle expands it.
    expect(find.byType(SearchBar), findsNothing);
    await tester.tap(find.byTooltip('Search sessions'));
    await tester.pumpAndSettle();

    // The expanded seat is a native M3 SearchBar with the capsule's
    // interaction: typing dispatches the query, the trailing close
    // clears and collapses.
    expect(find.byType(SearchBar), findsOneWidget);
    await tester.enterText(find.byType(SearchBar), 'needle');
    await tester.pump();
    expect(queries, contains('needle'));

    await tester.tap(
      find.descendant(
        of: find.byType(SearchBar),
        matching: find.byIcon(Icons.close),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SearchBar), findsNothing);
    expect(queries.last, isEmpty);
  });

  testWidgets('the browsing chrome rides native Material components', (
    tester,
  ) async {
    await _pumpPanel(tester);

    // Group headers are native ExpansionTiles (one per workspace group:
    // 'proj' current and 'other' folded).
    expect(find.byType(ExpansionTile), findsNWidgets(2));

    // The current group's session rows are native ListTiles — the
    // selected session pinned first plus the four newest (the collapsed
    // run of five before the overflow control).
    expect(find.byType(ListTile), findsWidgets);
    expect(find.byType(SessionTreeRow), findsNWidgets(5));

    // New Session is a native button seat, and the section header's
    // search toggle is a standard IconButton.
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.byTooltip('Search sessions'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SessionPanel),
        matching: find.byType(IconButton),
      ),
      findsWidgets,
    );
  });

  testWidgets('the new session button ink rides the primary contrast pair', (
    tester,
  ) async {
    await _pumpPanel(tester);

    // Stock filled seat: the contrast pair comes from the scheme through
    // the framework's own defaults, not from a style override.
    final context = tester.element(find.byType(FilledButton));
    final scheme = Theme.of(context).colorScheme;
    final style = FilledButton.styleFrom().merge(
      tester.widget<FilledButton>(find.byType(FilledButton)).style ??
          const ButtonStyle(),
    );
    expect(style.backgroundColor?.resolve(<WidgetState>{}), isNull);
    final material = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(FilledButton),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(material.color, scheme.primary);
    expect(material.textStyle?.color, scheme.onPrimary);
  });

  group('rail form', () {
    // A re-pump inside one test (the theme loop) updates the element tree
    // in place, so the panel keeps its rail state across pumps: expand
    // first to make the collapse idempotent per iteration.
    Future<void> expandIfRail(WidgetTester tester) async {
      if (find.byTooltip('Open sidebar').evaluate().isNotEmpty) {
        await tester.tap(find.byTooltip('Open sidebar'));
        await tester.pumpAndSettle();
      }
    }

    Future<void> collapseToRail(WidgetTester tester) async {
      await expandIfRail(tester);
      await tester.tap(find.byTooltip('Collapse sidebar'));
      await tester.pumpAndSettle();
    }

    testWidgets('the rail column declares the shared rail width', (
      tester,
    ) async {
      await _pumpPanel(tester);
      await collapseToRail(tester);
      // The panel's root Container sizes its rail form to the same
      // theme.dart constant the two-pane host animates to.
      final box = tester.widget<ConstrainedBox>(
        find
            .descendant(
              of: find.byType(SessionPanel),
              matching: find.byType(ConstrainedBox),
            )
            .first,
      );
      expect(box.constraints, const BoxConstraints.tightFor(width: kRailWidth));
    });

    testWidgets('rail seats ride the stock IconButton: no hand-spun ink, '
        'size, or sub-48 constraints, in both themes', (tester) async {
      for (final theme in [DshTheme.light(), DshTheme.dark()]) {
        await _pumpPanel(tester, theme: theme);
        await collapseToRail(tester);
        // Past the theme lerp so the read-back colors are the new scheme's.
        await tester.pump(const Duration(milliseconds: 400));
        final scheme = theme.colorScheme;
        for (final glyph in [
          Icons.add_comment_outlined,
          Icons.search,
          Icons.menu,
        ]) {
          final seat = tester.widget<IconButton>(
            find
                .ancestor(
                  of: find.byIcon(glyph),
                  matching: find.byType(IconButton),
                )
                .first,
          );
          expect(seat.color, isNull, reason: '$glyph carries hand-spun ink');
          expect(
            seat.constraints,
            isNull,
            reason: '$glyph replaces the stock 48px seat',
          );
          expect(
            seat.padding,
            isNull,
            reason: '$glyph replaces the stock padding',
          );
          expect(
            (seat.icon as Icon).size,
            isNull,
            reason: '$glyph carries a hand-spun size',
          );
          // What the framework resolves for a stock seat is the contract:
          // the onSurfaceVariant role and the 24px default glyph.
          final iconTheme = IconTheme.of(tester.element(find.byIcon(glyph)));
          expect(iconTheme.color, scheme.onSurfaceVariant);
          expect(iconTheme.size, 24);
        }
      }
    });

    testWidgets("the rail repeats the pane's New Session glyph", (
      tester,
    ) async {
      await _pumpPanel(tester);
      // Expanded: one add_comment glyph on the filled seat, and the
      // bottom-nav's chat bubble names no sidebar verb.
      expect(find.byIcon(Icons.add_comment_outlined), findsOneWidget);
      expect(find.byIcon(Icons.chat_bubble_outline), findsNothing);
      await collapseToRail(tester);
      // Rail: the same verb keeps the same glyph; nothing was swapped.
      expect(find.byIcon(Icons.add_comment_outlined), findsOneWidget);
      expect(find.byIcon(Icons.chat_bubble_outline), findsNothing);
    });

    testWidgets('the selected avatar rides the selected row role, in both '
        'themes', (tester) async {
      for (final theme in [DshTheme.light(), DshTheme.dark()]) {
        await _pumpPanel(tester, theme: theme);
        await expandIfRail(tester);
        final scheme = theme.colorScheme;
        // Expanded: the selected tree row fills on secondaryContainer.
        final tile = tester.widget<ListTile>(
          find
              .ancestor(
                of: find.text('session 1'),
                matching: find.byType(ListTile),
              )
              .first,
        );
        expect(tile.selected, isTrue);
        expect(tile.selectedTileColor, scheme.secondaryContainer);
        await collapseToRail(tester);
        await tester.pump(const Duration(milliseconds: 400));
        // Rail: the selected avatar wears the same role, and its letter
        // pairs (a filled seat never keeps quiet ink).
        final selectedAvatar = tester.widget<CircleAvatar>(
          find.descendant(
            of: find.byTooltip('session 1'),
            matching: find.byType(CircleAvatar),
          ),
        );
        expect(selectedAvatar.backgroundColor, scheme.secondaryContainer);
        expect(
          tester
              .widget<Text>(
                find.descendant(
                  of: find.byTooltip('session 1'),
                  matching: find.byType(Text),
                ),
              )
              .style!
              .color,
          scheme.onSecondaryContainer,
        );
        // A resting avatar is the raised seat above the rail's
        // surfaceContainerLow chrome, in quiet ink.
        final restingAvatar = tester.widget<CircleAvatar>(
          find.descendant(
            of: find.byTooltip('session 2'),
            matching: find.byType(CircleAvatar),
          ),
        );
        expect(restingAvatar.backgroundColor, scheme.surfaceContainerHigh);
        expect(
          tester
              .widget<Text>(
                find.descendant(
                  of: find.byTooltip('session 2'),
                  matching: find.byType(Text),
                ),
              )
              .style!
              .color,
          scheme.onSurfaceVariant,
        );
      }
    });

    testWidgets('the selected seat reads selected to semantics', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpPanel(tester);
      await collapseToRail(tester);
      expect(
        tester.getSemantics(find.byTooltip('session 1')),
        isSemantics(isSelected: true),
      );
      expect(
        tester.getSemantics(find.byTooltip('session 2')),
        isSemantics(isSelected: false),
      );
      handle.dispose();
    });
  });
}
