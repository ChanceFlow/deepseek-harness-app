/// Access-mode chip tests — current-value label, the preset list the sheet
/// offers, safe switching through the `/permission` command, the full-access
/// risk gate, and the read-only `custom` state, driven through the real
/// ChatScreen entry path.
///
/// The options come from the deployment's process catalog
/// (`permissionPresets/catalog`): the pin's `permissions` projection is
/// `{currentValue}` alone (`interaction/permission-presets/src/index.ts:243`),
/// so a fixture that puts the option list in the projection is exactly the
/// contract that produced a bare card.
library;

import 'dart:async';

import 'package:domain/model/permission_select.dart';
import 'package:domain/model/prompt.dart';
import 'package:domain/model/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/ui/chat/chat_screen.dart';
import 'package:app/ui/chat/chat_ui_state.dart';
import 'package:app/ui/chat/permission_select.dart';

import '../../l10n_app.dart';

const SessionSummary _session = SessionSummary(
  id: 's1',
  title: 'Permissions',
  blank: false,
);

/// Options mirror the host's default preset table plus one configured
/// extra (interaction/permission-presets/src/index.ts `static Config`
/// presets dict).
const PermissionSelect _permissions = PermissionSelect(
  options: [
    PermissionPresetOption(
      value: 'read-only',
      name: 'read-only',
      description: 'Read files; every change needs approval.',
    ),
    PermissionPresetOption(
      value: 'workspace-write',
      name: 'workspace-write',
      description:
          'Write inside the workspace and permitted temporary '
          'directories; wider retries require approval.',
    ),
    PermissionPresetOption(
      value: 'danger-full-access',
      name: 'danger-full-access',
      description: 'Full file access without approval prompts.',
    ),
  ],
  currentValue: 'workspace-write',
);

/// The projection payload the Host actually publishes: `currentValue` and
/// nothing else, so this seat has no options of its own to render.
const PermissionSelect _projectionOnly = PermissionSelect(
  options: <PermissionPresetOption>[],
  currentValue: 'workspace-write',
);

/// The deployment's process catalog, the list the sheet offers.
const PermissionPresetCatalog _catalog = PermissionPresetCatalog(
  options: <PermissionPresetOption>[
    PermissionPresetOption(
      value: 'read-only',
      name: 'read-only',
      description: 'Read files; every change needs approval.',
    ),
    PermissionPresetOption(
      value: 'workspace-write',
      name: 'workspace-write',
      description: 'Write inside the workspace; wider retries need approval.',
    ),
    PermissionPresetOption(
      value: 'danger-full-access',
      name: 'danger-full-access',
      description: 'Full file access without approval prompts.',
    ),
  ],
  defaultOptions: <PermissionPresetOption>[
    PermissionPresetOption(value: 'workspace-write', name: 'workspace-write'),
  ],
  defaultPreset: 'workspace-write',
);

