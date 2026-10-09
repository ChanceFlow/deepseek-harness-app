/// The shell and web-search plugin settings pages: the pin's rows, the
/// effective values they show, and the one CAS-guarded write Save performs.
///
/// The repository is a double because these pages are the settings seam's
/// callers, not its wire: the describe, the path ops, the revision and the
/// credential write are asserted at the call, and the rows are read through the
/// real page widgets ([docs/testing.md](../../../../docs/testing.md)).
library;

import 'dart:convert';

import 'package:app/di/providers.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/ui/settings/settings_chrome.dart';
import 'package:app/ui/settings/shell_settings_page.dart';
import 'package:app/ui/settings/web_search_settings_page.dart';
import 'package:domain/model/settings.dart';
import 'package:domain/repository/chat_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';

/// The settings plane as these pages use it: the described namespaces and their
/// revisions, the applied path ops, and the credential store.
class _FakeSettingsRepository implements ChatRepository {
  _FakeSettingsRepository({
    required this.namespaces,
    this.writable = true,
    this.credentialConfigured = false,
    this.credentialWritable = true,
    this.failWrites = false,
  });

  List<SettingsNamespace> namespaces;
  bool writable;
  bool credentialConfigured;
  bool credentialWritable;
  bool failWrites;

  final List<(String ns, List<SettingPathOp> ops, int? revision)> mutates =
      <(String, List<SettingPathOp>, int?)>[];
  final List<(String ref, String value)> credentialWrites =
      <(String, String)>[];

  @override
  Future<SettingsSnapshot> describeSettings() async => SettingsSnapshot(
    writable: writable,
    hasDocument: true,
    namespaces: namespaces,
    credentialRefs: const <String>[],
  );

  @override
  Future<SettingsNamespace> mutateSetting(
    String ns,
    List<SettingPathOp> ops, {
    int? expectedRevision,
  }) async {
    mutates.add((ns, ops, expectedRevision));
    if (failWrites) throw StateError('write refused');
    final SettingsNamespace before = namespaces.firstWhere(
      (SettingsNamespace entry) => entry.ns == ns,
    );
    final Map<String, Object?> value = <String, Object?>{
      ...?before.value as Map<String, Object?>?,
    };
    final Map<String, Object?> user = <String, Object?>{
      ...?before.user as Map<String, Object?>?,
    };
    for (final SettingPathOp op in ops) {
      final String key = op.path.isEmpty ? '' : op.path.first;
      if (op.op == 'unset') {
        value.remove(key);
        user.remove(key);
      } else {
        final Object? decoded = jsonDecode(op.jsonValue ?? 'null');
        value[key] = decoded;
        user[key] = decoded;
      }
    }
    final SettingsNamespace after = SettingsNamespace(
      ns: ns,
      applies: before.applies,
      revision: before.revision + 1,
      hasUserLayer: user.isNotEmpty,
      secretCount: before.secretCount,
      value: value,
      user: user,
    );
    namespaces = <SettingsNamespace>[
      for (final SettingsNamespace entry in namespaces)
        if (entry.ns == ns) after else entry,
    ];
    return after;
  }

  @override
  Future<List<CredentialStatus>> describeCredentials(List<String> refs) async =>
      <CredentialStatus>[
        CredentialStatus(
          ref: refs.first,
          configured: credentialConfigured,
          writable: credentialWritable,
        ),
      ];

  @override
  Future<void> setCredential(String ref, String value) async {
    credentialWrites.add((ref, value));
    credentialConfigured = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}

SettingsNamespace _namespace(
  String ns, {
  Map<String, Object?> value = const <String, Object?>{},
  Map<String, Object?> user = const <String, Object?>{},
  int revision = 4,
}) => SettingsNamespace(
  ns: ns,
  applies: SettingsApplies.live,
  revision: revision,
  hasUserLayer: user.isNotEmpty,
  secretCount: 0,
  value: value,
  user: user,
);

Future<void> _pumpShell(
  WidgetTester tester,
  _FakeSettingsRepository repository,
) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [chatRepositoryProvider('b1').overrideWithValue(repository)],
      child: l10nApp(home: const SettingsShellPage(backendId: 'b1')),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpWebSearch(
  WidgetTester tester,
  _FakeSettingsRepository repository,
) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [chatRepositoryProvider('b1').overrideWithValue(repository)],
      child: l10nApp(home: const SettingsWebSearchPage(backendId: 'b1')),
    ),
  );
  await tester.pumpAndSettle();
}

