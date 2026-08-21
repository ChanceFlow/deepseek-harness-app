import 'dart:convert';

import 'package:dev/src/crash_bundle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CrashBundleWire — intake wire contract', () {
    test('toJson emits exactly the intake CrashBundle shape', () {
      final bundle = CrashBundleWire(
        app: 'dsh-android',
        version: '0.3.1',
        build: '412',
        platform: 'android',
        device: 'Pixel 9',
        dshBaseUrl: 'http://10.0.2.2:3080',
        sessionId: 'sess-1',
        sourceRepo: 'Chance/deepseek-harness-android',
        sourceCommit: '1f6ce39d55bb7eeac48fee900605b7206f14fe5c',
        crash: CapturedCrash(
          kind: 'uncaught-async',
          type: 'SocketException',
          message: 'Connection refused',
          stackFrames: ['#0 _post', '#1 main'],
          occurredAt: DateTime.utc(2026, 8, 21, 3, 0, 0),
        ),
        logs: ['2026-08-21T03:00:00.000 I/flutter hi'],
      );
      final json = jsonDecode(jsonEncode(bundle.toJson())) as Map<String, Object?>;
      // The intake server reads these exact keys (src/triage-context.ts).
      expect(json['app'], 'dsh-android');
      expect(json['version'], '0.3.1');
      expect(json['build'], '412');
      expect(json['platform'], 'android');
      expect(json['device'], 'Pixel 9');
      expect(json['dshBaseUrl'], 'http://10.0.2.2:3080');
      expect(json['sessionId'], 'sess-1');
      final source = json['source'] as Map<String, Object?>;
      expect(source['repo'], 'Chance/deepseek-harness-android');
      expect(source['commit'], '1f6ce39d55bb7eeac48fee900605b7206f14fe5c');
      final crash = json['crash'] as Map<String, Object?>;
      expect(crash['type'], 'SocketException');
      expect(crash['message'], 'Connection refused');
      expect(crash['occurredAt'], '2026-08-21T03:00:00.000Z');
      expect(crash['stackFrames'], ['#0 _post', '#1 main']);
      expect(json['logs'], ['2026-08-21T03:00:00.000 I/flutter hi']);
    });

    test('fromJson round-trips a marker payload', () {
      final bundle = CrashBundleWire(
        app: 'dsh-android',
        version: '0.3.1',
        build: '412',
        platform: 'android',
        device: 'Pixel 9',
        dshBaseUrl: '',
        sessionId: '',
        sourceRepo: 'Chance/deepseek-harness-android',
        sourceCommit: 'abc',
        crash: CapturedCrash(
          kind: 'FlutterError',
          type: 'StateError',
          message: 'bad state',
          stackFrames: const ['#0 f'],
          occurredAt: DateTime.utc(2026, 1, 2),
        ),
        logs: const ['l1'],
      );
      final round = CrashBundleWire.fromJson(bundle.toJson());
      expect(round.app, 'dsh-android');
      expect(round.sourceCommit, 'abc');
      expect(round.crash.type, 'StateError');
      expect(round.crash.stackFrames, ['#0 f']);
      expect(round.logs, ['l1']);
    });

    test('fromJson tolerates missing optional fields', () {
      final round = CrashBundleWire.fromJson({
        'crash': {'type': 'X'},
        'source': {},
      });
      expect(round.app, 'dsh-android');
      expect(round.version, '');
      expect(round.sourceRepo, 'Chance/deepseek-harness-android');
      expect(round.crash.type, 'X');
      expect(round.crash.stackFrames, isEmpty);
      expect(round.logs, isEmpty);
    });
  });

  group('CrashBuildInfo', () {
    test('defaults are well-formed without dart-defines', () {
      const info = CrashBuildInfo();
      expect(info.app, 'dsh-android');
      expect(info.sourceCommit, 'unknown');
      expect(info.sourceRepo, 'Chance/deepseek-harness-android');
    });
  });
}