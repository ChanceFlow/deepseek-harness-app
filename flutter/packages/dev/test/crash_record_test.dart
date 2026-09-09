import 'package:dev/src/build_info.dart';
import 'package:dev/src/crash_record.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const build = DebugBuildInfo(
    app: 'dsh-android',
    version: '0.1.0',
    build: '7',
    platform: 'android',
    sourceRepo: 'ChanceFlow/deepseek-harness-app',
    sourceCommit: 'abc1234',
  );

  test('CrashRecord round-trips through its JSON schema', () {
    final record = CrashRecord(
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
      logs: const ['09:00:00.000 INFO hello'],
    );
    final decoded = CrashRecord.fromJson(record.toJson());
    expect(decoded.crash.kind, 'FlutterError');
    expect(decoded.crash.type, 'StateError');
    expect(decoded.crash.message, 'boom');
    expect(decoded.crash.stackFrames, ['#0 main']);
    expect(decoded.crash.occurredAt.toUtc(), DateTime.utc(2026, 8, 21, 9, 30));
    expect(decoded.device, 'Pixel 9');
    expect(decoded.dshBaseUrl, 'http://10.0.2.2:3080');
    expect(decoded.sessionId, 'sess-9');
    expect(decoded.build.app, 'dsh-android');
    expect(decoded.build.version, '0.1.0');
    expect(decoded.build.sourceCommit, 'abc1234');
    expect(decoded.logs, ['09:00:00.000 INFO hello']);
  });

  test('fromFlutterError captures the context name and stack head', () {
    final details = FlutterErrorDetails(
      exception: StateError('boom'),
      stack: StackTrace.fromString('#0 top\n#1 middle\n#2 bottom\n'),
      context: ErrorDescription('during build'),
    );
    final crash = CapturedCrash.fromFlutterError(
      details,
      occurredAt: DateTime.utc(2026, 8, 21),
    );
    expect(crash.kind, 'FlutterError:during build');
    expect(crash.type, 'StateError');
    expect(crash.message, 'Bad state: boom');
    expect(crash.stackFrames.length, lessThanOrEqualTo(20));
    expect(crash.stackFrames.first, startsWith('#0'));
    expect(crash.occurredAt, DateTime.utc(2026, 8, 21));
  });

  test('fromFlutterError retains deep stack frames (not truncated to 20)', () {
    final frames = List.generate(50, (i) => '#$i frame$i()').join('\n');
    final details = FlutterErrorDetails(
      exception: StateError('deep stack'),
      stack: StackTrace.fromString(frames),
    );
    final crash = CapturedCrash.fromFlutterError(
      details,
      occurredAt: DateTime.utc(2026, 8, 21),
    );
    expect(crash.stackFrames.length, 50);
    expect(crash.stackFrames.first, '#0 frame0()');
    expect(crash.stackFrames.last, '#49 frame49()');
  });

  test('fromAsyncError retains deep stack frames (not truncated to 20)', () {
    final frames = List.generate(60, (i) => '#$i asyncFrame$i()').join('\n');
    final crash = CapturedCrash.fromAsyncError(
      ArgumentError('bad arg'),
      StackTrace.fromString(frames),
      occurredAt: DateTime.utc(2026, 8, 21),
    );
    expect(crash.kind, 'uncaught-async');
    expect(crash.type, 'ArgumentError');
    expect(crash.message, 'Invalid argument(s): bad arg');
    expect(crash.stackFrames.length, 60);
    expect(crash.stackFrames.first, '#0 asyncFrame0()');
    expect(crash.stackFrames.last, '#59 asyncFrame59()');
  });

  test('toTelemetryAttributes carries provenance and crash facts', () {
    final record = CrashRecord(
      crash: CapturedCrash(
        kind: 'FlutterError',
        type: 'StateError',
        message: 'boom',
        stackFrames: const ['#0 frame1', '#1 frame2'],
        occurredAt: DateTime.utc(2026, 8, 21),
      ),
      build: build,
      device: 'Pixel 9',
      dshBaseUrl: 'http://10.0.2.2:3080',
      sessionId: 'sess-9',
      logs: const ['09:00:00.000 INFO hello'],
    );
    final attrs = record.toTelemetryAttributes();
    expect(attrs['app'], 'dsh-android');
    expect(attrs['source.commit'], 'abc1234');
    expect(attrs['crash.kind'], 'FlutterError');
    expect(attrs['crash.type'], 'StateError');
    expect(attrs['crash.message'], 'boom');
    expect(attrs['crash.stack'], '#0 frame1\n#1 frame2');
    expect(attrs['crash.stackFrames'], ['#0 frame1', '#1 frame2']);
    expect(attrs['crash.log_count'], 1);
    expect(attrs['crash.logs'], ['09:00:00.000 INFO hello']);
    expect(attrs['device'], 'Pixel 9');
  });
}
