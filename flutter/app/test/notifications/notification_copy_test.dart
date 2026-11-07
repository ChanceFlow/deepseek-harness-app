/// The one copy rule: result in the title, the subject (quoted session, then
/// workspace, then host) in the body — identical for both surfaces.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:app/notifications/notification_copy.dart';
import 'package:app/notifications/notification_events.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final AppLocalizations _en = lookupAppLocalizations(const Locale('en'));
final AppLocalizations _zh = lookupAppLocalizations(const Locale('zh'));

AppNotificationEvent _event({
  AppNotificationKind kind = AppNotificationKind.otherTurnComplete,
  String? context,
  String? host,
}) => AppNotificationEvent(
  kind: kind,
  backendId: 'b1',
  sessionId: 's1',
  sessionTitle: 'Login refactor',
  sessionContext: context,
  hostLabel: host,
);

void main() {
  test('a finished turn reads as a new reply, not a completed session', () {
    final copy = notificationCopy(_event(), _en);
    expect(copy.title, 'New reply');
    expect(copy.body, '“Login refactor”');
  });

  test('the body names the host when the registry resolved one', () {
    final copy = notificationCopy(_event(host: 'Build box'), _en);
    expect(copy.body, '“Login refactor” · Build box');
  });

  test('the body orders session, workspace, host and omits empty segments', () {
    final copy = notificationCopy(
      _event(context: 'proj-a', host: 'Build box'),
      _en,
    );
    expect(copy.body, '“Login refactor” · proj-a · Build box');
    expect(
      notificationCopy(_event(context: '', host: ''), _en).body,
      '“Login refactor”',
    );
  });

  test('both completion kinds share one wording', () {
    expect(
      notificationCopy(
        _event(kind: AppNotificationKind.selectedTurnComplete),
        _en,
      ).title,
      notificationCopy(_event(), _en).title,
    );
  });

  test('pending interactions keep their own titles', () {
    expect(
      notificationCopy(
        _event(kind: AppNotificationKind.approvalRequested),
        _en,
      ).title,
      'Approval needed',
    );
    expect(
      notificationCopy(
        _event(kind: AppNotificationKind.planReviewRequested),
        _en,
      ).title,
      'Plan ready',
    );
  });

  test('a reply preview rides under the subject for a finished reply', () {
    final copy = notificationCopy(
      const AppNotificationEvent(
        kind: AppNotificationKind.otherTurnComplete,
        backendId: 'b1',
        sessionId: 's1',
        sessionTitle: 'Login refactor',
        replyPreview: 'The login page is wired up',
      ),
      _en,
    );
    expect(copy.body, '“Login refactor”\nThe login page is wired up');
  });

  test('a failed turn shows no preview even if one was read', () {
    final copy = notificationCopy(
      const AppNotificationEvent(
        kind: AppNotificationKind.turnFailed,
        backendId: 'b1',
        sessionId: 's1',
        sessionTitle: 'Login refactor',
        replyPreview: 'half an answer',
      ),
      _en,
    );
    expect(copy.title, 'Reply failed');
    expect(copy.body, '“Login refactor”');
  });

  test('Chinese copy quotes with 「」 and says 有新回复', () {
    final copy = notificationCopy(_event(host: '构建机'), _zh);
    expect(copy.title, '有新回复');
    expect(copy.body, '「Login refactor」 · 构建机');
  });
}
