/// Device-local backend registry — the persisted list of configured dsh
/// hosts plus which one the chat surface presents.
///
/// The store owns a JSON document in the app's documents directory
/// (`{"backends": [...], "activeId": "..."}`); writes are atomic
/// (temp file + rename). The seed backend comes from the build-time
/// base URL, so a fresh install behaves exactly like the single-backend
/// build.
library;

import 'dart:convert';
import 'dart:io';

import 'package:domain/model/backend.dart';

/// Load/save errors surface as [BackendStoreException] with the cause in
/// the message; the controller decides whether to fall back to the seed.
class BackendStoreException implements Exception {
  const BackendStoreException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() =>
      cause == null
          ? 'BackendStoreException: $message'
          : 'BackendStoreException: $message ($cause)';
}

/// One persisted registry document.
final class BackendStoreData {
  const BackendStoreData({required this.backends, this.activeId});

  final List<BackendConfig> backends;
  final String? activeId;
}

/// JSON file store for the backend registry.
class BackendStore {
  BackendStore(this._file, {required this.seedBaseUrl});

  final File _file;

  /// Build-time base URL; becomes the first backend on a fresh install
  /// (label `host:port`, id `default`).
  final String seedBaseUrl;

  /// Reads the document; an absent file yields the seed-only document.
  Future<BackendStoreData> load() async {
    if (!await _file.exists()) {
      return BackendStoreData(backends: [_seedBackend()]);
    }
    try {
      final decoded = jsonDecode(await _file.readAsString());
      if (decoded is! Map<String, Object?>) {
        throw const BackendStoreException('backends.json: root is not an object');
      }
      final rawList = decoded['backends'];
      if (rawList is! List<Object?>) {
        throw const BackendStoreException('backends.json: backends is not an array');
      }
      final backends = <BackendConfig>[];
      for (final raw in rawList) {
        final obj = raw is Map<String, Object?> ? raw : null;
        final id = obj?['id'];
        final label = obj?['label'];
        final baseUrl = obj?['baseUrl'];
        if (id is! String || label is! String || baseUrl is! String) {
          throw const BackendStoreException('backends.json: malformed entry');
        }
        final uri = Uri.tryParse(baseUrl);
        if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
          throw BackendStoreException('backends.json: bad baseUrl "$baseUrl"');
        }
        backends.add(
          BackendConfig(id: id, label: label, baseUri: uri),
        );
      }
      if (backends.isEmpty) {
        throw const BackendStoreException('backends.json: empty backend list');
      }
      final activeId = decoded['activeId'];
      return BackendStoreData(
        backends: backends,
        activeId: activeId is String ? activeId : null,
      );
    } on BackendStoreException {
      rethrow;
    } on FileSystemException catch (error) {
      throw BackendStoreException('backends.json: read failed', error);
    } on FormatException catch (error) {
      throw BackendStoreException('backends.json: invalid JSON', error);
    }
  }

  /// Atomically persists the document (temp file + rename).
  Future<void> save(BackendStoreData data) async {
    final payload = jsonEncode(<String, Object?>{
      'backends': <Object?>[
        for (final backend in data.backends)
          <String, Object?>{
            'id': backend.id,
            'label': backend.label,
            'baseUrl': backend.baseUri.toString(),
          },
      ],
      'activeId': data.activeId,
    });
    try {
      await _file.parent.create(recursive: true);
      final temp = File('${_file.path}.tmp');
      await temp.writeAsString(payload, flush: true);
      await temp.rename(_file.path);
    } on FileSystemException catch (error) {
      throw BackendStoreException('backends.json: write failed', error);
    }
  }

  BackendConfig _seedBackend() {
    final uri = Uri.parse(seedBaseUrl);
    return BackendConfig(
      id: 'default',
      label: uri.host.isEmpty ? seedBaseUrl : '${uri.host}:${uri.port}',
      baseUri: uri,
    );
  }
}
