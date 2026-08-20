/// Device-local UI-state cache — string-keyed JSON values that survive app
/// restarts (composer drafts, reading positions, expansion states, the
/// last navigation destination).
///
/// The store owns one JSON document in the app's documents directory
/// (mirroring [BackendStore]'s file posture: atomic temp-file + rename
/// writes). A corrupt or unreadable document is an EMPTY cache, not an
/// error: every key here is regenerable UI state, so losing it is cheaper
/// than failing the surface that reads it. Reads are synchronous against
/// the in-memory cache once [load] completes; writes coalesce through a
/// short debounce so rapid edits (every draft keystroke, scroll ticks)
/// cost at most one disk write per quiet interval.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Debounce window for coalescing disk writes after a [write].
const Duration kLocalStateFlushDelay = Duration(milliseconds: 500);

class LocalStateStore {
  LocalStateStore(this._file);

  final File _file;

  Map<String, Object?> _cache = <String, Object?>{};

  /// True once [load] finished (successfully or by treating a bad file as
  /// empty); reads before that return null for every key.
  bool _loaded = false;
  Timer? _flushTimer;
  Future<void>? _flushing;

  /// Reads the document into the cache. Idempotent: a second call
  /// re-reads and replaces the cache.
  Future<void> load() async {
    Map<String, Object?> decoded = <String, Object?>{};
    if (await _file.exists()) {
      try {
        final raw = jsonDecode(await _file.readAsString());
        if (raw is Map<String, Object?>) decoded = raw;
      } on FileSystemException {
        // Unreadable file: an empty cache (regenerable UI state).
      } on FormatException {
        // Corrupt JSON: an empty cache (regenerable UI state).
      }
    }
    _cache = decoded;
    _loaded = true;
  }

  /// One key's cached value; null before [load], after a null [write],
  /// or when the key was never written.
  Object? read(String key) => _cache[key];

  /// Whether [load] has completed (values are authoritative from here on).
  bool get isLoaded => _loaded;

  /// Stores one JSON-encodable value (null deletes the key) and schedules
  /// the coalesced flush.
  void write(String key, Object? value) {
    if (value == null) {
      _cache.remove(key);
    } else {
      _cache[key] = value;
    }
    _scheduleFlush();
  }

  /// Persists now, cancelling any pending debounce. Safe to call
  /// concurrently; callers await the returned future to know the document
  /// reached disk.
  Future<void> flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    final pending = _flushing;
    if (pending != null) {
      await pending;
    }
    final future = _writeDocument();
    _flushing = future;
    try {
      await future;
    } finally {
      if (identical(_flushing, future)) _flushing = null;
    }
  }

  void _scheduleFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer(kLocalStateFlushDelay, () {
      _flushTimer = null;
      unawaited(flush());
    });
  }

  Future<void> _writeDocument() async {
    try {
      await _file.parent.create(recursive: true);
      final temp = File('${_file.path}.tmp');
      await temp.writeAsString(jsonEncode(_cache), flush: true);
      await temp.rename(_file.path);
    } on FileSystemException {
      // A failed UI-state write drops that update; the next write
      // retries. Nothing here is worth surfacing to the user.
    }
  }
}
