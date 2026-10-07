/// The archive and unarchive verbs both browsing surfaces share.
///
/// One home for the wire calls and the outcome mapping: a quiet archive
/// raises the archived notice, a Host refusal over running work asks the app
/// root for the stop-and-archive confirmation (its wording is the reference's
/// own two-step flow), and any other failure reads as a plain archive
/// failure. The flow logs what it swallows, so a failed archive or undo still
/// reaches the error log; this object only decides what the user is told.
library;

import 'package:domain/model/session_archive.dart';
import 'package:domain/repository/chat_repository.dart';

import '../../logging/error_log_collector.dart';
import '../../notifications/session_notice_center.dart';

final class SessionArchiveFlow {
  const SessionArchiveFlow({required this.repository, this.notices});

  final ChatRepository repository;

  /// The notice seat; null in a bare controller (a test double that only
  /// exercises the wire call), where an outcome is logged and nothing is
  /// shown.
  final SessionNoticeSink? notices;

  /// Archives one session without stopping anything.
  ///
  /// [displayTitle] names the row in the confirmation body, so the user can
  /// tell which session still runs work when the request arrives after a
  /// surface change.
  Future<void> archive({
    required String sessionId,
    required String displayTitle,
  }) async {
    try {
      await repository.archiveSession(sessionId);
      notices?.archived(sessionId);
    } on SessionArchiveRefused catch (refused) {
      // The expected refusal: the Host named the work that must stop. Not an
      // error — the confirmation is how the user answers it.
      notices?.requestArchiveConfirm(
        sessionId: sessionId,
        displayTitle: displayTitle,
        activity: refused.activity,
      );
    } catch (error, stackTrace) {
      notices?.archiveFailed();
      ErrorLogCollector.instance.captureError(
        error,
        stackTrace: stackTrace,
        context: const <String, Object?>{
          'controller': 'SessionArchiveFlow',
          'action': 'archive',
        },
      );
    }
  }

  /// Restores one archived session. Silent on success — the row returning is
  /// the feedback — and a failure is logged only, matching the reference's
  /// undo path.
  Future<void> unarchive(String sessionId) async {
    try {
      await repository.unarchiveSession(sessionId);
    } catch (error, stackTrace) {
      ErrorLogCollector.instance.captureError(
        error,
        stackTrace: stackTrace,
        context: const <String, Object?>{
          'controller': 'SessionArchiveFlow',
          'action': 'unarchive',
        },
      );
    }
  }
}
