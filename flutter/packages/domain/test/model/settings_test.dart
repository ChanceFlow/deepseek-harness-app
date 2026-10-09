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
      schema: SettingsSchema.empty,
    );

    test('SettingsNamespace equality and hashCode', () {
      const copy = SettingsNamespace(
        ns: 'workspace',
        applies: SettingsApplies.live,
        revision: 1,
        hasUserLayer: true,
        secretCount: 0,
        schema: SettingsSchema.empty,
      );
      const diff = SettingsNamespace(
        ns: 'workspace',
        applies: SettingsApplies.restart,
        revision: 1,
        hasUserLayer: true,
        secretCount: 0,
        schema: SettingsSchema.empty,
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
            schema: SettingsSchema.empty,
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

  group('Settings schema projection', () {
    const root = SettingsSchemaNode(
      uid: 1,
      type: 'object',
      meta: SettingsSchemaMeta(),
      dictUids: <String, int>{'mode': 2, 'count': 3},
    );
    const mode = SettingsSchemaNode(
      uid: 2,
      type: 'const',
      meta: SettingsSchemaMeta(),
      value: 'fast',
    );
    const count = SettingsSchemaNode(
      uid: 3,
      type: 'number',
      meta: SettingsSchemaMeta(
        defaultValue: 2,
        min: 1,
        max: 9,
        description: <String, String>{'': 'Count', 'zh': '数量'},
      ),
    );
    const schema = SettingsSchema(
      root: root,
      nodes: <int, SettingsSchemaNode>{1: root, 2: mode, 3: count},
    );

    test('resolves declared fields by name', () {
      final fields = schema.dictOf(schema.root);
      expect(fields.keys, <String>['mode', 'count']);
      expect(fields['mode']!.type, 'const');
      expect(fields['mode']!.value, 'fast');
      expect(fields['count']!.meta.defaultValue, 2);
      expect(fields['count']!.meta.min, 1);
      expect(fields['count']!.meta.max, 9);
    });

    test('a label follows the locale, then the unlocalized text', () {
      final meta = schema.dictOf(schema.root)['count']!.meta;
      expect(meta.labelFor('zh'), '数量');
      expect(meta.labelFor('de'), 'Count');
    });

    test('an undeclared reference resolves to nothing, not a throw', () {
      const dangling = SettingsSchemaNode(
        uid: 4,
        type: 'array',
        meta: SettingsSchemaMeta(),
        innerUid: 99,
      );
      expect(schema.innerOf(dangling), isNull);
      expect(schema.listOf(dangling), isEmpty);
    });

    test('the empty projection declares no fields', () {
      expect(SettingsSchema.empty.dictOf(SettingsSchema.empty.root), isEmpty);
      expect(SettingsSchema.empty, equals(SettingsSchema.empty));
    });

    test('equality and hashCode are structural across the node table', () {
      const copy = SettingsSchema(
        root: root,
        nodes: <int, SettingsSchemaNode>{1: root, 2: mode, 3: count},
      );
      const differentMeta = SettingsSchema(
        root: root,
        nodes: <int, SettingsSchemaNode>{
          1: root,
          2: mode,
          3: SettingsSchemaNode(
            uid: 3,
            type: 'number',
            meta: SettingsSchemaMeta(defaultValue: 3, min: 1, max: 9),
          ),
        },
      );

      expect(schema, equals(copy));
      expect(schema.hashCode, equals(copy.hashCode));
      expect(schema, isNot(equals(differentMeta)));
      expect(
        const SettingsNamespace(
          ns: 'a',
          applies: SettingsApplies.live,
          revision: 0,
          hasUserLayer: false,
          secretCount: 0,
          schema: schema,
          autoGenerate: true,
        ),
        isNot(
          equals(
            const SettingsNamespace(
              ns: 'a',
              applies: SettingsApplies.live,
              revision: 0,
              hasUserLayer: false,
              secretCount: 0,
              schema: schema,
            ),
          ),
        ),
      );
    });

    test('a missing autoGenerate reads as no generated page', () {
      const ns = SettingsNamespace(
        ns: 'a',
        applies: SettingsApplies.live,
        revision: 0,
        hasUserLayer: false,
        secretCount: 0,
        schema: SettingsSchema.empty,
      );
      expect(ns.autoGenerate, isFalse);
    });
  });
}
