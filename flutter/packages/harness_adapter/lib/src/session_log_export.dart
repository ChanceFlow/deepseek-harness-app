/// The session-log download route: the dsh wire knowledge for
/// `GET /api/session.export` — path, query parameters, deadline, and the
/// filename convention — mapped onto the neutral [SessionLogExport].
///
/// The route is a plain HTTP GET outside the typert RPC envelope, so it
/// rides the network package's binary download seam rather than an RPC call.
library;

import 'package:domain/model/session_log_export.dart';
import 'package:network/dsh_download_client.dart';

import 'rpc_map.dart';

/// Deadline for one archive download.
///
/// Deliberately long, and deliberately not unbounded. A session tree's log
/// with its attachments is orders of magnitude larger than any unary RPC,
/// so the adapter's short 30 s unary deadline would kill legitimate exports
/// over a slow link; leaving it unbounded would leave a wedged host with a
/// spinner forever. Five minutes covers a multi-hundred-megabyte archive on
/// a slow mobile link while still settling.
const Duration kSessionLogExportTimeout = Duration(minutes: 5);

/// One requested archive's query parameters. The host rejects a missing or
/// empty `sessionId` with 400 and any `includeDescendants` other than
/// `'true'`/`'false'` with 400, so the client only ever sends those two
/// spellings: `true` when the whole subtree is wanted, and the parameter
/// omitted otherwise (absent is the host's `false`).
Map<String, String> sessionLogExportQuery(
  String sessionId, {
  required bool includeDescendants,
}) => <String, String>{
  'sessionId': sessionId,
  if (includeDescendants) 'includeDescendants': 'true',
};

/// Collapse an untrusted session id into the download filename, mirroring
/// the host's own convention
/// (`reference/deepseek-harness/packages/session-query/session-log-export/src/archive.ts`
/// `sessionLogZipFilename`): everything outside `[A-Za-z0-9_-]` becomes an
/// underscore, so a hostile id can never steer the file outside the
/// directory the platform layer writes to.
String sessionLogZipFilename(String sessionId) =>
    'dsh-session-${sessionId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.zip';

/// Reads the session-log archive for one session tree.
final class SessionLogExportClient {
  const SessionLogExportClient(this._downloads);

  final DshDownloadClient _downloads;

  /// Downloads [sessionId]'s archive and returns it under its filename.
  ///
  /// [includeDescendants] selects the whole subtree (the reference client
  /// always asks for it). The archive is returned whole; a non-2xx status,
  /// a deadline overrun, or a truncated body throws the download seam's
  /// `DshTransportException`.
  Future<SessionLogExport> fetch(
    String sessionId, {
    bool includeDescendants = true,
  }) async {
    final path = Uri(
      path: DshHttpRoutes.sessionLogExport,
      queryParameters: sessionLogExportQuery(
        sessionId,
        includeDescendants: includeDescendants,
      ),
    ).toString();
    final download = await _downloads.download(
      path,
      timeout: kSessionLogExportTimeout,
    );
    return SessionLogExport(
      filename: sessionLogZipFilename(sessionId),
      bytes: download.bytes,
    );
  }
}
