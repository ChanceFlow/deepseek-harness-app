/// Crash marker — on-disk record written at crash time, read on next launch.
///
/// The whole point is the *dying-process* case: when an uncaught error or
/// fatal Flutter error hits, the process may not live long enough for an
/// async HTTP report. So the marker is written SYNCHRONOUSLY (blocking
/// file I/O), carrying the crash summary plus the log tail, and the actual
/// reporting happens on the next launch (restart detection).
library;

import 'dart:convert';
import 'dart:io';

import 'crash_bundle.dart';

class CrashMarker {
  CrashMarker(this.file);

  final File file;

  static const String markerName = 'crash_marker.json';

  /// Write the marker synchronously. Best-effort: failures are swallowed
  /// (a debug crash capture must never crash the crash handler).
  void writeSync({
    required CapturedCrash crash,
    required List<String> logs,
    required CrashBuildInfo build,
    required String device,
    required String dshBaseUrl,
    required String sessionId,
  }) {
    try {
      file.parent.createSync(recursive: true);
      final payload = CrashBundleWire(
        app: build.app,
        version: build.version,
        build: build.build,
        platform: build.platform,
        device: device,
        dshBaseUrl: dshBaseUrl,
        sessionId: sessionId,
        sourceRepo: build.sourceRepo,
        sourceCommit: build.sourceCommit,
        crash: crash,
        logs: logs,
      );
      file.writeAsStringSync(jsonEncode(payload.toJson()), flush: true);
    } catch (_) {
      // Never let marker write failure escape into the crash handler.
    }
  }

  /// True when a marker exists (i.e. the previous run crashed).
  bool get exists => file.existsSync();

  /// Read and delete the marker in one step; returns null when absent or
  /// unreadable. Deleting here means a later report failure will not
  /// re-report the same crash on every launch.
  CrashBundleWire? takeIfPresent() {
    if (!exists) return null;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      final bundle = CrashBundleWire.fromJson(decoded as Map<String, Object?>);
      clear();
      return bundle;
    } catch (_) {
      clear();
      return null;
    }
  }

  void clear() {
    try {
      if (exists) file.deleteSync();
    } catch (_) {
      // best effort
    }
  }
}