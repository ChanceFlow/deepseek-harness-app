/// Default-permission-preset page: the deployment catalog's `defaultOptions`
/// drive the rows, the settings namespace's `defaultPreset` is the selection,
/// and one pick writes that single key with the described revision.
library;

import 'package:app/di/providers.dart';
import 'package:app/ui/settings/permission_defaults.dart';
import 'package:app/ui/settings/settings_backend_scope.dart';
import 'package:app/ui/settings/settings_chrome.dart';
import 'package:app/ui/settings/settings_ui_state.dart';
import 'package:domain/model/permission_select.dart';
import 'package:domain/model/repository_failure.dart';
import 'package:domain/model/settings.dart';
import 'package:domain/repository/chat_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';

const String _backendId = 'default';

class _FixedScope extends SettingsBackendScope {
  @override
  String build() => _backendId;
}

class _FakeRepository extends Fake implements ChatRepository {
  _FakeRepository(this.catalog);

  /// The catalog the host answers with; throwing stands for a host that
  /// composes no permission service.
  final Future<PermissionPresetCatalog> Function() catalog;

  @override
  Future<PermissionPresetCatalog> loadPermissionPresetCatalog() => catalog();
}

PermissionPresetCatalog _catalog() => const PermissionPresetCatalog(
  options: <PermissionPresetOption>[
    PermissionPresetOption(
      value: 'workspace-write',
      name: 'Workspace write',
      description: 'Write inside the workspace.',
    ),
    PermissionPresetOption(
      value: 'danger-full-access',
      name: 'Full access',
      description: 'Full file access without approval prompts.',
    ),
  ],
  defaultOptions: <PermissionPresetOption>[
    PermissionPresetOption(
      value: 'workspace-write',
      name: 'Workspace write',
      description: 'Write inside the workspace.',
    ),
    PermissionPresetOption(
      value: 'danger-full-access',
      name: 'Full access',
      description: 'Full file access without approval prompts.',
    ),
  ],
  defaultPreset: 'danger-full-access',
);

SettingsChannel _channel({
  bool writable = true,
  String? defaultPreset = 'danger-full-access',
  List<SettingsAction>? actions,
}) => SettingsChannel(
  state: SettingsUiState(
    snapshot: SettingsSnapshot(
      writable: writable,
      hasDocument: true,
      credentialRefs: const <String>[],
      namespaces: <SettingsNamespace>[
        SettingsNamespace(
          ns: kPermissionSettingsNamespace,
          applies: SettingsApplies.live,
          revision: 7,
          hasUserLayer: true,
          secretCount: 0,
          schema: SettingsSchema.empty,
          value: defaultPreset == null
              ? const <String, Object?>{}
              : <String, Object?>{kPermissionDefaultKey: defaultPreset},
        ),
      ],
    ),
  ),
  onAction: (action) => actions?.add(action),
);

