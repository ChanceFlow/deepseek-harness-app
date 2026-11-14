/// Process-exit attribution for the in-app error log.
///
/// Android 11+ (API 30) keeps the last few `ApplicationExitInfo` records: why
/// this process last died, when, and the system's description. A WebView
/// renderer death can kill the app without a Dart error ever being raised, and
/// Android's own reporting does not surface every such kill, so this history
/// is the only on-device evidence that the previous run ended abnormally.
/// `DiagnosticsBridge.kt` owns the platform side (`dsh/diagnostics`); this file
/// decodes its answer, filters the exits that were deliberate, and records the
/// newest unreported abnormal one through [ErrorLogCollector]. It also asks the
/// same channel for that exit's bounded system trace (the ANR or crash stack),
/// so the next report explains a death that never reached the Dart layer.
///
/// Every call is non-throwing: a host without the channel (widget tests,
/// desktop, API < 30) answers with no records and no trace, and startup
/// proceeds unchanged.
library;

import 'package:flutter/services.dart';

import 'error_log_collector.dart';
import 'error_log_entry.dart';

/// Method channel name; must match `DiagnosticsBridge.kt`.
const String kDiagnosticsChannel = 'dsh/diagnostics';

/// The `type` prefix that marks an [ErrorLogEntry] as a process-exit record.
const String kProcessExitTypePrefix = 'process-exit:';

/// One entry from `ActivityManager.getHistoricalProcessExitReasons`.
class ProcessExitReason {
  const ProcessExitReason({
    required this.timestamp,
    required this.reason,
    required this.description,
    required this.importance,
    required this.status,
    required this.processName,
    this.pid,
    this.hasTrace = false,
  });

  /// When the process died, in UTC; epoch zero when the platform sent no
  /// usable timestamp.
  final DateTime timestamp;

  /// The `ApplicationExitInfo` reason constant.
  final int reason;

  /// The system's description of the exit, when it has one.
  final String? description;

  /// The process's importance immediately before it died.
  final int importance;

  /// The exit status (`ApplicationExitInfo.getStatus`).
  final int status;

  /// The dead process's name, when the system records one.
  final String? processName;

  /// The dead process's pid, when the platform reports one.
  ///
  /// Together with [timestamp] it identifies the record the trace read must
  /// match; null when the record predates the field or the answer omitted it.
  final int? pid;

  /// Whether the platform reports a readable trace stream for this record.
  ///
  /// False below API 30, for an exit with no trace, or when the stream cannot
  /// be opened. Only a true value makes [recordProcessExitReasons] ask for the
  /// trace at all.
  final bool hasTrace;

  /// Decodes one platform map tolerantly.
  ///
  /// This seam is best-effort diagnostic evidence, not a wire contract: a
  /// missing or mistyped field becomes zero/null instead of throwing, so one
  /// malformed record never discards the usable records beside it.
  factory ProcessExitReason.fromMap(Map<Object?, Object?> map) {
    final Object? rawTimestamp = map['timestamp'];
    final Object? rawReason = map['reason'];
    final Object? rawDescription = map['description'];
    final Object? rawImportance = map['importance'];
    final Object? rawStatus = map['status'];
    final Object? rawProcessName = map['processName'];
    final Object? rawPid = map['pid'];
    final Object? rawHasTrace = map['hasTrace'];
    return ProcessExitReason(
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        rawTimestamp is int ? rawTimestamp : 0,
        isUtc: true,
      ),
      reason: rawReason is int ? rawReason : 0,
      description: rawDescription is String ? rawDescription : null,
      importance: rawImportance is int ? rawImportance : 0,
      status: rawStatus is int ? rawStatus : 0,
      processName: rawProcessName is String ? rawProcessName : null,
      pid: rawPid is int ? rawPid : null,
      hasTrace: rawHasTrace is bool ? rawHasTrace : false,
    );
  }
}

