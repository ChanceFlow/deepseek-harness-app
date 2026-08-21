import 'dart:io';

import 'package:dev/src/crash_bundle.dart';
import 'package:dev/src/crash_marker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const build = CrashBuildInfo(
    app: 'dsh-android',
    version: '0.1.0',
    build: '7',
    platform: 'android',
    sourceRepo: 'Chance/deepseek-harness-android',
    sourceCommit: 'abc1234',
  );

  Directory tempDir() {
    final dir = Directory.systemTemp.createTempSync('crash-marker-test-');
    addTearDown(() => dir.deleteSync(recursive: true));
    return dir;
  }

  test('writeSync then takeIfPresent round-trips the bundle', () {
    final marker = CrashMarker(File('${tempDir().path}/${CrashMarker.markerName}'));
    expect(marker.exists, isFalse);
    marker.writeSync(
      crash: CapturedCrash(
        kind: 'FlutterError',
        type: 'StateError',
        message: 'boom',
        stackFrames: const ['#0 main'],
        occurredAt: DateTime.utc(2026, 8, 21),
      ),
      logs: const ['log line'],
      build: build,
      device: 'Pixel 9',
      dshBaseUrl: 'http://10.0.2.2:3080',
      sessionId: 'sess-1',
    );
    expect(marker.exists, isTrue);

    final read = marker.takeIfPresent();
    expect(read, isNotNull);
    expect(read!.crash.type, 'StateError');
    expect(read.crash.message, 'boom');
    expect(read.logs, ['log line']);
    expect(read.device, 'Pixel 9');
    expect(read.sessionId, 'sess-1');
    expect(read.sourceCommit, 'abc1234');
    expect(read.build, '7');
    // takeIfPresent deletes the marker: a restarted app reports once.
    expect(marker.exists, isFalse);
  });

  test('takeIfPresent returns null when absent', () {
    final marker = CrashMarker(File('${tempDir().path}/${CrashMarker.markerName}'));
    expect(marker.takeIfPresent(), isNull);
  });

  test('takeIfPresent clears unreadable marker instead of crashing', () {
    final dir = tempDir();
    final file = File('${dir.path}/${CrashMarker.markerName}');
    file.writeAsStringSync('{not json');
    final marker = CrashMarker(file);
    expect(marker.takeIfPresent(), isNull);
    expect(marker.exists, isFalse);
  });

  test('clear removes the marker', () {
    final marker = CrashMarker(File('${tempDir().path}/${CrashMarker.markerName}'));
    marker.writeSync(
      crash: CapturedCrash(
        kind: 'x',
        type: 'StateError',
        message: 'm',
        occurredAt: DateTime.utc(2026),
      ),
      logs: const [],
      build: build,
      device: 'd',
      dshBaseUrl: '',
      sessionId: '',
    );
    marker.clear();
    expect(marker.exists, isFalse);
  });

  test('writeSync swallows IO failures (marker path is a directory)', () {
    final dir = tempDir();
    // Occupy the marker path with a directory so the file write fails.
    Directory('${dir.path}/${CrashMarker.markerName}').createSync();
    final marker = CrashMarker(File('${dir.path}/${CrashMarker.markerName}'));
    // Must not throw.
    marker.writeSync(
      crash: CapturedCrash(
        kind: 'x',
        type: 'StateError',
        message: 'm',
        occurredAt: DateTime.utc(2026),
      ),
      logs: const [],
      build: build,
      device: 'd',
      dshBaseUrl: '',
      sessionId: '',
    );
    expect(marker.exists, isFalse);
  });
}