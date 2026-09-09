/// Debug telemetry facade — logs, events, metrics, and crash records through
/// the OpenTelemetry SDK, exported over OTLP/HTTP to the SigNoz collector.
///
/// The facade is the only surface app code touches. It wraps the global OTel
/// providers (initialized once by [DebugTelemetry.initialize], or by the
/// test harness in tests) and adds local ring buffering and an event rate
/// cap on top. Every emit path is best-effort: telemetry must never break
/// the app, so all facade methods swallow errors.
library;

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, visibleForTesting;

import 'build_info.dart';
import 'crash_record.dart';
import 'log_buffer.dart';

/// OTLP endpoint + service identity + limits for debug telemetry.
class TelemetrySettings {
  const TelemetrySettings({
    required this.endpoint,
    this.serviceName = 'dsh-android',
    this.serviceVersion = '0.0.0-dev',
    this.resourceAttributes = const {},
    this.metricFlushInterval = const Duration(seconds: 15),
    this.eventRatePerSecond = 100,
    this.bufferCapacity = 300,
    this.enabled = true,
  });

  /// OTLP/HTTP collector base URL, e.g. `http://10.0.2.2:4318`.
  final String endpoint;

  /// Service identity reported on every signal.
  final String serviceName;
  final String serviceVersion;

  /// Extra resource attributes (build provenance, source commit, ...).
  final Map<String, Object> resourceAttributes;

  /// How often the SDK collects and exports metrics.
  final Duration metricFlushInterval;

  /// Event-rate cap enforced by a sliding window (events per second).
  final int eventRatePerSecond;

  /// Ring-buffer capacity shared by logs and events.
  final int bufferCapacity;

  /// Master switch; gates every facade call.
  final bool enabled;
}

/// One telemetry facade bound to the global OTel providers.
class DebugTelemetry {
  DebugTelemetry._(
    this._settings,
    this._logger,
    this._meter, {
    this.isLocalFallback = false,
  }) : _buffer = LogBuffer(capacity: _settings.bufferCapacity);

  final TelemetrySettings _settings;
  final APILogger? _logger;
  final APIMeter? _meter;
  final bool isLocalFallback;

  final Map<String, APICounter<int>> _counters = {};
  final Map<String, APIHistogram<double>> _histograms = {};
  final Map<String, APIGauge<double>> _gauges = {};
  final LogBuffer _buffer;

  final List<int> _eventWindow = [];

  static DebugTelemetry? _instance;

  /// The active facade; null until [initialize] succeeded.
  static DebugTelemetry? get instance => _instance;

  /// Resets the cached singleton instance for testing.
  @visibleForTesting
  static void resetForTesting() {
    _instance = null;
  }

