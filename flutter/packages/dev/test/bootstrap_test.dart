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
    marker: CrashMarker(
      File('${dir.path}/${CrashMarker.markerName}'),
    ),
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
    FlutterError.reportError(FlutterErrorDetails(exception: StateError('kapow')));
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
}