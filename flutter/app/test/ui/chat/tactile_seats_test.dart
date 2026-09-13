/// The tactile-press contract on the composer's most-tapped seats: each
/// carries exactly one [DshTappable], keeps its own component and tap path,
/// and answers a press the same way with motion disabled.
library;

import 'package:app/ui/chat/chat_screen.dart';
import 'package:app/ui/chat/chat_ui_state.dart';
import 'package:app/ui/chat/model_select.dart';
import 'package:app/ui/chat/permission_select.dart';
import 'package:app/ui/chat/voice_input/voice_hold_bar.dart';
import 'package:app/ui/shared/tappable_feedback.dart';
import 'package:domain/model/model_catalog.dart';
import 'package:domain/model/permission_select.dart';
import 'package:domain/model/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';

const SessionSummary _session = SessionSummary(
  id: 's1',
  title: 'Tactile',
  blank: false,
);

const SessionModels _models = SessionModels(
  current: ModelSelection(provider: 'p', model: 'base'),
  routable: true,
  groups: [
    ModelProviderGroup(
      id: 'p',
      name: 'Provider',
      models: [ModelCatalogModel(id: 'base', name: 'Base')],
    ),
  ],
);

const PermissionSelect _permissions = PermissionSelect(
  currentValue: 'workspace-write',
  options: [
    PermissionPresetOption(
      value: 'workspace-write',
      name: 'Workspace write',
      description: 'Writes inside the workspace',
    ),
  ],
);

/// The send/stop seat inside the composer's tooltip.
Finder _sendFab() => find.descendant(
  of: find.byTooltip('Send'),
  matching: find.byType(FloatingActionButton),
);

/// The wrapper around [seat] when the seat builds the wrapper itself.
Finder _wraps(Finder seat) =>
    find.descendant(of: seat, matching: find.byType(DshTappable));

/// The wrapper around [seat] when the wrapping call site is outside it.
Finder _wrappedBy(Finder seat) =>
    find.ancestor(of: seat, matching: find.byType(DshTappable));

Finder _scaleIn(Finder tappable) =>
    find.descendant(of: tappable, matching: find.byType(ScaleTransition));

Future<void> _pump(
  WidgetTester tester,
  List<ChatAction> actions, {
  String? draft,
  bool reducedMotion = false,
}) async {
  tester.view.physicalSize = const Size(800, 1280);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  Widget screen() => ChatScreen(
    uiState: const ChatUiState(
      sessions: [_session],
      selectedSessionId: 's1',
      models: _models,
      permissions: _permissions,
    ),
    onAction: actions.add,
  );

  await tester.pumpWidget(
    ProviderScope(
      child: l10nApp(
        home: reducedMotion
            ? Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(disableAnimations: true),
                  child: screen(),
                ),
              )
            : screen(),
      ),
    ),
  );
  await tester.pump();
  if (draft case final text?) {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
  }
}

void main() {
  testWidgets('every primary composer seat carries one DshTappable', (
    tester,
  ) async {
    await _pump(tester, <ChatAction>[]);

    // The filled primary seat keeps its FloatingActionButton identity and
    // gains the wrapper outside it.
    expect(_wrappedBy(_sendFab()), findsOneWidget);
    // The +, mode, model and permission seats build the wrapper themselves.
    expect(
      find.ancestor(
        of: find.byIcon(Icons.add),
        matching: find.byType(DshTappable),
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.byIcon(Icons.mic_none),
        matching: find.byType(DshTappable),
      ),
      findsOneWidget,
    );
    expect(_wraps(find.byType(ModelSelect)), findsOneWidget);
    expect(_wraps(find.byType(PermissionSelectChip)), findsOneWidget);
  });

  testWidgets('one press costs one haptic: the hold bar keeps its impacts', (
    tester,
  ) async {
    await _pump(tester, <ChatAction>[]);

    DshTappable wrapOf(Finder seat) => tester.widget<DshTappable>(_wraps(seat));
    // The mode seat is a plain switch, so it clicks like its neighbours; the
    // hold bar produces its own phase impacts, so the wrapper stays silent.
    expect(
      tester
          .widget<DshTappable>(
            find.ancestor(
              of: find.byIcon(Icons.mic_none),
              matching: find.byType(DshTappable),
            ),
          )
          .enableHaptic,
      isTrue,
    );
    expect(wrapOf(find.byType(ModelSelect)).enableHaptic, isTrue);
    expect(wrapOf(find.byType(PermissionSelectChip)).enableHaptic, isTrue);
    expect(
      tester.widget<DshTappable>(_wrappedBy(_sendFab())).enableHaptic,
      isTrue,
    );

    await tester.tap(find.byIcon(Icons.mic_none));
    await tester.pump();
    expect(wrapOf(find.byType(VoiceHoldBar)).enableHaptic, isFalse);
  });

  testWidgets('one tap on the send seat dispatches exactly one prompt', (
    tester,
  ) async {
    final actions = <ChatAction>[];
    await _pump(tester, actions, draft: 'hello');

    await tester.tap(find.byTooltip('Send'));
    await tester.pump();

    expect(actions.whereType<SendPrompt>(), hasLength(1));
  });

  testWidgets('an empty draft leaves the send seat disabled and still', (
    tester,
  ) async {
    final actions = <ChatAction>[];
    await _pump(tester, actions);

    final wrap = _wrappedBy(_sendFab());
    expect(tester.widget<DshTappable>(wrap).enabled, isFalse);
    // Disabled passes the FAB through unwrapped, so no press can animate it.
    expect(_scaleIn(wrap), findsNothing);

    await tester.tap(find.byTooltip('Send'), warnIfMissed: false);
    await tester.pump();
    expect(actions.whereType<SendPrompt>(), isEmpty);
  });

  testWidgets('reduced motion leaves the send seat usable and still', (
    tester,
  ) async {
    final actions = <ChatAction>[];
    await _pump(tester, actions, draft: 'hello', reducedMotion: true);

    expect(_scaleIn(_wrappedBy(_sendFab())), findsNothing);

    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    expect(actions.whereType<SendPrompt>(), hasLength(1));
  });
}
