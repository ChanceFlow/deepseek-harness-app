/// Ring log buffer for crash capture.
///
/// Keeps the most recent [LogBuffer.capacity] lines with a monotonically
/// increasing sequence and an ISO-8601 timestamp per line. The buffer is a
/// debug-build aid: app code appends lines it already formats (or raw debug
/// strings), and a crash dump flushes the tail. Memory-only; persistence is
/// the crash marker's job (the marker points at buffered lines only if the
/// buffer is drained into it synchronously at crash time).
library;

class LogBuffer {
  // ignore: prefer_initializing_formals
  LogBuffer({int capacity = 200}) : _capacity = capacity;

  final int _capacity;
  final List<String> _lines = [];

  int get length => _lines.length;

  bool get isEmpty => _lines.isEmpty;

  /// Append one line; drops the oldest beyond capacity.
  void append(String line, {DateTime? at}) {
    final stamp = at ?? DateTime.now();
    _lines.add(_format(stamp, line));
    if (_lines.length > _capacity) {
      _lines.removeRange(0, _lines.length - _capacity);
    }
  }

  /// Append many lines as a batch (e.g. a chunked log drain).
  void appendAll(Iterable<String> lines) {
    for (final line in lines) {
      append(line);
    }
  }

  /// Snapshot of the buffered lines, newest last, without mutating state.
  List<String> snapshot() => List.unmodifiable(_lines);

  /// Clear the buffer.
  void clear() => _lines.clear();

  String _format(DateTime at, String line) {
    final iso = at.toIso8601String();
    return '$iso $line';
  }
}

/// Formats [line] with the log style the intake triage expects: a readable
/// clock prefix (`HH:mm:ss.SSS`) plus the caller's own level tag.
String formatLogLine(String level, String message, {DateTime? at}) {
  final t = at ?? DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final ms = t.millisecond.toString().padLeft(3, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.$ms $level $message';
}