/// Session-log download route tests: the dsh wire facts (path, query
/// parameters, filename convention) checked against a real loopback
/// `HttpServer` through the network package's binary download client.
///
/// Contract source:
/// `reference/deepseek-harness/packages/session-query/session-log-export/src/index.ts`
/// (`SESSION_LOG_EXPORT_PATH`, the 400 on a missing `sessionId` or a
/// non-`true`/`false` `includeDescendants`) and
/// `.../src/archive.ts` (`sessionLogZipFilename`).
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:harness_adapter/harness_adapter.dart';
import 'package:network/dsh_download_client.dart';
import 'package:network/dsh_exceptions.dart';
import 'package:test/test.dart';

/// Starts one in-process HTTP server on an ephemeral loopback port.
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
  final archive = Uint8List.fromList(List<int>.generate(512, (i) => i % 97));

  /// Serves [archive] on every request and records the requested URI.
  Future<(HttpServer, Uri, Completer<Uri>)> servingArchive() async {
    final seen = Completer<Uri>();
    final (server, base) = await startServer((request) async {
      if (!seen.isCompleted) seen.complete(request.uri);
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType('application', 'zip');
      request.response.headers.set(
        'content-disposition',
        'attachment; filename="dsh-session-session-root.zip"',
      );
      request.response.add(archive);
      await request.response.close();
    });
    return (server, base, seen);
  }

  test('fetch asks for the session tree and returns the archive', () async {
    final (server, base, seen) = await servingArchive();
    addTearDown(() => server.close(force: true));

    final export = await SessionLogExportClient(HttpDshDownloadClient(base))
        .fetch('session-root');

    final uri = await seen.future;
    expect(uri.path, '/api/session.export');
    expect(uri.queryParameters, <String, String>{
      'sessionId': 'session-root',
      'includeDescendants': 'true',
    });
    expect(export.bytes, archive);
    expect(export.filename, 'dsh-session-session-root.zip');
  });

  test('a shallow export omits includeDescendants', () async {
    final (server, base, seen) = await servingArchive();
    addTearDown(() => server.close(force: true));

    await SessionLogExportClient(HttpDshDownloadClient(base))
        .fetch('session-root', includeDescendants: false);

    expect((await seen.future).queryParameters, <String, String>{
      'sessionId': 'session-root',
    });
  });

  test('the filename collapses an untrusted session id', () async {
    final (server, base, seen) = await servingArchive();
    addTearDown(() => server.close(force: true));

    final export = await SessionLogExportClient(HttpDshDownloadClient(base))
        .fetch('../../etc/passwd');

    expect(
      (await seen.future).queryParameters['sessionId'],
      '../../etc/passwd',
    );
    expect(export.filename, 'dsh-session-______etc_passwd.zip');
    expect(export.filename, isNot(contains('/')));
  });

  test('a 404 surfaces the host status', () async {
    final (server, base) = await startServer((request) async {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('session not found');
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));

    await expectLater(
      DshSessionLogExportRepository(HttpDshDownloadClient(base))
          .exportSessionLog('gone'),
      throwsA(
        isA<DshTransportException>().having(
          (error) => error.message,
          'message',
          allOf(contains('HTTP 404'), contains('session not found')),
        ),
      ),
    );
  });
}
