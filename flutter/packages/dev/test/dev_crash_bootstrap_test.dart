import 'dart:io';

import 'package:dev/src/crash_bundle.dart';
import 'package:dev/src/crash_marker.dart';
import 'package:dev/src/crash_reporter.dart';
import 'package:dev/src/dev_crash_bootstrap.dart';
import 'package:dev/src/log_buffer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const build = CrashBuildInfo(
    app: 'dsh-android',
    version: '0.1.0',
    build: '3',
    platform: 'android',
    sourceRepo: 'Chance/deepseek-harness-android',
    sourceCommit: 'c0ffee',
  );

  DevCrashBootstrap makeBootstrap(Directory dir) {
    final marker = CrashMarker(File('${dir.path}/${CrashMarker.markerName}'));
    final client = MockClient((_) async => http.Response('{"jobId":"j"}', 202));
    final reporter = CrashReporter(
      intakeUrl: Uri.parse('http://10.0.2.2:9876'),
      httpClient: client,
    );
    return DevCrashBootstrap(
      buffer: LogBuffer(),
      marker: marker,
      reporter: reporter,
      build: build,
      deviceProvider: () => 'Pixel 9',
      dshBaseUrl: 'http://10.0.2.2:3080',
      sessionIdProvider: () => 'sess-9',
    );
  }

  test('hooks are installed and restore previous handlers on dispose', () {
    final dir = Directory.systemTemp.createTempSync('bootstrap-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final bootstrap = makeBootstrap(dir);
    final previous = FlutterError.onError;
    expect(bootstrap.start(), isTrue);
    expect(bootstrap.isInstalled, isTrue);
    expect(FlutterError.onError, isNot(same(previous)));
    bootstrap.dispose();
    expect(FlutterError.onError, same(previous));
    expect(bootstrap.isInstalled, isFalse);
  });

  test('restart detection reports the previous crash bundle', () async {
    final dir = Directory.systemTemp.createTempSync('bootstrap-');
    addTearDown(() => dir.deleteSync(recursive: true));
    // Simulate previous run: write a marker directly.
    final marker = CrashMarker(File('${dir.path}/${CrashMarker.markerName}'));
    marker.writeSync(
      crash: CapturedCrash(
        kind: 'FlutterError',
        type: 'StateError',
        message: 'boom',
        stackFrames: const ['#0 main'],
        occurredAt: DateTime.utc(2026, 8, 21),
      ),
      logs: const ['prev log'],
      build: build,
      device: 'Pixel 9',
      dshBaseUrl: 'http://10.0.2.2:3080',
      sessionId: 'sess-prev',
    );

    final bootstrap = makeBootstrap(dir);
    CrashBundleWire? reported;
    bootstrap.onRestartDetected = (bundle) {
      reported = bundle;
    };
    bootstrap.start();
    expect(bootstrap.pendingCrashFromLastRun, isTrue);
    expect(reported, isNotNull);
    expect(reported!.crash.type, 'StateError');
    expect(reported!.logs, ['prev log']);
    // Marker consumed: no re-report next launch.
    expect(marker.exists, isFalse);
  });

  test('triggered FlutterError writes a marker and chains to previous handler', () {
    final dir = Directory.systemTemp.createTempSync('bootstrap-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final bootstrap = makeBootstrap(dir);

    // Wrap the default test handler first, then install bootstrap hooks so
    // the chain is: bootstrap -> our wrapper -> default.
    Object? seenByWrapper;
    final defaultHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      seenByWrapper = details.exception;
      defaultHandler?.call(details);
    };
    bootstrap.start();
    final marker = bootstrap.marker;
    bootstrap.buffer.append('before crash');

    try {
      throw StateError('kaput');
    } catch (e, st) {
      FlutterError.reportError(FlutterErrorDetails(exception: e, stack: st));
    } finally {
      bootstrap.dispose();
      FlutterError.onError = defaultHandler;
    }

    // Chained to the wrapper (which got the original exception).
    expect(seenByWrapper, isA<StateError>());
    // Marker on disk carries the crash + log tail.
    expect(marker.exists, isTrue);
    final read = marker.takeIfPresent();
    expect(read!.crash.type, 'StateError');
    // Buffer lines carry ISO timestamp prefixes; match the raw content.
    expect(read.logs.single, contains('before crash'));
  });
}