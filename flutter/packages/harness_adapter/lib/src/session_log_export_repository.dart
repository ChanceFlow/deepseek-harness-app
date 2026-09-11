/// The dsh implementation of the session-log archive seam.
///
/// The route is a plain HTTP GET outside the typert RPC envelope, so it
/// needs none of the wire repository's connection state: this class holds
/// the binary download seam, and [SessionLogExportClient] owns every dsh
/// wire fact (path, query, filename).
library;

import 'package:domain/model/session_log_export.dart';
import 'package:domain/repository/session_log_export_repository.dart';
import 'package:network/dsh_download_client.dart';

import 'session_log_export.dart';

final class DshSessionLogExportRepository
    implements SessionLogExportRepository {
  const DshSessionLogExportRepository(this._downloads);

  final DshDownloadClient _downloads;

  @override
  Future<SessionLogExport> exportSessionLog(
    String sessionId, {
    bool includeDescendants = true,
  }) =>
      SessionLogExportClient(_downloads)
          .fetch(sessionId, includeDescendants: includeDescendants);
}
