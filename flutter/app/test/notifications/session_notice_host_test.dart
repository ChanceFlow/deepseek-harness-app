/// Session-notice copy tests: the mapping from a controller-raised fact to
/// the sentence the root shows, and which notices carry the archive undo.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:app/notifications/session_notice.dart';
import 'package:app/notifications/session_notice_host.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  SessionNotice notice(
    SessionNoticeKind kind, {
    String? code,
    String? message,
    String? sessionId = 's1',
  }) => SessionNotice(
    kind: kind,
    backendId: 'b1',
    sessionId: sessionId,
    code: code,
    message: message,
  );

  test('the archive notices offer the undo; the rest do not', () {
    expect(sessionNoticeCopy(en, notice(SessionNoticeKind.archived)), (
      text: en.archiveNoticeArchived,
      undo: true,
    ));
    expect(
      sessionNoticeCopy(en, notice(SessionNoticeKind.stoppedAndArchived)),
      (text: en.archiveNoticeStopped, undo: true),
    );
    for (final kind in <SessionNoticeKind>[
      SessionNoticeKind.archiveNotOpenable,
      SessionNoticeKind.archiveFailed,
      SessionNoticeKind.pluginRefreshFailed,
    ]) {
      expect(
        sessionNoticeCopy(en, notice(kind)).undo,
        isFalse,
        reason: '$kind',
      );
    }
  });

  test('an already-owned create quotes the specific copy, not the message', () {
    expect(
      sessionNoticeCopy(
        en,
        notice(
          SessionNoticeKind.createFailed,
          code: kSessionAlreadyOwnedCode,
          message: 'locked by another client',
        ),
      ).text,
      en.sessionAlreadyOwnedError,
    );
  });

  test('any other create refusal states the Host line', () {
    expect(
      sessionNoticeCopy(
        en,
        notice(
          SessionNoticeKind.createFailed,
          code: 'internal',
          message: 'internal: the host refused',
        ),
      ).text,
      en.createSessionFailedNotice('internal: the host refused'),
    );
  });

  test(
    'a failed archive names itself, and the not-openable notice explains',
    () {
      expect(
        sessionNoticeCopy(en, notice(SessionNoticeKind.archiveFailed)).text,
        en.archiveFailedNotice,
      );
      expect(
        sessionNoticeCopy(
          en,
          notice(SessionNoticeKind.archiveNotOpenable),
        ).text,
        en.archiveNotOpenableNotice,
      );
    },
  );
}
