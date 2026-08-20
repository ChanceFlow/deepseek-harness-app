/// Access-mode chip tests — current-value label, safe switching through
/// the `/permission` command, the full-access risk gate, and the
/// read-only `custom` state, driven through the real ChatScreen entry
/// path.
library;

import 'package:domain/model/permission_select.dart';
import 'package:domain/model/prompt.dart';
import 'package:domain/model/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/ui/chat/chat_screen.dart';
import 'package:app/ui/chat/chat_ui_state.dart';
import 'package:app/ui/chat/permission_select.dart';

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

Future<void> _pump(
  WidgetTester tester,
  ChatUiState uiState,
  List<ChatAction> actions,
) {
  tester.view.physicalSize = const Size(800, 1280);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  return tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: ChatScreen(uiState: uiState, onAction: actions.add),
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
      contains(const SendPrompt('/permission read-only', mode: PromptMode.queue)),
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
        const SendPrompt('/permission danger-full-access', mode: PromptMode.queue),
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

  test('kebab names title-case; non-kebab names pass through', () {
    expect(permissionDisplayName('workspace-write'), 'Workspace Write');
    expect(permissionDisplayName(' danger '), ' danger ');
    expect(permissionDisplayName('ReadOnly'), 'ReadOnly');
  });
}
