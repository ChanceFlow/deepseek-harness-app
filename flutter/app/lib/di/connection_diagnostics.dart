/// The shared throttle behind the app's two connection-diagnostics sinks.
///
/// `backendConnectionProvider` (the connection manager's transport
/// diagnostics) and `chatRepositoryProvider` (the repository's adapter
/// diagnostics) both see the same failure once per reconnect attempt. One
/// [ConnectionDiagnosticLog] is built per sink; it keeps the breadcrumb
/// evidence complete and folds only the persisted entry:
///
/// - Every diagnostic appends its breadcrumb line exactly as before, at every
///   level and however often it repeats, so the bounded breadcrumb ring keeps
///   the attempt history.
/// - A diagnostic is captured when it is an error, or a warning carrying an
///   error. The first occurrence in a 60 s window is stored unchanged; later
///   occurrences of the same fact inside that window are only counted; the
///   first occurrence after the window stores one entry with
///   ` (N repeats suppressed)` appended to its message and
///   `suppressedRepeats` in its context.
/// - The gate key is backend id + diagnostic context + whitespace-normalized
///   message + the captured error's runtime type, so two distinct failures
///   never share a suppression count. Only whitespace is normalized: a
///   message differing in a meaningful token (an address, a status code)
///   stays distinct.
/// - Telemetry logging stays unconditional, so the debug stream still shows
///   every attempt even when the persisted entry is folded.
///
/// The manager and repository behavior is untouched: this seam observes their
/// diagnostics; it never suppresses a reconnect, retry, or rejection.
library;

import 'package:harness_adapter/harness_adapter.dart';

import '../logging/error_log_collector.dart';
import '../logging/error_log_entry.dart';

/// The adapter severity under an app-side name, so this seam and its tests
/// speak one level vocabulary without the adapter import in test code.
typedef ConnectionDiagnosticLevel = AdapterDiagnosticLevel;

/// Forwards one diagnostic to `DebugTelemetry`; [level] is `error` or `warn`,
/// mirroring the per-level mapping the sinks applied before this seam.
typedef ConnectionDiagnosticTelemetry = void Function(
  String message, {
  required String level,
});

/// Records one sink's connection diagnostics into the on-device error log.
///
/// See the library comment for the folding contract. Construct one per sink:
/// each instance owns its own gate, so two sinks never share a suppression
/// count.
final class ConnectionDiagnosticLog {
  ConnectionDiagnosticLog({
    required this.source,
    ErrorLogCollector? collector,
    DateTime Function()? now,
    Duration window = const Duration(seconds: 60),
    this.telemetry,
  }) : _collector = collector ?? ErrorLogCollector.instance,
       _gate = DiagnosticGate(now: now, window: window);

  /// The sink's label: `Connection` for the manager's transport diagnostics,
  /// `Adapter` for the repository's. Breadcrumbs read `[<source> <LEVEL>] ...`
  /// and telemetry falls back to the lower-cased source when the diagnostic
  /// carries no context.
  final String source;

  final ErrorLogCollector _collector;
  final DiagnosticGate _gate;

  /// Optional debug telemetry sink; production passes one so every diagnostic
  /// reaches it, suppressed or not.
  final ConnectionDiagnosticTelemetry? telemetry;

  /// Records one diagnostic.
  ///
  /// The breadcrumb and telemetry always run. The gate is consulted only for
  /// the captures the sinks persist (error, and warning-with-error); when it
  /// withholds this occurrence, [ErrorLogCollector.entries] gains nothing and
  /// the occurrence joins the next recap's count.
  void record({
    required String backendId,
    required String message,
    required ConnectionDiagnosticLevel level,
    String? uri,
    String? context,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final String levelName = level.name;
    _collector.addBreadcrumb(
      '[$source ${levelName.toUpperCase()}] ${context ?? ""}: $message',
      level: levelName,
    );
    telemetry?.call(
      '${context ?? source.toLowerCase()}: $message',
      level: level == ConnectionDiagnosticLevel.error ? 'error' : 'warn',
    );

    final bool captures =
        level == ConnectionDiagnosticLevel.error ||
        (level == ConnectionDiagnosticLevel.warning && error != null);
    if (!captures) return;

    // The entry carries the error's own text and runtime type, exactly as the
    // pre-gate capture did; `error == null` captures the message string.
    final Object captured = error ?? message;
    final int? suppressed = _gate.admit(
      <String>[
        backendId,
        context ?? '',
        _normalize(message),
        _captureType(captured),
      ].join('\u0000'),
    );
    if (suppressed == null) return;

    final Map<String, Object?> entryContext = <String, Object?>{
      'backendId': backendId,
      if (uri != null) 'uri': uri,
      'diagnostic_context': context,
      // Only the warning-with-error branch recorded the raw diagnostic message
      // historically; the error branch's entry message is the error's text.
      if (level == ConnectionDiagnosticLevel.warning)
        'diagnostic_message': message,
      ...metadata,
      if (suppressed > 0) 'suppressedRepeats': suppressed,
    };
    final Object entryMessage = suppressed > 0
        ? '$captured ($suppressed repeats suppressed)'
        : captured;
    _collector.captureError(
      entryMessage,
      stackTrace: stackTrace,
      level: level == ConnectionDiagnosticLevel.error
          ? ErrorLogLevel.error
          : ErrorLogLevel.warning,
      type: _captureType(captured),
      context: entryContext,
    );
  }
}

/// The runtime type the collector would name this capture by, kept explicit so
/// a recap's message rewrite does not change the entry's `type`.
String _captureType(Object captured) => captured.runtimeType.toString();

final RegExp _whitespace = RegExp(r'\s+');

/// Collapses whitespace runs and trims, so a message that only differs in line
/// wrapping or padding folds into the same gate key. No other part is
/// stripped: a differing address, code, or count stays a distinct failure.
String _normalize(String message) =>
    message.trim().replaceAll(_whitespace, ' ');
