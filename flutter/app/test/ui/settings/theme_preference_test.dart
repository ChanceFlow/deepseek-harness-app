/// Appearance preference tests — the host `ui-theme` read/write, the
/// device-local OLED flag, and the settings row that drives both.
library;

import 'dart:convert';
import 'dart:io';

import 'package:app/di/providers.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/local_state/local_state_providers.dart';
import 'package:app/local_state/local_state_store.dart';
import 'package:app/ui/settings/theme_preference.dart';
import 'package:app/ui/theme/theme.dart';
import 'package:domain/model/settings.dart';
import 'package:domain/repository/chat_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';

/// The surface the harness below actually rendered, read back from
/// `Theme.of` so the assertion rides the resolved theme, not a hard-coded
/// color.
ColorScheme? _resolvedScheme;

/// Mirrors `DshApp`'s theme wiring in one tree with the settings row, so a
/// tap on a seat travels the real path: store → provider → `MaterialApp`
/// theme.
class _AppearanceHarness extends ConsumerWidget {
  const _AppearanceHarness();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: DshTheme.light(),
      darkTheme: ref.watch(appDarkThemeProvider),
      themeMode: ref.watch(appThemeModeProvider),
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) {
            _resolvedScheme = Theme.of(context).colorScheme;
            return const ThemePreferenceRow();
          },
        ),
      ),
    );
  }
}

class _FakeThemeRepository implements ChatRepository {
  _FakeThemeRepository({
    this.namespacePresent = true,
    this.failWrites = false,
    this.preference = 'dark',
  });

  String preference;
  int revision = 4;
  bool namespacePresent;
  bool writable = true;
  bool failWrites;

  final List<(String, String, String, int?)> writes =
      <(String, String, String, int?)>[];

  @override
  Future<SettingsSnapshot> describeSettings() async {
    return SettingsSnapshot(
      writable: writable,
      hasDocument: true,
      namespaces: namespacePresent
          ? <SettingsNamespace>[
              SettingsNamespace(
                ns: kThemeSettingsNamespace,
                applies: SettingsApplies.live,
                revision: revision,
                hasUserLayer: true,
                secretCount: 0,
                value: <String, Object?>{kThemePreferenceField: preference},
              ),
            ]
          : const <SettingsNamespace>[],
      credentialRefs: const <String>[],
    );
  }

