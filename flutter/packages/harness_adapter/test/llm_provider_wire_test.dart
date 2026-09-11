/// `llm/*` provider-administration wire tests (DSH 0.1.5).
///
/// Fixtures are transcribed from a live `dsh web` host (pinned
/// `dsh-v0.1.5-rc.2`, `POST /api/llm/listProviders` etc.) and cross-checked
/// against the declaration source
/// `reference/deepseek-harness/packages/llm/llm/src/index.ts` (`LlmRuntime`)
/// and its `types.ts` (`LlmProviderInfo`, `LlmConfigurableProvider`,
/// `LlmDiscoveredModel`, `LlmModelDiscoveryRequest`).
library;

import 'dart:async';

import 'package:domain/model/llm_provider.dart';
import 'package:harness_adapter/src/dsh_connection_manager.dart';
import 'package:harness_adapter/src/harness_repository_impl.dart';
import 'package:harness_adapter/src/rpc_map.dart';
import 'package:harness_adapter/src/wire_json.dart';
import 'package:network/dsh_event_socket.dart';
import 'package:network/dsh_rpc_client.dart';
import 'package:network/rpc_envelope.dart';
import 'package:test/test.dart';

/// `POST /api/llm/listProviders` on the live host: a bare JSON array, which
/// the RPC envelope parks under `value`.
const JsonMap _listProvidersValue = <String, Object?>{
  'value': <Object?>[
    <String, Object?>{'id': 'deepseek-official', 'name': 'DeepSeek'},
    <String, Object?>{'id': 'google-vertex', 'name': 'Google Vertex (Gemini)'},
    <String, Object?>{'id': 'p1', 'name': 'p1 (claude.p1.cn)'},
  ],
};

/// `POST /api/llm/listConfigurableProviders` on the live host, trimmed to
/// four entries: the whole-section DeepSeek profile plus three pi-ai dict
/// routes.
const JsonMap _listConfigurableProvidersValue = <String, Object?>{
  'value': <Object?>[
    <String, Object?>{
      'provider': 'deepseek-official',
      'displayName': 'DeepSeek',
      'settingsNs': 'llm-deepseek',
      'settingsPath': <Object?>[],
    },
    <String, Object?>{
      'provider': 'amazon-bedrock',
      'displayName': 'amazon-bedrock',
      'settingsNs': 'llm-pi-ai',
      'settingsPath': <Object?>['providers', 'amazon-bedrock'],
      'declared': false,
    },
    <String, Object?>{
      'provider': 'anthropic',
      'displayName': 'anthropic',
      'settingsNs': 'llm-pi-ai',
      'settingsPath': <Object?>['providers', 'anthropic'],
      'declared': false,
    },
    <String, Object?>{
      'provider': 'acme-gateway',
      'displayName': 'Acme Gateway',
      'settingsNs': 'llm-pi-ai',
      'settingsPath': <Object?>['providers', 'acme-gateway'],
      'declared': true,
      'error': 'model "acme-large" has no contextWindow',
    },
  ],
};

/// `POST /api/llm/discoverModels` with `settingsNs: llm-pi-ai` and
/// `provider: deepseek` on the live host (the installed pi-ai catalog
/// answers without a network call).
const JsonMap _discoverModelsValue = <String, Object?>{
  'value': <Object?>[
    <String, Object?>{
      'id': 'deepseek-v4-flash',
      'name': 'DeepSeek V4 Flash',
      'contextWindow': 1000000,
      'maxTokens': 384000,
    },
    <String, Object?>{
      'id': 'deepseek-v4-pro',
      'name': 'DeepSeek V4 Pro',
      'contextWindow': 1000000,
      'maxTokens': 384000,
    },
  ],
};

class _FakeRpc implements DshRpcClient {
  _FakeRpc();

  final Map<String, JsonMap> values = <String, JsonMap>{};
  final Map<String, JsonMap> lastPayload = <String, JsonMap>{};
  final Map<String, int> calls = <String, int>{};

  @override
  Future<RpcResult> call(
    String endpoint,
    String method,
    JsonMap payload, {
    Duration? timeout,
  }) async {
    calls[endpoint] = (calls[endpoint] ?? 0) + 1;
    lastPayload[endpoint] = payload;
    final JsonMap? value = values[endpoint];
    if (value == null) {
      // Every other endpoint the repository reads on construction
      // (session/list, session/page, workspace/follow) answers an empty
      // object; each of those decoders reads an absent collection as empty.
      return RpcResult(ok: true, value: const <String, Object?>{});
    }
    return RpcResult(ok: true, value: value);
  }

  @override
  Future<void> respond(String rpcId, RpcResult result) async {}
}

/// The `$events` registration answer the gateway sends over `/api/remote.mux`
/// (`reference/deepseek-harness/packages/api/gateway/src/stream-protocol.ts`
/// `RemoteEventReadyFrame`); it is the connection generation handshake.
ServerRequest _readyFrame() => ServerRequest(
  rpcId: 'remote-events',
  method: 'item',
  payload: <String, Object?>{
    'type': 'ready',
    'clientId': 'client-1',
    'host': <String, Object?>{'home': '/home/tester'},
  },
);

