/// Crash marker — on-disk record written at crash time, read on next launch.
///
/// The whole point is the *dying-process* case: when an uncaught error or
/// fatal Flutter error hits, the process may not live long enough for an
/// async HTTP export to complete. So the marker is written SYNCHRONOUSLY
/// (blocking file I/O), carrying the crash summary plus the log tail, and
/// the actual reporting happens on the next launch (restart detection).
library;

import 'dart:convert';
import 'dart:io';

import 'crash_record.dart';

class CrashMarker {
  CrashMarker(this.file);

  final File file;

  static const String markerName = 'crash_marker.json';

  /// Write the marker synchronously. Best-effort: failures are swallowed
  /// (a debug crash capture must never crash the crash handler).
  void writeSync(CrashRecord record) {
    try {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode(record.toJson()), flush: true);
    } catch (_) {
      // Never let marker write failure escape into the crash handler.
    }
  }

  /// True when a marker exists (i.e. the previous run crashed).
  bool get exists => file.existsSync();

  /// Read and delete the marker in one step; returns null when absent or
  /// unreadable. Deleting here means a later report failure will not
  /// re-report the same crash on every launch.
  CrashRecord? takeIfPresent() {
    if (!exists) return null;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      final record = CrashRecord.fromJson(decoded as Map<String, Object?>);
      clear();
      return record;
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