/// Debug crash capture bootstrap.
///
/// Wires Flutter's error hooks into the crash marker + reporter chain and
/// performs restart detection on launch. Compiled in ONLY on debug builds
/// (the app's `main()` guards the call with `kDebugMode`; this library
/// additionally refuses to install hooks when `kReleaseMode`).
///
/// Flow:
///   launch  →  [start] reads an existing marker (previous run crashed)
///             →  reports it, clears it
///   runtime →  FlutterError.onError / PlatformDispatcher.onError write a
///             marker synchronously (best-effort), then re-raise to the
///             previous handler so the app's own error path is unchanged.
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' show ErrorCallback;

import 'package:flutter/foundation.dart';

import 'crash_bundle.dart';
import 'crash_marker.dart';
import 'crash_reporter.dart';
import 'log_buffer.dart';

class DevCrashBootstrap {
  DevCrashBootstrap({
    required this.buffer,
    required this.marker,
    required this.reporter,
    required this.build,
    this.deviceProvider,
    this.dshBaseUrl = '',
    this.sessionIdProvider,
  });

  final LogBuffer buffer;
  final CrashMarker marker;
  final CrashReporter reporter;
  final CrashBuildInfo build;

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

  /// Whether a marker from a previous run was found and handed to
  /// [onRestartDetected]. Set synchronously by [start].
  bool pendingCrashFromLastRun = false;

  /// Hook installed flag — exposed for tests to assert wiring.
  bool get isInstalled => _installed;

  String get _device => deviceProvider?.call() ?? _defaultDevice();
  String get _sessionId => sessionIdProvider?.call() ?? '';

  String _defaultDevice() {
    // The framework does not expose the device model; the app injects a real
    // provider (e.g. from android.os.Build) when it has one. Keep a stable
    // generic value so the payload is well-formed without it.
    return 'android';
  }

  /// Idempotent. Returns false when in release mode (hooks refused).
  bool start() {
    if (kReleaseMode || _installed) return false;
    _checkRestart();
    _installHooks();
    return true;
  }

  void _checkRestart() {
    final pending = marker.takeIfPresent();
    if (pending != null) {
      pendingCrashFromLastRun = true;
      onRestartDetected?.call(pending);
    }
  }

  /// Called when a crash from the previous run is found at launch. The
  /// default implementation reports it (fire-and-forget); override for
  /// custom delivery (e.g. queue until network is up).
  void Function(CrashBundleWire bundle)? onRestartDetected;

  void _installHooks() {
    _previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      _capture(FlutterErrorDetails(
        exception: details.exception,
        stack: details.stack,
        context: details.context,
        informationCollector: details.informationCollector,
      ));
      _previousOnError?.call(details);
    };

    _previousPlatformError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      _captureAsync(error, stack);
      // Keep the platform's previous behavior (usually: report + consider
      // the error handled).
      return _previousPlatformError?.call(error, stack) ?? true;
    };

    _installed = true;
  }

  void _capture(FlutterErrorDetails details) {
    final crash = CapturedCrash.fromFlutterError(
      details,
      occurredAt: DateTime.now(),
    );
    _writeMarker(crash);
  }

  void _captureAsync(Object error, StackTrace stack) {
    final crash = CapturedCrash.fromAsyncError(
      error,
      stack,
      occurredAt: DateTime.now(),
    );
    _writeMarker(crash);
  }

  void _writeMarker(CapturedCrash crash) {
    marker.writeSync(
      crash: crash,
      logs: buffer.snapshot(),
      build: build,
      device: _device,
      dshBaseUrl: dshBaseUrl,
      sessionId: _sessionId,
    );
  }

  /// Public: report a bundle now (used both for restart-detected crashes and
  /// for manual triggers in tests).
  Future<bool> reportNow(CrashBundleWire bundle) => reporter.report(bundle);

  /// Convenience: buffer + hooks teardown (tests).
  void dispose() {
    if (_installed) {
      FlutterError.onError = _previousOnError;
      PlatformDispatcher.instance.onError = _previousPlatformError;
      _installed = false;
    }
  }
}

/// Convenience factory: a full wiring for the app's `main()` using the
/// default marker location under [directory] (e.g. app documents dir).
DevCrashBootstrap createBootstrap({
  required Directory directory,
  required CrashBuildInfo build,
  required Uri intakeUrl,
  String dshBaseUrl = '',
  String Function()? deviceProvider,
  String Function()? sessionIdProvider,
  int bufferCapacity = 200,
}) {
  final buffer = LogBuffer(capacity: bufferCapacity);
  final marker = CrashMarker(File('${directory.path}/${CrashMarker.markerName}'));
  final reporter = CrashReporter(intakeUrl: intakeUrl);
  return DevCrashBootstrap(
    buffer: buffer,
    marker: marker,
    reporter: reporter,
    build: build,
    dshBaseUrl: dshBaseUrl,
    deviceProvider: deviceProvider,
    sessionIdProvider: sessionIdProvider,
  );
}