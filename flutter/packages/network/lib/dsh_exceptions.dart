/// Transport exceptions mapped from wire failures.
library;

import 'rpc_envelope.dart' show JsonMap;

/// Transport-level failure: HTTP error, invalid envelope, socket loss.
class DshTransportException implements Exception {
  DshTransportException(this.message, [this.cause]) : httpStatus = null;

  /// A non-2xx HTTP response the transport refused.
  ///
  /// The status is the response's own fact, so it travels as a field: a caller
  /// that classifies the failure (the settings reachability probe) reads
  /// [httpStatus] instead of scraping `HTTP <status>` back out of [message],
  /// which stays a human-readable string for a log or a crash report.
  DshTransportException.http(this.message, int status, [this.cause])
    : httpStatus = status;

  final String message;
  final Object? cause;

  /// The HTTP status the transport read, when the failure was a response
  /// rather than a socket, TLS, or deadline failure; null otherwise.
  final int? httpStatus;

  @override
  String toString() => cause == null
      ? 'DshTransportException: $message'
      : 'DshTransportException: $message ($cause)';
}

/// Business-level failure carried by an `ok == false` RPC result.
class DshBusinessException implements Exception {
  DshBusinessException({
    required this.code,
    required this.message,
    this.details,
  });

  final String code;
  final String message;
  final JsonMap? details;

  @override
  String toString() => details == null
      ? 'DshBusinessException: $code: $message'
      : 'DshBusinessException: $code: $message (details: $details)';
}
