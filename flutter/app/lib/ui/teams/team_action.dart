/// Session-header Agent-Team action: a members glyph that appears only while
/// the Lead session carries an `agentTeam` projection, and opens the team's
/// roster and shared task board.
///
/// The panel itself ([TeamPanel]) is presentation only; this widget owns the
/// projection read and the navigation into a teammate's conversation.
library;

import 'dart:async';

import 'package:app/di/providers.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/agent_team.dart';
import 'package:domain/model/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/theme.dart';
import 'team_panel.dart';

/// The Lead session of a conversation: a teammate's parent, else the session
/// itself — the reference resolves the same way from the subagent address.
String teamLeadSessionId({
  required String sessionId,
  required List<SessionSummary> sessions,
}) {
  for (final session in sessions) {
    if (session.id == sessionId) {
      return session.parentSessionId ?? sessionId;
    }
  }
  return sessionId;
}

class TeamAction extends ConsumerWidget {
  const TeamAction({
    required this.backendId,
    required this.sessionId,
    required this.onOpenMember,
    super.key,
  });

  final String backendId;

  /// The conversation on screen; a teammate row for it is inert.
  final String sessionId;

  /// Opens a member's conversation: the Lead directly, a teammate through the
  /// addressed child route.
  final void Function(String leadSessionId, TeamMember member) onOpenMember;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions =
        ref.watch(chatUiStateProvider(backendId)).value?.sessions ??
        const <SessionSummary>[];
    final leadSessionId = teamLeadSessionId(
      sessionId: sessionId,
      sessions: sessions,
    );
    final team = ref.watch(agentTeamProvider((backendId, leadSessionId))).value;
    if (team == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(kShapeDock),
      onTap: () => _open(context, ref, team, leadSessionId, sessions),
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.groups_outlined, size: 16, color: scheme.primary),
            const SizedBox(width: 4),
            Text(
              '${team.members.length}',
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  void _open(
    BuildContext context,
    WidgetRef ref,
    AgentTeam team,
    String leadSessionId,
    List<SessionSummary> sessions,
  ) {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) => TeamPanel(
          team: team,
          currentSessionId: sessionId,
          leadSessionId: leadSessionId,
          runningBySession: <String, bool>{
            for (final session in sessions) session.id: session.running,
          },
          onOpenMember: (member) {
            Navigator.of(sheetContext).pop();
            onOpenMember(leadSessionId, member);
          },
        ),
      ),
    );
  }
}

/// Tooltip label for the header action, kept here so a compact header can
/// still name the control.
String teamActionTooltip(AppLocalizations l10n) => l10n.teamPanelTitle;