  /// Brings up the OTel SDK (once per process) with OTLP/HTTP exporters for
  /// metrics and logs and constructs the facade over the global providers.
  ///
  /// Returns null when [TelemetrySettings.enabled] is false or when the SDK
  /// is already initialized (caller adopts the existing SDK via
  /// [fromGlobal] instead — e.g. after the test harness initialized it).
  /// If initialization throws or fails, falls back gracefully to a local-only
  /// telemetry instance.
  static Future<DebugTelemetry?> initialize(TelemetrySettings settings) async {
    if (!settings.enabled) return null;
    final factory = OTelFactory.otelFactory;
    if (factory != null && !factory.isAPIFactory) {
      _instance = fromGlobal(settings);
      return _instance;
    }
    try {
      await OTel.initialize(
        endpoint: settings.endpoint,
        secure: settings.endpoint.startsWith('https://'),
        serviceName: settings.serviceName,
        serviceVersion: settings.serviceVersion,
        resourceAttributes: OTel.attributesFromMap({
          ...settings.resourceAttributes,
          ...DebugBuildInfo.fromEnvironment().toResourceAttributes(),
        }),
        detectPlatformResources: false,
        enableMetrics: true,
        enableLogs: true,
        metricExporter: OtlpHttpMetricExporter(
          OtlpHttpMetricExporterConfig(endpoint: settings.endpoint),
        ),
        metricReader: PeriodicExportingMetricReader(
          OtlpHttpMetricExporter(
            OtlpHttpMetricExporterConfig(endpoint: settings.endpoint),
          ),
          interval: settings.metricFlushInterval,
        ),
        logRecordExporter: OtlpHttpLogRecordExporter(
          OtlpHttpLogRecordExporterConfig(endpoint: settings.endpoint),
        ),
        logRecordProcessor: SimpleLogRecordProcessor(
          OtlpHttpLogRecordExporter(
            OtlpHttpLogRecordExporterConfig(endpoint: settings.endpoint),
          ),
        ),
      );
      _instance = fromGlobal(settings);
      return _instance;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint(
          'DebugTelemetry.initialize failed to initialize OTel: $e\n$st\n'
          'Falling back to local-only telemetry.',
        );
      }
      _instance = localFallback(settings);
      return _instance;
    }
  }

  /// Constructs the facade over already-initialized global OTel providers.
  /// Used by the app after [initialize] and by tests after the harness
  /// initialized the SDK with in-memory exporters.
  static DebugTelemetry fromGlobal(TelemetrySettings settings) {
    final logger = OTel.loggerProvider().getLogger(
      settings.serviceName,
      version: settings.serviceVersion,
    );
    final meter = OTel.meterProvider().getMeter(
      name: settings.serviceName,
      version: settings.serviceVersion,
    );
    final telemetry = DebugTelemetry._(settings, logger, meter);
    _instance ??= telemetry;
    return telemetry;
  }

  /// Creates a local fallback facade when OTel SDK is unavailable or failed
  /// to initialize. The ring buffer, local debugPrint mirrors, and crash
  /// markers continue to function without remote OTLP export.
  static DebugTelemetry localFallback(TelemetrySettings settings) {
    APILogger? logger;
    APIMeter? meter;
    try {
      logger = OTelAPI.loggerProvider().getLogger(
        settings.serviceName,
        version: settings.serviceVersion,
      );
    } catch (_) {}
    try {
      meter = OTelAPI.meterProvider().getMeter(
        name: settings.serviceName,
        version: settings.serviceVersion,
      );
    } catch (_) {}
    final telemetry = DebugTelemetry._(
      settings,
      logger,
      meter,
      isLocalFallback: true,
    );
    _instance ??= telemetry;
    return telemetry;
  }

  /// The ring buffer shared by logs and events; snapshot feeds crash markers.
  LogBuffer get buffer => _buffer;

  /// Structured log record. [level] is one of `debug`, `info`, `warn`,
  /// `error`, `fatal`; unknown levels fall back to `info`.
  void log(
    String message, {
    String level = 'info',
    Map<String, Object> attributes = const {},
  }) {
    if (!_settings.enabled) return;
    final levelTag = level.toUpperCase();
    _buffer.append(formatLogLine(levelTag, message));
    if (kDebugMode) {
      if (attributes.isNotEmpty) {
        debugPrint('[$levelTag] $message $attributes');
      } else {
        debugPrint('[$levelTag] $message');
      }
    }
    try {
      _logger?.emit(
        severityNumber: _severityFor(level),
        severityText: levelTag,
        body: message,
        attributes: OTel.attributesFromMap(attributes),
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('DebugTelemetry: failed to emit log ($levelTag): $e\n$st');
      }
    }
  }

  /// Event 打点: a named occurrence (e.g. `app.start`, `session.opened`)
  /// with free-form attributes. Rate-capped by
  /// [TelemetrySettings.eventRatePerSecond].
  void event(String name, {Map<String, Object> attributes = const {}}) {
    if (!_settings.enabled) return;
    if (!_eventAllowed()) return;
    _buffer.append(formatLogLine('EVENT', name));
    if (kDebugMode) {
      if (attributes.isNotEmpty) {
        debugPrint('[EVENT] $name $attributes');
      } else {
        debugPrint('[EVENT] $name');
      }
    }
    try {
      _logger?.emit(
        severityNumber: Severity.INFO,
        severityText: 'EVENT',
        eventName: name,
        attributes: OTel.attributesFromMap(attributes),
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('DebugTelemetry: failed to emit event ($name): $e\n$st');
      }
    }
  }

  /// Lazily-created monotonic counter, e.g. `app.op.count`.
  APICounter<int>? counter(String name, {String? unit, String? description}) {
    final meter = _meter;
    if (meter == null) return null;
    return _counters.putIfAbsent(
      name,
      () => meter.createCounter<int>(
        name: name,
        unit: unit,
        description: description,
      ),
    );
  }

  /// Cumulative count.
  void count(String name, [int amount = 1]) {
    if (!_settings.enabled) return;
    try {
      counter(name)?.add(amount);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('DebugTelemetry: failed to count ($name): $e\n$st');
      }
    }
  }

  /// Lazily-created histogram, e.g. `app.frame.total_ms`.
  APIHistogram<double>? histogram(
    String name, {
    String? unit,
    String? description,
  }) {
    final meter = _meter;
    if (meter == null) return null;
    return _histograms.putIfAbsent(
      name,
      () => meter.createHistogram<double>(
        name: name,
        unit: unit,
        description: description,
      ),
    );
  }

  /// Record one measurement into a histogram.
  void record(String name, double value) {
    if (!_settings.enabled) return;
    try {
      histogram(name)?.record(value);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('DebugTelemetry: failed to record ($name): $e\n$st');
      }
    }
  }

  /// Lazily-created gauge, e.g. `app.frame.fps`.
  APIGauge<double>? gauge(String name, {String? unit, String? description}) {
    final meter = _meter;
    if (meter == null) return null;
    return _gauges.putIfAbsent(
      name,
      () => meter.createGauge<double>(
        name: name,
        unit: unit,
        description: description,
      ),
    );
  }

  /// Set the current value of a gauge.
  void setGauge(String name, double value) {
    if (!_settings.enabled) return;
    try {
      gauge(name)?.record(value);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('DebugTelemetry: failed to set gauge ($name): $e\n$st');
      }
    }
  }

  /// Emit a crash record as a fatal log record (best-effort at capture time;
  /// the durable path is the on-disk marker + restart detection).
  void reportCrash(CrashRecord record) {
    if (!_settings.enabled) return;
    if (kDebugMode) {
      debugPrint(
        '*** CRASH REPORT [${record.crash.kind}] ***\n'
        'Type: ${record.crash.type}\n'
        'Message: ${record.crash.message}\n'
        'Stack (${record.crash.stackFrames.length} frames):\n'
        '${record.crash.stackFrames.join('\n')}',
      );
    }
    try {
      _logger?.emit(
        severityNumber: Severity.FATAL,
        severityText: 'FATAL',
        eventName: 'crash',
        body: record.crash.message,
        attributes: OTel.attributesFromMap(record.toTelemetryAttributes()),
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('DebugTelemetry: failed to emit crash: $e\n$st');
      }
    }
  }

  Severity _severityFor(String level) => switch (level) {
    'debug' => Severity.DEBUG,
    'warn' || 'warning' => Severity.WARN,
    'error' => Severity.ERROR,
    'fatal' => Severity.FATAL,
    _ => Severity.INFO,
  };

  /// Sliding-window rate cap for events: at most
  /// [TelemetrySettings.eventRatePerSecond] events per second; the excess
  /// is dropped (sampling, never buffered).
  bool _eventAllowed() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final floor = now - 1000;
    while (_eventWindow.isNotEmpty && _eventWindow.first <= floor) {
      _eventWindow.removeAt(0);
    }
    if (_eventWindow.length >= _settings.eventRatePerSecond) {
      return false;
    }
    _eventWindow.add(now);
    return true;
  }
}
