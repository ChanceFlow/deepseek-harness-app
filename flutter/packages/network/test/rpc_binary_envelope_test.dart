/// Tests for the multipart binary-attachment RPC carrier.
///
/// Fixtures are framed the way the dsh host frames them
/// (`reference/deepseek-harness/packages/client/connection/src/rpc-host.ts:300-311`):
/// a `metadata` text field holding the JSON envelope (with each byte field's
/// former position left as `null`), one binary field per declared attachment,
/// and `attachments[i] = {path, codec: 'bytes', part}`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:network/dsh_exceptions.dart';
import 'package:network/http_dsh_rpc_client.dart';
import 'package:network/rpc_binary_envelope.dart';
import 'package:test/test.dart';

/// The boundary undici mints for a `FormData` body, shortened.
const String _boundary = '----formdata-undici-0.1234567890';

/// The `Content-Type` the host answers with for an attachment carrier.
const String _contentType = '$_kMediaType; boundary=$_boundary';

const String _kMediaType = 'multipart/form-data';

void main() {
  group('decodeRpcAttachmentResponse', () {
    test('splices the binary part over its null placeholder', () {
      const List<int> bytes = <int>[0, 1, 2, 254, 255];
      final response = decodeRpcAttachmentResponse(
        bodyBytes: _carrier(
          value: _bytesValue(data: null, size: 5, eof: true),
          attachments: <Map<String, Object?>>[_attachment('data', 'bytes-0')],
          parts: <_Field>[const _Field.bytes('bytes-0', bytes)],
        ),
        contentType: _contentType,
      );

      expect(response.rpcId, 'rpc-1');
      expect(response.result.ok, isTrue);
      final value = response.result.value!;
      expect(value['absolutePath'], '/workspace/blob.bin');
      expect(value['version'], 'v1');
      expect(value['bytes'], 5);
      expect(value['offset'], 0);
      expect(value['eof'], isTrue);
      expect(value['data'], isA<Uint8List>());
      expect(value['data'], bytes);
    });

    test('an empty file decodes to empty bytes and keeps eof', () {
      final response = decodeRpcAttachmentResponse(
        bodyBytes: _carrier(
          value: _bytesValue(data: null, size: 0, eof: true),
          attachments: <Map<String, Object?>>[_attachment('data', 'bytes-0')],
          parts: <_Field>[const _Field.bytes('bytes-0', <int>[])],
        ),
        contentType: _contentType,
      );

      final data = response.result.value!['data'];
      expect(data, isA<Uint8List>());
      expect(data, isEmpty);
      expect(response.result.value!['eof'], isTrue);
    });

    test('a byte window keeps its offset and non-final eof', () {
      final response = decodeRpcAttachmentResponse(
        bodyBytes: _carrier(
          value: _bytesValue(data: null, size: 4096, eof: false, offset: 1024),
          attachments: <Map<String, Object?>>[_attachment('data', 'bytes-0')],
          parts: <_Field>[
            const _Field.bytes('bytes-0', <int>[7, 7, 7]),
          ],
        ),
        contentType: _contentType,
      );

      expect(response.result.value!['offset'], 1024);
      expect(response.result.value!['eof'], isFalse);
      expect(response.result.value!['data'], <int>[7, 7, 7]);
    });

    test('a nested path is spliced where the path points', () {
      final response = decodeRpcAttachmentResponse(
        bodyBytes: _carrier(
          value: <String, Object?>{
            'stat': <String, Object?>{'absolutePath': '/workspace/blob.bin'},
            'window': <String, Object?>{'data': null},
          },
          attachments: <Map<String, Object?>>[
            _attachment(<Object?>['window', 'data'], 'bytes-0'),
          ],
          parts: <_Field>[
            const _Field.bytes('bytes-0', <int>[9, 8]),
          ],
        ),
        contentType: _contentType,
      );

      final window = response.result.value!['window']! as Map<String, Object?>;
      expect(window['data'], <int>[9, 8]);
    });

    test('a truncated part fails loud instead of returning partial bytes', () {
      // No closing delimiter: the last part never terminates.
      final body = _carrier(
        value: _bytesValue(data: null, size: 5, eof: true),
        attachments: <Map<String, Object?>>[_attachment('data', 'bytes-0')],
        parts: <_Field>[
          const _Field.bytes('bytes-0', <int>[0, 1, 2, 3, 4]),
        ],
        terminated: false,
      );

      expect(
        () => decodeRpcAttachmentResponse(
          bodyBytes: body,
          contentType: _contentType,
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('ends inside a part'),
          ),
        ),
      );
    });

    test('a carrier that declares no attachment fails loud', () {
      final body = _carrier(
        value: _bytesValue(data: null, size: 0, eof: true),
        attachments: const <Map<String, Object?>>[],
        parts: <_Field>[const _Field.bytes('bytes-0', <int>[])],
      );

      expect(
        () => decodeRpcAttachmentResponse(
          bodyBytes: body,
          contentType: _contentType,
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('declares no attachment'),
          ),
        ),
      );
    });

    test('a declared attachment with no field in the body fails loud', () {
      final body = _carrier(
        value: _bytesValue(data: null, size: 5, eof: true),
        attachments: <Map<String, Object?>>[_attachment('data', 'bytes-7')],
        parts: <_Field>[
          const _Field.bytes('bytes-0', <int>[1]),
        ],
      );

      expect(
        () => decodeRpcAttachmentResponse(
          bodyBytes: body,
          contentType: _contentType,
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            allOf(contains('bytes-7'), contains('no field')),
          ),
        ),
      );
    });

    test('an undeclared field in the body fails loud', () {
      final body = _carrier(
        value: _bytesValue(data: null, size: 5, eof: true),
        attachments: <Map<String, Object?>>[_attachment('data', 'bytes-0')],
        parts: <_Field>[
          const _Field.bytes('bytes-0', <int>[1]),
          const _Field.text('extra', 'surprise'),
        ],
      );

      expect(
        () => decodeRpcAttachmentResponse(
          bodyBytes: body,
          contentType: _contentType,
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('undeclared field'),
          ),
        ),
      );
    });

    test('a placeholder that is not null fails loud', () {
      final body = _carrier(
        value: _bytesValue(data: 'not-null', size: 5, eof: true),
        attachments: <Map<String, Object?>>[_attachment('data', 'bytes-0')],
        parts: <_Field>[
          const _Field.bytes('bytes-0', <int>[1]),
        ],
      );

      expect(
        () => decodeRpcAttachmentResponse(
          bodyBytes: body,
          contentType: _contentType,
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('is not null'),
          ),
        ),
      );
    });

    test('a path that leaves the result value fails loud', () {
      final body = _carrier(
        value: _bytesValue(data: null, size: 5, eof: true),
        attachments: <Map<String, Object?>>[
          _attachment(<Object?>['missing'], 'bytes-0'),
        ],
        parts: <_Field>[
          const _Field.bytes('bytes-0', <int>[1]),
        ],
      );

      expect(
        () => decodeRpcAttachmentResponse(
          bodyBytes: body,
          contentType: _contentType,
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('leaves the result value'),
          ),
        ),
      );
    });

    test('a non-bytes codec fails loud', () {
      final body = _carrier(
        value: _bytesValue(data: null, size: 5, eof: true),
        attachments: const <Map<String, Object?>>[
          <String, Object?>{
            'path': <Object?>['data'],
            'codec': 'text',
            'part': 'bytes-0',
          },
        ],
        parts: <_Field>[
          const _Field.bytes('bytes-0', <int>[1]),
        ],
      );

      expect(
        () => decodeRpcAttachmentResponse(
          bodyBytes: body,
          contentType: _contentType,
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('"bytes"'),
          ),
        ),
      );
    });

    test('a contentType with no boundary parameter fails loud', () {
      expect(
        () => decodeRpcAttachmentResponse(
          bodyBytes: utf8.encode(''),
          contentType: _kMediaType,
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('no boundary'),
          ),
        ),
      );
    });
  });

  group('rpcBaseMediaType', () {
    test('strips parameters and lowercases the base type', () {
      expect(rpcBaseMediaType('MULTIPART/FORM-DATA; boundary=x'), _kMediaType);
      expect(
        rpcBaseMediaType('application/json; charset=utf-8'),
        'application/json',
      );
      expect(rpcBaseMediaType(null), isNull);
      expect(rpcBaseMediaType('  '), isNull);
    });

    test('isRpcAttachmentResponse selects only the multipart carrier', () {
      expect(isRpcAttachmentResponse(_contentType), isTrue);
      expect(
        isRpcAttachmentResponse('application/json; charset=utf-8'),
        isFalse,
      );
      expect(isRpcAttachmentResponse(null), isFalse);
    });
  });

  group('HttpDshRpcClient multipart responses', () {
    test('call reassembles the bytes into the result value', () async {
      const List<int> bytes = <int>[10, 20, 30];
      final client = HttpDshRpcClient(
        Uri.parse('http://127.0.0.1:3080'),
        httpClient: MockClient((request) async {
          final sent = jsonDecode(request.body) as Map<String, Object?>;
          expect(request.url.path, '/api/workspaceFiles/readBytes');
          // Echo the caller's rpcId: the metadata envelope carries it.
          final framed = _carrier(
            rpcId: sent['rpcId']! as String,
            value: _bytesValue(data: null, size: 3, eof: true),
            attachments: <Map<String, Object?>>[_attachment('data', 'bytes-0')],
            parts: <_Field>[const _Field.bytes('bytes-0', bytes)],
          );
          return http.Response.bytes(
            framed,
            200,
            headers: <String, String>{'content-type': _contentType},
          );
        }),
      );

      final result = await client.call(
        'workspaceFiles/readBytes',
        'workspaceFiles/readBytes',
        <String, Object?>{'args': <String, Object?>{}},
      );
      expect(result.ok, isTrue);
      expect(result.value!['data'], bytes);
    });

    test(
      'a truncated multipart reply surfaces a DshTransportException',
      () async {
        final client = HttpDshRpcClient(
          Uri.parse('http://127.0.0.1:3080'),
          httpClient: MockClient(
            (request) async => http.Response.bytes(
              utf8.encode(
                '--$_boundary\r\nContent-Disposition: form-data; '
                'name="metadata"',
              ),
              200,
              headers: <String, String>{'content-type': _contentType},
            ),
          ),
        );

        await expectLater(
          client.call(
            'workspaceFiles/readBytes',
            'workspaceFiles/readBytes',
            {},
          ),
          throwsA(isA<DshTransportException>()),
        );
      },
    );
  });
}

