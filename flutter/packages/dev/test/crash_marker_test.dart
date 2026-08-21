import 'dart:io';

import 'package:dev/src/build_info.dart';
import 'package:dev/src/crash_marker.dart';
import 'package:dev/src/crash_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const build = DebugBuildInfo(
    app: 'dsh-android',
    version: '0.1.0',
    build: '7',
    platform: 'android',
    sourceRepo: 'Chance/deepseek-harness-android',
    sourceCommit: 'abc1234',
  );

  CrashRecord makeRecord() => CrashRecord(
    crash: CapturedCrash(
      kind: 'FlutterError',
      type: 'StateError',
      message: 'boom',
      stackFrames: const ['#0 main'],
      occurredAt: DateTime.utc(2026, 8, 21, 9, 30),
    ),
    build: build,
    device: 'Pixel 9',
    dshBaseUrl: 'http://10.0.2.2:3080',
    sessionId: 'sess-9',
    logs: const ['09:00:00.000 INFO hello', '09:00:01.000 CRASH boom'],
  );

  Directory tempDir() {
    final dir = Directory.systemTemp.createTempSync('crash-marker-test-');
    addTearDown(() => dir.deleteSync(recursive: true));
    return dir;
  }

  test('writeSync then takeIfPresent round-trips the record', () {
    final marker = CrashMarker(
      File('${tempDir().path}/${CrashMarker.markerName}'),
    );
    expect(marker.exists, isFalse);
    marker.writeSync(makeRecord());
    expect(marker.exists, isTrue);
    final record = marker.takeIfPresent();
    expect(record, isNotNull);
    expect(record!.crash.kind, 'FlutterError');
    expect(record.crash.message, 'boom');
    expect(record.device, 'Pixel 9');
    expect(record.logs, hasLength(2));
    expect(marker.exists, isFalse, reason: 'takeIfPresent deletes the marker');
    expect(marker.takeIfPresent(), isNull);
  });

  test('absent marker yields null without touching the file system', () {
    final marker = CrashMarker(File('${tempDir().path}/does-not-exist.json'));
    expect(marker.takeIfPresent(), isNull);
  });

  test('corrupt marker clears itself and yields null', () {
    final file = File('${tempDir().path}/${CrashMarker.markerName}')
      ..writeAsStringSync('{not json');
    final marker = CrashMarker(file);
    expect(marker.takeIfPresent(), isNull);
    expect(marker.exists, isFalse);
  });

  test('write failure is swallowed (crash handler must never throw)', () {
    final marker = CrashMarker(File('${tempDir().path}/no-such-dir/x.json'));
    expect(() => marker.writeSync(makeRecord()), returnsNormally);
  });
}