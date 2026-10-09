/// Tests for the plugin-manager roster results, which are bare JSON arrays.
///
/// `pluginManager/listBundles` and `pluginManager/listPlugins` answer
/// `BundleInfo[]` and `PluginInfo[]`
/// (`reference/deepseek-harness/packages/boot/plugin-manager/src/index.ts:279-280`
/// and `:255-256`; the committed catalog at
/// `packages/extensions/tool-cordis/src/api-catalog.ts:1643,1656` carries the
/// same signatures). The result is therefore the array itself, and the
/// transport parks a non-object result under the envelope's `value` key
/// (`packages/network/lib/rpc_envelope.dart` `RpcResult.fromJson`). Requiring
/// a `bundles`/`plugins` field rejects the only shape the host ever sends.
///
/// Every fixture is built through `RpcResult.fromJson`, so the envelope park
/// under test is the real one rather than a hand-written map.
library;

import 'dart:async';

import 'package:harness_adapter/src/dsh_connection_manager.dart';
import 'package:harness_adapter/src/harness_repository_impl.dart';
import 'package:network/dsh_event_socket.dart';
import 'package:network/dsh_rpc_client.dart';
import 'package:network/rpc_envelope.dart';
import 'package:test/test.dart';

/// One `BundleInfo` row: `name`, `enabled`, `installed`, `optional`, and
/// `removable` are required, `rows` is a required object array
/// (`packages/boot/plugin-manager/src/types.ts:47-70`).
Map<String, Object?> _bundleRow({String name = 'dsh-schedule'}) =>
    <String, Object?>{
      'name': name,
      'version': '0.2.0-rc.2',
      'enabled': true,
      'installed': true,
      'optional': false,
      'removable': true,
      'rows': <Object?>[
        <String, Object?>{
          'rowId': 'schedule-core',
          'moduleName': '@deepseek-ai/dsh-schedule',
          'entryId': 'entry-1',
        },
      ],
      'overrides': <Object?>[],
    };

/// One `PluginInfo` row: a `PluginInventoryEntry` plus exactly one of
/// `patchId` or `readOnlyReason`.
Map<String, Object?> _pluginRow({String entryId = 'entry-1'}) =>
    <String, Object?>{
      'entryId': entryId,
      'moduleName': '@deepseek-ai/dsh-schedule',
      'enabled': true,
      'patchId': 'patch-1',
    };

void main() {
  group('listPluginBundles', () {
    test('decodes the bare array the method answers with', () async {
      final repository = _repository(_BareResultRpc(<Object?>[_bundleRow()]));

      final bundles = await repository.listPluginBundles();
      expect(bundles, hasLength(1));
      expect(bundles.single.name, 'dsh-schedule');
      expect(bundles.single.installed, isTrue);
      expect(bundles.single.rows.single.rowId, 'schedule-core');
    });

    test('an empty roster is an empty array, not a missing field', () async {
      final repository = _repository(_BareResultRpc(<Object?>[]));

      expect(await repository.listPluginBundles(), isEmpty);
    });

    test('the object-wrapped shape the host never sends fails loud', () async {
      // The defect this replaced: a `{bundles: [...]}` wrapper that no
      // `BundleInfo[]` result can produce.
      final repository = _repository(
        _BareResultRpc(<String, Object?>{'bundles': <Object?>[]}),
      );

      await expectLater(
        repository.listPluginBundles(),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            allOf(contains('value'), contains('must be a JSON array')),
          ),
        ),
      );
    });

    test('a non-array result fails loud naming the envelope slot', () async {
      final repository = _repository(_BareResultRpc('not a roster'));

      await expectLater(
        repository.listPluginBundles(),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('must be a JSON array'),
          ),
        ),
      );
    });

    test('a non-object row fails loud', () async {
      final repository = _repository(_BareResultRpc(<Object?>[42]));

      await expectLater(
        repository.listPluginBundles(),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('row must be an object'),
          ),
        ),
      );
    });

    test('a row missing a required field still fails loud', () async {
      final repository = _repository(
        _BareResultRpc(<Object?>[
          <String, Object?>{'name': 'dsh-schedule', 'enabled': true},
        ]),
      );

      await expectLater(
        repository.listPluginBundles(),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('listPlugins', () {
    test('decodes the bare array the method answers with', () async {
      final repository = _repository(_BareResultRpc(<Object?>[_pluginRow()]));

      final plugins = await repository.listPlugins();
      expect(plugins, hasLength(1));
      expect(plugins.single.entryId, 'entry-1');
      expect(plugins.single.patchId, 'patch-1');
    });

    test('an empty roster is an empty array, not a missing field', () async {
      final repository = _repository(_BareResultRpc(<Object?>[]));

      expect(await repository.listPlugins(), isEmpty);
    });

    test('the object-wrapped shape the host never sends fails loud', () async {
      final repository = _repository(
        _BareResultRpc(<String, Object?>{'plugins': <Object?>[]}),
      );

      await expectLater(
        repository.listPlugins(),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            allOf(contains('value'), contains('must be a JSON array')),
          ),
        ),
      );
    });

    test('a non-array result fails loud naming the envelope slot', () async {
      final repository = _repository(_BareResultRpc('not a roster'));

      await expectLater(
        repository.listPlugins(),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('must be a JSON array'),
          ),
        ),
      );
    });

    test('a non-object row fails loud', () async {
      final repository = _repository(_BareResultRpc(<Object?>[null]));

      await expectLater(
        repository.listPlugins(),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('row must be an object'),
          ),
        ),
      );
    });
  });
}

/// Builds the repository over an RPC seam that answers one scripted result.
HarnessRepositoryImpl _repository(DshRpcClient rpc) => HarnessRepositoryImpl(
  rpc,
  DshConnectionManager(_FakeSocket(), (_) => 10000),
);

/// Answers every call with `{ok: true, value: <raw>}`, decoded through the
/// real envelope so a non-object value is parked exactly as the transport
/// parks it.
final class _BareResultRpc implements DshRpcClient {
  _BareResultRpc(this.rawValue);

  /// The wire `result.value`, as the host's JSON carries it.
  final Object? rawValue;

  @override
  Future<RpcResult> call(
    String endpoint,
    String method,
    JsonMap payload, {
    Duration? timeout,
  }) async =>
      RpcResult.fromJson(<String, Object?>{'ok': true, 'value': rawValue});

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
