import 'dart:convert';

import 'package:dev/src/crash_bundle.dart';
import 'package:dev/src/crash_reporter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  CrashBundleWire sampleBundle() => CrashBundleWire(
    app: 'dsh-android',
    version: '0.1.0',
    build: '1',
    platform: 'android',
    device: 'Pixel 9',
    dshBaseUrl: 'http://10.0.2.2:3080',
    sessionId: 's1',
    sourceRepo: 'Chance/deepseek-harness-android',
    sourceCommit: 'deadbeef',
    crash: CapturedCrash(
      kind: 'uncaught-async',
      type: 'SocketException',
      message: 'refused',
      stackFrames: const ['#0 _post'],
      occurredAt: DateTime.utc(2026, 8, 21),
    ),
    logs: const ['2026-08-21T00:00:00.000 I/flutter hi'],
  );

  test('POSTs to api/crash with the exact bundle JSON', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response('{"jobId":"job-1","status":"queued"}', 202);
    });
    final reporter = CrashReporter(
      intakeUrl: Uri.parse('http://10.0.2.2:9876'),
      httpClient: client,
    );

    final ok = await reporter.report(sampleBundle());

    expect(ok, isTrue);
    expect(captured.method, 'POST');
    expect(captured.url.toString(), 'http://10.0.2.2:9876/api/crash');
    expect(captured.headers['Content-Type'], contains('application/json'));
    final body = jsonDecode(captured.body) as Map<String, Object?>;
    expect(body['app'], 'dsh-android');
    expect((body['source'] as Map<String, Object?>)['commit'], 'deadbeef');
  });

  test('returns false on non-2xx', () async {
    final client = MockClient((_) async => http.Response('nope', 500));
    final reporter = CrashReporter(
      intakeUrl: Uri.parse('http://10.0.2.2:9876'),
      httpClient: client,
    );
    expect(await reporter.report(sampleBundle()), isFalse);
  });

  test('returns false on network error, never throws', () async {
    final client = MockClient((_) async => throw Exception('connection refused'));
    final reporter = CrashReporter(
      intakeUrl: Uri.parse('http://10.0.2.2:9876'),
      httpClient: client,
    );
    expect(await reporter.report(sampleBundle()), isFalse);
  });
}