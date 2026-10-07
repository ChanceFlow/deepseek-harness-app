/// Agent-Team header action: it appears only while the Lead session carries an
/// `agentTeam` projection, resolves the Lead from a teammate's conversation,
/// and opens the read-only panel.
library;

import 'package:app/config.dart';
import 'package:app/di/providers.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/ui/chat/chat_ui_state.dart';
import 'package:app/ui/teams/team_action.dart';
import 'package:app/ui/teams/team_panel.dart';
import 'package:domain/model/agent_team.dart';
import 'package:domain/model/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';

final AppLocalizations _l10n = lookupAppLocalizations(const Locale('en'));

const AgentTeam _team = AgentTeam(
  members: <TeamMember>[
    TeamMember(
      id: 'session-t',
      name: 'lead',
      isLead: true,
      phase: TeamMemberPhase.active,
    ),
    TeamMember(
      id: 'child-1',
      name: 'reviewer',
      isLead: false,
      phase: TeamMemberPhase.active,
    ),
  ],
);

/// The roster the header resolves the Lead from: a teammate names its parent.
const List<SessionSummary> _sessions = <SessionSummary>[
  SessionSummary(id: 'session-t', blank: false),
  SessionSummary(id: 'child-1', blank: false, parentSessionId: 'session-t'),
];

Future<void> _pump(
  WidgetTester tester, {
  required String sessionId,
  required AgentTeam? team,
  required String teamKeySessionId,
  void Function(String leadSessionId, TeamMember member)? onOpenMember,
  List<SessionSummary> sessions = _sessions,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chatUiStateProvider(kDshBaseUrl).overrideWith(
          (ref) => Stream<ChatUiState>.value(ChatUiState(sessions: sessions)),
        ),
        // Both keys the action can resolve to: the Lead's, and — on the
        // first frame, before the roster arrives — the conversation's own,
        // which carries no Team of its own.
        agentTeamProvider((kDshBaseUrl, teamKeySessionId))
            .overrideWith((ref) => Stream<AgentTeam?>.value(team)),
        if (sessionId != teamKeySessionId)
          agentTeamProvider((kDshBaseUrl, sessionId))
              .overrideWith((ref) => Stream<AgentTeam?>.value(null)),
      ],
      child: l10nApp(
        home: Scaffold(
          body: TeamAction(
            backendId: kDshBaseUrl,
            sessionId: sessionId,
            onOpenMember: onOpenMember ?? (String lead, TeamMember member) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test(
    'the lead session is a teammate\u2019s parent, else the session itself',
    () {
      expect(
        teamLeadSessionId(sessionId: 'child-1', sessions: _sessions),
        'session-t',
      );
      expect(
        teamLeadSessionId(sessionId: 'session-t', sessions: _sessions),
        'session-t',
      );
      // A session the roster does not know is its own lead.
      expect(
        teamLeadSessionId(sessionId: 'unknown', sessions: _sessions),
        'unknown',
      );
    },
  );

  testWidgets('no team renders no action', (WidgetTester tester) async {
    await _pump(
      tester,
      sessionId: 'session-t',
      team: null,
      teamKeySessionId: 'session-t',
    );

    expect(find.byIcon(Icons.groups_outlined), findsNothing);
    expect(find.text(_l10n.teamPanelTitle), findsNothing);
  });

  testWidgets('a team renders the count and opens the panel', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      sessionId: 'session-t',
      team: _team,
      teamKeySessionId: 'session-t',
    );

    expect(find.byIcon(Icons.groups_outlined), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.groups_outlined));
    await tester.pumpAndSettle();

    expect(find.text(_l10n.teamPanelTitle), findsOneWidget);
    expect(find.text(_l10n.teamRosterHeading), findsOneWidget);
    expect(find.byType(TeamPanel), findsOneWidget);
    expect(find.text('reviewer'), findsOneWidget);
  });

  testWidgets('a teammate conversation reads its lead\u2019s team', (
    WidgetTester tester,
  ) async {
    // The value is registered under the lead's id only; a teammate's
    // conversation must still find it.
    var openedLead = '';
    var openedMember = '';
    await _pump(
      tester,
      sessionId: 'child-1',
      team: _team,
      teamKeySessionId: 'session-t',
      onOpenMember: (String leadSessionId, TeamMember member) {
        openedLead = leadSessionId;
        openedMember = member.id;
      },
    );

    expect(find.byIcon(Icons.groups_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.groups_outlined));
    await tester.pumpAndSettle();

    // The Lead row opens that session; the panel hands the row back with the
    // lead id the parent resolved.
    await tester.tap(find.byIcon(Icons.open_in_new));
    await tester.pumpAndSettle();
    expect(openedLead, 'session-t');
    expect(openedMember, 'session-t');
    // The panel closed as it navigated.
    expect(find.byType(TeamPanel), findsNothing);
  });
}
