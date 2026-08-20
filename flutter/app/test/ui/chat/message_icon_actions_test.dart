/// MessageIconActions parity tests — copy chrome and clock side.
library;

import 'package:domain/model/chat_message.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/ui/chat/chat_screen.dart';
import 'package:app/ui/chat/chat_ui_state.dart';
import 'package:app/ui/chat/message_icon_actions.dart';

import '../../l10n_app.dart';

ChatMessage _message({
  MessageRole role = MessageRole.assistant,
  bool streaming = false,
}) {
  return ChatMessage(
    id: role == MessageRole.user ? 'u1' : 'm1',
    sessionId: 's1',
    role: role,
    text: 'copy me',
    streaming: streaming,
    createdAtEpochMs: 1723996800000, // 2024-08-18T16:00:00Z
  );
}

Future<void> _pump(WidgetTester tester, List<TimelineItem> timeline) {
  tester.view.physicalSize = const Size(800, 1280);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  return tester.pumpWidget(
    ProviderScope(
      child: l10nApp(
        home: ChatScreen(
          uiState: ChatUiState(
            sessions: const [
              SessionSummary(id: 's1', title: 'Alpha', blank: false),
            ],
            selectedSessionId: 's1',
            timeline: timeline,
          ),
          onAction: (_) {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('settled messages carry copy + clock actions', (tester) async {
    await _pump(tester, [TimelineMessage(_message())]);
    expect(find.byType(MessageIconActions), findsOneWidget);
    expect(find.byTooltip('Copy'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^\d{2}:\d{2}$')), findsOneWidget);
  });

  testWidgets('streaming messages hide the actions', (tester) async {
    await _pump(tester, [TimelineMessage(_message(streaming: true))]);
    expect(find.byType(MessageIconActions), findsNothing);
  });

  testWidgets('copy swaps to the check chrome then resets', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
    await _pump(tester, [TimelineMessage(_message())]);
    await tester.tap(find.byTooltip('Copy'));
    await tester.pump();
    await tester.pump();
    // The write rides the (mocked) platform channel; allow the roundtrip.
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byTooltip('Copied'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1300));
    expect(find.byTooltip('Copy'), findsOneWidget);
  });

  testWidgets('user rows render actions too (clock first)', (tester) async {
    await _pump(tester, [TimelineMessage(_message(role: MessageRole.user))]);
    final actions = tester.widget<MessageIconActions>(
      find.byType(MessageIconActions),
    );
    expect(actions.clockAtStart, isTrue);
  });
}
