/// Debug tooling bootstrap — crash hooks, restart detection, frame tracking.
///
/// Wires Flutter's error hooks into the marker + telemetry chain, reports a
/// pending marker from a previous run at launch, and starts frame-rate
/// telemetry. Compiled in ONLY on debug builds (the app's `main()` guards
/// the call with `kDebugMode`; this library additionally refuses to install
/// hooks in release mode).
///
/// Flow:
///   launch  →  [start] reads an existing marker (previous run crashed)
///             →  emits it as an OTel fatal log record, clears it
///   runtime →  FlutterError.onError / PlatformDispatcher.onError write a
///             marker synchronously (best-effort) and emit an OTel fatal
///             log record fire-and-forget, then re-raise to the previous
///             handler so the app's own error path is unchanged.
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' show ErrorCallback;

import 'package:flutter/foundation.dart';

import 'build_info.dart';
import 'crash_marker.dart';
import 'crash_record.dart';
import 'frame_tracker.dart';
import 'log_buffer.dart';
import 'telemetry.dart';

class DebugToolBootstrap {
  DebugToolBootstrap({
    required this.telemetry,
    required this.marker,
    this.deviceProvider,
    this.dshBaseUrl = '',
    this.sessionIdProvider,
  });

  final DebugTelemetry telemetry;
  final CrashMarker marker;

  /// Device model, e.g. `Pixel 9`. Injected because adding a device-info
  /// plugin is out of scope; defaults to the Android model from
  /// `PlatformDispatcher` when available.
  final String Function()? deviceProvider;
  final String dshBaseUrl;

  /// Current session id, e.g. derived from the active session's id.
  final String Function()? sessionIdProvider;

  bool _installed = false;
  FlutterExceptionHandler? _previousOnError;
  ErrorCallback? _previousPlatformError;

  /// Frame-rate telemetry, started when [start] is called with
  /// [trackFrames] (default true).
  FrameTracker? frameTracker;

  /// Whether a marker from a previous run was found and reported. Set
  /// synchronously by [start].
  bool pendingCrashFromLastRun = false;

  /// Hook installed flag — exposed for tests to assert wiring.
  bool get isInstalled => _installed;

  String get _device => deviceProvider?.call() ?? 'android';
  String get _sessionId => sessionIdProvider?.call() ?? '';

  /// Idempotent. Returns false when in release mode (hooks refused).
  bool start({bool trackFrames = true}) {
    if (kReleaseMode || _installed) return false;
    _reportPendingCrash();
    _installHooks();
    if (trackFrames) {
      frameTracker = FrameTracker(telemetry: telemetry)..start();
    }
    return true;
  }

  void _reportPendingCrash() {
    final pending = marker.takeIfPresent();
    if (pending != null) {
      pendingCrashFromLastRun = true;
      telemetry.reportCrash(pending);
    }
  }

  void _installHooks() {
    _previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      telemetry.buffer.append(formatLogLine('CRASH', details.exceptionAsString()));
      final record = CrashRecord(
        crash: CapturedCrash.fromFlutterError(
          details,
          occurredAt: DateTime.now(),
        ),
        build: DebugBuildInfo.fromEnvironment(),
        device: _device,
        dshBaseUrl: dshBaseUrl,
        sessionId: _sessionId,
        logs: telemetry.buffer.snapshot(),
      );
      marker.writeSync(record);
      telemetry.reportCrash(record);
      _previousOnError?.call(details);
    };

    _previousPlatformError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      final record = CrashRecord(
        crash: CapturedCrash.fromAsyncError(
          error,
          stack,
          occurredAt: DateTime.now(),
        ),
        build: DebugBuildInfo.fromEnvironment(),
        device: _device,
        dshBaseUrl: dshBaseUrl,
        sessionId: _sessionId,
        logs: telemetry.buffer.snapshot(),
      );
      marker.writeSync(record);
      telemetry.reportCrash(record);
      // Keep the platform's previous behavior (usually: report + consider
      // the error handled).
      return _previousPlatformError?.call(error, stack) ?? true;
    };

    _installed = true;
  }

  /// Convenience: hooks teardown (tests).
  void dispose() {
    frameTracker?.stop();
    frameTracker = null;
    if (_installed) {
      FlutterError.onError = _previousOnError;
      PlatformDispatcher.instance.onError = _previousPlatformError;
      _installed = false;
    }
  }
}

/// Full wiring for the app's `main()`: telemetry facade + crash hooks +
/// pending-crash report + frame tracking, all behind the debug gate.
///
/// Returns null when telemetry is disabled or initialization fails —
/// debug tooling must never prevent the app from starting.
Future<DebugToolBootstrap?> initDebugTelemetry({
  required TelemetrySettings settings,
  required Directory markerDirectory,
  String dshBaseUrl = '',
  String Function()? deviceProvider,
  String Function()? sessionIdProvider,
}) async {
  if (kReleaseMode) return null;
  try {
    final telemetry = await DebugTelemetry.initialize(settings);
    if (telemetry == null) return null;
    return DebugToolBootstrap(
      telemetry: telemetry,
      marker: CrashMarker(
        File('${markerDirectory.path}/${CrashMarker.markerName}'),
      ),
      dshBaseUrl: dshBaseUrl,
      deviceProvider: deviceProvider,
      sessionIdProvider: sessionIdProvider,
    )..start();
  } catch (_) {
    // Debug tooling never breaks app startup.
    return null;
  }
}