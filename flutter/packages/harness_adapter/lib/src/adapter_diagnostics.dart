/// Pure-Dart diagnostic types for reporting adapter anomalies, frame fallthroughs,
/// and decode errors to outer layers without violating package boundaries.
library;

enum AdapterDiagnosticLevel { debug, info, warning, error }

final class AdapterDiagnostic {
  const AdapterDiagnostic({
    required this.message,
    this.level = AdapterDiagnosticLevel.warning,
    this.context,
    this.error,
    this.stackTrace,
    this.metadata = const <String, Object?>{},
  });

  final String message;
  final AdapterDiagnosticLevel level;
  final String? context;
  final Object? error;
  final StackTrace? stackTrace;
  final Map<String, Object?> metadata;

  @override
  String toString() =>
      'AdapterDiagnostic($level, context: $context, message: $message, error: $error)';
}

typedef AdapterDiagnosticListener = void Function(AdapterDiagnostic diagnostic);
