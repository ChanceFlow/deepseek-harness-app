/// Presentation of one [SessionNotice]: the localized sentence, whether it
/// offers the archive undo, and the [SnackBar] that carries it.
///
/// Rendering-only: the notice is a fact ([session_notice.dart]) and the copy
/// resolves through `AppLocalizations` here, so the controllers that raise
/// notices stay free of UI vocabulary. The archive notices hold longer than
/// the rest — they carry an action the user must have time to reach.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import 'session_notice.dart';

/// Hold for the notices that carry the archive undo; the rest use the
/// [SnackBar] default.
const Duration kArchiveNoticeHold = Duration(seconds: 6);

/// The Host's refusal code for a session another process or CLI already
/// owns; the one create refusal with specific copy.
const String kSessionAlreadyOwnedCode = 'session-persistence/already-owned';

/// One notice's rendered copy and whether it offers the undo.
typedef SessionNoticeCopy = ({String text, bool undo});

/// Maps one notice to its localized sentence.
SessionNoticeCopy sessionNoticeCopy(
  AppLocalizations l10n,
  SessionNotice notice,
) => switch (notice.kind) {
  SessionNoticeKind.archived => (text: l10n.archiveNoticeArchived, undo: true),
  SessionNoticeKind.stoppedAndArchived => (
    text: l10n.archiveNoticeStopped,
    undo: true,
  ),
  SessionNoticeKind.archiveNotOpenable => (
    text: l10n.archiveNotOpenableNotice,
    undo: false,
  ),
  SessionNoticeKind.archiveFailed => (
    text: l10n.archiveFailedNotice,
    undo: false,
  ),
  SessionNoticeKind.createFailed => (
    text: notice.code == kSessionAlreadyOwnedCode
        ? l10n.sessionAlreadyOwnedError
        : l10n.createSessionFailedNotice(notice.message ?? ''),
    undo: false,
  ),
  SessionNoticeKind.pluginRefreshFailed => (
    text: l10n.pluginRefreshFailedNotice,
    undo: false,
  ),
};

/// Shows [notice] on the root messenger, with the archive undo action when
/// the notice carries one and [onUndo] can reach the owning host.
void showSessionNotice({
  required ScaffoldMessengerState messenger,
  required AppLocalizations l10n,
  required SessionNotice notice,
  required void Function(SessionNotice notice) onUndo,
}) {
  final copy = sessionNoticeCopy(l10n, notice);
  final sessionId = notice.sessionId;
  messenger.showSnackBar(
    SnackBar(
      content: Text(copy.text),
      duration: copy.undo
          ? kArchiveNoticeHold
          : const Duration(milliseconds: 4000),
      action: copy.undo && sessionId != null
          ? SnackBarAction(
              label: l10n.undoAction,
              onPressed: () => onUndo(notice),
            )
          : null,
    ),
  );
}
