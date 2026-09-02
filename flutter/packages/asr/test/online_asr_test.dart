/// Online ASR coverage: settings persistence, the Volcengine v3 binary
/// protocol codec, the Tencent signature/URL assembly, and both engines'
/// session behavior against scripted sockets.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:asr/asr.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

void main() {
  group('OnlineAsrSettingsStore', () {
    late Directory dir;
    late File file;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('online_asr_test');
      file = File('${dir.path}/online_asr_settings.json');
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    test('defaults to offline mode with empty credentials', () async {
      final OnlineAsrSettingsStore store = OnlineAsrSettingsStore(file);
      await store.load();
      expect(store.settings.mode, VoiceInputMode.offline);
      expect(store.settings.isOnlineReady, isFalse);
      expect(store.settings.volcengine.isConfigured, isFalse);
      expect(store.settings.tencent.isConfigured, isFalse);
    });

    test('persists mode, provider, and credentials across reloads', () async {
      final OnlineAsrSettingsStore store = OnlineAsrSettingsStore(file);
      await store.load();
      await store.setMode(VoiceInputMode.online);
      await store.setVolcengine(
        const VolcengineDoubaoAsrConfig(apiKey: 'k-test'),
      );

      final OnlineAsrSettingsStore reloaded = OnlineAsrSettingsStore(file);
      await reloaded.load();
      expect(reloaded.settings.mode, VoiceInputMode.online);
      expect(reloaded.settings.provider, OnlineAsrProvider.volcengineDoubao);
      expect(reloaded.settings.volcengine.apiKey, 'k-test');
      expect(reloaded.settings.isOnlineReady, isTrue);
    });

    test('a corrupt document falls back to defaults, not a crash', () async {
      await file.writeAsString('{not json');
      final OnlineAsrSettingsStore store = OnlineAsrSettingsStore(file);
      await store.load();
      expect(store.settings.mode, VoiceInputMode.offline);
    });

    test('updates stream publishes every change', () async {
      final OnlineAsrSettingsStore store = OnlineAsrSettingsStore(file);
      await store.load();
      final Future<List<OnlineAsrSettings>> seen = store.updates
          .take(2)
          .toList();
      await store.setProvider(OnlineAsrProvider.tencentHunyuan);
      await store.setMode(VoiceInputMode.online);
      final List<OnlineAsrSettings> events = await seen;
      expect(events[0].provider, OnlineAsrProvider.tencentHunyuan);
      expect(events[1].mode, VoiceInputMode.online);
    });
  });

  group('Volcengine v3 protocol', () {
    test('full client request carries header, sequence, size, gzip JSON', () {
      final Uint8List frame = AsrV3Request.fullClientRequest(<String, Object?>{
        'model_name': 'bigmodel',
      }, 1);
      expect(frame[0], 0x11); // version 1, header 1 word
      expect(frame[1], 0x11); // full client request, sequence flag
      expect(frame[2], 0x11); // JSON serialization, gzip compression
      expect(frame[3], 0x00);

      final ByteData body = ByteData.sublistView(frame, 4);
      expect(body.getInt32(0, Endian.big), 1); // sequence
      final int size = body.getUint32(4, Endian.big);
      expect(size, frame.length - 12);
      final Map<String, Object?> decoded = jsonDecode(
        utf8.decode(GZipCodec().decode(frame.sublist(12))),
      ) as Map<String, Object?>;
      expect(decoded['model_name'], 'bigmodel');
    });

    test('audio requests flag the last package with a negative sequence', () {
      final Uint8List regular = AsrV3Request.audioOnlyRequest(
        <int>[1, 2, 3, 4],
        sequence: 7,
        isLast: false,
      );
      expect(regular[1], 0x21); // audio-only, sequence flag
      expect(ByteData.sublistView(regular, 4).getInt32(0, Endian.big), 7);

      final Uint8List last = AsrV3Request.audioOnlyRequest(
        const <int>[],
        sequence: 7,
        isLast: true,
      );
      expect(last[1], 0x23); // audio-only, sequence + last-package flags
      expect(ByteData.sublistView(last, 4).getInt32(0, Endian.big), -7);
    });

    test('parses a gzip JSON full server response with the last flag', () {
      final Uint8List payload = Uint8List.fromList(
        GZipCodec().encode(
          utf8.encode(
            jsonEncode(<String, Object?>{
              'result': <String, Object?>{'text': '你好世界'},
            }),
          ),
        ),
      );
      final ByteData out = ByteData(4 + 4 + payload.length);
      out.setUint32(0, payload.length, Endian.big);
      final Uint8List bytes = out.buffer.asUint8List()..setAll(4, payload);
      final Uint8List seq = Uint8List(4);
      seq.buffer.asByteData().setInt32(0, 3, Endian.big);
      // Header: type 0b1001, flags sequence|lastPackage; plus sequence 3.
      final BytesBuilder frame = BytesBuilder()
        ..add(<int>[0x11, 0x9B, 0x11, 0x00])
        ..add(seq)
        ..add(bytes);

      final AsrV3ServerFrame parsed = AsrV3ResponseParser.parse(
        frame.toBytes(),
      );
      expect(parsed, isA<AsrV3FullResponse>());
      final AsrV3FullResponse response = parsed as AsrV3FullResponse;
      expect(response.isLastPackage, isTrue);
      expect(
        (response.payloadMsg['result'] as Map<String, Object?>)['text'],
        '你好世界',
      );
    });

    test('parses an error response into code and message', () {
      final Uint8List body = Uint8List.fromList(
        GZipCodec().encode(
          utf8.encode(jsonEncode(<String, Object?>{'message': 'bad key'})),
        ),
      );
      final ByteData tail = ByteData(8 + body.length)
        ..setInt32(0, -1001, Endian.big)
        ..setUint32(4, body.length, Endian.big);
      final Uint8List bytes = tail.buffer.asUint8List()..setAll(8, body);
      final Uint8List frame = Uint8List.fromList(
        <int>[0x11, 0xF0, 0x11, 0x00] + bytes,
      );

      final AsrV3ServerFrame parsed = AsrV3ResponseParser.parse(frame);
      expect(parsed, isA<AsrV3ErrorResponse>());
      final AsrV3ErrorResponse error = parsed as AsrV3ErrorResponse;
      expect(error.code, -1001);
      expect(error.message, 'bad key');
    });

    test('rejects frames shorter than the header', () {
      expect(
        () => AsrV3ResponseParser.parse(Uint8List.fromList(<int>[0x11])),
        throwsArgumentError,
      );
    });
  });

  group('Tencent signature and URL', () {
    test('signs the sorted raw-value string and encodes the URL', () {
      const TencentHunyuanAsrConfig config = TencentHunyuanAsrConfig(
        appId: '1234567890',
        secretId: 'AKIDtest',
        secretKey: 'secret/key+value',
      );
      final Map<String, String> params = tencentAsrQueryParams(
        config: config,
        voiceId: 'voice-1',
        timestampSeconds: 1700000000,
      );
      final String signString = tencentAsrSignString(
        appId: config.appId,
        params: params,
      );

      // The signed string uses raw (never percent-encoded) values and
      // excludes appid from the pair list.
      expect(
        signString,
        startsWith('asr.cloud.tencent.com/asr/v2/1234567890?'),
      );
      expect(signString, contains('engine_model_type=Hy-ASR-3.0-preview'));
      expect(signString, isNot(contains('appid=')));
      expect(signString, contains('voice_format=1'));
      final List<String> keys = signString.split('?')[1].split('&').map((
        String p,
      ) {
        return p.split('=')[0];
      }).toList();
      expect(keys, equals(List<String>.from(keys)..sort()));

      // The signature is base64(HMAC-SHA1(secretKey, signString)).
      final String expected = base64.encode(
        Hmac(
          sha1,
          utf8.encode(config.secretKey),
        ).convert(utf8.encode(signString)).bytes,
      );
      expect(tencentAsrSignature(signString, config.secretKey), expected);

      // The URL percent-encodes every value, including the signature.
      final String url = tencentAsrSignedUrl(
        config: config,
        voiceId: 'voice-1',
        timestampSeconds: 1700000000,
      );
      expect(url, startsWith('wss://asr.cloud.tencent.com/asr/v2/1234567890?'));
      expect(url, contains('&signature='));
      expect(url, isNot(contains('signature=$expected')));
      expect(url, contains(Uri.encodeComponent(expected)));
      expect(url, contains('timestamp=1700000000'));
      expect(url, contains('expired=1700086400'));
    });
  });

  group('VolcengineDoubaoAsrEngine', () {
    test('streams audio and collects the final transcript', () async {
      final _FakeSocket socket = _FakeSocket();
      final VolcengineDoubaoAsrEngine engine = VolcengineDoubaoAsrEngine(
        config: const VolcengineDoubaoAsrConfig(apiKey: 'k'),
        opener: (_, __) async => socket,
      );

      final List<String> partials = <String>[];
      await engine.initialize(null, null);
      engine.transcriptionStream.listen(
        (AsrTranscriptionChunk c) => partials.add(c.text),
      );

      // Start request: seq 1, gzip JSON.
      expect(socket.sent, hasLength(1));

      engine.acceptAudio(Float32List.fromList(<double>[0.1, -0.1]));
      expect(socket.sent, hasLength(2)); // audio, seq 2

      // Partial arrives while recording.
      socket.incoming.add(_volcResponse('你好', isLast: false));
      await _pump();
      expect(partials, contains('你好'));

      // Finish sends the last package (negative sequence) and waits for
      // the server's final response.
      final Future<String> finished = engine.finish();
      await _pump();
      final Uint8List lastFrame = socket.sent.last as Uint8List;
      expect(lastFrame[1] & 0x2, isNot(0)); // last-package flag
      expect(
        ByteData.sublistView(lastFrame, 4).getInt32(0, Endian.big),
        isNegative,
      );

      socket.incoming.add(_volcResponse('你好，世界。', isLast: true));
      expect(await finished, '你好，世界。');
      await engine.dispose();
      expect(socket.closed, isTrue);
    });

    test('rejects unconfigured credentials before any network work', () async {
      var opened = false;
      final VolcengineDoubaoAsrEngine engine = VolcengineDoubaoAsrEngine(
        config: const VolcengineDoubaoAsrConfig(),
        opener: (_, __) async {
          opened = true;
          return _FakeSocket();
        },
      );
      await expectLater(
        engine.initialize(null, null),
        throwsA(isA<OnlineAsrException>()),
      );
      expect(opened, isFalse);
    });

    test('surfaces service error frames as a thrown exception', () async {
      final _FakeSocket socket = _FakeSocket();
      final VolcengineDoubaoAsrEngine engine = VolcengineDoubaoAsrEngine(
        config: const VolcengineDoubaoAsrConfig(apiKey: 'bad'),
        opener: (_, __) async => socket,
      );
      await engine.initialize(null, null);
      engine.acceptAudio(Float32List.fromList(<double>[0.5]));

      final Future<String> finished = engine.finish();
      await _pump();
      socket.incoming.add(
        Uint8List.fromList(<int>[
          0x11, 0xF1, 0x11, 0x00, // error response, no sequence
          ..._errorBody(-1001, 'invalid api key'),
        ]),
      );
      await expectLater(finished, throwsA(isA<OnlineAsrException>()));
      await engine.dispose();
    });
  });

  group('TencentHunyuanAsrEngine', () {
    test('assembles sentence pieces and ends with the end signal', () async {
      final _FakeSocket socket = _FakeSocket();
      final TencentHunyuanAsrEngine engine = TencentHunyuanAsrEngine(
        config: const TencentHunyuanAsrConfig(
          appId: '123',
          secretId: 'id',
          secretKey: 'key',
        ),
        opener: (_, __) async => socket,
      );

      final List<String> partials = <String>[];
      await engine.initialize(null, null);
      engine.transcriptionStream.listen(
        (AsrTranscriptionChunk c) => partials.add(c.text),
      );

      // Handshake.
      socket.incoming.add(
        jsonEncode(<String, Object?>{'code': 0, 'message': 'success'}),
      );
      await _pump();

      engine.acceptAudio(Float32List.fromList(<double>[0.2, 0.3]));
      expect(socket.sent, isNotEmpty);

      // First sentence finishes, second one streams.
      socket.incoming.add(
        jsonEncode(<String, Object?>{
          'code': 0,
          'result': <String, Object?>{
            'slice_type': 2,
            'index': 0,
            'voice_text_str': '第一句。',
          },
        }),
      );
      socket.incoming.add(
        jsonEncode(<String, Object?>{
          'code': 0,
          'result': <String, Object?>{
            'slice_type': 1,
            'index': 1,
            'voice_text_str': '第二',
          },
        }),
      );
      await _pump();
      expect(partials, contains('第一句。'));
      expect(partials.last, '第一句。第二');

      final Future<String> finished = engine.finish();
      await _pump();
      expect(socket.sent.last, '{"type":"end"}');
      socket.incoming.add(jsonEncode(<String, Object?>{'final': 1}));
      expect(await finished, '第一句。第二');
      await engine.dispose();
      expect(socket.closed, isTrue);
    });

    test('fails the session when the service rejects the signature', () async {
      final _FakeSocket socket = _FakeSocket();
      final TencentHunyuanAsrEngine engine = TencentHunyuanAsrEngine(
        config: const TencentHunyuanAsrConfig(
          appId: '123',
          secretId: 'id',
          secretKey: 'wrong',
        ),
        opener: (_, __) async => socket,
      );
      await engine.initialize(null, null);

      final Future<String> finished = engine.finish();
      await _pump();
      socket.incoming.add(
        jsonEncode(<String, Object?>{
          'code': 4001,
          'message': 'signature invalid',
        }),
      );
      await expectLater(finished, throwsA(isA<OnlineAsrException>()));
      await engine.dispose();
    });
  });
}

