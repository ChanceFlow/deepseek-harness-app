/// Provider/model administration surface tests — the Settings section that
/// lists providers, stores or clears an API key through the host credential
/// plane, adds and removes provider profiles, and discovers models.
library;

import 'package:app/di/providers.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/ui/settings/llm_providers.dart';
import 'package:app/ui/settings/settings_backend_scope.dart';
import 'package:domain/model/llm_provider.dart';
import 'package:domain/model/settings.dart';
import 'package:domain/repository/chat_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';

const String _backendId = 'test-backend';

/// Fixed scope so the section resolves one backend without a registry.
class _FixedScope extends SettingsBackendScope {
  @override
  String build() => _backendId;
}

class _FakeProvidersRepository implements ChatRepository {
  _FakeProvidersRepository({
    this.providers = const <LlmProvider>[],
    this.directory = const <LlmConfigurableProvider>[],
    this.credentials = const <String, CredentialStatus>{},
    this.discovered = const <LlmDiscoveredModel>[],
    this.discoverError,
    this.setKeyError,
    this.writable = true,
  });

  List<LlmProvider> providers;
  List<LlmConfigurableProvider> directory;
  Map<String, CredentialStatus> credentials;
  List<LlmDiscoveredModel> discovered;
  Object? discoverError;
  Object? setKeyError;
  bool writable;
  int revision = 4;

  final List<(String, String)> setCredentialCalls = <(String, String)>[];
  final List<String> unsetCredentialCalls = <String>[];
  final List<(String, List<SettingPathOp>, int?)> mutateCalls =
      <(String, List<SettingPathOp>, int?)>[];
  final List<(String, LlmModelDiscoveryRequest)> discoverCalls =
      <(String, LlmModelDiscoveryRequest)>[];

  static const Map<String, Object?> _profileValue = <String, Object?>{
    'providers': <String, Object?>{
      'anthropic': <String, Object?>{
        'apiKeyEnv': 'ANTHROPIC_API_KEY',
        'baseURL': 'https://api.anthropic.com',
      },
    },
  };

  static const Map<String, Object?> _profileUser = <String, Object?>{
    'providers': <String, Object?>{
      'anthropic': <String, Object?>{'apiKeyEnv': 'ANTHROPIC_API_KEY'},
    },
  };

  @override
  Future<SettingsSnapshot> describeSettings() async => SettingsSnapshot(
    writable: writable,
    hasDocument: true,
    namespaces: <SettingsNamespace>[
      SettingsNamespace(
        ns: 'llm-pi-ai',
        applies: SettingsApplies.live,
        revision: revision,
        hasUserLayer: true,
        secretCount: 0,
        value: _profileValue,
        user: _profileUser,
      ),
    ],
    credentialRefs: credentials.keys.toList(),
  );

  @override
  Future<List<LlmProvider>> listLlmProviders() async => providers;

  @override
  Future<List<LlmConfigurableProvider>> listConfigurableProviders() async =>
      directory;

  @override
  Future<List<CredentialStatus>> describeCredentials(List<String> refs) async =>
      <CredentialStatus>[
        for (final String ref in refs)
          credentials[ref] ??
              CredentialStatus(ref: ref, configured: false, writable: true),
      ];

  @override
  Future<void> setCredential(String ref, String value) async {
    setCredentialCalls.add((ref, value));
    if (setKeyError != null) throw setKeyError!;
    credentials = <String, CredentialStatus>{
      ...credentials,
      ref: CredentialStatus(ref: ref, configured: true, writable: true),
    };
  }

  @override
  Future<void> unsetCredential(String ref) async {
    unsetCredentialCalls.add(ref);
    credentials = <String, CredentialStatus>{
      ...credentials,
      ref: CredentialStatus(ref: ref, configured: false, writable: true),
    };
  }

  @override
  Future<SettingsNamespace> mutateSetting(
    String ns,
    List<SettingPathOp> ops, {
    int? expectedRevision,
  }) async {
    mutateCalls.add((ns, ops, expectedRevision));
    revision += 1;
    return SettingsNamespace(
      ns: ns,
      applies: SettingsApplies.live,
      revision: revision,
      hasUserLayer: true,
      secretCount: 0,
      value: _profileValue,
      user: _profileUser,
    );
  }

