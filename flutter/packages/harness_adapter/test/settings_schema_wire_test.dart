/// Tests for the settings descriptor's `schema` and `autoGenerate` decode.
///
/// The recorded envelope below was produced by the pin's own emitter:
/// `volatileForm(schema).toJSON()` run under
/// `reference/deepseek-harness/vendor/schemastery` and
/// `packages/settings/settings/src/schema.ts` for
///
/// ```ts
/// z.object({
///   mode: z.union(['one', 'two']).default('one').volatile(),
///   count: z.number().min(1).max(9).step(1).default(2).volatile(),
///   token: z.string().role('secret').volatile(),
///   path: z.string().pattern(/^\/x/).description('Path').comment('note').volatile(),
///   flags: z.bitset({ alpha: 1, beta: 2 }).volatile(),
///   cb: z.transform(z.string(), (v: string) => v.length).volatile(),
///   plain: z.string().hidden().disabled().collapse().experimental().link('https://x').volatile(),
///   rows: z.array(z.object({ name: z.string().required() })).volatile(),
///   keys: z.dict(z.number()).volatile(),
/// })
/// ```
///
/// It is the exact `schema` member
/// `packages/settings/settings/src/index.ts:326` sends and
/// `packages/api/settings-controller/src/index.ts:52` forwards.
library;

import 'dart:async';
import 'dart:convert';

import 'package:domain/model/settings.dart';
import 'package:harness_adapter/src/dsh_connection_manager.dart';
import 'package:harness_adapter/src/dsh_wire_types.dart';
import 'package:harness_adapter/src/harness_repository_impl.dart';
import 'package:network/dsh_event_socket.dart';
import 'package:network/dsh_rpc_client.dart';
import 'package:network/rpc_envelope.dart';
import 'package:test/test.dart';

/// See this library's doc comment for how this was recorded.
const String _recordedSchema = r'''
{
  "uid": 59,
  "refs": {
    "43": { "type": "const", "meta": { "required": true }, "value": "one" },
    "44": { "type": "const", "meta": { "required": true }, "value": "two" },
    "45": { "type": "union", "meta": { "default": "one" }, "list": [43, 44] },
    "46": { "type": "number", "meta": { "min": 1, "max": 9, "step": 1, "default": 2 } },
    "47": { "type": "string", "meta": { "role": "secret" } },
    "48": {
      "type": "string",
      "meta": {
        "pattern": { "source": "^\\/x", "flags": "" },
        "description": "Path",
        "comment": "note"
      }
    },
    "49": { "type": "bitset", "meta": { "default": 0 }, "bits": { "alpha": 1, "beta": 2 } },
    "50": { "type": "string", "meta": {} },
    "51": { "type": "transform", "meta": {}, "inner": 50 },
    "52": {
      "type": "string",
      "meta": {
        "hidden": true,
        "disabled": true,
        "collapse": true,
        "badges": [{ "text": "experimental", "type": "warning" }],
        "link": "https://x"
      }
    },
    "53": { "type": "string", "meta": { "required": true } },
    "54": { "type": "object", "meta": { "default": {} }, "dict": { "name": 53 } },
    "55": { "type": "array", "meta": { "default": [] }, "inner": 54 },
    "56": { "type": "number", "meta": {} },
    "57": { "type": "string", "meta": {} },
    "58": { "type": "dict", "meta": { "default": {} }, "inner": 56, "sKey": 57 },
    "59": {
      "type": "object",
      "meta": { "default": {} },
      "dict": {
        "mode": 45,
        "count": 46,
        "token": 47,
        "path": 48,
        "flags": 49,
        "cb": 51,
        "plain": 52,
        "rows": 55,
        "keys": 58
      }
    }
  }
}
''';

