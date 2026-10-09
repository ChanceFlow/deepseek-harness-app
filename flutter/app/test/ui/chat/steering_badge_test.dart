/// Steering badge tests: a user row a durable `agent/inbox/spliced` claimed
/// mid-run is named, so a reader can tell it from an ordinary ask.
library;

import 'package:app/config.dart';
import 'package:app/di/providers.dart';
import 'package:app/ui/chat/chat_screen.dart';
import 'package:app/ui/chat/chat_ui_state.dart';
import 'package:domain/model/chat_message.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';

/// The bare transport: an empty successful reply.
class _FakeRpc implements DshRpcClient {
  @override
  Future<RpcResult> call(
    String endpoint,
    String method,
    JsonMap payload, {
    Duration? timeout,
  }) async => RpcResult(ok: true, value: <String, Object?>{});

  @override
  Future<void> respond(String rpcId, RpcResult result) async {}
}

/// A socket that never speaks.
class _NeverSocket implements DshEventSocket {
  @override
  Stream<ServerRequest> connect(String path, {void Function()? onOpen}) =>
      const Stream<ServerRequest>.empty();
}

TimelineMessage _user(
  String id,
  String text, {
  bool steering = false,
  int? seq,
}) => TimelineMessage(
  ChatMessage(
    id: id,
    sessionId: 's1',
    role: MessageRole.user,
    text: text,
    createdAtEpochMs: 1700000000000,
    seq: seq,
  ),
  steering: steering,
);

/// The answer row that closed a step, with the step's two logged bounds.
TimelineMessage _assistant(
  String id,
  String text, {
  int? stepStartedAtEpochMs,
  int? stepEndedAtEpochMs,
  int? seq,
}) => TimelineMessage(
  ChatMessage(
    id: id,
    sessionId: 's1',
    role: MessageRole.assistant,
    text: text,
    createdAtEpochMs: 1700000000000,
    seq: seq,
  ),
  stepStartedAtEpochMs: stepStartedAtEpochMs,
  stepEndedAtEpochMs: stepEndedAtEpochMs,
);

Future<void> _pump(WidgetTester tester, List<TimelineItem> timeline) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dshRpcClientProvider(Uri.parse(kDshBaseUrl))
            .overrideWithValue(_FakeRpc()),
        dshEventSocketProvider(Uri.parse(kDshBaseUrl))
            .overrideWithValue(_NeverSocket()),
      ],
      child: l10nApp(
        home: ChatScreen(
          uiState: ChatUiState(
            sessions: const <SessionSummary>[
              SessionSummary(
                id: 's1',
                title: 'steering',
                blank: false,
                updatedAtEpochMs: 1700000000000,
              ),
            ],
            selectedSessionId: 's1',
            timeline: timeline,
          ),
          onAction: (_) {},
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('only the spliced row carries the badge', (tester) async {
    await _pump(tester, <TimelineItem>[
      _user('u1', 'Start on the parser.', seq: 1),
      _user('u2', 'Stop; use the other branch.', steering: true, seq: 3),
    ]);

    // Both rows render as reader words; only the admitted one is named.
    expect(find.text('Start on the parser.'), findsOneWidget);
    expect(find.text('Stop; use the other branch.'), findsOneWidget);
    expect(find.text('Steering'), findsOneWidget);
  });

  testWidgets('an ordinary ask carries no badge', (tester) async {
    await _pump(tester, <TimelineItem>[
      _user('u1', 'Start on the parser.', seq: 1),
    ]);

    expect(find.text('Start on the parser.'), findsOneWidget);
    expect(find.text('Steering'), findsNothing);
  });

  testWidgets('a step names its own range beside the answer', (tester) async {
    await _pump(tester, <TimelineItem>[
      _assistant(
        'a1',
        'Re-ran the parser.',
        stepStartedAtEpochMs: 1000,
        stepEndedAtEpochMs: 6000,
        seq: 5,
      ),
    ]);

    expect(find.text('Re-ran the parser.'), findsOneWidget);
    // `step/end − step/start`, in the turn label's own units.
    expect(find.text('5s'), findsOneWidget);
  });

  testWidgets('a step whose range fell outside the window shows none', (
    tester,
  ) async {
    await _pump(tester, <TimelineItem>[
      _assistant('a1', 'Re-ran the parser.', stepEndedAtEpochMs: 6000, seq: 5),
    ]);

    expect(find.text('Re-ran the parser.'), findsOneWidget);
    expect(find.text('5s'), findsNothing);
  });
}
