/// Throttles repeated adapter diagnostics so one malformed wire value cannot
/// fill the app's bounded diagnostic log.
///
/// A decode failure on every baseline and reconnect is one contract problem,
/// not N: the value is still rejected, but the log records the first
/// occurrence and then only a periodic recap carrying the suppressed count.
/// The clock is injectable so tests can cross [DiagnosticGate.window] without
/// waiting in real time.
final class DiagnosticGate {
  DiagnosticGate({
    DateTime Function()? now,
    this.window = const Duration(seconds: 60),
  }) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  /// How long one emission stays final before the next occurrence is emitted
  /// again with the repeats folded into its message.
  final Duration window;

  final Map<String, _GateEntry> _entries = <String, _GateEntry>{};

  /// Decides whether the diagnostic identified by [key] may be emitted now.
  ///
  /// Returns the number of occurrences suppressed since this key last emitted
  /// (`0` on its first emission), or `null` when this occurrence joins that
  /// suppressed count instead of emitting. A non-suppressed admit resets the
  /// count and restarts the window.
  int? admit(String key) {
    final at = _now();
    final prior = _entries[key];
    if (prior != null && at.difference(prior.lastEmitted) < window) {
      prior.suppressed++;
      return null;
    }
    final suppressed = prior?.suppressed ?? 0;
    _entries[key] = _GateEntry(lastEmitted: at);
    return suppressed;
  }
}

final class _GateEntry {
  _GateEntry({required this.lastEmitted});

  /// The last emission, not the last occurrence: the window is measured from
  /// the diagnostic the app last saw, so a steady repeat still recaps.
  final DateTime lastEmitted;

  int suppressed = 0;
}
