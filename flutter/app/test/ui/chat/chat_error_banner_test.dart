/// Chat failure strip tests: the localized headline plus the controller's
/// existing retry ([RetrySessions]) and dismiss ([DismissError]) actions,
/// never a raw exception string.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/config.dart';
import 'package:app/di/providers.dart';
import 'package:app/ui/chat/chat_screen.dart';
import 'package:app/ui/chat/chat_ui_state.dart';

import '../../l10n_app.dart';

class _FakeRpc implements DshRpcClient {
  @override
  Future<RpcResult> call(
    String endpoint,
    String method,
    JsonMap payload, {
    Duration? timeout,
  }) async {
    return RpcResult(ok: true, value: <String, Object?>{});
  }

  @override
  Future<void> respond(String rpcId, RpcResult result) async {}
}

class _NeverSocket implements DshEventSocket {
  final StreamController<ServerRequest> _frames =
      StreamController<ServerRequest>.broadcast();

  @override
  Stream<ServerRequest> connect(String path, {void Function()? onOpen}) {
    onOpen?.call();
    return _frames.stream;
  }
}

Future<void> _pumpChat(
  WidgetTester tester,
  ChatUiState uiState,
  List<ChatAction> actions,
) async {
  tester.view.physicalSize = const Size(800, 1280);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dshRpcClientProvider(Uri.parse(kDshBaseUrl))
            .overrideWithValue(_FakeRpc()),
        dshEventSocketProvider(Uri.parse(kDshBaseUrl))
            .overrideWithValue(_NeverSocket()),
      ],
      child: l10nApp(
        home: ChatScreen(uiState: uiState, onAction: actions.add),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('the chat error strip localizes, retries and dismisses', (
    tester,
  ) async {
    final actions = <ChatAction>[];
    await _pumpChat(
      tester,
      const ChatUiState(errorMessage: 'boom detail'),
      actions,
    );

    // A localized headline carries the message; the raw host detail is a
    // secondary line, not the whole surface.
    expect(find.text("That action couldn't be completed."), findsOneWidget);
    expect(find.text('boom detail'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(actions, contains(const RetrySessions()));

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    expect(actions, contains(const DismissError()));
  });

  testWidgets('the session-owned failure keeps its specific copy', (
    tester,
  ) async {
    await _pumpChat(
      tester,
      const ChatUiState(errorMessage: 'SESSION_ALREADY_OWNED'),
      <ChatAction>[],
    );

    expect(
      find.text('This session is currently locked by another process or CLI.'),
      findsOneWidget,
    );
    expect(find.text('SESSION_ALREADY_OWNED'), findsNothing);
  });

  testWidgets('a command failure dismisses without a retry', (tester) async {
    await _pumpChat(
      tester,
      const ChatUiState(commandFailed: true),
      <ChatAction>[],
    );

    expect(find.byTooltip('Dismiss'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });
}
