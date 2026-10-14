/// Tests for the `officeToPdf/render` wire path.
///
/// The result is `RenderedDocumentBytes`
/// (`reference/deepseek-harness/packages/document/office-to-pdf/src/types.ts:48-51`):
/// a `WorkspaceFileBytes` plus `missingFonts`, so the reply rides the same
/// multipart attachment carrier `workspaceFiles/readBytes` uses
/// (`reference/deepseek-harness/packages/client/connection/src/rpc-host.ts:300-311`).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:harness_adapter/src/dsh_connection_manager.dart';
import 'package:harness_adapter/src/dsh_wire_types.dart';
import 'package:harness_adapter/src/harness_repository_impl.dart';
import 'package:harness_adapter/src/rpc_map.dart';
import 'package:network/dsh_event_socket.dart';
import 'package:network/dsh_exceptions.dart';
import 'package:network/dsh_rpc_client.dart';
import 'package:network/rpc_binary_envelope.dart';
import 'package:network/rpc_envelope.dart';
import 'package:test/test.dart';

/// The boundary undici mints for a `FormData` body, shortened.
const String _boundary = '----formdata-undici-0.1234567890';

const String _contentType = 'multipart/form-data; boundary=$_boundary';

void main() {
  group('OfficePdfDocumentWire (DSH 0.2.0)', () {
    test('decodes the complete render result and its missing fonts', () {
      final wire = OfficePdfDocumentWire.fromJson(<String, Object?>{
        'absolutePath': '/workspace/report.docx',
        'version': 'v7',
        'bytes': 4,
        'offset': 0,
        'data': Uint8List.fromList(<int>[37, 80, 68, 70]),
        'eof': true,
        'missingFonts': <Object?>['Calibri', 'Cambria'],
      });

      expect(wire.absolutePath, '/workspace/report.docx');
      expect(wire.version, 'v7');
      expect(wire.bytes, 4);
      expect(wire.offset, 0);
      expect(wire.data, <int>[37, 80, 68, 70]);
      expect(wire.eof, isTrue);
      expect(wire.missingFonts, <String>['Calibri', 'Cambria']);
    });

    test('an empty missingFonts list is a valid render', () {
      final wire = OfficePdfDocumentWire.fromJson(<String, Object?>{
        'absolutePath': '/workspace/report.xlsx',
        'version': 'v1',
        'offset': 0,
        'data': Uint8List(0),
        'eof': true,
        'missingFonts': <Object?>[],
      });

      expect(wire.missingFonts, isEmpty);
      expect(wire.bytes, isNull);
    });

    test('fails loud on every missing required field, naming it', () {
      final complete = <String, Object?>{
        'absolutePath': '/workspace/report.docx',
        'version': 'v7',
        'bytes': 4,
        'offset': 0,
        'data': Uint8List.fromList(<int>[37, 80, 68, 70]),
        'eof': true,
        'missingFonts': <Object?>['Calibri'],
      };
      for (final field in <String>[
        'absolutePath',
        'version',
        'offset',
        'data',
        'eof',
        'missingFonts',
      ]) {
        final json = Map<String, Object?>.from(complete)..remove(field);
        expect(
          () => OfficePdfDocumentWire.fromJson(json),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains(field),
            ),
          ),
          reason: 'removing "$field" must fail loud',
        );
      }
    });

    test('fails loud when the byte part never arrived', () {
      // The result codec leaves `data: null`; only the transport's attachment
      // splice fills it in, so a `null` here is a carrier that did not carry
      // the binary part.
      expect(
        () => OfficePdfDocumentWire.fromJson(<String, Object?>{
          'absolutePath': '/workspace/report.docx',
          'version': 'v7',
          'offset': 0,
          'data': null,
          'eof': true,
          'missingFonts': <Object?>[],
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

    test('fails loud on a non-string missing-font member', () {
      expect(
        () => OfficePdfDocumentWire.fromJson(<String, Object?>{
          'absolutePath': '/workspace/report.docx',
          'version': 'v7',
          'offset': 0,
          'data': Uint8List(0),
          'eof': true,
          'missingFonts': <Object?>['Calibri', 7],
        }),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('missingFonts'),
          ),
        ),
      );
    });
  });

  group('HarnessRepositoryImpl office conversion', () {
    test(
      'renderOfficeToPdf sends the scope lookup, path and foreground',
      () async {
        final rpc = _FakeRenderRpc();
        final manager = DshConnectionManager(_FakeSocket(), (_) => 10000);
        final repo = HarnessRepositoryImpl(rpc, manager);

        final document = await repo.renderOfficeToPdf(
          'session-1',
          'report.docx',
        );

        expect(
          rpc.calls.containsKey(DshRpcEndpoints.officeToPdfRender),
          isTrue,
        );
        final args =
            rpc.calls[DshRpcEndpoints.officeToPdfRender]!.last['args']
                as JsonMap?;
        // The scope argument is the shared `workspaceFileScope` lookup's wire
        // field; `sessionId` is refused by the host as an unknown argument.
        expect(args?['workspaceFileScopeId'], 'session-1');
        expect(args?.containsKey('sessionId'), isFalse);
        expect(args?['path'], 'report.docx');
        expect(args?['priority'], 'foreground');
        // Cancellation is the transport's injected `signal`, never an `args`
        // member.
        expect(args?.containsKey('signal'), isFalse);

        expect(document.data, <int>[37, 80, 68, 70]);
        expect(document.missingFonts, <String>['Calibri']);
      },
    );

    test('renderOfficeToPdf decodes the multipart byte carrier', () async {
      const pdf = <int>[0x25, 0x50, 0x44, 0x46, 0x2d, 0x31, 0x2e, 0x37];
      final rpc = _FakeRenderRpc()..carrierBody = _carrier(pdf: pdf);
      final manager = DshConnectionManager(_FakeSocket(), (_) => 10000);
      final repo = HarnessRepositoryImpl(rpc, manager);

      final document = await repo.renderOfficeToPdf('session-1', 'report.docx');

      expect(document.data, pdf);
      expect(document.missingFonts, <String>['Calibri', 'Cambria']);
    });

    test('a document-render/failed refusal keeps its reason', () async {
      final rpc = _FakeRenderRpc()
        ..failure = RpcError(
          code: 'document-render/failed',
          message: 'Office conversion failed.',
          details: <String, Object?>{'reason': 'unsupported-format'},
        );
      final manager = DshConnectionManager(_FakeSocket(), (_) => 10000);
      final repo = HarnessRepositoryImpl(rpc, manager);

      await expectLater(
        repo.renderOfficeToPdf('session-1', 'report.docx'),
        throwsA(
          isA<DshBusinessException>()
              .having((error) => error.code, 'code', 'document-render/failed')
              .having(
                (error) => error.details?['reason'],
                'details.reason',
                'unsupported-format',
              ),
        ),
      );
    });
  });
}

class _FakeRenderRpc implements DshRpcClient {
  final Map<String, List<JsonMap>> calls = <String, List<JsonMap>>{};

  /// A raw `multipart/form-data` body shaped like the host's reply. When set,
  /// `call` runs it through the transport decoder the HTTP client uses, so the
  /// binary carrier is exercised end to end.
  List<int>? carrierBody;

  /// The `data` member of a JSON reply. Null leaves the codec's unspliced
  /// placeholder.
  Object? data = Uint8List.fromList(<int>[37, 80, 68, 70]);

  List<String> missingFonts = <String>['Calibri'];

  RpcError? failure;

  @override
  Future<RpcResult> call(
    String endpoint,
    String method,
    JsonMap payload, {
    Duration? timeout,
  }) async {
    calls.putIfAbsent(endpoint, () => <JsonMap>[]).add(payload);
    if (endpoint != DshRpcEndpoints.officeToPdfRender) {
      return RpcResult(ok: true, value: <String, Object?>{});
    }
    final body = carrierBody;
    if (body != null) {
      return decodeRpcAttachmentResponse(
        bodyBytes: body,
        contentType: _contentType,
      ).result;
    }
    final refusal = failure;
    if (refusal != null) {
      return RpcResult(ok: false, error: refusal);
    }
    return RpcResult(
      ok: true,
      value: _renderValue(data: data, missingFonts: missingFonts),
    );
  }

  @override
  Future<void> respond(String rpcId, RpcResult result) async {}
}

/// A `RenderedDocumentBytes` result value, its byte field as the codec left it.
Map<String, Object?> _renderValue({
  required Object? data,
  required List<String> missingFonts,
}) => <String, Object?>{
  'absolutePath': '/workspace/report.docx',
  'version': 'v7',
  'bytes': 4,
  'offset': 0,
  'data': data,
  'eof': true,
  'missingFonts': missingFonts,
};

/// The multipart carrier the host writes for one byte-field result.
List<int> _carrier({required List<int> pdf}) {
  final metadata = jsonEncode(<String, Object?>{
    'type': 'server-response',
    'rpcId': 'rpc-1',
    'result': <String, Object?>{
      'ok': true,
      'value': _renderValue(
        data: null,
        missingFonts: <String>['Calibri', 'Cambria'],
      ),
    },
    'attachments': <Map<String, Object?>>[
      <String, Object?>{
        'path': <Object?>['data'],
        'codec': 'bytes',
        'part': 'bytes-0',
      },
    ],
  });
  final out = <int>[];
  void line(String value) => out.addAll(utf8.encode(value));
  line('--$_boundary\r\n');
  line('Content-Disposition: form-data; name="bytes-0"; filename="blob"\r\n');
  line('Content-Type: application/octet-stream\r\n\r\n');
  out.addAll(pdf);
  line('\r\n');
  line('--$_boundary\r\n');
  line('Content-Disposition: form-data; name="metadata"\r\n\r\n');
  line(metadata);
  line('\r\n');
  line('--$_boundary--\r\n');
  return out;
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
