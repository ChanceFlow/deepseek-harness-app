import 'dart:async';

import 'package:harness_adapter/src/dsh_connection_manager.dart';
import 'package:harness_adapter/src/dsh_wire_types.dart';
import 'package:harness_adapter/src/harness_repository_impl.dart';
import 'package:network/dsh_event_socket.dart';
import 'package:network/dsh_rpc_client.dart';
import 'package:network/rpc_envelope.dart';
import 'package:test/test.dart';

void main() {
  group('WorkspaceFiles wire DTOs (DSH 0.1.5)', () {
    test(
      'WorkspaceFileStatWire decodes valid json and handles optional bytes',
      () {
        final json = <String, Object?>{
          'absolutePath': '/workspace/README.md',
          'version': 'v1-hash-1234',
          'bytes': 2048,
        };

        final stat = WorkspaceFileStatWire.fromJson(json);
        expect(stat.absolutePath, '/workspace/README.md');
        expect(stat.version, 'v1-hash-1234');
        expect(stat.bytes, 2048);

        final jsonNoBytes = <String, Object?>{
          'absolutePath': '/workspace/README.md',
          'version': 'v1-hash-1234',
        };
        final stat2 = WorkspaceFileStatWire.fromJson(jsonNoBytes);
        expect(stat2.bytes, isNull);
      },
    );

    test('WorkspaceFileStatWire fails loud on missing required fields', () {
      expect(
        () =>
            WorkspaceFileStatWire.fromJson(<String, Object?>{'version': 'v1'}),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('absolutePath'),
          ),
        ),
      );
      expect(
        () => WorkspaceFileStatWire.fromJson(<String, Object?>{
          'absolutePath': '/a',
        }),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('version'),
          ),
        ),
      );
    });

    test('WorkspaceFileTextWire decodes complete paged text payload', () {
      final json = <String, Object?>{
        'absolutePath': '/workspace/src/main.dart',
        'version': 'ver-abc',
        'bytes': 512,
        'offset': 1,
        'text': 'void main() {\n  print("hello");\n}',
        'lines': 3,
        'eof': true,
      };

      final textWire = WorkspaceFileTextWire.fromJson(json);
      expect(textWire.absolutePath, '/workspace/src/main.dart');
      expect(textWire.version, 'ver-abc');
      expect(textWire.bytes, 512);
      expect(textWire.offset, 1);
      expect(textWire.text, 'void main() {\n  print("hello");\n}');
      expect(textWire.lines, 3);
      expect(textWire.eof, isTrue);
    });

    test('WorkspaceDirectoryListingWire decodes entries and truncated', () {
      final json = <String, Object?>{
        'path': 'src',
        'entries': <Object?>[
          <String, Object?>{'name': 'main.dart', 'type': 'file', 'size': 512},
          <String, Object?>{'name': 'utils', 'type': 'directory'},
        ],
        'truncated': false,
      };

      final listing = WorkspaceDirectoryListingWire.fromJson(json);
      expect(listing.path, 'src');
      expect(listing.truncated, isFalse);
      expect(listing.entries.length, 2);
      expect(listing.entries[0].name, 'main.dart');
      expect(listing.entries[0].type, 'file');
      expect(listing.entries[0].size, 512);
      expect(listing.entries[1].name, 'utils');
      expect(listing.entries[1].type, 'directory');
      expect(listing.entries[1].size, isNull);
    });
  });

  group('HarnessRepositoryImpl WorkspaceFiles operations', () {
    test(
      'readWorkspaceFile invokes workspaceFiles/read with correct payload',
      () async {
        final rpc = _FakeFilesRpc();
        final manager = DshConnectionManager(_FakeSocket(), (_) => 10000);
        final repo = HarnessRepositoryImpl(rpc, manager);

        final content = await repo.readWorkspaceFile(
          'session-1',
          'README.md',
          offset: 1,
          limit: 50,
        );
        expect(rpc.calls.containsKey('workspaceFiles/read'), isTrue);
        final calledPayload = rpc.calls['workspaceFiles/read']!.last;
        final args = calledPayload['args'] as JsonMap?;
        expect(args?['sessionId'], 'session-1');
        expect(args?['path'], 'README.md');
        final range = args?['range'] as JsonMap?;
        expect(range?['offset'], 1);
        expect(range?['limit'], 50);

        expect(content.absolutePath, '/workspace/README.md');
        expect(content.text, '# Hello');
        expect(content.lines, 1);
        expect(content.eof, isTrue);
      },
    );

    test('statWorkspaceFile invokes workspaceFiles/stat', () async {
      final rpc = _FakeFilesRpc();
      final manager = DshConnectionManager(_FakeSocket(), (_) => 10000);
      final repo = HarnessRepositoryImpl(rpc, manager);

      final stat = await repo.statWorkspaceFile('session-1', 'doc.txt');
      expect(rpc.calls.containsKey('workspaceFiles/stat'), isTrue);
      expect(stat.absolutePath, '/workspace/doc.txt');
      expect(stat.version, 'v2');
      expect(stat.bytes, 500);
    });

    test('listWorkspaceDirectory invokes workspaceFiles/list', () async {
      final rpc = _FakeFilesRpc();
      final manager = DshConnectionManager(_FakeSocket(), (_) => 10000);
      final repo = HarnessRepositoryImpl(rpc, manager);

      final listing = await repo.listWorkspaceDirectory('session-1', '');
      expect(rpc.calls.containsKey('workspaceFiles/list'), isTrue);
      expect(listing.path, '');
      expect(listing.truncated, isFalse);
      expect(listing.entries.length, 2);
      expect(listing.entries[0].name, 'lib');
      expect(listing.entries[0].type, 'directory');
      expect(listing.entries[1].name, 'pubspec.yaml');
      expect(listing.entries[1].size, 120);
    });
  });
}

class _FakeFilesRpc implements DshRpcClient {
  final Map<String, List<JsonMap>> calls = <String, List<JsonMap>>{};

  @override
  Future<RpcResult> call(
    String endpoint,
    String method,
    JsonMap payload, {
    Duration? timeout,
  }) async {
    calls.putIfAbsent(endpoint, () => <JsonMap>[]).add(payload);
    if (endpoint == 'workspaceFiles/read') {
      return RpcResult(
        ok: true,
        value: <String, Object?>{
          'absolutePath': '/workspace/README.md',
          'version': 'v1',
          'bytes': 100,
          'offset': 1,
          'text': '# Hello',
          'lines': 1,
          'eof': true,
        },
      );
    }
    if (endpoint == 'workspaceFiles/stat') {
      return RpcResult(
        ok: true,
        value: <String, Object?>{
          'absolutePath': '/workspace/doc.txt',
          'version': 'v2',
          'bytes': 500,
        },
      );
    }
    if (endpoint == 'workspaceFiles/list') {
      return RpcResult(
        ok: true,
        value: <String, Object?>{
          'path': '',
          'truncated': false,
          'entries': <Object?>[
            <String, Object?>{'name': 'lib', 'type': 'directory'},
            <String, Object?>{
              'name': 'pubspec.yaml',
              'type': 'file',
              'size': 120,
            },
          ],
        },
      );
    }
    return RpcResult(ok: true, value: <String, Object?>{});
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