  @override
  Future<List<LlmDiscoveredModel>> discoverModels(
    String settingsNs,
    LlmModelDiscoveryRequest request,
  ) async {
    discoverCalls.add((settingsNs, request));
    if (discoverError != null) throw discoverError!;
    return discovered;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}

_FakeProvidersRepository _repository({
  List<LlmProvider> providers = const <LlmProvider>[
    LlmProvider(id: 'anthropic', name: 'anthropic'),
  ],
  List<LlmConfigurableProvider> directory = const <LlmConfigurableProvider>[
    LlmConfigurableProvider(
      provider: 'anthropic',
      displayName: 'anthropic',
      settingsNs: 'llm-pi-ai',
      settingsPath: <String>['providers', 'anthropic'],
    ),
    LlmConfigurableProvider(
      provider: 'groq',
      displayName: 'groq',
      settingsNs: 'llm-pi-ai',
      settingsPath: <String>['providers', 'groq'],
    ),
  ],
  Map<String, CredentialStatus> credentials = const <String, CredentialStatus>{
    'ANTHROPIC_API_KEY': CredentialStatus(
      ref: 'ANTHROPIC_API_KEY',
      configured: true,
      source: 'file',
      writable: true,
    ),
  },
  List<LlmDiscoveredModel> discovered = const <LlmDiscoveredModel>[
    LlmDiscoveredModel(
      id: 'claude-sonnet-4-5',
      name: 'Claude Sonnet 4.5',
      contextWindow: 200000,
      maxTokens: 8192,
    ),
  ],
  Object? discoverError,
  Object? setKeyError,
  bool writable = true,
}) {
  return _FakeProvidersRepository(
    providers: providers,
    directory: directory,
    credentials: credentials,
    discovered: discovered,
    discoverError: discoverError,
    setKeyError: setKeyError,
    writable: writable,
  );
}

Future<void> _pump(
  WidgetTester tester,
  _FakeProvidersRepository repository,
) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chatRepositoryProvider(_backendId).overrideWithValue(repository),
        settingsBackendScopeProvider.overrideWith(_FixedScope.new),
      ],
      child: l10nApp(
        home: const Scaffold(
          body: SingleChildScrollView(child: SettingsLlmProvidersSection()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openSheet(WidgetTester tester, String title) async {
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => ErrorLogCollector.instance.clear());

  testWidgets('lists providers with live/dormant and key state', (
    WidgetTester tester,
  ) async {
    await _pump(tester, _repository());

    expect(find.text('Providers'), findsOneWidget);
    expect(find.text('anthropic'), findsWidgets);
    expect(find.text('groq'), findsOneWidget);
    // anthropic is registered (Live); groq is declared but dormant.
    expect(find.textContaining('Live'), findsOneWidget);
    expect(find.textContaining('Dormant'), findsOneWidget);
    // The profile names ANTHROPIC_API_KEY (configured); groq derives
    // GROQ_API_KEY, which no credential carries.
    expect(find.textContaining('API key configured'), findsOneWidget);
    expect(find.textContaining('API key missing'), findsOneWidget);
  });

  testWidgets('stores an API key and records the derived apiKeyEnv', (
    WidgetTester tester,
  ) async {
    final _FakeProvidersRepository repository = _repository(
      credentials: const <String, CredentialStatus>{},
    );
    await _pump(tester, repository);
    await _openSheet(tester, 'groq');

    // The key field is obscured.
    final TextField field = tester.widget<TextField>(find.byType(TextField));
    expect(field.obscureText, isTrue);

    await tester.enterText(find.byType(TextField), 'sk-secret-value');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repository.setCredentialCalls, <(String, String)>[
      ('GROQ_API_KEY', 'sk-secret-value'),
    ]);
    // The profile named no apiKeyEnv, so the write records the derived ref.
    expect(repository.mutateCalls, hasLength(1));
    final (String ns, List<SettingPathOp> ops, int? revision) =
        repository.mutateCalls.single;
    expect(ns, 'llm-pi-ai');
    expect(revision, 4);
    expect(ops.single.op, 'set');
    expect(ops.single.path, <String>['providers', 'groq', 'apiKeyEnv']);
    expect(ops.single.jsonValue, '"GROQ_API_KEY"');
    // The literal never reaches the rendered tree.
    expect(find.text('sk-secret-value'), findsNothing);
  });

  testWidgets('a refused key write reports it without logging the secret', (
    WidgetTester tester,
  ) async {
    final _FakeProvidersRepository repository = _repository(
      credentials: const <String, CredentialStatus>{},
      setKeyError: StateError('credential/rejected: read-only source'),
    );
    await _pump(tester, repository);
    await _openSheet(tester, 'groq');

    await tester.enterText(find.byType(TextField), 'sk-do-not-log-me');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('credential/rejected'), findsOneWidget);
    final List<ErrorLogEntry> entries = ErrorLogCollector.instance.entries;
    expect(entries, isNotEmpty);
    for (final ErrorLogEntry entry in entries) {
      final String serialized =
          '${entry.message} ${entry.context} ${entry.breadcrumbs}';
      expect(serialized.contains('sk-do-not-log-me'), isFalse);
    }
  });

  testWidgets('clears a stored key through credentials.unset', (
    WidgetTester tester,
  ) async {
    final _FakeProvidersRepository repository = _repository();
    await _pump(tester, repository);
    await _openSheet(tester, 'anthropic');

    await tester.tap(find.text('Unset'));
    await tester.pumpAndSettle();

    expect(repository.unsetCredentialCalls, <String>['ANTHROPIC_API_KEY']);
  });

  testWidgets('discovers models for a configured provider', (
    WidgetTester tester,
  ) async {
    final _FakeProvidersRepository repository = _repository();
    await _pump(tester, repository);
    await _openSheet(tester, 'anthropic');

    await tester.tap(find.text('Discover models'));
    await tester.pumpAndSettle();

    expect(repository.discoverCalls, hasLength(1));
    final (String ns, LlmModelDiscoveryRequest request) =
        repository.discoverCalls.single;
    expect(ns, 'llm-pi-ai');
    expect(
      request,
      const LlmModelDiscoveryRequest(
        provider: 'anthropic',
        baseURL: 'https://api.anthropic.com',
      ),
    );
    expect(find.text('Claude Sonnet 4.5'), findsOneWidget);
    expect(find.textContaining('200000'), findsOneWidget);
  });

  testWidgets('reports a refused discovery without a key literal', (
    WidgetTester tester,
  ) async {
    final _FakeProvidersRepository repository = _repository(
      discoverError: StateError('no model discovery is registered'),
    );
    await _pump(tester, repository);
    await _openSheet(tester, 'anthropic');

    await tester.tap(find.text('Discover models'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Model discovery failed'), findsOneWidget);
  });

  testWidgets('removes a removable provider profile', (
    WidgetTester tester,
  ) async {
    final _FakeProvidersRepository repository = _repository();
    await _pump(tester, repository);
    await _openSheet(tester, 'anthropic');

    await tester.tap(find.text('Remove provider'));
    await tester.pumpAndSettle();
    expect(find.text('Remove anthropic?'), findsOneWidget);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(repository.mutateCalls, hasLength(1));
    final (String ns, List<SettingPathOp> ops, int? _) =
        repository.mutateCalls.single;
    expect(ns, 'llm-pi-ai');
    expect(ops.single.op, 'unset');
    expect(ops.single.path, <String>['providers', 'anthropic']);
  });

  testWidgets('adds a hand-declared provider profile and stores its key', (
    WidgetTester tester,
  ) async {
    final _FakeProvidersRepository repository = _repository();
    await _pump(tester, repository);

    await tester.tap(find.text('Add provider'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'acme-gateway');
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(repository.mutateCalls, hasLength(1));
    final (String ns, List<SettingPathOp> ops, int? revision) =
        repository.mutateCalls.single;
    expect(ns, 'llm-pi-ai');
    expect(revision, 4);
    expect(ops.single.op, 'set');
    expect(ops.single.path, <String>['providers', 'acme-gateway']);
    expect(ops.single.jsonValue, isNot(contains('apiKeyEnv')));
  });

  testWidgets('rejects a route id outside the kebab-case grammar', (
    WidgetTester tester,
  ) async {
    final _FakeProvidersRepository repository = _repository();
    await _pump(tester, repository);

    await tester.tap(find.text('Add provider'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Acme Gateway');
    await tester.pump();

    expect(
      find.text(
        'Use lower-case letters, digits, and single hyphens, starting with a letter.',
      ),
      findsOneWidget,
    );
    final FilledButton add = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Add'),
    );
    expect(add.onPressed, isNull);
  });

  testWidgets('renders the read-only notice and disables the add row', (
    WidgetTester tester,
  ) async {
    await _pump(tester, _repository(writable: false));

    expect(
      find.text('The settings document is read-only in this deployment.'),
      findsOneWidget,
    );
    final ListTile addRow = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'Add provider'),
    );
    expect(addRow.enabled, isFalse);
  });

  testWidgets('has no provider rows while the host lists none', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      _repository(
        providers: const <LlmProvider>[],
        directory: const <LlmConfigurableProvider>[],
      ),
    );

    expect(
      find.text('No configurable providers on this host.'),
      findsOneWidget,
    );
  });

  testWidgets('localizes the section in Chinese', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatRepositoryProvider(_backendId).overrideWithValue(_repository()),
          settingsBackendScopeProvider.overrideWith(_FixedScope.new),
        ],
        child: l10nApp(
          locale: const Locale('zh'),
          home: const Scaffold(
            body: SingleChildScrollView(child: SettingsLlmProvidersSection()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final AppLocalizations l10n = await AppLocalizations.delegate.load(
      const Locale('zh'),
    );
    expect(find.text(l10n.settingsSectionProviders), findsOneWidget);
    expect(find.text(l10n.addProvider), findsOneWidget);
  });
}