/// The name of an `ApplicationExitInfo` reason constant.
///
/// An unknown constant keeps its number (`reason-<n>`) rather than guessing a
/// meaning; the vocabulary covers every constant Android 16 defines.
String processExitReasonName(int reason) => switch (reason) {
  0 => 'unknown',
  1 => 'exit-self',
  2 => 'signaled',
  3 => 'low-memory',
  4 => 'crash',
  5 => 'crash-native',
  6 => 'anr',
  7 => 'initialization-failure',
  8 => 'permission-change',
  9 => 'excessive-resource-usage',
  10 => 'user-requested',
  11 => 'user-stopped',
  12 => 'dependency-died',
  13 => 'other',
  14 => 'freezer',
  15 => 'package-state-change',
  16 => 'package-updated',
  _ => 'reason-$reason',
};

/// Whether [exit] is a death the user or the system did not ask for.
///
/// Exit-self (1), user-requested (10), user-stopped (11),
/// package-state-change (15) and package-updated (16) are deliberate: the app,
/// the user, or an install/update ended the process, so recording them would
/// fill the log with expected shutdowns. Every other reason — a crash, a
/// low-memory kill, an ANR, a native crash — is abnormal and worth a record.
bool isAbnormalExit(ProcessExitReason exit) => switch (exit.reason) {
  1 || 10 || 11 || 15 || 16 => false,
  _ => true,
};

/// The log level for a recorded exit.
///
/// A low-memory kill, a signal, and the catch-all "other" are warnings: the
/// process was ended from outside, not necessarily broken. A native crash, an
/// ANR, and an initialization failure are fatal: the process died before the
/// Dart layer could report anything. The remaining reasons are errors.
ErrorLogLevel exitReasonLevel(int reason) => switch (reason) {
  2 || 3 || 13 => ErrorLogLevel.warning,
  5 || 6 || 7 => ErrorLogLevel.fatal,
  _ => ErrorLogLevel.error,
};

/// Reads the platform's process-exit history, newest first.
///
/// No channel (tests, desktop, an Android build without the bridge) or a
/// platform error answers with no records: the history is optional diagnostic
/// evidence, so its absence never fails startup.
Future<List<ProcessExitReason>> readProcessExitReasons() async {
  try {
    final List<Object?>? raw = await const MethodChannel(kDiagnosticsChannel)
        .invokeMethod<List<Object?>>('lastExitReasons');
    if (raw == null) return const <ProcessExitReason>[];
    return <ProcessExitReason>[
      for (final Object? item in raw)
        if (item is Map<Object?, Object?>) ProcessExitReason.fromMap(item),
    ];
  } on PlatformException {
    return const <ProcessExitReason>[];
  } on MissingPluginException {
    return const <ProcessExitReason>[];
  }
}

/// Deadline for one trace read. The platform worker normally answers in
/// milliseconds; a binder call that never returns would otherwise hold the
/// exit record itself hostage, because the record is written after the read.
/// On timeout the exit is still recorded, without a trace.
const Duration kExitTraceTimeout = Duration(seconds: 3);

/// Reads the bounded system trace belonging to [exit], or null.
///
/// The platform answers only while the exit record is still in its history,
/// and only with the trace blocks that belong to this app's process, capped at
/// 64 KiB; a protobuf tombstone, a record without a readable stream, an absent
/// channel, or a platform error all answer null. The trace is optional
/// diagnostic evidence, so a null answer leaves the recorded exit unchanged.
/// [timeout] bounds the wait so a stalled platform worker cannot suppress the
/// record itself; the default is [kExitTraceTimeout].
Future<String?> readExitTrace(
  ProcessExitReason exit, {
  Duration timeout = kExitTraceTimeout,
}) async {
  if (!exit.hasTrace) return null;
  final int? pid = exit.pid;
  if (pid == null) return null;
  try {
    final String? trace = await const MethodChannel(kDiagnosticsChannel)
        .invokeMethod<String>('exitTrace', <String, Object?>{
          'timestamp': exit.timestamp.millisecondsSinceEpoch,
          'pid': pid,
        })
        .timeout(timeout, onTimeout: () => null);
    if (trace == null || trace.trim().isEmpty) return null;
    return trace;
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  } catch (_) {
    // A malformed answer is absence of evidence, not a startup failure.
    return null;
  }
}

