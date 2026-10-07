/// Transient action-notice vocabulary — what an action's settled outcome
/// tells the user, raised from a controller and shown by the app root.
///
/// The model carries facts only: the kind, the backend that owns the action
/// (the undo of an archive must reach that host), the session when one is
/// involved, and the Host's own line for a refused New Session. User-facing
/// copy is composed in the rendering layer ([session_notice_host.dart]
/// localizes through `AppLocalizations`), the same split the notification
/// vocabulary uses.
library;

import 'package:domain/model/session_archive.dart';

/// What happened that the user should be told about, briefly.
enum SessionNoticeKind {
  /// A quiet session was archived; the notice carries the undo.
  archived,

  /// The user confirmed stopping a session's running work; the archive is
  /// durable and the stopped work will not resume. The notice carries the
  /// undo.
  stoppedAndArchived,

  /// The user asked to open a row the archived filter is showing: archived
  /// sessions are not openable, so the notice explains instead.
  archiveNotOpenable,

  /// Archiving failed for a reason other than the running-work refusal
  /// (transport, permission, a store fault).
  archiveFailed,

  /// An explicit New Session request was refused.
  createFailed,

  /// A plugin-roster refresh failed while the user was on the Plugins page;
  /// the notice outlives that page.
  pluginRefreshFailed,
}

/// One notice: the fact plus whatever the rendering layer needs to phrase it.
final class SessionNotice {
  const SessionNotice({
    required this.kind,
    required this.backendId,
    this.sessionId,
    this.code,
    this.message,
  });

  /// The settled outcome.
  final SessionNoticeKind kind;

  /// The backend whose controller raised the notice; the undo action
  /// dispatches unarchive there.
  final String backendId;

  /// The session the outcome belongs to, when one is involved.
  final String? sessionId;

  /// The Host's stable refusal code for [SessionNoticeKind.createFailed];
  /// null elsewhere.
  final String? code;

  /// The Host's own message for [SessionNoticeKind.createFailed] (already
  /// `code: message` for a refusal); null elsewhere.
  final String? message;
}

/// A pending "stop and archive" confirmation: the Host refused to archive a
/// session that still runs work, and [activity] is what it named.
final class SessionArchiveRequest {
  const SessionArchiveRequest({
    required this.backendId,
    required this.sessionId,
    required this.displayTitle,
    required this.activity,
  });

  /// The backend the session lives on; the confirmation archives there.
  final String backendId;

  /// The session the user tried to archive.
  final String sessionId;

  /// The row's display title, named in the confirmation's body.
  final String displayTitle;

  /// The running work the Host reported, in its provider order.
  final List<SessionActivityEntry> activity;
}