class _QuietSocket implements DshEventSocket {
  final StreamController<ServerRequest> _mux =
      StreamController<ServerRequest>();

  @override
  Stream<ServerRequest> connect(String path, {void Function()? onOpen}) {
    onOpen?.call();
    _mux.add(_readyFrame());
    return _mux.stream;
  }
}

Future<HarnessRepositoryImpl> _repository(_FakeRpc rpc) async {
  final DshConnectionManager manager = DshConnectionManager(
    _QuietSocket(),
    (int _) => 10000,
  );
  final HarnessRepositoryImpl repository = HarnessRepositoryImpl(rpc, manager);
  await pumpEventQueue();
  return repository;
}

void main() {
  group('llm provider wire DTOs (DSH 0.1.5)', () {
    test('decodeLlmProviderList reads the bare-array listing', () {
      final List<LlmProvider> providers = decodeLlmProviderList(
        _listProvidersValue,
      );

      expect(providers, hasLength(3));
      expect(providers.first.id, 'deepseek-official');
      expect(providers.first.name, 'DeepSeek');
      expect(providers.last.id, 'p1');
    });

    test('decodeLlmProviderList throws naming a missing required field', () {
      expect(
        () => decodeLlmProviderList(const <String, Object?>{
          'value': <Object?>[
            <String, Object?>{'id': 'no-name'},
          ],
        }),
        throwsA(
          isA<FormatException>().having(
            (FormatException e) => e.message,
            'message',
            contains('name'),
          ),
        ),
      );
    });

    test('decodeLlmProviderList throws when value is not an array', () {
      expect(
        () => decodeLlmProviderList(const <String, Object?>{
          'providers': <Object?>[],
        }),
        throwsA(
          isA<FormatException>().having(
            (FormatException e) => e.message,
            'message',
            contains(DshRpcEndpoints.llmListProviders),
          ),
        ),
      );
    });

    test('decodeLlmConfigurableProviderList keeps path and declared state', () {
      final List<LlmConfigurableProvider> directory =
          decodeLlmConfigurableProviderList(_listConfigurableProvidersValue);

      expect(directory, hasLength(4));
      expect(directory.first.provider, 'deepseek-official');
      expect(directory.first.settingsNs, 'llm-deepseek');
      expect(directory.first.settingsPath, isEmpty);
      expect(directory.first.declared, isNull);
      expect(directory[1].settingsPath, <String>[
        'providers',
        'amazon-bedrock',
      ]);
      expect(directory[1].declared, isFalse);
      expect(directory.last.declared, isTrue);
      expect(directory.last.error, contains('acme-large'));
    });

    test('decodeLlmConfigurableProviderList requires settingsPath', () {
      expect(
        () => decodeLlmConfigurableProviderList(const <String, Object?>{
          'value': <Object?>[
            <String, Object?>{
              'provider': 'x',
              'displayName': 'x',
              'settingsNs': 'llm-pi-ai',
            },
          ],
        }),
        throwsA(
          isA<FormatException>().having(
            (FormatException e) => e.message,
            'message',
            contains('settingsPath'),
          ),
        ),
      );
    });

    test('decodeLlmConfigurableProviderList rejects a non-string path', () {
      expect(
        () => decodeLlmConfigurableProviderList(const <String, Object?>{
          'value': <Object?>[
            <String, Object?>{
              'provider': 'x',
              'displayName': 'x',
              'settingsNs': 'llm-pi-ai',
              'settingsPath': <Object?>['providers', 7],
            },
          ],
        }),
        throwsA(
          isA<FormatException>().having(
            (FormatException e) => e.message,
            'message',
            contains('settingsPath'),
          ),
        ),
      );
    });

    test('decodeLlmDiscoveredModelList reads optional capacities', () {
      final List<LlmDiscoveredModel> models = decodeLlmDiscoveredModelList(
        _discoverModelsValue,
      );

      expect(models, hasLength(2));
      expect(models.first.id, 'deepseek-v4-flash');
      expect(models.first.name, 'DeepSeek V4 Flash');
      expect(models.first.contextWindow, 1000000);
      expect(models.first.maxTokens, 384000);
    });

    test('decodeLlmDiscoveredModelList tolerates an id-only listing', () {
      final List<LlmDiscoveredModel> models = decodeLlmDiscoveredModelList(
        const <String, Object?>{
          'value': <Object?>[
            <String, Object?>{'id': 'bare-model'},
          ],
        },
      );

      expect(models.single.id, 'bare-model');
      expect(models.single.name, isNull);
      expect(models.single.contextWindow, isNull);
      expect(models.single.maxTokens, isNull);
    });

    test('decodeLlmDiscoveredModelList requires the model id', () {
      expect(
        () => decodeLlmDiscoveredModelList(const <String, Object?>{
          'value': <Object?>[
            <String, Object?>{'name': 'unnamed'},
          ],
        }),
        throwsA(
          isA<FormatException>().having(
            (FormatException e) => e.message,
            'message',
            contains('id'),
          ),
        ),
      );
    });
  });

  group('repository llm methods', () {
    test('listLlmProviders and listConfigurableProviders decode both '
        'listings', () async {
      final _FakeRpc rpc = _FakeRpc()
        ..values[DshRpcEndpoints.llmListProviders] = _listProvidersValue
        ..values[DshRpcEndpoints.llmListConfigurableProviders] =
            _listConfigurableProvidersValue;
      final HarnessRepositoryImpl repository = await _repository(rpc);

      final List<LlmProvider> providers = await repository.listLlmProviders();
      final List<LlmConfigurableProvider> directory = await repository
          .listConfigurableProviders();

      expect(rpc.calls[DshRpcEndpoints.llmListProviders], 1);
      expect(rpc.calls[DshRpcEndpoints.llmListConfigurableProviders], 1);
      expect(providers.first.name, 'DeepSeek');
      expect(directory[1].settingsPath, <String>[
        'providers',
        'amazon-bedrock',
      ]);
    });

    test(
      'discoverModels sends the namespace and a credential-free draft',
      () async {
        final _FakeRpc rpc = _FakeRpc()
          ..values[DshRpcEndpoints.llmDiscoverModels] = _discoverModelsValue;
        final HarnessRepositoryImpl repository = await _repository(rpc);

        final List<LlmDiscoveredModel> models = await repository.discoverModels(
          'llm-pi-ai',
          const LlmModelDiscoveryRequest(
            provider: 'deepseek',
            baseURL: 'https://gateway.example/v1',
            api: 'openai-completions',
          ),
        );

        expect(models, hasLength(2));
        final JsonMap payload =
            rpc.lastPayload[DshRpcEndpoints.llmDiscoverModels]!;
        final JsonMap args = asJsonObject(payload['args'])!;
        expect(args['settingsNs'], 'llm-pi-ai');
        final JsonMap request = asJsonObject(args['request'])!;
        expect(request['provider'], 'deepseek');
        expect(request['baseURL'], 'https://gateway.example/v1');
        expect(request['api'], 'openai-completions');
        // The client never puts a credential literal on this request: the host
        // resolves a named route's stored key.
        expect(request.containsKey('apiKey'), isFalse);
      },
    );

    test('discoverModels rejects an empty settings namespace', () async {
      final _FakeRpc rpc = _FakeRpc();
      final HarnessRepositoryImpl repository = await _repository(rpc);

      expect(
        () => repository.discoverModels(
          '',
          const LlmModelDiscoveryRequest(provider: 'deepseek'),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('provider directory join', () {
    test('joinProviderDirectory marks live/dormant and appends undeclared '
        'routes', () {
      final List<LlmProviderRow> rows = joinProviderDirectory(
        const <LlmProvider>[
          LlmProvider(id: 'deepseek-official', name: 'DeepSeek'),
          LlmProvider(id: 'llm-only-route', name: 'llm-only-route'),
        ],
        const <LlmConfigurableProvider>[
          LlmConfigurableProvider(
            provider: 'deepseek-official',
            displayName: 'DeepSeek',
            settingsNs: 'llm-deepseek',
            settingsPath: <String>[],
          ),
          LlmConfigurableProvider(
            provider: 'anthropic',
            displayName: 'anthropic',
            settingsNs: 'llm-pi-ai',
            settingsPath: <String>['providers', 'anthropic'],
            declared: false,
          ),
        ],
      );

      expect(rows, hasLength(3));
      expect(rows[0].provider, 'deepseek-official');
      expect(rows[0].active, isTrue);
      expect(rows[1].provider, 'anthropic');
      expect(rows[1].active, isFalse);
      expect(rows[1].configurable, isTrue);
      expect(rows[2].provider, 'llm-only-route');
      expect(rows[2].active, isTrue);
      expect(rows[2].configurable, isFalse);
    });

    test('providerKeyRef derives the conventional credential reference', () {
      expect(providerKeyRef('acme-gateway'), 'ACME_GATEWAY_API_KEY');
      expect(providerKeyRef('p1'), 'P1_API_KEY');
      expect(providerKeyRef('minimax-cn'), 'MINIMAX_CN_API_KEY');
    });

    test('providerFamilies and providerPathFor address a hand-added route', () {
      const List<LlmConfigurableProvider> directory = <LlmConfigurableProvider>[
        LlmConfigurableProvider(
          provider: 'deepseek-official',
          displayName: 'DeepSeek',
          settingsNs: 'llm-deepseek',
          settingsPath: <String>[],
        ),
        LlmConfigurableProvider(
          provider: 'anthropic',
          displayName: 'anthropic',
          settingsNs: 'llm-pi-ai',
          settingsPath: <String>['providers', 'anthropic'],
        ),
      ];

      // Only the path-addressed family can host a second route.
      expect(providerFamilies(directory), <String>['llm-pi-ai']);
      expect(providerPathFor(directory, 'llm-pi-ai', 'acme-gateway'), <String>[
        'providers',
        'acme-gateway',
      ]);
      expect(providerPathFor(directory, 'llm-deepseek', 'x'), isNull);
    });
  });
}
