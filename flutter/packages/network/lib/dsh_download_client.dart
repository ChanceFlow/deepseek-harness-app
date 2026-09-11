/// Protocol-agnostic binary download over `package:http`.
///
/// The RPC seam ([DshRpcClient]) speaks JSON-RPC envelopes; a route that
/// answers with a file body (an archive, an export, a media blob) has no
/// envelope to unwrap. This client is the other shape: hand it a
/// caller-supplied path and it buffers the body, with no knowledge of which
/// route it is, what the bytes mean, or which headers the caller wants.
library;

import 'dart:async';
import 'dart:io' show HttpClient;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' show IOClient;

import 'dsh_exceptions.dart';
import 'http_dsh_rpc_client.dart' show kDshRpcConnectTimeout;

/// One buffered download: the complete body plus the response headers a
/// caller may act on (a filename lives in `content-disposition`).
final class DshDownload {
  const DshDownload({
    required this.bytes,
    this.contentType,
    this.contentDisposition,
  });

  /// The complete body. Truncation is never a shorter buffer: a body that
  /// ends before its declared length fails the call instead.
  final Uint8List bytes;

  /// The `content-type` header verbatim, or null when the host sent none.
  final String? contentType;

  /// The `content-disposition` header verbatim, or null when absent.
  final String? contentDisposition;
}

/// Binary GET seam shared by the adapter and its test doubles.
abstract class DshDownloadClient {
  /// GETs [pathAndQuery] against this client's base URL and buffers the body.
  ///
  /// [timeout] is the caller's request deadline and owns the whole exchange
  /// — connect, response head, and body. `null` (the default) means no
  /// deadline. Which routes need one, and how long it is, is the caller's
  /// policy: this package forwards the value without interpreting it.
  ///
  /// Implementations throw [DshTransportException] on a non-2xx status, a
  /// transport failure, a deadline overrun, or a body that ends before the
  /// response declared it would.
  Future<DshDownload> download(String pathAndQuery, {Duration? timeout});
}

final class HttpDshDownloadClient implements DshDownloadClient {
  HttpDshDownloadClient(
    this._baseUrl, {
    http.Client? httpClient,
    this.connectTimeout = kDshRpcConnectTimeout,
    Map<String, String> headers = const <String, String>{},
  }) : _headers = Map<String, String>.unmodifiable(headers),
       _httpClient =
           httpClient ??
           IOClient(HttpClient()..connectionTimeout = connectTimeout);

  final Uri _baseUrl;
  final http.Client _httpClient;
  final Map<String, String> _headers;

  /// See [kDshRpcConnectTimeout].
  final Duration connectTimeout;

  /// Headers the caller supplied at construction. As in [HttpDshRpcClient]
  /// this package never reads, names, or validates their meaning — whatever
  /// is handed in is copied onto every outgoing request, so an auth header
  /// set for the RPC leg reaches a download without this package learning
  /// what it is.
  Map<String, String> get headers => _headers;

  @override
  Future<DshDownload> download(String pathAndQuery, {Duration? timeout}) async {
    final Uri url;
    try {
      // Both legs treat the configured base URL as an origin: the RPC
      // client resolves `api/<endpoint>` against it, which drops a base
      // path segment the same way an origin-relative path does. Splicing
      // the path onto `_baseUrl.origin` keeps the two legs addressing one
      // host (and keeps a hostile path from walking up to another).
      url = Uri.parse('${_baseUrl.origin}$pathAndQuery');
    } catch (error) {
      throw DshTransportException(
        'cannot resolve $pathAndQuery against $_baseUrl',
        error,
      );
    }
    try {
      final exchange = _buffer(url);
      return await (timeout == null ? exchange : exchange.timeout(timeout));
    } on TimeoutException catch (error) {
      throw DshTransportException(
        'download deadline ${timeout!.inMilliseconds}ms exceeded for '
        '$pathAndQuery',
        error,
      );
    } on DshTransportException {
      rethrow;
    } catch (error) {
      throw DshTransportException('transport failure for $pathAndQuery', error);
    }
  }

  Future<DshDownload> _buffer(Uri url) async {
    final request = http.Request('GET', url);
    request.headers.addAll(_headers);
    final response = await _httpClient.send(request);
    final bytes = await response.stream.toBytes();
    if (response.statusCode ~/ 100 != 2) {
      throw DshTransportException.http(
        'HTTP ${response.statusCode} for ${url.path}: ${_clipped(bytes)}',
        response.statusCode,
      );
    }
    return DshDownload(
      bytes: bytes,
      contentType: response.headers['content-type'],
      contentDisposition: response.headers['content-disposition'],
    );
  }
}

/// The error-body excerpt carried in a failed download's message: enough to
/// name the host's reason, capped so a large HTML error page never becomes
/// the message.
String _clipped(Uint8List bytes) {
  const limit = 300;
  final text = String.fromCharCodes(
    bytes.length <= limit ? bytes : bytes.sublist(0, limit),
  );
  final oneLine = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return oneLine.length <= limit ? oneLine : oneLine.substring(0, limit);
}
