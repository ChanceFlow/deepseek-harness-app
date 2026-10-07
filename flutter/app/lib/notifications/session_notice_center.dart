/// The app-wide transient notice seat, shared by every browsing controller.
///
/// Two streams rather than one state value: two archives of two sessions
/// produce equal-looking notices, so a state holder would compare the second
/// against the first and drop it — the user would never see it. The app root
/// subscribes and renders each arrival (the same reasoning the foreground
/// notification stream carries).
///
/// The center is app-scoped; [SessionNoticeSink] is the per-backend face a
/// controller holds, so the backend that owns an action is stamped once, at
/// the call site, instead of being threaded through every notice.
library;

import 'dart:async';

import 'package:domain/model/session_archive.dart';

import 'session_notice.dart';

/// The app-lifetime emitter for [SessionNotice]s and pending archive
/// confirmations.
class SessionNoticeCenter {
  final StreamController<SessionNotice> _notices =
      StreamController<SessionNotice>.broadcast();
  final StreamController<SessionArchiveRequest> _archiveRequests =
      StreamController<SessionArchiveRequest>.broadcast();

  /// Every notice, in arrival order; no value is replayed on listen.
  Stream<SessionNotice> get notices => _notices.stream;

  /// Every stop-and-archive confirmation request, in arrival order.
  Stream<SessionArchiveRequest> get archiveRequests => _archiveRequests.stream;

  /// Show one notice.
  void show(SessionNotice notice) {
    if (!_notices.isClosed) _notices.add(notice);
  }

  /// Ask the app root to confirm stopping a session's running work.
  void requestArchiveConfirmation(SessionArchiveRequest request) {
    if (!_archiveRequests.isClosed) _archiveRequests.add(request);
  }

  void dispose() {
    unawaited(_notices.close());
    unawaited(_archiveRequests.close());
  }
}

/// One backend's notice seat: the controllers of that backend raise notices
/// through it, and it stamps the backend on each one.
final class SessionNoticeSink {
  const SessionNoticeSink({required this.center, required this.backendId});

  final SessionNoticeCenter center;

  /// The backend every notice from this sink belongs to.
  final String backendId;

  /// A quiet session was archived.
  void archived(String sessionId) => center.show(
    SessionNotice(
      kind: SessionNoticeKind.archived,
      backendId: backendId,
      sessionId: sessionId,
    ),
  );

  /// The user's running work was stopped and the session archived.
  void stoppedAndArchived(String sessionId) => center.show(
    SessionNotice(
      kind: SessionNoticeKind.stoppedAndArchived,
      backendId: backendId,
      sessionId: sessionId,
    ),
  );

  /// The user asked to open an archived row.
  void archiveNotOpenable() => center.show(
    SessionNotice(
      kind: SessionNoticeKind.archiveNotOpenable,
      backendId: backendId,
    ),
  );

  /// Archiving failed for a reason other than the running-work refusal.
  void archiveFailed() => center.show(
    SessionNotice(kind: SessionNoticeKind.archiveFailed, backendId: backendId),
  );

  /// A New Session request was refused; [code] lets the rendering layer pick
  /// the specific copy, and [message] is the Host's own line.
  void createFailed({required String code, required String message}) =>
      center.show(
        SessionNotice(
          kind: SessionNoticeKind.createFailed,
          backendId: backendId,
          code: code,
          message: message,
        ),
      );

  /// A plugin-roster refresh failed.
  void pluginRefreshFailed() => center.show(
    SessionNotice(
      kind: SessionNoticeKind.pluginRefreshFailed,
      backendId: backendId,
    ),
  );

  /// The Host refused an archive because the session still runs work; ask
  /// the app root for the stop-and-archive confirmation.
  void requestArchiveConfirm({
    required String sessionId,
    required String displayTitle,
    required List<SessionActivityEntry> activity,
  }) => center.requestArchiveConfirmation(
    SessionArchiveRequest(
      backendId: backendId,
      sessionId: sessionId,
      displayTitle: displayTitle,
      activity: activity,
    ),
  );
}