/// The row a namespace field renders, by the key the form gives it.
Finder _field(String key) =>
    find.byKey(ValueKey<String>('host-namespace-field-$key'));

void main() {
  final AppLocalizations l10n = lookupAppLocalizations(const Locale('en'));

  group('shell page', () {
    testWidgets('renders the executor namespace\'s two rows', (
      WidgetTester tester,
    ) async {
      final repository = _FakeSettingsRepository(
        namespaces: <SettingsNamespace>[
          _namespace(
            kShellBashNamespace,
            value: const <String, Object?>{
              'timeoutMs': 30000,
              'maxOutputBytes': 1048576,
            },
          ),
        ],
      );
      await _pumpShell(tester, repository);

      expect(find.text(l10n.settingsShellTimeoutMsLabel), findsOneWidget);
      expect(find.text(l10n.settingsShellMaxOutputBytesLabel), findsOneWidget);
      expect(find.text('30000'), findsOneWidget);
      expect(find.text('1048576'), findsOneWidget);
      // The pin's summary copy leads the page.
      expect(find.text(l10n.settingsShellDescription), findsOneWidget);
    });

    testWidgets('Save writes one CAS-guarded path op for the edited row', (
      WidgetTester tester,
    ) async {
      final repository = _FakeSettingsRepository(
        namespaces: <SettingsNamespace>[
          _namespace(
            kShellBashNamespace,
            value: const <String, Object?>{
              'timeoutMs': 30000,
              'maxOutputBytes': 1048576,
            },
          ),
        ],
      );
      await _pumpShell(tester, repository);

      await tester.enterText(_field('timeoutMs'), '45000');
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.save));
      await tester.pumpAndSettle();

      expect(repository.mutates, hasLength(1));
      final (String ns, List<SettingPathOp> ops, int? revision) =
          repository.mutates.single;
      expect(ns, kShellBashNamespace);
      // The described revision is the CAS guard the write rides.
      expect(revision, 4);
      expect(ops, hasLength(1));
      expect(ops.single.op, 'set');
      expect(ops.single.path, <String>['timeoutMs']);
      expect(jsonDecode(ops.single.jsonValue!), 45000);
      // The page adopts what the Host reports after the write.
      expect(find.text('45000'), findsOneWidget);
    });

    testWidgets('an overridden row offers the reset and unsets on Save', (
      WidgetTester tester,
    ) async {
      final repository = _FakeSettingsRepository(
        namespaces: <SettingsNamespace>[
          _namespace(
            kShellBashNamespace,
            value: const <String, Object?>{'timeoutMs': 30000},
            user: const <String, Object?>{'timeoutMs': 30000},
          ),
        ],
      );
      await _pumpShell(tester, repository);

      expect(find.text(l10n.settingsFormOverridden), findsOneWidget);
      await tester.tap(find.text(l10n.settingsFormReset));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.save));
      await tester.pumpAndSettle();

      final (_, List<SettingPathOp> ops, _) = repository.mutates.single;
      expect(ops.single.op, 'unset');
      expect(ops.single.path, <String>['timeoutMs']);
    });

    testWidgets('a refused write states the pin\'s save-failed copy', (
      WidgetTester tester,
    ) async {
      final repository = _FakeSettingsRepository(
        failWrites: true,
        namespaces: <SettingsNamespace>[
          _namespace(
            kShellBashNamespace,
            value: const <String, Object?>{'timeoutMs': 30000},
          ),
        ],
      );
      await _pumpShell(tester, repository);

      await tester.enterText(_field('timeoutMs'), '45000');
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.save));
      await tester.pumpAndSettle();

      expect(repository.mutates, hasLength(1));
      expect(find.text(l10n.settingsFormSaveFailed), findsOneWidget);
    });

    testWidgets('a non-numeric draft blocks the save with the pin copy', (
      WidgetTester tester,
    ) async {
      final repository = _FakeSettingsRepository(
        namespaces: <SettingsNamespace>[
          _namespace(
            kShellBashNamespace,
            value: const <String, Object?>{'timeoutMs': 30000},
          ),
        ],
      );
      await _pumpShell(tester, repository);

      // The formatter keeps letters out, so the invalid state is reached the
      // way a reader reaches it: a quantity that is not a number.
      await tester.enterText(_field('timeoutMs'), '30.5.5');
      await tester.pumpAndSettle();

      expect(find.text(l10n.settingsFormInvalidNumber), findsOneWidget);
      final FilledButton save = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, l10n.save),
      );
      expect(save.onPressed, isNull);
      expect(repository.mutates, isEmpty);
    });

    testWidgets('an unserved namespace states the pin\'s unavailable copy', (
      WidgetTester tester,
    ) async {
      final repository = _FakeSettingsRepository(
        namespaces: const <SettingsNamespace>[],
      );
      await _pumpShell(tester, repository);

      expect(find.text(l10n.settingsFormUnavailable), findsOneWidget);
      expect(find.text(l10n.save), findsNothing);
    });

    testWidgets('a read-only document disables the form', (
      WidgetTester tester,
    ) async {
      final repository = _FakeSettingsRepository(
        writable: false,
        namespaces: <SettingsNamespace>[
          _namespace(
            kShellBashNamespace,
            value: const <String, Object?>{'timeoutMs': 30000},
          ),
        ],
      );
      await _pumpShell(tester, repository);

      expect(find.text(l10n.settingsFormReadOnly), findsOneWidget);
      final TextField timeout = tester.widget<TextField>(_field('timeoutMs'));
      expect(timeout.enabled, isFalse);
      final FilledButton save = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, l10n.save),
      );
      expect(save.onPressed, isNull);
    });

    testWidgets('the PowerShell binding serves the page on Windows', (
      WidgetTester tester,
    ) async {
      final repository = _FakeSettingsRepository(
        namespaces: <SettingsNamespace>[
          _namespace(
            kShellPwshNamespace,
            value: const <String, Object?>{'timeoutMs': 20000},
          ),
        ],
      );
      await _pumpShell(tester, repository);

      expect(find.text('20000'), findsOneWidget);
    });
  });

  group('web search page', () {
    testWidgets('renders the key, the endpoint and the search budget', (
      WidgetTester tester,
    ) async {
      final repository = _FakeSettingsRepository(
        namespaces: <SettingsNamespace>[
          _namespace(
            kWebSearchNamespace,
            value: const <String, Object?>{'maxUses': 5},
          ),
        ],
      );
      await _pumpWebSearch(tester, repository);

      expect(find.text(l10n.settingsWebSearchApiKeyLabel), findsOneWidget);
      expect(find.text(l10n.settingsWebSearchBaseUrlLabel), findsOneWidget);
      expect(find.text(l10n.settingsWebSearchMaxUsesLabel), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      // The key reports its state, never its literal.
      expect(find.text(l10n.settingsWebSearchApiKeyUnset), findsOneWidget);
    });

    testWidgets('Save writes the key through the credentials domain', (
      WidgetTester tester,
    ) async {
      final repository = _FakeSettingsRepository(
        namespaces: <SettingsNamespace>[
          _namespace(kWebSearchNamespace, value: const <String, Object?>{}),
        ],
      );
      await _pumpWebSearch(tester, repository);

      await tester.enterText(
        find.byKey(const ValueKey<String>('host-namespace-secret')),
        'sk-live',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.save));
      await tester.pumpAndSettle();

      expect(repository.credentialWrites, <(String, String)>[
        (kWebSearchDefaultApiKeyRef, 'sk-live'),
      ]);
      // The key is not a settings field: the document carries no op for it.
      expect(repository.mutates, isEmpty);
      expect(find.text(l10n.settingsWebSearchApiKeySet), findsOneWidget);
    });

    testWidgets('a blank key draft keeps the stored key', (
      WidgetTester tester,
    ) async {
      final repository = _FakeSettingsRepository(
        credentialConfigured: true,
        namespaces: <SettingsNamespace>[
          _namespace(
            kWebSearchNamespace,
            value: const <String, Object?>{'maxUses': 3},
          ),
        ],
      );
      await _pumpWebSearch(tester, repository);

      await tester.enterText(_field('maxUses'), '7');
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.save));
      await tester.pumpAndSettle();

      expect(repository.credentialWrites, isEmpty);
      expect(repository.mutates.single.$2.single.path, <String>['maxUses']);
    });

    testWidgets('the key stays writable while the document is read-only', (
      WidgetTester tester,
    ) async {
      final repository = _FakeSettingsRepository(
        writable: false,
        credentialWritable: true,
        namespaces: <SettingsNamespace>[
          _namespace(
            kWebSearchNamespace,
            value: const <String, Object?>{'maxUses': 3},
          ),
        ],
      );
      await _pumpWebSearch(tester, repository);

      // The two stores refuse separately: the credentials domain accepts a key
      // even when the settings document does not (`WebSearchCard.tsx:35-39`).
      expect(find.text(l10n.settingsFormReadOnly), findsOneWidget);
      final TextField key = tester.widget<TextField>(
        find.byKey(const ValueKey<String>('host-namespace-secret')),
      );
      expect(key.enabled, isTrue);
      final TextField budget = tester.widget<TextField>(_field('maxUses'));
      expect(budget.enabled, isFalse);
    });

    testWidgets('an unwritable credential disables only the key control', (
      WidgetTester tester,
    ) async {
      final repository = _FakeSettingsRepository(
        credentialWritable: false,
        namespaces: <SettingsNamespace>[
          _namespace(
            kWebSearchNamespace,
            value: const <String, Object?>{'maxUses': 3},
          ),
        ],
      );
      await _pumpWebSearch(tester, repository);

      final TextField key = tester.widget<TextField>(
        find.byKey(const ValueKey<String>('host-namespace-secret')),
      );
      expect(key.enabled, isFalse);
      final TextField budget = tester.widget<TextField>(_field('maxUses'));
      expect(budget.enabled, isTrue);
    });
  });

  group('index rows', () {
    testWidgets('the shell row opens the page while the Host serves it', (
      WidgetTester tester,
    ) async {
      final repository = _FakeSettingsRepository(
        namespaces: <SettingsNamespace>[
          _namespace(
            kShellBashNamespace,
            value: const <String, Object?>{'timeoutMs': 30000},
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeBackendIdProvider.overrideWith(
              (Ref ref) => Stream<String>.value('b1'),
            ),
            chatRepositoryProvider('b1').overrideWithValue(repository),
          ],
          child: l10nApp(home: const Scaffold(body: SettingsShellEntryRow())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.settingsNavShell), findsOneWidget);
      expect(find.text(l10n.settingsFormUnavailable), findsNothing);
      await tester.tap(find.text(l10n.settingsNavShell));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsShellPage), findsOneWidget);
    });

    testWidgets('a namespace the Host does not serve disables its row', (
      WidgetTester tester,
    ) async {
      final repository = _FakeSettingsRepository(
        namespaces: <SettingsNamespace>[],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeBackendIdProvider.overrideWith(
              (Ref ref) => Stream<String>.value('b1'),
            ),
            chatRepositoryProvider('b1').overrideWithValue(repository),
          ],
          child: l10nApp(
            home: const Scaffold(body: SettingsWebSearchEntryRow()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.settingsNavWebSearch), findsOneWidget);
      expect(find.text(l10n.settingsFormUnavailable), findsOneWidget);
      final SettingsNavRow row = tester.widget<SettingsNavRow>(
        find.byType(SettingsNavRow),
      );
      expect(row.enabled, isFalse);
    });
  });
}
