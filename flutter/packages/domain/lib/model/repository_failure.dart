/// A Host refusal carried as its stable code plus the Host's own message.
library;

/// One business failure a repository call reports: the wire error code the
/// Host sent and its message, with nothing of the transport in between.
///
/// The reference's notices quote a refusal in exactly this shape —
/// `code: message`, the stable code kept in the copy so a report stays
/// searchable — so [toString] is that line and a surface may show it
/// verbatim. A caller that must branch on one refusal reads [code] instead of
/// sniffing a formatted exception.
final class RepositoryFailure implements Exception {
  const RepositoryFailure(this.code, this.message);

  /// The Host's stable error code (dsh `RpcError.code`).
  final String code;

  /// The Host's message for this failure.
  final String message;

  @override
  String toString() => '$code: $message';
}
