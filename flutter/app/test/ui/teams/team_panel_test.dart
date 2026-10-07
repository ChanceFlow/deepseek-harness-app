/// Agent-Team panel behavior: the durable roster with activity derived from
/// live Session status, the read-only shared task board, and the failure
/// banner a rejected persisted Team record raises.
///
/// The panel is a real widget fed a real `AgentTeam` value decoded by the
/// adapter's fixture tests; these assertions read what a user sees
/// ([docs/testing.md](../../../../docs/testing.md)).
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:app/ui/teams/team_panel.dart';
import 'package:domain/model/agent_team.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';

final AppLocalizations _l10n = lookupAppLocalizations(const Locale('en'));

const TeamMember _lead = TeamMember(
  id: 'session-t',
  name: 'lead',
  isLead: true,
  phase: TeamMemberPhase.active,
);

const TeamMember _reviewer = TeamMember(
  id: 'child-1',
  name: 'reviewer',
  isLead: false,
  phase: TeamMemberPhase.active,
);

Future<void> _pump(
  WidgetTester tester,
  AgentTeam team, {
  String currentSessionId = 'session-t',
  Map<String, bool> runningBySession = const <String, bool>{},
  void Function(TeamMember)? onOpenMember,
}) async {
  await tester.pumpWidget(
    l10nApp(
      home: Scaffold(
        body: TeamPanel(
          team: team,
          currentSessionId: currentSessionId,
          leadSessionId: 'session-t',
          runningBySession: runningBySession,
          onOpenMember: onOpenMember ?? (TeamMember member) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('roster rows read their activity from the live running bit', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      const AgentTeam(members: <TeamMember>[_lead, _reviewer]),
      runningBySession: const <String, bool>{'child-1': true},
    );

    expect(find.text('lead'), findsOneWidget);
    expect(find.text('reviewer'), findsOneWidget);
    // The Lead has no live running bit of its own here, so it reads inactive
    // and wears the person glyph instead of a dot.
    expect(find.text(_l10n.teamMemberRunning), findsOneWidget);
    expect(find.text(_l10n.teamMemberInactive), findsOneWidget);
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
    // The conversation on screen is tagged and cannot be reopened from here.
    expect(find.text(_l10n.teamCurrentChat), findsOneWidget);
    expect(find.byIcon(Icons.open_in_new), findsOneWidget);
  });

  testWidgets('a provisioning member has no conversation to open', (
    WidgetTester tester,
  ) async {
    // Opened from the reviewer's own conversation: the Lead row is openable
    // and the provisioning row is not.
    await _pump(
      tester,
      const AgentTeam(
        members: <TeamMember>[
          _lead,
          TeamMember(
            id: 'child-2',
            name: 'newcomer',
            isLead: false,
            phase: TeamMemberPhase.provisioning,
          ),
        ],
      ),
      currentSessionId: 'child-1',
    );

    expect(find.text(_l10n.teamMemberProvisioning), findsOneWidget);
    expect(find.byIcon(Icons.open_in_new), findsOneWidget);
  });

  testWidgets('the task board shows identity, owner, readiness and scopes', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      const AgentTeam(
        members: <TeamMember>[_lead],
        tasks: <TeamTask>[
          TeamTask(
            id: 'task-1',
            revision: 2,
            subject: 'Audit the diff',
            description: 'Read every hunk',
            status: TeamTaskStatus.inProgress,
            blockedBy: <String>['task-0'],
            writeScopes: <String>['flutter/app'],
            ownerName: 'reviewer',
            writeScopeWarnings: <String>['write scopes overlap with task-2'],
          ),
          TeamTask(
            id: 'task-2',
            revision: 1,
            subject: 'Unclaimed work',
            description: '',
            status: TeamTaskStatus.pending,
            ready: true,
          ),
        ],
      ),
    );

    expect(find.text('Audit the diff'), findsOneWidget);
    expect(find.text(_l10n.teamTaskInProgress), findsOneWidget);
    expect(find.text(_l10n.teamTaskOwner('reviewer')), findsOneWidget);
    expect(find.text(_l10n.teamTaskBlockedBy('task-0')), findsOneWidget);
    expect(find.text(_l10n.teamTaskWriteScopes('flutter/app')), findsOneWidget);
    expect(find.text('write scopes overlap with task-2'), findsOneWidget);

    // A ready pending task reads ready; an unowned one names no owner.
    expect(find.text(_l10n.teamTaskReady), findsOneWidget);
    expect(
      find.text(_l10n.teamTaskOwner(_l10n.teamTaskUnowned)),
      findsOneWidget,
    );
  });

  testWidgets('an empty board shows its notice', (WidgetTester tester) async {
    await _pump(tester, const AgentTeam(members: <TeamMember>[_lead]));

    expect(find.text(_l10n.teamTaskBoardEmpty), findsOneWidget);
    // A lone member and no tasks: the roster count badge stays off.
    expect(find.text('1'), findsNothing);
  });

  testWidgets('a rejected persisted record shows above the last valid state', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      const AgentTeam(
        members: <TeamMember>[_lead],
        tasks: <TeamTask>[
          TeamTask(
            id: 'task-1',
            revision: 1,
            subject: 'Audit the diff',
            description: '',
            status: TeamTaskStatus.pending,
          ),
        ],
        failure: 'member child-9 references an unknown session',
      ),
    );

    expect(
      find.text(
        _l10n.teamFailure('member child-9 references an unknown session'),
      ),
      findsOneWidget,
    );
    // The last valid roster and board stay visible under the banner.
    expect(find.text('lead'), findsOneWidget);
    expect(find.text('Audit the diff'), findsOneWidget);
  });

  testWidgets(
    'a long description offers an expand toggle, a short one does not',
    (WidgetTester tester) async {
      await _pump(
        tester,
        const AgentTeam(
          members: <TeamMember>[_lead],
          tasks: <TeamTask>[
            TeamTask(
              id: 'task-1',
              revision: 1,
              subject: 'Short',
              description: 'One line',
              status: TeamTaskStatus.pending,
            ),
            TeamTask(
              id: 'task-2',
              revision: 1,
              subject: 'Long',
              description:
                  'A description long enough that the two-line clamp truncates '
                  'it on a phone, which is exactly when the reference shows its '
                  'own expand control rather than a dead one.',
              status: TeamTaskStatus.pending,
            ),
          ],
        ),
      );

      // The short card has no control; the long one has exactly one.
      expect(find.text(_l10n.teamTaskShowMore), findsOneWidget);
      await tester.tap(find.text(_l10n.teamTaskShowMore));
      await tester.pumpAndSettle();
      expect(find.text(_l10n.teamTaskShowLess), findsOneWidget);
    },
  );

  testWidgets('opening a member hands back the row', (
    WidgetTester tester,
  ) async {
    final opened = <TeamMember>[];
    await _pump(
      tester,
      const AgentTeam(members: <TeamMember>[_lead, _reviewer]),
      runningBySession: const <String, bool>{'child-1': true},
      onOpenMember: opened.add,
    );

    await tester.tap(find.byIcon(Icons.open_in_new));
    await tester.pumpAndSettle();

    expect(opened.single.id, 'child-1');
    expect(opened.single.name, 'reviewer');
  });
}
