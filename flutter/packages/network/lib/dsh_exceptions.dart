/// Transport exceptions mapped from wire failures.
library;

import 'rpc_envelope.dart' show JsonMap;

/// Transport-level failure: HTTP error, invalid envelope, socket loss.
class DshTransportException implements Exception {
  DshTransportException(this.message, [this.cause]);

  final String message;
  final Object? cause;

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
