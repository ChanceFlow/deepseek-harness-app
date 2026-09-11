/// In-process tests for the binary download seam against a local
/// `HttpServer` (the same loopback style as the event-socket suite).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:network/dsh_download_client.dart';
import 'package:network/dsh_exceptions.dart';

/// One body the download must buffer, plus the headers it must expose.
final _zipBytes = Uint8List.fromList(
  List<int>.generate(2048, (index) => index % 251),
);

/// Starts one in-process HTTP server on an ephemeral loopback port; the
/// handler decides the response. Returns the bound server and its base URI.
Future<(HttpServer, Uri)> startServer(
  Future<void> Function(HttpRequest request) handler,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) {
    unawaited(handler(request));
  });
  return (server, Uri.parse('http://127.0.0.1:${server.port}'));
}

void main() {
  test(
    'successful download buffers the body and exposes its headers',
    () async {
      final (server, base) = await startServer((request) async {
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType(
          'application',
          'zip',
        );
        request.response.headers.set(
          'content-disposition',
          'attachment; filename="dsh-session-session-root.zip"',
        );
        request.response.add(_zipBytes);
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));

      final download = await HttpDshDownloadClient(base).download(
        '/api/session.export?sessionId=session-root&includeDescendants=true',
      );

      expect(download.bytes, _zipBytes);
      expect(download.contentType, 'application/zip');
      expect(
        download.contentDisposition,
        'attachment; filename="dsh-session-session-root.zip"',
      );
    },
  );

  test(
    'the caller-supplied path and query reach the server verbatim',
    () async {
      final seen = Completer<Uri>();
      final (server, base) = await startServer((request) async {
        if (!seen.isCompleted) seen.complete(request.uri);
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));

      await HttpDshDownloadClient(base).download(
        '/api/session.export?sessionId=session-root&includeDescendants=true',
      );

      final uri = await seen.future;
      expect(uri.path, '/api/session.export');
      expect(uri.queryParameters['sessionId'], 'session-root');
      expect(uri.queryParameters['includeDescendants'], 'true');
    },
  );

  test(
    'the configured base URL is an origin; a base path is not spliced on',
    () async {
      final seen = Completer<Uri>();
      final (server, base) = await startServer((request) async {
        if (!seen.isCompleted) seen.complete(request.uri);
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));

      await HttpDshDownloadClient(base.replace(path: '/gateway/prefix'))
          .download('/api/session.export?sessionId=s1');

      expect((await seen.future).path, '/api/session.export');
    },
  );

  test('caller headers ride the request', () async {
    final seen = Completer<HttpHeaders>();
    final (server, base) = await startServer((request) async {
      if (!seen.isCompleted) seen.complete(request.headers);
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));

    final client = HttpDshDownloadClient(
      base,
      headers: const <String, String>{'X-Caller-Header': 'caller-value'},
    );
    expect(client.headers, const <String, String>{
      'X-Caller-Header': 'caller-value',
    });
    await client.download('/api/session.export');

    expect((await seen.future).value('X-Caller-Header'), 'caller-value');
  });

  test('a non-200 status surfaces the status and the host reason', () async {
    final (server, base) = await startServer((request) async {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('session not found');
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));

    await expectLater(
      HttpDshDownloadClient(base)
          .download('/api/session.export?sessionId=gone'),
      throwsA(
        isA<DshTransportException>()
            .having((error) => error.httpStatus, 'httpStatus', 404)
            .having((error) => error.message, 'message', contains('HTTP 404'))
            .having(
              (error) => error.message,
              'message',
              contains('session not found'),
            ),
      ),
    );
  });

  test(
    'a body truncated below its declared length fails the download',
    () async {
      // A raw socket, not HttpServer: the point is a response whose
      // Content-Length promises more bytes than the connection delivers
      // before it dies. That is what a network drop mid-download looks like,
      // and it must never settle as a short archive.
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      final responseBytes = utf8.encode(
        'HTTP/1.1 200 OK\r\n'
        'Content-Type: application/zip\r\n'
        'Content-Length: 64\r\n'
        '\r\n'
        'PK\u0003\u0004truncated',
      );
      server.listen((socket) {
        socket.add(responseBytes);
        unawaited(socket.flush().then((_) => socket.destroy()));
      });

      await expectLater(
        HttpDshDownloadClient(Uri.parse('http://127.0.0.1:${server.port}'))
            .download('/api/session.export?sessionId=s1'),
        throwsA(isA<DshTransportException>()),
      );
    },
  );
}
