/// Keeps the Android keep-alive foreground service in step with agent work
/// in flight.
///
/// The service is the price of a connection that survives screen lock, so it
/// must be scoped to the window where it buys something: while at least one
/// session is running or waiting on the user. This class owns that policy —
/// the DI layer only feeds it the merged fact and the copy.
library;

import 'dart:async';

import 'package:flutter/services.dart' show MissingPluginException;

import 'keep_alive_service.dart';

/// How long the service lingers after the last session settles.
///
/// A follow-on turn — a queued prompt, the next round of a goal loop — often
/// starts seconds after the previous one settles. Android refuses a
/// foreground-service start from the background (`ForegroundServiceStartNotAllowedException`),
/// so letting the service lapse and immediately requesting it again is both
/// churn and a start that can be refused; the linger keeps the same service
/// (and the socket) across the gap.
const Duration kKeepAliveLinger = Duration(seconds: 30);

/// Resolves the notification copy at call time, so the DI layer owns locale
/// resolution exactly as it does for the notification center.
typedef KeepAliveCopyResolver = KeepAliveNotificationCopy Function();

/// Receives a failed start/stop. The coordinator treats every seam failure as
/// a diagnostic: losing the keep-alive degrades to a reconnect on resume, it
/// never fails a turn.
typedef KeepAliveFailureListener = void Function(
  Object error,
  StackTrace stackTrace,
);

/// Drives one [KeepAliveService] from the merged work-in-flight fact.
class KeepAliveCoordinator {
  KeepAliveCoordinator({
    required this._service,
    required this._copy,
    this._onFailure,
    this._linger = kKeepAliveLinger,
  });

  final KeepAliveService _service;
  final KeepAliveCopyResolver _copy;
  final KeepAliveFailureListener? _onFailure;
  final Duration _linger;

  /// Desired state. A settle keeps it `true` until the linger expires, so a
  /// start already in flight cannot race the linger away.
  bool _wanted = false;

  /// Host-reported state: the service was accepted and has not been stopped.
  bool _running = false;

  bool _applying = false;
  bool _applyQueued = false;
  bool _disposed = false;
  bool _unsupported = false;
  Timer? _lingerTimer;

  /// Whether the service is currently asked to run.
  bool get isRunning => _running;

  /// Whether agent work is in flight right now, with no linger applied: the
  /// raw merged fact, emitted on transitions only.
  ///
  /// [isRunning] is the service's state (it outlives the work by
  /// [kKeepAliveLinger]); this is the work's own state, which is what a
  /// surface asking "is a turn running?" wants — the notification-permission
  /// ask waits for the first `true` so its prompt has a visible reason.
  bool get hasWorkInFlight => _hasWorkInFlight;
  bool _hasWorkInFlight = false;

  final StreamController<bool> _workInFlightChanges =
      StreamController<bool>.broadcast();

  /// Change stream for [hasWorkInFlight]; no value is replayed on listen.
  Stream<bool> get workInFlightChanges => _workInFlightChanges.stream;

  /// Feeds the merged work-in-flight fact. Idempotent: a value equal to the
  /// current desire changes nothing. A failed start clears the desire, so
  /// this same call is the retry point once the fact is recomputed.
  void update({required bool workInFlight}) {
    if (_disposed) return;
    if (workInFlight != _hasWorkInFlight) {
      _hasWorkInFlight = workInFlight;
      if (!_workInFlightChanges.isClosed) {
        _workInFlightChanges.add(workInFlight);
      }
    }
    if (workInFlight) {
      if (_unsupported) return;
      _lingerTimer?.cancel();
      _lingerTimer = null;
      if (_wanted) return;
      _wanted = true;
      unawaited(_apply());
      return;
    }
    if (!_wanted) return;
    _lingerTimer?.cancel();
    _lingerTimer = Timer(_linger, () {
      _lingerTimer = null;
      _wanted = false;
      unawaited(_apply());
    });
  }

  /// Stops the service and releases the coordinator. Safe to call more than
  /// once; a stop failure is reported and swallowed.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _lingerTimer?.cancel();
    _lingerTimer = null;
    _wanted = false;
    await _stop();
    await _workInFlightChanges.close();
  }

  Future<void> _apply() async {
    if (_applying) {
      _applyQueued = true;
      return;
    }
    _applying = true;
    try {
      do {
        _applyQueued = false;
        while (!_disposed && _running != _wanted) {
          if (!_wanted) {
            await _stop();
            continue;
          }
          try {
            await _service.start(_copy());
            _running = true;
          } on MissingPluginException {
            // No host implements the channel (widget tests, desktop). Not a
            // failure worth reporting, and never worth retrying.
            _unsupported = true;
            _wanted = false;
          } catch (error, stackTrace) {
            // Android refused the start, typically a background
            // foreground-service start. Drop the desire so the next change
            // (or the next resume) retries instead of spinning.
            _wanted = false;
            _onFailure?.call(error, stackTrace);
          }
        }
      } while (_applyQueued && !_disposed);
    } finally {
      _applying = false;
    }
  }

  Future<void> _stop() async {
    try {
      await _service.stop();
    } on MissingPluginException {
      // Nothing to stop where the channel does not exist.
    } catch (error, stackTrace) {
      _onFailure?.call(error, stackTrace);
    }
    _running = false;
  }
}