Future<void> _pump(
  WidgetTester tester, {
  required ChatRepository repository,
  required SettingsChannel channel,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chatRepositoryProvider(_backendId).overrideWithValue(repository),
        settingsBackendScopeProvider.overrideWith(_FixedScope.new),
      ],
      child: l10nApp(
        home: Scaffold(body: SettingsPermissionDefaultsPage(channel: channel)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

PermissionPresetCatalog _catalogWithAuto() => const PermissionPresetCatalog(
  options: <PermissionPresetOption>[
    PermissionPresetOption(
      value: 'workspace-write',
      name: 'Workspace write',
      description: 'Write inside the workspace.',
    ),
  ],
  defaultOptions: <PermissionPresetOption>[
    PermissionPresetOption(
      value: 'workspace-write',
      name: 'Workspace write',
      description: 'Write inside the workspace.',
    ),
    PermissionPresetOption(
      value: 'auto',
      name: 'Auto',
      description: "The host's own sentence.",
    ),
  ],
  defaultPreset: 'workspace-write',
);

void main() {
  testWidgets('renders the catalog defaults and marks the effective one', (
    tester,
  ) async {
    await _pump(
      tester,
      repository: _FakeRepository(() async => _catalog()),
      channel: _channel(),
    );

    expect(find.text('Workspace write'), findsOneWidget);
    expect(find.text('Write inside the workspace.'), findsOneWidget);
    expect(find.text('Full access'), findsOneWidget);
    expect(
      tester
          .widget<RadioListTile<String>>(
            find.widgetWithText(RadioListTile<String>, 'Full access'),
          )
          .value,
      'danger-full-access',
    );
    final group = tester.widget<RadioGroup<String>>(
      find.byType(RadioGroup<String>),
    );
    expect(group.groupValue, 'danger-full-access');
  });

  testWidgets('a pick writes only the default preset key with its revision', (
    tester,
  ) async {
    final actions = <SettingsAction>[];
    await _pump(
      tester,
      repository: _FakeRepository(() async => _catalog()),
      channel: _channel(actions: actions),
    );

    await tester.tap(find.text('Workspace write'));
    await tester.pumpAndSettle();

    final action = actions.single as UpdateSettingAction;
    expect(action.ns, kPermissionSettingsNamespace);
    expect(action.key, kPermissionDefaultKey);
    expect(action.jsonValue, '"workspace-write"');
    expect(action.expectedRevision, 7);
  });

  testWidgets('a namespace value overrides the catalog default', (
    tester,
  ) async {
    await _pump(
      tester,
      repository: _FakeRepository(() async => _catalog()),
      channel: _channel(defaultPreset: 'workspace-write'),
    );

    expect(
      tester
          .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
          .groupValue,
      'workspace-write',
    );
  });

  testWidgets('a host without a catalog states it instead of choosing', (
    tester,
  ) async {
    await _pump(
      tester,
      repository: _FakeRepository(
        () => throw const RepositoryFailure('gateway/not-found', 'no catalog'),
      ),
      channel: _channel(),
    );

    expect(
      find.text(
        'This deployment composes no permission preset catalog, so there is '
        'no default to set.',
      ),
      findsOneWidget,
    );
    expect(find.byType(RadioListTile<String>), findsNothing);
  });

  testWidgets('a read-only document shows no selection and writes nothing', (
    tester,
  ) async {
    final actions = <SettingsAction>[];
    await _pump(
      tester,
      repository: _FakeRepository(() async => _catalog()),
      channel: _channel(writable: false, actions: actions),
    );

    expect(
      tester
          .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
          .groupValue,
      isNull,
    );
    expect(
      find.text('Settings are read-only on this deployment.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Workspace write'));
    await tester.pumpAndSettle();
    expect(actions, isEmpty);
  });

  testWidgets('the auto preset carries the EXP badge and its own sentence', (
    tester,
  ) async {
    await _pump(
      tester,
      repository: _FakeRepository(() async => _catalogWithAuto()),
      channel: _channel(defaultPreset: 'workspace-write'),
    );

    // The pin's `auto.badge` and `auto.description`
    // (`ui-permission-presets/src/client/index.ts:89-91`).
    // The pin's `auto.label` (`index.ts:87`): the row's name is the
    // reference's, not the host's bare value.
    expect(find.text('Auto review'), findsOneWidget);
    expect(find.text('EXP'), findsOneWidget);
    expect(
      find.text(
        'Runs without a sandbox: every native tool call and PTC inner call '
        'is reviewed by the same model before it runs.',
      ),
      findsOneWidget,
    );
    // The host's generic sentence is not what the experimental preset shows.
    expect(find.text("The host's own sentence."), findsNothing);
  });

  testWidgets(
    'choosing auto confirms first and writes only once acknowledged',
    (tester) async {
      final actions = <SettingsAction>[];
      await _pump(
        tester,
        repository: _FakeRepository(() async => _catalogWithAuto()),
        channel: _channel(defaultPreset: 'workspace-write', actions: actions),
      );

      await tester.tap(find.text('Auto review'));
      await tester.pumpAndSettle();

      // The pin's own confirmation block (`index.ts:97-101`), and the enable
      // action is unreachable until the acknowledgement is made.
      expect(find.text('Enable Auto review (experimental)?'), findsOneWidget);
      expect(actions, isEmpty);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Enable Auto review'),
            )
            .onPressed,
        isNull,
      );

      await tester.tap(
        find.text('I understand these risks and want to continue'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enable Auto review'));
      await tester.pumpAndSettle();

      final action = actions.single as UpdateSettingAction;
      expect(action.key, kPermissionDefaultKey);
      expect(action.jsonValue, '"auto"');
      expect(action.expectedRevision, 7);
    },
  );

  testWidgets('cancelling the auto confirmation writes nothing', (
    tester,
  ) async {
    final actions = <SettingsAction>[];
    await _pump(
      tester,
      repository: _FakeRepository(() async => _catalogWithAuto()),
      channel: _channel(defaultPreset: 'workspace-write', actions: actions),
    );

    await tester.tap(find.text('Auto review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(actions, isEmpty);
  });
}