/// The newest abnormal exit that has no record yet, or null.
///
/// [recorded] is the collector's current entries, including the ones restored
/// from disk. The cutoff is the newest entry whose type starts with
/// [kProcessExitTypePrefix]: an exit timestamp at or before it was already
/// attributed, so only a strictly newer exit is new evidence. That rule keeps
/// every launch from re-recording the same historical records, because the
/// record's own timestamp is when this app wrote it — always later than the
/// exit it describes.
ProcessExitReason? newestUnreportedExit(
  List<ProcessExitReason> reasons,
  List<ErrorLogEntry> recorded,
) {
  DateTime? lastReported;
  for (final ErrorLogEntry entry in recorded) {
    if (!entry.type.startsWith(kProcessExitTypePrefix)) continue;
    if (lastReported == null || entry.timestamp.isAfter(lastReported)) {
      lastReported = entry.timestamp;
    }
  }

  ProcessExitReason? newest;
  for (final ProcessExitReason exit in reasons) {
    if (!isAbnormalExit(exit)) continue;
    if (lastReported != null && !exit.timestamp.isAfter(lastReported)) continue;
    if (newest == null || exit.timestamp.isAfter(newest.timestamp)) {
      newest = exit;
    }
  }
  return newest;
}

/// Records the newest abnormal exit from the previous run, at most once.
///
/// Called from `main` after the collector has restored its persisted entries,
/// so the dedupe compares against what the last launch wrote. A deliberate
/// stop produces nothing; an abnormal exit becomes an `ErrorLogEntry` of type
/// `process-exit:<name>` carrying the platform's own description and identity,
/// plus a breadcrumb for later errors. When the platform reports a readable
/// trace for the selected exit, that bounded trace rides on the entry and in
/// the `traceChars`/`traceTruncated` facts; a null trace leaves the record
/// exactly as a build without trace capture would write it.
Future<void> recordProcessExitReasons() async {
  final ErrorLogCollector collector = ErrorLogCollector.instance;
  try {
    final List<ProcessExitReason> reasons = await readProcessExitReasons();
    final ProcessExitReason? exit = newestUnreportedExit(
      reasons,
      collector.entries,
    );
    if (exit == null) return;

    final String name = processExitReasonName(exit.reason);
    final ErrorLogLevel level = exitReasonLevel(exit.reason);
    final String description = exit.description?.trim() ?? '';
    final String? trace = _captureTrace(await readExitTrace(exit));
    collector.addBreadcrumb(
      'Previous run: process exit $name (reason ${exit.reason})',
      level: level.name,
    );
    collector.captureError(
      description.isEmpty
          ? 'Previous process exit: $name'
          : 'Previous process exit: $name — $description',
      level: level,
      type: '$kProcessExitTypePrefix$name',
      context: <String, Object?>{
        'exitTimestamp': exit.timestamp.toIso8601String(),
        'reason': exit.reason,
        'reasonName': name,
        if (description.isNotEmpty) 'description': description,
        'importance': exit.importance,
        'status': exit.status,
        if (exit.processName != null) 'processName': exit.processName,
        if (trace != null) 'traceChars': trace.length,
        if (trace != null) 'traceTruncated': isTraceTruncated(trace),
      },
      trace: trace,
    );
  } catch (_) {
    // Best-effort diagnostics: attribution failure never breaks startup.
  }
}

/// The form of [trace] the log stores: null when absent, else bounded.
///
/// The platform already caps the text; this last-resort guard keeps an
/// unexpected or hostile channel answer from bloating the persisted log, and
/// records the cut with the marker a report renders.
String? _captureTrace(String? trace) {
  if (trace == null || trace.trim().isEmpty) return null;
  return renderableTrace(trace);
}