Future<void> _pump(
  WidgetTester tester,
  ChatUiState uiState,
  List<ChatAction> actions, {
  PermissionCatalogLoader? loadCatalog,
}) {
  // Wide enough that the dock clears the composer's 460dp label cut: these
  // tests read the chip's label, and the phone-width collapsed form is pinned
  // in chat_screen_test.dart §composer dock bands.
  tester.view.physicalSize = const Size(1000, 1280);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  return tester.pumpWidget(
    ProviderScope(
      child: l10nApp(
        home: ChatScreen(
          uiState: uiState,
          onAction: actions.add,
          loadPermissionCatalog: loadCatalog,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('hidden without a permission projection', (tester) async {
    await _pump(
      tester,
      const ChatUiState(sessions: [_session], selectedSessionId: 's1'),
      [],
    );
    expect(find.byType(PermissionSelectChip), findsNothing);
  });

  testWidgets('shows the title-cased current preset label', (tester) async {
    await _pump(
      tester,
      const ChatUiState(
        sessions: [_session],
        selectedSessionId: 's1',
        permissions: _permissions,
      ),
      [],
    );
    expect(find.byType(PermissionSelectChip), findsOneWidget);
    expect(find.text('Workspace Write'), findsOneWidget);
  });

  testWidgets('picking a safe preset submits the permission command', (
    tester,
  ) async {
    final actions = <ChatAction>[];
    await _pump(
      tester,
      const ChatUiState(
        sessions: [_session],
        selectedSessionId: 's1',
        permissions: _permissions,
      ),
      actions,
    );

    await tester.tap(find.byType(PermissionSelectChip));
    await tester.pumpAndSettle();
    expect(find.text('Access mode'), findsOneWidget);
    // Exactly the current row carries the check mark.
    expect(find.byIcon(Icons.check), findsOneWidget);

    await tester.tap(find.text('Read Only'));
    await tester.pumpAndSettle();
    expect(
      actions,
      contains(
        const SendPrompt('/permission read-only', mode: PromptMode.queue),
      ),
    );
  });

  testWidgets('full access passes the acknowledgement gate', (tester) async {
    final actions = <ChatAction>[];
    await _pump(
      tester,
      const ChatUiState(
        sessions: [_session],
        selectedSessionId: 's1',
        permissions: _permissions,
      ),
      actions,
    );

    await tester.tap(find.byType(PermissionSelectChip));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Full access'));
    await tester.pumpAndSettle();

    expect(find.text('Enable Full access?'), findsOneWidget);
    // The enable button stays inert until the box is ticked.
    final enable = find.ancestor(
      of: find.text('Enable Full access'),
      matching: find.byType(FilledButton),
    );
    expect(tester.widget<FilledButton>(enable).enabled, isFalse);

    await tester.tap(find.text('I understand the risks and want to continue'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(enable).enabled, isTrue);

    await tester.tap(enable);
    await tester.pumpAndSettle();
    expect(
      actions,
      contains(
        const SendPrompt(
          '/permission danger-full-access',
          mode: PromptMode.queue,
        ),
      ),
    );
  });

  testWidgets('cancelling the risk dialog submits nothing', (tester) async {
    final actions = <ChatAction>[];
    await _pump(
      tester,
      const ChatUiState(
        sessions: [_session],
        selectedSessionId: 's1',
        permissions: _permissions,
      ),
      actions,
    );

    await tester.tap(find.byType(PermissionSelectChip));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Full access'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Enable Full access?'), findsNothing);
    expect(actions.whereType<SendPrompt>(), isEmpty);
  });

  testWidgets('a custom effective value renders the chip read-only', (
    tester,
  ) async {
    final actions = <ChatAction>[];
    await _pump(
      tester,
      const ChatUiState(
        sessions: [_session],
        selectedSessionId: 's1',
        permissions: PermissionSelect(
          options: [
            PermissionPresetOption(
              value: 'workspace-write',
              name: 'workspace-write',
            ),
            PermissionPresetOption(value: 'custom', name: 'custom'),
          ],
          currentValue: 'custom',
        ),
      ),
      actions,
    );

    expect(find.text('Custom'), findsOneWidget);
    await tester.tap(find.byType(PermissionSelectChip));
    await tester.pumpAndSettle();
    // No switch target: the roster sheet never opens.
    expect(find.text('Access mode'), findsNothing);
    expect(actions, isEmpty);
  });

  testWidgets('the sheet lists the catalog presets the projection omits', (
    tester,
  ) async {
    final actions = <ChatAction>[];
    await _pump(
      tester,
      const ChatUiState(
        sessions: [_session],
        selectedSessionId: 's1',
        permissions: _projectionOnly,
      ),
      actions,
      loadCatalog: () async => _catalog,
    );

    await tester.tap(find.byType(PermissionSelectChip));
    await tester.pumpAndSettle();

    // The photographed defect: the card showed its title over nothing. The
    // options are the catalog's, and the current one is marked. The chip also
    // renders the current label, so the row assertions read inside the card.
    final Finder card = find.byKey(const ValueKey<String>('menu-sheet-card'));
    Finder inCard(Finder matching) =>
        find.descendant(of: card, matching: matching);
    expect(inCard(find.text('Read Only')), findsOneWidget);
    expect(inCard(find.text('Workspace Write')), findsOneWidget);
    expect(inCard(find.text('Full access')), findsOneWidget);
    expect(inCard(find.byIcon(Icons.check)), findsOneWidget);
    expect(inCard(find.text('Access mode')), findsOneWidget);
  });

  testWidgets('an in-flight catalog read states that it is loading', (
    tester,
  ) async {
    final actions = <ChatAction>[];
    await _pump(
      tester,
      const ChatUiState(
        sessions: [_session],
        selectedSessionId: 's1',
        permissions: _projectionOnly,
      ),
      actions,
      loadCatalog: () => Completer<PermissionPresetCatalog>().future,
    );

    await tester.tap(find.byType(PermissionSelectChip));
    await tester.pump();
    expect(find.text('Reading the access modes…'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('a failed catalog read says so and retries', (tester) async {
    final actions = <ChatAction>[];
    var attempts = 0;
    await _pump(
      tester,
      const ChatUiState(
        sessions: [_session],
        selectedSessionId: 's1',
        permissions: _projectionOnly,
      ),
      actions,
      loadCatalog: () async {
        attempts += 1;
        if (attempts == 1) throw StateError('catalog unavailable');
        return _catalog;
      },
    );

    await tester.tap(find.byType(PermissionSelectChip));
    await tester.pumpAndSettle();
    expect(find.text('Could not read the access modes.'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Read Only'), findsOneWidget);
  });

  testWidgets('an empty catalog says the deployment composes none', (
    tester,
  ) async {
    final actions = <ChatAction>[];
    await _pump(
      tester,
      const ChatUiState(
        sessions: [_session],
        selectedSessionId: 's1',
        permissions: _projectionOnly,
      ),
      actions,
      loadCatalog: () async => const PermissionPresetCatalog(
        options: <PermissionPresetOption>[],
        defaultOptions: <PermissionPresetOption>[],
        defaultPreset: 'read-only',
      ),
    );

    await tester.tap(find.byType(PermissionSelectChip));
    await tester.pumpAndSettle();
    expect(
      find.text('This deployment composes no access modes to switch between.'),
      findsOneWidget,
    );
  });

  testWidgets('the card explains what the choice governs', (tester) async {
    final actions = <ChatAction>[];
    await _pump(
      tester,
      const ChatUiState(
        sessions: [_session],
        selectedSessionId: 's1',
        permissions: _projectionOnly,
      ),
      actions,
      loadCatalog: () async => _catalog,
    );

    await tester.tap(find.byType(PermissionSelectChip));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('What the agent may do in this conversation'),
      findsOneWidget,
    );
  });

  test('kebab names title-case; non-kebab names pass through', () {
    expect(permissionDisplayName('workspace-write'), 'Workspace Write');
    expect(permissionDisplayName(' danger '), ' danger ');
    expect(permissionDisplayName('ReadOnly'), 'ReadOnly');
  });
}