/// Builds a full-server-response binary frame carrying JSON [text].
Uint8List _volcResponse(String text, {required bool isLast}) {
  final Uint8List payload = Uint8List.fromList(
    GZipCodec().encode(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'result': <String, Object?>{'text': text},
        }),
      ),
    ),
  );
  final ByteData sized = ByteData(4 + payload.length)
    ..setUint32(0, payload.length, Endian.big);
  final Uint8List body = sized.buffer.asUint8List()..setAll(4, payload);
  final Uint8List seq = Uint8List(4)
    ..buffer.asByteData().setInt32(0, 1, Endian.big);
  final int flags = 0x1 | (isLast ? 0x2 : 0x0);
  final BytesBuilder frame = BytesBuilder()
    ..add(<int>[0x11, 0x90 | flags, 0x11, 0x00])
    ..add(seq)
    ..add(body);
  return frame.toBytes();
}

/// Builds an error-response payload (code + size + gzip JSON message).
List<int> _errorBody(int code, String message) {
  final Uint8List payload = Uint8List.fromList(
    GZipCodec().encode(
      utf8.encode(jsonEncode(<String, Object?>{'message': message})),
    ),
  );
  final ByteData head = ByteData(8)
    ..setInt32(0, code, Endian.big)
    ..setUint32(4, payload.length, Endian.big);
  return head.buffer.asUint8List() + payload;
}

/// Lets socket events reach the engine's listener.
Future<void> _pump() => Future<void>.delayed(Duration.zero);

/// Scripted socket capturing everything the engine sends.
class _FakeSocket implements OnlineAsrSocket {
  final StreamController<Object> incoming = StreamController<Object>();
  final List<Object> sent = <Object>[];
  bool closed = false;

  @override
  Stream<Object> get messages => incoming.stream;

  @override
  void sendBinary(List<int> bytes) => sent.add(Uint8List.fromList(bytes));

  @override
  void sendText(String text) => sent.add(text);

  @override
  Future<void> close() async {
    closed = true;
  }
}