  @override
  Future<SettingsNamespace> updateSetting(
    String ns,
    String key,
    String jsonValue, {
    int? expectedRevision,
  }) async {
    writes.add((ns, key, jsonValue, expectedRevision));
    if (failWrites) throw StateError('write refused');
    preference = jsonDecode(jsonValue) as String;
    revision += 1;
    return (await describeSettings()).namespaces.first;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}

/// A temp-file-backed store for widget tests. Deliberately unloaded: real
/// dart:io does not complete inside a `testWidgets` fake-async zone, so a
/// `load()` here would hang. Reads are null (the unset default) and writes
/// land in the cache the row asserts against.
LocalStateStore _widgetStore() {
  final Directory directory = Directory.systemTemp.createTempSync(
    'theme_pref_test',
  );
  addTearDown(() => directory.deleteSync(recursive: true));
  return LocalStateStore(File('${directory.path}/local_state.json'));
}

/// A temp directory for a test that needs to reload the same document.
Directory _tempDir() {
  final Directory directory = Directory.systemTemp.createTempSync(
    'theme_pref_test',
  );
  addTearDown(() => directory.deleteSync(recursive: true));
  return directory;
}

Future<LocalStateStore> _loadStore(File file) async {
  final LocalStateStore store = LocalStateStore(file);
  await store.load();
  return store;
}

Future<void> _pumpRow(
  WidgetTester tester,
  ThemePreferenceController controller, {
  LocalStateStore? store,
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        activeBackendIdProvider.overrideWith(
          (ref) => Stream<String>.value('b1'),
        ),
        themePreferenceControllerProvider('b1').overrideWithValue(controller),
        if (store != null)
          localStateStoreProvider.overrideWith((ref) async => store),
      ],
      child: l10nApp(
        home: Scaffold(
          // The real settings-card nesting at phone width: the four-seat
          // selector has to fit the row the screen actually gives it.
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: <Widget>[
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: ThemePreferenceRow(),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('reads the persisted preference and the described revision', () async {
    final repository = _FakeThemeRepository();
    final controller = ThemePreferenceController(repository);
    addTearDown(controller.dispose);

    await controller.refresh();

    expect(controller.state.preference, ThemePreference.dark);
    expect(controller.state.preference.themeMode, ThemeMode.dark);
    expect(controller.state.revision, 4);
    expect(controller.state.exposed, isTrue);
    expect(controller.state.writable, isTrue);
  });

  test(
    'an absent namespace reports unavailable and leaves system standing',
    () async {
      final repository = _FakeThemeRepository(namespacePresent: false);
      final controller = ThemePreferenceController(repository);
      addTearDown(controller.dispose);

      await controller.refresh();

      expect(controller.state.exposed, isFalse);
      expect(controller.state.preference, ThemePreference.system);
    },
  );

  test('select writes the field revision-checked and re-reads', () async {
    final repository = _FakeThemeRepository();
    final controller = ThemePreferenceController(repository);
    addTearDown(controller.dispose);
    await controller.refresh();

    await controller.select(ThemePreference.light);

    expect(repository.writes, <(String, String, String, int?)>[
      (kThemeSettingsNamespace, kThemePreferenceField, '"light"', 4),
    ]);
    expect(controller.state.preference, ThemePreference.light);
    expect(controller.state.revision, 5);
  });

  test(
    'a refused write reverts the selection and states the failure',
    () async {
      final repository = _FakeThemeRepository(failWrites: true);
      final controller = ThemePreferenceController(repository);
      addTearDown(controller.dispose);
      await controller.refresh();

      await controller.select(ThemePreference.light);

      expect(controller.state.preference, ThemePreference.dark);
      expect(controller.state.failed, isTrue);
    },
  );

  test('OLED wears the dark mode and never rides the host union', () {
    expect(ThemePreference.oled.themeMode, ThemeMode.dark);
    expect(ThemePreference.oled.hostStored, isFalse);
    // The host value `oled` is not a member of the reference
    // `THEME_PREFERENCES` union, so a stray one leaves the default standing.
    expect(ThemePreference.fromStored('oled'), isNull);
    for (final preference in <ThemePreference>[
      ThemePreference.light,
      ThemePreference.dark,
      ThemePreference.system,
    ]) {
      expect(ThemePreference.fromStored(preference.wireName), preference);
    }
  });

  test('an unset flag leaves OLED off and the key absent', () async {
    final store = await _loadStore(File('${_tempDir().path}/local_state.json'));
    final controller = OledAppearanceController(store);
    addTearDown(controller.dispose);

    expect(controller.state, isFalse);
    expect(store.read(kOledAppearanceKey), isNull);
  });

  test('the OLED flag round-trips through the store', () async {
    final File file = File('${_tempDir().path}/local_state.json');

    final store = await _loadStore(file);
    final controller = OledAppearanceController(store);
    addTearDown(controller.dispose);
    expect(controller.state, isFalse);

    await controller.select(true);
    expect(controller.state, isTrue);
    expect(store.read(kOledAppearanceKey), isTrue);

    // A fresh store over the same document restores the choice: what launch
    // reads back is what the selection wrote.
    final restored = OledAppearanceController(await _loadStore(file));
    addTearDown(restored.dispose);
    expect(restored.state, isTrue);

    // Turning it off deletes the key rather than storing a `false`, so the
    // pre-OLED default stands again.
    await restored.select(false);
    final LocalStateStore cleared = await _loadStore(file);
    expect(cleared.read(kOledAppearanceKey), isNull);
    final off = OledAppearanceController(cleared);
    addTearDown(off.dispose);
    expect(off.state, isFalse);
  });

  testWidgets('the row renders the four seats and writes the tap', (
    tester,
  ) async {
    final store = _widgetStore();
    final repository = _FakeThemeRepository();
    final controller = ThemePreferenceController(repository);
    addTearDown(controller.dispose);
    await controller.refresh();

    await _pumpRow(tester, controller, store: store);

    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('OLED'), findsOneWidget);
    expect(find.text('System'), findsOneWidget);

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();

    expect(repository.writes, <(String, String, String, int?)>[
      (kThemeSettingsNamespace, kThemePreferenceField, '"light"', 4),
    ]);
    expect(controller.state.preference, ThemePreference.light);
  });

  testWidgets('the OLED seat persists locally and leaves the host alone', (
    tester,
  ) async {
    final store = _widgetStore();
    final repository = _FakeThemeRepository(preference: 'system');
    final controller = ThemePreferenceController(repository);
    addTearDown(controller.dispose);
    await controller.refresh();

    await _pumpRow(tester, controller, store: store);

    await tester.tap(find.text('OLED'));
    await tester.pumpAndSettle();

    expect(store.read(kOledAppearanceKey), isTrue);
    expect(repository.writes, isEmpty);

    // A host seat clears the flag and writes the host preference.
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(store.read(kOledAppearanceKey), isNull);
    expect(repository.writes, <(String, String, String, int?)>[
      (kThemeSettingsNamespace, kThemePreferenceField, '"dark"', 4),
    ]);
    expect(controller.state.preference, ThemePreference.dark);
  });

  testWidgets('an unexposed namespace states it instead of a control', (
    tester,
  ) async {
    final store = _widgetStore();
    final repository = _FakeThemeRepository(namespacePresent: false);
    final controller = ThemePreferenceController(repository);
    addTearDown(controller.dispose);
    await controller.refresh();

    await _pumpRow(tester, controller, store: store);

    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Host theme settings are unavailable.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Light'), findsNothing);
    expect(find.text('OLED'), findsNothing);
  });

  testWidgets('an unavailable device-local store disables only the OLED seat', (
    tester,
  ) async {
    // No store override: path_provider has no plugin, so the device-local
    // controller never resolves. The host seats must keep working.
    final repository = _FakeThemeRepository();
    final controller = ThemePreferenceController(repository);
    addTearDown(controller.dispose);
    await controller.refresh();

    await _pumpRow(tester, controller);

    // The OLED seat states that its store is missing; the host seats stay live.
    final SegmentedButton<ThemePreference> selector = tester
        .widget<SegmentedButton<ThemePreference>>(
          find.byType(SegmentedButton<ThemePreference>),
        );
    expect(
      selector.segments
          .firstWhere((s) => s.value == ThemePreference.oled)
          .enabled,
      isFalse,
    );
    expect(
      selector.segments
          .firstWhere((s) => s.value == ThemePreference.light)
          .enabled,
      isTrue,
    );

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(repository.writes, <(String, String, String, int?)>[
      (kThemeSettingsNamespace, kThemePreferenceField, '"light"', 4),
    ]);
    expect(controller.state.preference, ThemePreference.light);
  });

  testWidgets('the OLED seat applies the pure-black theme', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = _widgetStore();
    // The host says `system`, and the test device is light: an untouched
    // device must keep the previous default, not the OLED appearance.
    final repository = _FakeThemeRepository(preference: 'system');
    final controller = ThemePreferenceController(repository);
    addTearDown(controller.dispose);
    await controller.refresh();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeBackendIdProvider.overrideWith(
            (ref) => Stream<String>.value('b1'),
          ),
          themePreferenceControllerProvider('b1').overrideWithValue(controller),
          localStateStoreProvider.overrideWith((ref) async => store),
        ],
        child: const _AppearanceHarness(),
      ),
    );
    await tester.pumpAndSettle();

    expect(_resolvedScheme!.brightness, Brightness.light);

    await tester.tap(find.text('OLED'));
    await tester.pumpAndSettle();

    // The selection reached the app: dark mode, and the theme's own surface
    // role is true black.
    expect(_resolvedScheme!.brightness, Brightness.dark);
    expect(_resolvedScheme!.surface.computeLuminance(), 0.0);
    expect(_resolvedScheme!.surface, DshTheme.oled().colorScheme.surface);
  });
}