void main() {
  group('decodeSettingsSchema on the recorded envelope', () {
    late SettingsSchema schema;

    setUp(() {
      schema = decodeSettingsSchema(jsonDecode(_recordedSchema));
    });

    test('keeps the root and names the declared fields in order', () {
      expect(schema.root.uid, 59);
      expect(schema.root.type, 'object');
      expect(schema.root.meta.defaultValue, <String, Object?>{});
      expect(schema.dictOf(schema.root).keys, <String>[
        'mode',
        'count',
        'token',
        'path',
        'flags',
        'cb',
        'plain',
        'rows',
        'keys',
      ]);
    });

    test('a union of constants carries the option values', () {
      final mode = schema.dictOf(schema.root)['mode']!;
      expect(mode.type, 'union');
      expect(mode.meta.defaultValue, 'one');
      final options = schema.listOf(mode);
      expect(options.map((node) => node.type), <String>['const', 'const']);
      expect(options.map((node) => node.value), <String>['one', 'two']);
      expect(options.first.meta.required, isTrue);
    });

    test('numeric bounds and stepping decode', () {
      final count = schema.dictOf(schema.root)['count']!;
      expect(count.type, 'number');
      expect(count.meta.min, 1);
      expect(count.meta.max, 9);
      expect(count.meta.step, 1);
      expect(count.meta.defaultValue, 2);
    });

    test('a renderer role decodes', () {
      expect(schema.dictOf(schema.root)['token']!.meta.role, 'secret');
    });

    test('pattern, label, and comment decode', () {
      final meta = schema.dictOf(schema.root)['path']!.meta;
      expect(meta.pattern!.source, r'^\/x');
      expect(meta.pattern!.flags, '');
      expect(meta.description, <String, String>{'': 'Path'});
      expect(meta.labelFor('zh'), 'Path');
      expect(meta.comment, 'note');
    });

    test('a bitset carries its bit positions', () {
      final flags = schema.dictOf(schema.root)['flags']!;
      expect(flags.type, 'bitset');
      expect(flags.bits, <String, int>{'alpha': 1, 'beta': 2});
      expect(flags.meta.defaultValue, 0);
    });

    test('a transform resolves its element node and carries no callback', () {
      // The descriptor's schema is rehydrated by `plainSchema` before it is
      // serialized, and rehydration turns the recorded callback source text
      // back into a function, which JSON drops. The element node survives.
      final transform = schema.dictOf(schema.root)['cb']!;
      expect(transform.type, 'transform');
      expect(transform.callback, isNull);
      expect(schema.innerOf(transform)!.type, 'string');
    });

    test('hidden, disabled, collapse, badges, and link decode', () {
      final meta = schema.dictOf(schema.root)['plain']!.meta;
      expect(meta.hidden, isTrue);
      expect(meta.disabled, isTrue);
      expect(meta.collapse, isTrue);
      expect(meta.link, 'https://x');
      expect(meta.badges, <SettingsSchemaBadge>[
        const SettingsSchemaBadge(text: 'experimental', type: 'warning'),
      ]);
    });

    test('an array resolves its element object and that object its fields', () {
      final rows = schema.dictOf(schema.root)['rows']!;
      expect(rows.type, 'array');
      final element = schema.innerOf(rows)!;
      expect(element.type, 'object');
      expect(schema.dictOf(element)['name']!.meta.required, isTrue);
    });

    test('a dict resolves both its element and its key schema', () {
      final keys = schema.dictOf(schema.root)['keys']!;
      expect(keys.type, 'dict');
      expect(schema.innerOf(keys)!.type, 'number');
      expect(schema.sKeyOf(keys)!.type, 'string');
    });
  });

  group('decodeSettingsSchema edge cases', () {
    test('a recursive envelope decodes without looping', () {
      final schema = decodeSettingsSchema(<String, Object?>{
        'uid': 1,
        'refs': <String, Object?>{
          '1': <String, Object?>{
            'type': 'object',
            'dict': <String, Object?>{'child': 2},
          },
          '2': <String, Object?>{'type': 'lazy', 'inner': 1},
        },
      });

      final field = schema.dictOf(schema.root)['child']!;
      expect(field.type, 'lazy');
      expect(schema.innerOf(field), same(schema.root));
    });

    test('a node kind the pin does not know is carried, not rejected', () {
      final schema = decodeSettingsSchema(<String, Object?>{
        'uid': 1,
        'refs': <String, Object?>{
          '1': <String, Object?>{
            'type': 'plugin-defined',
            'meta': <String, Object?>{},
          },
        },
      });
      expect(schema.root.type, 'plugin-defined');
    });

    test('a malformed envelope fails loud, never as an empty form', () {
      final cases = <String, Object?>{
        'not an object': null,
        'no refs': <String, Object?>{'uid': 1},
        'empty refs': <String, Object?>{'uid': 1, 'refs': <String, Object?>{}},
        'root uid absent from refs': <String, Object?>{
          'uid': 9,
          'refs': <String, Object?>{
            '1': <String, Object?>{'type': 'object'},
          },
        },
        'ref key not a uid': <String, Object?>{
          'uid': 1,
          'refs': <String, Object?>{
            'x': <String, Object?>{'type': 'object'},
          },
        },
        'ref value not a node': <String, Object?>{
          'uid': 1,
          'refs': <String, Object?>{'1': 'nope'},
        },
        'node without a type': <String, Object?>{
          'uid': 1,
          'refs': <String, Object?>{
            '1': <String, Object?>{'meta': <String, Object?>{}},
          },
        },
        'dict naming a missing ref': <String, Object?>{
          'uid': 1,
          'refs': <String, Object?>{
            '1': <String, Object?>{
              'type': 'object',
              'dict': <String, Object?>{'field': 42},
            },
          },
        },
        'inner naming a missing ref': <String, Object?>{
          'uid': 1,
          'refs': <String, Object?>{
            '1': <String, Object?>{'type': 'array', 'inner': 42},
          },
        },
        'list naming a missing ref': <String, Object?>{
          'uid': 1,
          'refs': <String, Object?>{
            '1': <String, Object?>{
              'type': 'union',
              'list': <Object?>[42],
            },
          },
        },
        'sKey naming a missing ref': <String, Object?>{
          'uid': 1,
          'refs': <String, Object?>{
            '1': <String, Object?>{'type': 'dict', 'sKey': 42},
          },
        },
        'description locale not a string': <String, Object?>{
          'uid': 1,
          'refs': <String, Object?>{
            '1': <String, Object?>{
              'type': 'string',
              'meta': <String, Object?>{
                'description': <String, Object?>{'zh': 3},
              },
            },
          },
        },
        'description not text at all': <String, Object?>{
          'uid': 1,
          'refs': <String, Object?>{
            '1': <String, Object?>{
              'type': 'string',
              'meta': <String, Object?>{
                'description': <Object?>[1],
              },
            },
          },
        },
        'badge without text': <String, Object?>{
          'uid': 1,
          'refs': <String, Object?>{
            '1': <String, Object?>{
              'type': 'string',
              'meta': <String, Object?>{
                'badges': <Object?>[
                  <String, Object?>{'type': 'warning'},
                ],
              },
            },
          },
        },
        'pattern without a source': <String, Object?>{
          'uid': 1,
          'refs': <String, Object?>{
            '1': <String, Object?>{
              'type': 'string',
              'meta': <String, Object?>{
                'pattern': <String, Object?>{'flags': ''},
              },
            },
          },
        },
        'max not a number': <String, Object?>{
          'uid': 1,
          'refs': <String, Object?>{
            '1': <String, Object?>{
              'type': 'number',
              'meta': <String, Object?>{'max': 'nine'},
            },
          },
        },
        'bit not an integer': <String, Object?>{
          'uid': 1,
          'refs': <String, Object?>{
            '1': <String, Object?>{
              'type': 'bitset',
              'bits': <String, Object?>{'alpha': 'one'},
            },
          },
        },
      };

      cases.forEach((name, value) {
        expect(
          () => decodeSettingsSchema(value),
          throwsA(isA<FormatException>()),
          reason: name,
        );
      });
    });
  });

  group('SettingsNamespaceWire', () {
    test('decodes autoGenerate and the schema projection', () {
      final wire = SettingsNamespaceWire.fromJson(<String, Object?>{
        'ns': 'llm-deepseek',
        'autoGenerate': true,
        'schema': jsonDecode(_recordedSchema),
        'value': <String, Object?>{'mode': 'one'},
        'applies': 'live',
        'secrets': <Object?>[],
        'revision': 3,
      });

      expect(wire.ns, 'llm-deepseek');
      expect(wire.autoGenerate, isTrue);
      expect(wire.schema.root.type, 'object');
      expect(wire.schema.dictOf(wire.schema.root), hasLength(9));
    });

    test('a withheld autoGenerate reads as no generated page', () {
      final wire = SettingsNamespaceWire.fromJson(<String, Object?>{
        'ns': 'shell',
        'schema': jsonDecode(_recordedSchema),
        'applies': 'live',
        'revision': 0,
      });

      expect(wire.autoGenerate, isFalse);
    });

    test('an absent schema fails loud naming the field', () {
      expect(
        () => SettingsNamespaceWire.fromJson(<String, Object?>{
          'ns': 'shell',
          'autoGenerate': true,
          'applies': 'live',
          'revision': 0,
        }),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('schema'),
          ),
        ),
      );
    });
  });

  group('HarnessRepositoryImpl describeSettings', () {
    test('surfaces autoGenerate and the decoded schema', () async {
      final rpc = _FakeSettingsRpc();
      final manager = DshConnectionManager(_FakeSocket(), (_) => 10000);
      final repo = HarnessRepositoryImpl(rpc, manager);

      final snapshot = await repo.describeSettings();
      expect(snapshot.namespaces, hasLength(1));
      final namespace = snapshot.namespaces.single;
      expect(namespace.ns, 'llm-deepseek');
      expect(namespace.autoGenerate, isTrue);
      final fields = namespace.schema.dictOf(namespace.schema.root);
      expect(fields.keys, <String>['mode', 'count']);
      expect(fields['mode']!.type, 'const');
      expect(fields['mode']!.value, 'one');
      expect(fields['count']!.meta.min, 1);
    });

    test('a malformed schema fails the read loud', () async {
      final rpc = _FakeSettingsRpc()..schema = <String, Object?>{'uid': 1};
      final manager = DshConnectionManager(_FakeSocket(), (_) => 10000);
      final repo = HarnessRepositoryImpl(rpc, manager);

      await expectLater(
        repo.describeSettings(),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

class _FakeSettingsRpc implements DshRpcClient {
  /// The `schema` member the fake descriptor answers with.
  Object? schema = <String, Object?>{
    'uid': 1,
    'refs': <String, Object?>{
      '1': <String, Object?>{
        'type': 'object',
        'dict': <String, Object?>{'mode': 2, 'count': 3},
      },
      '2': <String, Object?>{'type': 'const', 'value': 'one'},
      '3': <String, Object?>{
        'type': 'number',
        'meta': <String, Object?>{'min': 1},
      },
    },
  };

  @override
  Future<RpcResult> call(
    String endpoint,
    String method,
    JsonMap payload, {
    Duration? timeout,
  }) async {
    expect(endpoint, 'settings/describe');
    return RpcResult(
      ok: true,
      value: <String, Object?>{
        'writable': true,
        'hasDocument': true,
        'namespaces': <Object?>[
          <String, Object?>{
            'ns': 'llm-deepseek',
            'autoGenerate': true,
            'schema': schema,
            'value': <String, Object?>{'mode': 'one'},
            'applies': 'live',
            'secrets': <Object?>[],
            'revision': 1,
          },
        ],
      },
    );
  }

  @override
  Future<void> respond(String rpcId, RpcResult result) async {}
}

/// A downlink seam that answers the generation handshake and then stays open.
class _FakeSocket implements DshEventSocket {
  @override
  Stream<ServerRequest> connect(String path, {void Function()? onOpen}) async* {
    onOpen?.call();
    yield ServerRequest(
      rpcId: 'remote-events',
      method: 'item',
      payload: <String, Object?>{
        'type': 'ready',
        'clientId': 'client-1',
        'host': <String, Object?>{'home': '/home/tester'},
      },
    );
    await Completer<void>().future;
  }
}
