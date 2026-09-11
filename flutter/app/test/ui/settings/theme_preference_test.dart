/// Appearance preference tests — the host `ui-theme` read/write and the
/// settings row that drives it.
library;

import 'dart:convert';

import 'package:app/di/providers.dart';
import 'package:app/ui/settings/theme_preference.dart';
import 'package:domain/model/settings.dart';
import 'package:domain/repository/chat_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';

class _FakeThemeRepository implements ChatRepository {
  _FakeThemeRepository({this.namespacePresent = true, this.failWrites = false});

  String preference = 'dark';
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

Future<void> _pumpRow(
  WidgetTester tester,
  ThemePreferenceController controller,
) async {
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
      ],
      child: l10nApp(home: const Scaffold(body: ThemePreferenceRow())),
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

  testWidgets('the row renders the three seats and writes the tap', (
    tester,
  ) async {
    final repository = _FakeThemeRepository();
    final controller = ThemePreferenceController(repository);
    addTearDown(controller.dispose);
    await controller.refresh();

    await _pumpRow(tester, controller);

    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('System'), findsOneWidget);

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();

    expect(repository.writes, <(String, String, String, int?)>[
      (kThemeSettingsNamespace, kThemePreferenceField, '"light"', 4),
    ]);
    expect(controller.state.preference, ThemePreference.light);
  });

  testWidgets('an unexposed namespace states it instead of a control', (
    tester,
  ) async {
    final repository = _FakeThemeRepository(namespacePresent: false);
    final controller = ThemePreferenceController(repository);
    addTearDown(controller.dispose);
    await controller.refresh();

    await _pumpRow(tester, controller);

    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Host theme settings are unavailable.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Light'), findsNothing);
  });
}
