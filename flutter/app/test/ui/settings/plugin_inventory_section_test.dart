/// Plugin inventory section tests — the read-only Settings catalog over
/// `pluginInventory/list`.
///
/// Every case drives the real [PluginInventoryController] through the
/// `chatRepositoryProvider` seam, so the states under test are the ones a
/// host read produces.
library;

import 'dart:async';

import 'package:app/di/providers.dart';
import 'package:app/ui/settings/plugin_inventory_section.dart';
import 'package:app/ui/settings/settings_backend_scope.dart';
import 'package:app/ui/theme/theme.dart';
import 'package:domain/model/plugin_inventory.dart';
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

/// The repository seam the settings tests use: answer
/// [listPluginInventory] and refuse every other verb.
class _FakePluginInventoryRepository implements ChatRepository {
  _FakePluginInventoryRepository(this.onList);

  Future<PluginInventorySnapshot> Function() onList;
  int calls = 0;

  @override
  Future<PluginInventorySnapshot> listPluginInventory() {
    calls += 1;
    return onList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}

const PluginInventorySnapshot _entries = PluginInventorySnapshot(
  entries: <PluginInventoryEntry>[
    PluginInventoryEntry(
      entryId: 'core/tool-bash',
      moduleName: '@deepseek-ai/dsh-tool-bash',
      enabled: true,
      fiberPhase: PluginFiberPhase.active,
    ),
    PluginInventoryEntry(
      entryId: 'include:core/tool-web',
      moduleName: '@deepseek-ai/dsh-tool-web',
      enabled: false,
    ),
    PluginInventoryEntry(
      entryId: 'core/broken-plugin',
      moduleName: '@deepseek-ai/dsh-broken',
      enabled: true,
      fiberPhase: PluginFiberPhase.failed,
    ),
  ],
);

const PluginInventorySnapshot _presets = PluginInventorySnapshot(
  entries: <PluginInventoryEntry>[],
  agentPresets: <AgentPresetPluginGroup>[
    AgentPresetPluginGroup(
      id: 'standard',
      trust: 'system',
      name: 'Standard',
      isDefault: true,
      rows: <AgentPresetPluginRow>[
        AgentPresetPluginRow(
          entryId: 'preset/bash',
          moduleName: '@deepseek-ai/dsh-tool-bash',
          enabled: PresetRowEnablement.enabled,
          fiberPhase: PluginFiberPhase.active,
        ),
        AgentPresetPluginRow(
          entryId: 'preset/web',
          moduleName: '@deepseek-ai/dsh-tool-web',
          enabled: PresetRowEnablement.conditional,
          condition: 'process.env.CI',
        ),
        AgentPresetPluginRow(
          entryId: 'preset/git',
          moduleName: '@deepseek-ai/dsh-tool-git',
          enabled: PresetRowEnablement.disabled,
        ),
      ],
    ),
    AgentPresetPluginGroup(
      id: 'code',
      trust: 'system',
      name: 'Code',
      isDefault: false,
      rows: <AgentPresetPluginRow>[
        AgentPresetPluginRow(
          entryId: 'preset/code-git',
          moduleName: '@deepseek-ai/dsh-tool-code-git',
          enabled: PresetRowEnablement.enabled,
        ),
      ],
    ),
  ],
);

_FakePluginInventoryRepository _repository(PluginInventorySnapshot snapshot) =>
    _FakePluginInventoryRepository(() async => snapshot);

Future<void> _pump(
  WidgetTester tester,
  ChatRepository repository, {
  ThemeData? theme,
  Locale? locale,
  bool settle = true,
}) async {
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
        theme: theme,
        locale: locale,
        home: const Scaffold(
          body: SingleChildScrollView(child: SettingsPluginInventorySection()),
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

void main() {
  setUp(() => ErrorLogCollector.instance.clear());

  testWidgets('renders entries with enablement tags and a failed marker', (
    WidgetTester tester,
  ) async {
    await _pump(tester, _repository(_entries));

    // Module short names are the card titles; the entry id is the secondary
    // detail, with the composition-only `include:` marker dropped.
    expect(find.text('tool-bash'), findsOneWidget);
    expect(find.text('core/tool-bash'), findsOneWidget);
    expect(find.text('tool-web'), findsOneWidget);
    expect(find.text('core/tool-web'), findsOneWidget);
    expect(find.text('include:core/tool-web'), findsNothing);
    expect(find.text('broken'), findsOneWidget);

    expect(find.text('Enabled'), findsOneWidget);
    expect(find.text('Disabled'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    // The global group states the count and the failed subset.
    expect(find.text('3 plugins'), findsOneWidget);
    expect(find.text('1 failed'), findsOneWidget);

    // The section states its read-only contract.
    expect(
      find.text(
        'Read-only. Enable, disable, and configure plugins on the host.',
      ),
      findsOneWidget,
    );

    // Facts stay behind the disclosure: the full specifier is not built.
    expect(find.text('@deepseek-ai/dsh-broken'), findsNothing);

    await tester.tap(find.text('broken'));
    await tester.pumpAndSettle();
    expect(find.text('@deepseek-ai/dsh-broken'), findsOneWidget);
    expect(find.text('Failed to start'), findsOneWidget);
  });

  testWidgets('distinguishes enabled, conditional, and disabled preset rows', (
    WidgetTester tester,
  ) async {
    await _pump(tester, _repository(_presets));

    expect(find.text('Enabled'), findsOneWidget);
    expect(find.text('Conditional'), findsOneWidget);
    expect(find.text('Disabled'), findsOneWidget);
  });

  testWidgets('preset groups render identity and row enablement', (
    WidgetTester tester,
  ) async {
    await _pump(tester, _repository(_presets));

    // The default preset opens with its composition.
    expect(find.text('Standard'), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
    expect(find.textContaining('Built-in'), findsNWidgets(2));
    expect(find.text('tool-bash'), findsOneWidget);

    // A non-default preset waits collapsed.
    expect(find.text('Code'), findsOneWidget);
    expect(find.text('tool-code-git'), findsNothing);

    await tester.tap(find.text('Code'));
    await tester.pumpAndSettle();
    expect(find.text('tool-code-git'), findsOneWidget);
  });

  testWidgets('the rank colors ride their scheme roles in both themes', (
    WidgetTester tester,
  ) async {
    for (final ThemeData theme in <ThemeData>[
      DshTheme.light(),
      DshTheme.dark(),
    ]) {
      await _pump(tester, _repository(_entries), theme: theme);
      expect(
        tester.widget<Text>(find.text('Failed')).style?.color,
        theme.colorScheme.error,
      );
      expect(
        tester.widget<Text>(find.text('Enabled')).style?.color,
        theme.colorScheme.success,
      );

      await _pump(tester, _repository(_presets), theme: theme);
      expect(
        tester.widget<Text>(find.text('Conditional')).style?.color,
        theme.colorScheme.warning,
      );
      expect(
        tester.widget<Text>(find.text('Disabled')).style?.color,
        theme.colorScheme.onSurfaceVariant,
      );
    }
  });

  testWidgets('search filters by module name and by entry id', (
    WidgetTester tester,
  ) async {
    await _pump(tester, _repository(_entries));

    await tester.enterText(find.byType(TextField), 'web');
    await tester.pump();
    expect(find.text('tool-web'), findsOneWidget);
    expect(find.text('tool-bash'), findsNothing);
    expect(find.text('broken'), findsNothing);

    // The query also matches a stable Loader entry id.
    await tester.enterText(find.byType(TextField), 'broken-plugin');
    await tester.pump();
    expect(find.text('broken'), findsOneWidget);
    expect(find.text('tool-web'), findsNothing);
    expect(find.text('core/broken-plugin'), findsOneWidget);
  });

  testWidgets('a failed read is generic and Retry re-reads', (
    WidgetTester tester,
  ) async {
    final _FakePluginInventoryRepository repository =
        _FakePluginInventoryRepository(() async {
          throw Exception('socket closed: ECONNREFUSED 127.0.0.1:3080');
        });
    await _pump(tester, repository);

    expect(find.text('Plugins are temporarily unavailable.'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Retry'), findsOneWidget);
    // No transport detail reaches the rendered tree.
    expect(find.textContaining('ECONNREFUSED'), findsNothing);
    expect(find.textContaining('socket'), findsNothing);
    expect(repository.calls, 1);

    repository.onList = () async => _entries;
    await tester.tap(find.widgetWithText(OutlinedButton, 'Retry'));
    await tester.pumpAndSettle();
    expect(repository.calls, 2);
    expect(find.text('tool-bash'), findsOneWidget);
    expect(find.text('Plugins are temporarily unavailable.'), findsNothing);
  });

  testWidgets('the failure state localizes', (WidgetTester tester) async {
    await _pump(
      tester,
      _FakePluginInventoryRepository(
        () async => throw Exception('ECONNREFUSED'),
      ),
      locale: const Locale('zh'),
    );

    expect(find.text('暂时无法读取插件。'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '重试'), findsOneWidget);
  });

  testWidgets('the no-match state replaces the catalog', (
    WidgetTester tester,
  ) async {
    await _pump(tester, _repository(_entries));

    await tester.enterText(find.byType(TextField), 'nothing-matches-this');
    await tester.pump();

    expect(find.text('No plugins match this search.'), findsOneWidget);
    expect(find.text('tool-bash'), findsNothing);
    expect(find.text('Enabled'), findsNothing);
  });

  testWidgets('the loading state precedes the snapshot', (
    WidgetTester tester,
  ) async {
    final Completer<PluginInventorySnapshot> pending =
        Completer<PluginInventorySnapshot>();
    await _pump(
      tester,
      _FakePluginInventoryRepository(() => pending.future),
      settle: false,
    );

    expect(find.text('Reading plugins…'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    pending.complete(_entries);
    await tester.pumpAndSettle();
    expect(find.text('Reading plugins…'), findsNothing);
    expect(find.text('tool-bash'), findsOneWidget);
  });

  testWidgets('an empty snapshot states it', (WidgetTester tester) async {
    await _pump(
      tester,
      _repository(
        const PluginInventorySnapshot(entries: <PluginInventoryEntry>[]),
      ),
    );

    expect(find.text('This host exposes no plugins.'), findsOneWidget);
  });
}
