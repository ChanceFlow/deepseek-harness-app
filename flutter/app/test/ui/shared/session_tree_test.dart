/// Session-tree derivation and row-status tests: the sidebar's activity
/// priority ordering within groups (selected > running > pending
/// interaction > recent-24h > recency), the switching-surface empty-group
/// hiding, and the status-dot mapping (amber pending / blue running /
/// green done) that mirrors web ui-workspace `sessionStatuses`.
library;

import 'package:domain/model/session.dart';
import 'package:domain/model/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/l10n/app_localizations.dart';
import 'package:app/ui/shared/session_tree.dart';
import 'package:app/ui/theme/theme.dart';

import '../../l10n_app.dart';

final AppLocalizations _en = lookupAppLocalizations(const Locale('en'));

SessionSummary _session(
  String id, {
  bool running = false,
  bool completed = false,
  SessionPendingInteraction? pendingInteraction,
  int updatedAtEpochMs = 0,
}) => SessionSummary(
  id: id,
  title: 'session $id',
  blank: false,
  running: running,
  completed: completed,
  pendingInteraction: pendingInteraction,
  updatedAtEpochMs: updatedAtEpochMs,
);

void main() {
  group('priorityOrderedMembers', () {
    final now = DateTime.now().millisecondsSinceEpoch;

    test('selected rides the top; running > pending > recent > rest', () {
      final members = <SessionSummary>[
        _session('a', updatedAtEpochMs: now), // recent
        _session('b', pendingInteraction: SessionPendingInteraction.approval),
        _session('c', running: true),
        _session('d', updatedAtEpochMs: now - (25 * 3600 * 1000)), // old
      ];
      // select 'd' (old) — pinned above running 'c'.
      final ordered = priorityOrderedMembers(members, 'd', now);
      expect(ordered.map((s) => s.id), <String>['d', 'c', 'b', 'a']);
    });

    test('within a tier recency wins, id breaks ties', () {
      final members = <SessionSummary>[
        _session('old', updatedAtEpochMs: 100),
        _session('new', updatedAtEpochMs: 300),
        _session('mid', updatedAtEpochMs: 200),
      ];
      final ordered = priorityOrderedMembers(members, null, now);
      expect(ordered.map((s) => s.id), <String>['new', 'mid', 'old']);
    });
  });

  group('deriveSessionGroups', () {
    final now = DateTime.now().millisecondsSinceEpoch;

    final workspaces = <WorkspaceSummary>[
      const WorkspaceSummary(
        workspaceId: 'w1',
        path: '/a',
        title: 'A',
        sessionIds: <String>['r', 'p', 'x'],
      ),
      const WorkspaceSummary(
        workspaceId: 'w2',
        path: '/b',
        title: 'empty',
      ),
    ];

    test('priority order applies within a workspace group', () {
      final sessions = <SessionSummary>[
        _session('r', running: true, updatedAtEpochMs: now),
        _session('p', pendingInteraction: SessionPendingInteraction.question),
        _session('x', updatedAtEpochMs: now),
      ];
      final groups = deriveSessionGroups(
        sessions,
        workspaces,
        null,
        _en,
        nowEpochMs: now,
        priorityOrder: true,
        includeEmptyGroups: false,
      );
      expect(groups, hasLength(1));
      expect(groups.single.sessions.map((s) => s.id), <String>['r', 'p', 'x']);
    });

    test('empty workspace groups hide for the switching surface', () {
      final sessions = <SessionSummary>[_session('r', running: true)];
      final groups = deriveSessionGroups(
        sessions,
        workspaces,
        null,
        _en,
        nowEpochMs: now,
        priorityOrder: true,
        includeEmptyGroups: false,
      );
      // w1 holds 'r'; the empty w2 group is dropped.
      expect(groups, hasLength(1));
      expect(groups.single.key, 'w1');
    });

    test('management surface keeps empty groups and account order', () {
      final sessions = <SessionSummary>[
        _session('x', updatedAtEpochMs: now),
        _session('r', running: true, updatedAtEpochMs: now),
        _session('p', updatedAtEpochMs: now),
      ];
      // No priorityOrder: w1 members keep account order (sessionIds), and
      // the empty w2 group still renders for management.
      final groups = deriveSessionGroups(
        sessions,
        workspaces,
        null,
        _en,
        nowEpochMs: now,
      );
      expect(groups, hasLength(2));
      expect(groups[0].sessions.map((s) => s.id), <String>['r', 'p', 'x']);
      expect(groups[1].key, 'w2');
    });
  });

  group('SessionStatusDot', () {
    testWidgets('pending interaction renders the amber warning dot', (
      tester,
    ) async {
      await tester.pumpWidget(
        l10nApp(
          home: Scaffold(
            body: SessionStatusDot(
              session: _session(
                'a',
                pendingInteraction: SessionPendingInteraction.planReview,
              ),
            ),
          ),
        ),
      );
      expect(find.byType(WarningDot), findsOneWidget);
      expect(find.byType(RunningDot), findsNothing);
      expect(find.byType(DoneDot), findsNothing);
    });

    testWidgets('running renders the blue ongoing dot', (tester) async {
      await tester.pumpWidget(
        l10nApp(
          home: Scaffold(
            body: SessionStatusDot(session: _session('a', running: true)),
          ),
        ),
      );
      expect(find.byType(RunningDot), findsOneWidget);
      expect(find.byType(WarningDot), findsNothing);
      expect(find.byType(DoneDot), findsNothing);
    });

    testWidgets('idle renders no dot (the web shows nothing idle)', (
      tester,
    ) async {
      await tester.pumpWidget(
        l10nApp(
          home: Scaffold(
            body: SessionStatusDot(session: _session('a')),
          ),
        ),
      );
      expect(find.byType(DoneDot), findsNothing);
      expect(find.byType(WarningDot), findsNothing);
      expect(find.byType(RunningDot), findsNothing);
    });

    testWidgets('completed (finished-unviewed) renders the green done dot', (
      tester,
    ) async {
      await tester.pumpWidget(
        l10nApp(
          home: Scaffold(
            body: SessionStatusDot(session: _session('a', completed: true)),
          ),
        ),
      );
      expect(find.byType(DoneDot), findsOneWidget);
      expect(find.byType(WarningDot), findsNothing);
      expect(find.byType(RunningDot), findsNothing);
    });

    testWidgets('the done dot paints whichever success the theme carries', (
      tester,
    ) async {
      for (final theme in [DshTheme.light(), DshTheme.dark()]) {
        await tester.pumpWidget(
          l10nApp(theme: theme, home: const Scaffold(body: DoneDot())),
        );
        // MaterialApp lerps between themes; land on the new one.
        await tester.pump(const Duration(milliseconds: 400));
        final core = tester.widget<Container>(
          find
              .descendant(
                of: find.byType(DoneDot),
                matching: find.byType(Container),
              )
              .last,
        );
        expect(
          (core.decoration! as BoxDecoration).color,
          theme.colorScheme.success,
        );
      }
    });
  });
}
