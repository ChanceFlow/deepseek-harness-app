/// The session-log archive contract, separate from [ChatRepository].
///
/// It is a second seam rather than a member of [ChatRepository] because the
/// wire implementation declares `implements ChatRepository`: in Dart every
/// interface member must be implemented by that class, so widening
/// [ChatRepository] buys nothing here — the download route is not an RPC and
/// needs none of the repository's connection state.
///
/// Implementations live behind the harness adapter. UI and controller code
/// must never import a dsh-specific implementation or type.
library;

import '../model/session_log_export.dart';

abstract class SessionLogExportRepository {
  /// Download one session's log archive — `session.jsonl`, every descendant
  /// session, and every referenced attachment, as one ZIP.
  ///
  /// [includeDescendants] selects the whole subtree (the reference client
  /// always asks for it).
  ///
  /// The archive is returned whole: it is bounded by one session tree's log,
  /// not by a stream that could outlive the call. Writing it somewhere the
  /// user can reach is the platform layer's job — this contract carries
  /// bytes and the host's suggested filename only.
  Future<SessionLogExport> exportSessionLog(
    String sessionId, {
    bool includeDescendants = true,
  });
}
