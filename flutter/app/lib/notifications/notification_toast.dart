/// Foreground notification toast — a transient, tappable banner that rides
/// the app root's top overlay. It presents one [AppNotificationEvent] as
/// localized copy and, on tap, hands the event to a navigation callback so
/// the user jumps to the session that produced it.
///
/// Rendering-only: the copy resolves through `AppLocalizations` here; the
/// event carries facts. The owner (AppRoot) decides what to show next and
/// when to unmount.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../ui/theme/deepsuite_extension.dart' show dsOf;
import 'notification_events.dart';

/// Resolves one event to its localized title/body pair.
({String title, String body}) notificationCopy(
  AppNotificationEvent event,
  AppLocalizations l10n,
) => switch (event.kind) {
  AppNotificationKind.selectedTurnComplete => (
    title: l10n.turnCompleteTitle,
    body: event.sessionTitle,
  ),
  AppNotificationKind.otherTurnComplete => (
    title: l10n.otherTurnCompleteTitle,
    body: event.sessionTitle,
  ),
  AppNotificationKind.approvalRequested => (
    title: l10n.approvalRequestedTitle,
    body: event.sessionTitle,
  ),
  AppNotificationKind.planReviewRequested => (
    title: l10n.planReviewRequestedTitle,
    body: event.sessionTitle,
  ),
};

/// Leading glyph per event kind.
IconData notificationIcon(AppNotificationKind kind) => switch (kind) {
  AppNotificationKind.selectedTurnComplete => Icons.check_circle_outline,
  AppNotificationKind.otherTurnComplete => Icons.mark_chat_unread_outlined,
  AppNotificationKind.approvalRequested => Icons.verified_user_outlined,
  AppNotificationKind.planReviewRequested => Icons.rule_outlined,
};

/// A top-anchored tappable banner. [onTap] receives the event so the owner
/// can navigate; [onDismiss] unmounts the banner.
class NotificationToast extends StatelessWidget {
  const NotificationToast({
    super.key,
    required this.event,
    required this.onTap,
    required this.onDismiss,
  });

  final AppNotificationEvent event;
  final void Function(AppNotificationEvent event) onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ds = dsOf(context);
    final copy = notificationCopy(event, l10n);
    return Material(
      color: Colors.transparent,
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Material(
          elevation: 6,
          color: ds.menu,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onTap(event),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              child: Row(
                children: [
                  Icon(notificationIcon(event.kind), color: ds.brandText),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          copy.title,
                          style: Theme.of(context).textTheme.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          copy.body,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: ds.labelSecondary),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    color: ds.labelSecondary,
                    tooltip: l10n.notificationDismissTooltip,
                    onPressed: onDismiss,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
