/// The one place notification copy is composed.
///
/// Both the in-app banner and the system notification call these helpers, so
/// the two surfaces cannot drift apart. The rule is result first, then the
/// subject: the title says what the user gained ("New reply"), the body names
/// the session and the host that produced it.
library;

import 'package:app/l10n/app_localizations.dart';

import 'notification_events.dart';

/// Title and body for one transient [event].
({String title, String body}) notificationCopy(
  AppNotificationEvent event,
  AppLocalizations l10n,
) => (
  title: switch (event.kind) {
    AppNotificationKind.selectedTurnComplete ||
    AppNotificationKind.otherTurnComplete => l10n.turnCompleteTitle,
    AppNotificationKind.turnFailed => l10n.notificationFailedTitle,
    AppNotificationKind.turnStopped => l10n.notificationStoppedTitle,
    AppNotificationKind.approvalRequested => l10n.approvalRequestedTitle,
    AppNotificationKind.planReviewRequested => l10n.planReviewRequestedTitle,
  },
  body: _body(event, l10n),
);

/// The subject line plus the reply's opening line when the completion probe
/// read one. A preview only ever accompanies a finished reply: a failed or
/// stopped turn has none to show.
String _body(AppNotificationEvent event, AppLocalizations l10n) {
  final subject = notificationBodyLine(
    l10n: l10n,
    sessionTitle: event.sessionTitle,
    sessionContext: event.sessionContext,
    hostLabel: event.hostLabel,
  );
  final preview = event.replyPreview;
  if (preview == null || preview.isEmpty) return subject;
  if (event.kind == AppNotificationKind.turnFailed ||
      event.kind == AppNotificationKind.turnStopped) {
    return subject;
  }
  return '$subject\n$preview';
}

/// The body every notification carries: the quoted session title plus the
/// disambiguators that actually add information.
///
/// [sessionContext] is the workspace label the host supplied; [hostLabel] is
/// the registry's name for the backend. Each is omitted when absent rather
/// than rendering an empty segment.
String notificationBodyLine({
  required AppLocalizations l10n,
  required String sessionTitle,
  String? sessionContext,
  String? hostLabel,
}) {
  final parts = <String>[
    l10n.notificationSubject(sessionTitle),
    if (sessionContext != null && sessionContext.isNotEmpty) sessionContext,
    if (hostLabel != null && hostLabel.isNotEmpty) hostLabel,
  ];
  return parts.join(' · ');
}