/// One form field: a `metadata` text value or a binary part.
final class _Field {
  const _Field.text(this.name, this.content) : bytes = null;

  const _Field.bytes(this.name, this.bytes) : content = null;

  final String name;
  final String? content;
  final List<int>? bytes;
}

/// Framing of one binary field, as the host names it in `attachments`.
Map<String, Object?> _attachment(Object? path, String part) =>
    <String, Object?>{
      'path': path is List<Object?> ? path : <Object?>[path],
      'codec': 'bytes',
      'part': part,
    };

/// A `WorkspaceFileBytes` result value with the byte field left as the codec's
/// `null` placeholder.
Map<String, Object?> _bytesValue({
  required Object? data,
  required int size,
  required bool eof,
  int offset = 0,
}) => <String, Object?>{
  'absolutePath': '/workspace/blob.bin',
  'version': 'v1',
  'bytes': size,
  'offset': offset,
  'data': data,
  'eof': eof,
};

/// Builds the multipart carrier the host writes for one attachment result.
List<int> _carrier({
  required Map<String, Object?> value,
  required List<Map<String, Object?>> attachments,
  required List<_Field> parts,
  String rpcId = 'rpc-1',
  bool terminated = true,
}) {
  final metadata = jsonEncode(<String, Object?>{
    'type': 'server-response',
    'rpcId': rpcId,
    'result': <String, Object?>{'ok': true, 'value': value},
    'attachments': attachments,
  });
  return _multipart(<_Field>[
    ...parts,
    _Field.text('metadata', metadata),
  ], terminated: terminated);
}

List<int> _multipart(List<_Field> fields, {bool terminated = true}) {
  final out = <int>[];
  void line(String value) => out.addAll(utf8.encode(value));
  for (final field in fields) {
    line('--$_boundary\r\n');
    line('Content-Disposition: form-data; name="${field.name}"');
    if (field.bytes != null) {
      line('; filename="blob"\r\n');
      line('Content-Type: application/octet-stream\r\n\r\n');
      out.addAll(field.bytes!);
    } else {
      line('\r\n\r\n');
      line(field.content!);
    }
    line('\r\n');
  }
  if (terminated) line('--$_boundary--\r\n');
  return out;
}
