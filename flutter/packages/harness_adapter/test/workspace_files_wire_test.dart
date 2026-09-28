import 'dart:async';
import 'dart:typed_data';

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

    test('WorkspaceFileBytesWire decodes the spliced byte view', () {
      final json = <String, Object?>{
        'absolutePath': '/workspace/blob.bin',
        'version': 'v9',
        'bytes': 4,
        'offset': 0,
        'data': Uint8List.fromList(<int>[0, 1, 254, 255]),
        'eof': true,
      };

      final wire = WorkspaceFileBytesWire.fromJson(json);
      expect(wire.absolutePath, '/workspace/blob.bin');
      expect(wire.version, 'v9');
      expect(wire.bytes, 4);
      expect(wire.offset, 0);
      expect(wire.data, <int>[0, 1, 254, 255]);
      expect(wire.eof, isTrue);
    });

    test('WorkspaceFileBytesWire accepts a JSON number array for data', () {
      final wire = WorkspaceFileBytesWire.fromJson(<String, Object?>{
        'absolutePath': '/workspace/blob.bin',
        'version': 'v9',
        'offset': 0,
        'data': <Object?>[7, 8],
        'eof': false,
      });

      expect(wire.data, <int>[7, 8]);
      expect(wire.bytes, isNull);
      expect(wire.eof, isFalse);
    });

    test('WorkspaceFileBytesWire fails loud when the bytes never arrived', () {
      // The result codec leaves `data: null`; only the transport's attachment
      // splice fills it in, so a `null` here is a carrier that did not carry
      // the binary part.
      expect(
        () => WorkspaceFileBytesWire.fromJson(<String, Object?>{
          'absolutePath': '/workspace/blob.bin',
          'version': 'v9',
          'offset': 0,
          'data': null,
          'eof': true,
        }),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('data'),
          ),
        ),
      );
      expect(
        () => WorkspaceFileBytesWire.fromJson(<String, Object?>{
          'absolutePath': '/workspace/blob.bin',
          'version': 'v9',
          'offset': 0,
          'eof': true,
        }),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('data'),
          ),
        ),
      );
    });

    test('WorkspaceFileBytesWire rejects a non-byte data element', () {
      expect(
        () => WorkspaceFileBytesWire.fromJson(<String, Object?>{
          'absolutePath': '/workspace/blob.bin',
          'version': 'v9',
          'offset': 0,
          'data': <Object?>[1, 'two'],
          'eof': true,
        }),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('data'),
          ),
        ),
      );
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
        // The scope argument is the `workspaceFileScope` lookup's wire field;
        // `sessionId` is refused by the host as an unknown argument.
        expect(args?['workspaceFileScopeId'], 'session-1');
        expect(args?.containsKey('sessionId'), isFalse);
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

    test('readWorkspaceFileBytes reads the whole file with empty options', () async {
      final rpc = _FakeFilesRpc();
      final manager = DshConnectionManager(_FakeSocket(), (_) => 10000);
      final repo = HarnessRepositoryImpl(rpc, manager);

      final bytes = await repo.readWorkspaceFileBytes('session-1', 'blob.bin');
      expect(rpc.calls.containsKey('workspaceFiles/readBytes'), isTrue);
      final args =
          rpc.calls['workspaceFiles/readBytes']!.last['args'] as JsonMap?;
      // The scope argument is the `workspaceFileScope` lookup's wire field;
      // `sessionId` is refused by the host as an unknown argument.
      expect(args?['workspaceFileScopeId'], 'session-1');
      expect(args?.containsKey('sessionId'), isFalse);
      expect(args?['path'], 'blob.bin');
      // `options` is required on the wire; `{}` means "no range" = whole file.
      expect(args?['options'], <String, Object?>{});

      expect(bytes.absolutePath, '/workspace/blob.bin');
      expect(bytes.version, 'v9');
      expect(bytes.bytes, 4);
      expect(bytes.offset, 0);
      expect(bytes.eof, isTrue);
      expect(bytes.data, <int>[0, 1, 254, 255]);
    });

    test(
      'readWorkspaceFileBytes sends the byte window and base file',
      () async {
        final rpc = _FakeFilesRpc();
        final manager = DshConnectionManager(_FakeSocket(), (_) => 10000);
        final repo = HarnessRepositoryImpl(rpc, manager);

        await repo.readWorkspaceFileBytes(
          'session-1',
          'blob.bin',
          offset: 4,
          length: 8,
          baseFile: 'notes.txt',
        );
        final args =
            rpc.calls['workspaceFiles/readBytes']!.last['args'] as JsonMap?;
        final options = args?['options'] as JsonMap?;
        expect(options?['range'], <String, Object?>{'offset': 4, 'length': 8});
        expect(options?['baseFile'], 'notes.txt');
      },
    );

    test('readWorkspaceFileBytes decodes an empty file', () async {
      final rpc = _FakeFilesRpc()
        ..readBytesData = Uint8List(0)
        ..readBytesSize = 0;
      final manager = DshConnectionManager(_FakeSocket(), (_) => 10000);
      final repo = HarnessRepositoryImpl(rpc, manager);

      final bytes = await repo.readWorkspaceFileBytes('session-1', 'empty.bin');
      expect(bytes.data, isEmpty);
      expect(bytes.bytes, 0);
      expect(bytes.eof, isTrue);
    });

    test(
      'readWorkspaceFileBytes fails loud when the byte part never arrived',
      () async {
        // A reply whose `data` is still the codec's `null` placeholder: the
        // transport carried no binary part.
        final rpc = _FakeFilesRpc()..readBytesData = null;
        final manager = DshConnectionManager(_FakeSocket(), (_) => 10000);
        final repo = HarnessRepositoryImpl(rpc, manager);

        await expectLater(
          repo.readWorkspaceFileBytes('session-1', 'blob.bin'),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('data'),
            ),
          ),
        );
      },
    );

    test('statWorkspaceFile invokes workspaceFiles/stat', () async {
      final rpc = _FakeFilesRpc();
      final manager = DshConnectionManager(_FakeSocket(), (_) => 10000);
      final repo = HarnessRepositoryImpl(rpc, manager);

      final stat = await repo.statWorkspaceFile('session-1', 'doc.txt');
      expect(rpc.calls.containsKey('workspaceFiles/stat'), isTrue);
      final statArgs =
          rpc.calls['workspaceFiles/stat']!.last['args'] as JsonMap?;
      expect(statArgs?['workspaceFileScopeId'], 'session-1');
      expect(statArgs?.containsKey('sessionId'), isFalse);
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
      final listArgs =
          rpc.calls['workspaceFiles/list']!.last['args'] as JsonMap?;
      expect(listArgs?['workspaceFileScopeId'], 'session-1');
      expect(listArgs?.containsKey('sessionId'), isFalse);
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

  /// Bytes a `workspaceFiles/readBytes` reply carries. Null leaves the codec's
  /// unspliced `data` placeholder, the shape a transport that dropped the
  /// binary part would deliver.
  Object? readBytesData = Uint8List.fromList(<int>[0, 1, 254, 255]);

  int readBytesSize = 4;

  @override
  Future<RpcResult> call(
    String endpoint,
    String method,
    JsonMap payload, {
    Duration? timeout,
  }) async {
    calls.putIfAbsent(endpoint, () => <JsonMap>[]).add(payload);
    if (endpoint == 'workspaceFiles/readBytes') {
      return RpcResult(
        ok: true,
        value: <String, Object?>{
          'absolutePath': '/workspace/blob.bin',
          'version': 'v9',
          'bytes': readBytesSize,
          'offset': 0,
          'data': readBytesData,
          'eof': true,
        },
      );
    }
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
