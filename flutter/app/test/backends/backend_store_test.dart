/// BackendStore behavior: the seed document, save/load round-trips,
/// and the malformed-document failures (each names the wire problem).
library;

import 'dart:convert';
import 'dart:io';

import 'package:app/backends/backend_store.dart';
import 'package:domain/model/backend.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('backend_store_test');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  File fileFor(String name) => File('${tempDir.path}/$name.json');

  test('an absent file loads the seed-only document', () async {
    final store = BackendStore(fileFor('absent'), seedBaseUrl: 'http://10.0.2.2:3080');

    final data = await store.load();
    expect(data.backends, hasLength(1));
    expect(data.backends.single.id, 'default');
    expect(data.backends.single.label, '10.0.2.2:3080');
    expect(data.backends.single.baseUri, Uri.parse('http://10.0.2.2:3080'));
    expect(data.activeId, isNull);
  });

  test('seedDocument returns the fresh-install document without reading', () async {
    final file = fileFor('seed');
    await file.writeAsString('{"backends": [], "activeId": null}');
    final store = BackendStore(file, seedBaseUrl: 'http://10.0.2.2:3080');

    final data = store.seedDocument();
    expect(data.backends.single.id, 'default');
    expect(data.activeId, isNull);
  });

  test('save round-trips backends and the active id', () async {
    final file = fileFor('roundtrip');
    final store = BackendStore(file, seedBaseUrl: 'http://10.0.2.2:3080');
    await store.load();

    await store.save(
      BackendStoreData(
        backends: [
          BackendConfig(
            id: 'default',
            label: 'Laptop',
            baseUri: Uri.parse('http://10.0.2.2:3080'),
          ),
          BackendConfig(
            id: 'b1',
            label: 'Build box',
            baseUri: Uri.parse('http://10.0.2.2:3081'),
          ),
        ],
        activeId: 'b1',
      ),
    );

    final reloaded = BackendStore(file, seedBaseUrl: 'http://10.0.2.2:3080');
    final data = await reloaded.load();
    expect(data.backends, hasLength(2));
    expect(data.backends[1].label, 'Build box');
    expect(data.activeId, 'b1');

    // The document is the documented JSON shape.
    final decoded = jsonDecode(await file.readAsString())
        as Map<String, Object?>;
    expect(decoded['activeId'], 'b1');
    expect((decoded['backends'] as List<Object?>).first,
        <String, Object?>{
          'id': 'default',
          'label': 'Laptop',
          'baseUrl': 'http://10.0.2.2:3080',
        });
  });

  test('a dangling active id survives a load (the controller resolves it)', () async {
    final file = fileFor('dangling');
    await file.writeAsString(
      '{"backends": ['
      '{"id": "default", "label": "Laptop", "baseUrl": "http://10.0.2.2:3080"}'
      '], "activeId": "gone"}',
    );
    final data = await BackendStore(
      file,
      seedBaseUrl: 'http://10.0.2.2:3080',
    ).load();
    expect(data.activeId, 'gone');
    expect(data.backends.single.id, 'default');
  });

  for (final (name, payload) in [
    ('root is not an object', '[]'),
    ('backends is not an array', '{"backends": {}}'),
    (
      'malformed entry',
      '{"backends": [{"id": "default"}], "activeId": null}',
    ),
    (
      'bad baseUrl',
      '{"backends": [{"id": "default", "label": "L", "baseUrl": "not-a-url"}]}',
    ),
    ('empty backend list', '{"backends": [], "activeId": null}'),
    ('invalid JSON', '{"backends": ['),
  ]) {
    test('a malformed document fails loud: $name', () async {
      final file = fileFor('bad-${name.hashCode}');
      await file.writeAsString(payload);
      final store = BackendStore(file, seedBaseUrl: 'http://10.0.2.2:3080');

      await expectLater(store.load(), throwsA(isA<BackendStoreException>()));
    });
  }
}
