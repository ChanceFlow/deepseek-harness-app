import 'package:test/test.dart';

import 'package:domain/model/settings.dart';

void main() {
  group('Settings models', () {
    const ns = SettingsNamespace(
      ns: 'workspace',
      applies: SettingsApplies.live,
      revision: 1,
      hasUserLayer: true,
      secretCount: 0,
    );

    test('SettingsNamespace equality and hashCode', () {
      const copy = SettingsNamespace(
        ns: 'workspace',
        applies: SettingsApplies.live,
        revision: 1,
        hasUserLayer: true,
        secretCount: 0,
      );
      const diff = SettingsNamespace(
        ns: 'workspace',
        applies: SettingsApplies.restart,
        revision: 1,
        hasUserLayer: true,
        secretCount: 0,
      );

      expect(ns, equals(copy));
      expect(ns.hashCode, equals(copy.hashCode));
      expect(ns, isNot(equals(diff)));
    });

    test('SettingsSnapshot collection equality', () {
      const a = SettingsSnapshot(
        writable: true,
        hasDocument: true,
        namespaces: [ns],
        credentialRefs: ['cred-1', 'cred-2'],
      );
      const b = SettingsSnapshot(
        writable: true,
        hasDocument: true,
        namespaces: [
          SettingsNamespace(
            ns: 'workspace',
            applies: SettingsApplies.live,
            revision: 1,
            hasUserLayer: true,
            secretCount: 0,
          ),
        ],
        credentialRefs: ['cred-1', 'cred-2'],
      );
      const diffRefs = SettingsSnapshot(
        writable: true,
        hasDocument: true,
        namespaces: [ns],
        credentialRefs: ['cred-1'],
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(diffRefs)));
    });

    test('CredentialStatus equality and hashCode', () {
      const a = CredentialStatus(
        ref: 'api-key',
        configured: true,
        source: 'env',
        writable: false,
      );
      const b = CredentialStatus(
        ref: 'api-key',
        configured: true,
        source: 'env',
        writable: false,
      );
      const diff = CredentialStatus(
        ref: 'api-key',
        configured: false,
        source: 'env',
        writable: true,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(diff)));
    });

    test('SettingPathOp validation and equality', () {
      final setOp = SettingPathOp(
        op: 'set',
        path: ['general', 'theme'],
        jsonValue: '"dark"',
      );
      final setOpCopy = SettingPathOp(
        op: 'set',
        path: ['general', 'theme'],
        jsonValue: '"dark"',
      );
      final unsetOp = SettingPathOp(op: 'unset', path: ['general', 'theme']);

      expect(setOp, equals(setOpCopy));
      expect(setOp.hashCode, equals(setOpCopy.hashCode));
      expect(setOp, isNot(equals(unsetOp)));

      // Validation failures
      expect(
        () => SettingPathOp(op: 'invalid', path: ['a']),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => SettingPathOp(op: 'set', path: ['a'], jsonValue: null),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
