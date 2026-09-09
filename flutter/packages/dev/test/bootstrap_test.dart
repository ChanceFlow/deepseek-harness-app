import 'dart:io';

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart'
    show Severity;
import 'package:dartastic_opentelemetry/testing.dart';
import 'package:dev/src/bootstrap.dart';
import 'package:dev/src/build_info.dart';
import 'package:dev/src/crash_marker.dart';
import 'package:dev/src/crash_record.dart';
import 'package:dev/src/telemetry.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestHarness harness;
  late DebugTelemetry telemetry;

  setUpAll(() async {
    harness = await maybeInitializeOtelForTest();
    telemetry = DebugTelemetry.fromGlobal(
      const TelemetrySettings(
        endpoint: 'http://localhost:4318',
        serviceName: 'dsh-android',
      ),
    );
  });

  setUp(() => harness.clear());

  Directory tempDir() {
    final dir = Directory.systemTemp.createTempSync('bootstrap-');
    addTearDown(() => dir.deleteSync(recursive: true));
    return dir;
  }

  DebugToolBootstrap makeBootstrap(Directory dir) => DebugToolBootstrap(
    telemetry: telemetry,
    marker: CrashMarker(File('${dir.path}/${CrashMarker.markerName}')),
    deviceProvider: () => 'Pixel 9',
    dshBaseUrl: 'http://10.0.2.2:3080',
    sessionIdProvider: () => 'sess-9',
  );

  CrashRecord makeRecord({String message = 'boom'}) => CrashRecord(
    crash: CapturedCrash(
      kind: 'FlutterError',
      type: 'StateError',
      message: message,
      occurredAt: DateTime.utc(2026, 8, 21),
    ),
    build: const DebugBuildInfo(sourceCommit: 'abc1234'),
    device: 'Pixel 9',
    dshBaseUrl: 'http://10.0.2.2:3080',
    sessionId: 'sess-9',
    logs: const ['09:00:00.000 INFO hello'],
  );

  test('start installs hooks and restore previous handlers on dispose', () {
    final bootstrap = makeBootstrap(tempDir());
    final previousError = FlutterError.onError;
    final previousPlatform = PlatformDispatcher.instance.onError;
    expect(bootstrap.start(trackFrames: false), isTrue);
    expect(bootstrap.isInstalled, isTrue);
    expect(FlutterError.onError, isNot(same(previousError)));
    expect(PlatformDispatcher.instance.onError, isNot(same(previousPlatform)));
    bootstrap.dispose();
    expect(bootstrap.isInstalled, isFalse);
    expect(FlutterError.onError, same(previousError));
    expect(PlatformDispatcher.instance.onError, same(previousPlatform));
  });

  test('pending marker from a previous run is reported and cleared', () {
    final dir = tempDir();
    final marker = CrashMarker(File('${dir.path}/${CrashMarker.markerName}'));
    marker.writeSync(makeRecord(message: 'crashed-last-run'));
    final bootstrap = makeBootstrap(dir);
    expect(bootstrap.start(trackFrames: false), isTrue);
    expect(bootstrap.pendingCrashFromLastRun, isTrue);
    expect(marker.exists, isFalse);
    // Reported as a fatal OTel log record through the real SDK.
    final crashRecords = harness.logs.findRecordsBySeverity(Severity.FATAL);
    expect(crashRecords, hasLength(1));
    expect(crashRecords.single.body, 'crashed-last-run');
    bootstrap.dispose();
  });

  test('crash hook writes the marker synchronously and chains to previous', () {
    final dir = tempDir();
    final marker = CrashMarker(File('${dir.path}/${CrashMarker.markerName}'));
    Object? previousSaw;
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previousSaw = details.exception;
    };
    final bootstrap = makeBootstrap(dir);
    bootstrap.start(trackFrames: false);
    FlutterError.reportError(
      FlutterErrorDetails(exception: StateError('kapow')),
    );
    expect(previousSaw, isA<StateError>(), reason: 'chain to previous handler');
    expect((previousSaw as StateError).message, 'kapow');
    expect(marker.exists, isTrue, reason: 'marker written synchronously');
    expect(harness.logs.findRecordsBySeverity(Severity.FATAL), isNotEmpty);
    bootstrap.dispose();
    FlutterError.onError = previous;
  });

  test('frame tracking starts and stops with the timings callback', () {
    final bootstrap = makeBootstrap(tempDir());
    bootstrap.start(); // trackFrames defaults to true
    expect(bootstrap.frameTracker, isNotNull);
    expect(bootstrap.frameTracker!.isStarted, isTrue);
    bootstrap.dispose();
    expect(bootstrap.frameTracker, isNull);
  });

  test('PlatformDispatcher.onError appends crash and stack to log buffer and writes marker', () {
    final dir = tempDir();
    final marker = CrashMarker(File('${dir.path}/${CrashMarker.markerName}'));
    final bootstrap = makeBootstrap(dir);
    bootstrap.start(trackFrames: false);

    telemetry.buffer.clear();
    final error = StateError('async kapow');
    final stack = StackTrace.fromString('#0 _runAsync\n#1 _eventLoop\n');

    PlatformDispatcher.instance.onError!(error, stack);

    final snapshot = telemetry.buffer.snapshot();
    expect(
      snapshot.any((l) => l.contains('CRASH') && l.contains('async kapow')),
      isTrue,
    );
    expect(
      snapshot.any((l) => l.contains('STACK') && l.contains('#0 _runAsync')),
      isTrue,
    );
    expect(
      snapshot.any((l) => l.contains('STACK') && l.contains('#1 _eventLoop')),
      isTrue,
    );

    expect(marker.exists, isTrue);
    final record = marker.takeIfPresent();
    expect(record, isNotNull);
    expect(record!.crash.message, contains('async kapow'));
    expect(
      record.logs.any((l) => l.contains('CRASH') && l.contains('async kapow')),
      isTrue,
    );
    expect(
      record.logs.any((l) => l.contains('STACK') && l.contains('#0 _runAsync')),
      isTrue,
    );

    bootstrap.dispose();
  });

  test('FlutterError.onError appends crash and stack to log buffer and writes marker', () {
    final dir = tempDir();
    final marker = CrashMarker(File('${dir.path}/${CrashMarker.markerName}'));
    final bootstrap = makeBootstrap(dir);
    bootstrap.start(trackFrames: false);

    telemetry.buffer.clear();
    final details = FlutterErrorDetails(
      exception: StateError('sync kapow'),
      stack: StackTrace.fromString(
        '#0 buildWidget (package:app/main.dart:10:5)\n#1 layout (package:flutter/src/rendering/box.dart:20:1)\n',
      ),
    );

    FlutterError.onError!(details);

    final snapshot = telemetry.buffer.snapshot();
    expect(
      snapshot.any((l) => l.contains('CRASH') && l.contains('sync kapow')),
      isTrue,
    );
    expect(
      snapshot.any((l) => l.contains('STACK') && l.contains('#0 buildWidget')),
      isTrue,
    );
    expect(
      snapshot.any((l) => l.contains('STACK') && l.contains('#1 layout')),
      isTrue,
    );

    expect(marker.exists, isTrue);
    final record = marker.takeIfPresent();
    expect(record, isNotNull);
    expect(record!.crash.message, contains('sync kapow'));
    expect(
      record.logs.any((l) => l.contains('CRASH') && l.contains('sync kapow')),
      isTrue,
    );
    expect(
      record.logs.any(
        (l) => l.contains('STACK') && l.contains('#0 buildWidget'),
      ),
      isTrue,
    );

    bootstrap.dispose();
  });

  test('initDebugTelemetry initializes gracefully even if remote telemetry throws or fails', () async {
    final dir = tempDir();
    final bootstrap = await initDebugTelemetry(
      settings: const TelemetrySettings(
        endpoint: 'http://localhost:4318',
        serviceName: 'dsh-android',
      ),
      markerDirectory: dir,
    );
    expect(bootstrap, isNotNull);
    expect(bootstrap!.isInstalled, isTrue);
    expect(bootstrap.marker.file.path, '${dir.path}/${CrashMarker.markerName}');
    bootstrap.dispose();
  });

  test('initDebugTelemetry returns null when disabled', () async {
    final dir = tempDir();
    final bootstrap = await initDebugTelemetry(
      settings: const TelemetrySettings(
        endpoint: 'http://localhost:4318',
        enabled: false,
      ),
      markerDirectory: dir,
    );
    expect(bootstrap, isNull);
  });
}
