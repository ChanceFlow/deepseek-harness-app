/// Fold-level identity guard through the real entry path.
///
/// The row-level tests inject a `ChatUiState` straight into `ChatScreen`, so
/// nothing there observes what a history page arriving after mount, a live
/// append, or the Turn boundary entering the window does to the rows already on
/// screen. This drives the real `ChatRoute()` / `ChatScreen` and asserts what a
/// reader would lose if the list matched by index, if a phase were named by the
/// row above it, or if the fold lived in the element instead of the store.
library;

import 'dart:async';
import 'dart:io';

import 'package:domain/model/chat_message.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/backends/backend_store.dart';
import 'package:app/config.dart';
import 'package:app/di/providers.dart';
import 'package:app/ui/chat/chat_screen.dart';
import 'package:app/ui/chat/chat_ui_state.dart';
import 'package:app/ui/chat/process_disclosure.dart';
import 'package:app/ui/chat/reasoning_row.dart';
import 'package:app/ui/chat/running_status_row.dart';

import '../../l10n_app.dart';
import 'chat_controller_test.dart' show FakeChatRepository;
import 'chat_local_state_fake.dart';

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

ServerRequest _readyFrame() => ServerRequest(
  rpcId: 'remote-events',
  method: 'item',
  payload: <String, Object?>{
    'type': 'ready',
    'clientId': 'client-1',
    'host': <String, Object?>{'home': '/home/tester'},
  },
);

class _QuietSocket implements DshEventSocket {
  final StreamController<ServerRequest> _frames =
      StreamController<ServerRequest>.broadcast();

  @override
  Stream<ServerRequest> connect(String path, {void Function()? onOpen}) {
    onOpen?.call();
    scheduleMicrotask(() => _frames.add(_readyFrame()));
    return _frames.stream;
  }
}

BackendStore _testStore() {
  final Directory dir = Directory.systemTemp.createTempSync(
    'timeline_identity',
  );
  addTearDown(() async {
    for (var i = 0; i < 50; i++) {
      try {
        dir.deleteSync(recursive: true);
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }
  });
  return BackendStore(
    File('${dir.path}/backends.json'),
    seedBaseUrl: kDshBaseUrl,
  );
}

TimelineMessage _message(
  String id,
  String text, {
  MessageRole role = MessageRole.assistant,
}) => TimelineMessage(
  ChatMessage(id: id, sessionId: 's1', role: role, text: text),
);

TimelineToolCall _tool(String id, String name, String result) =>
    TimelineToolCall(
      id: id,
      name: name,
      arguments: '{}',
      result: result,
      status: ToolRunStatus.completed,
    );

/// A running Turn: two settled calls fold into one activity card, and the open
/// boundary gives the tail row its clock.
class _FoldRepository extends FakeChatRepository {
  _FoldRepository()
    : super(
        initialSessions: const <SessionSummary>[
          SessionSummary(
            id: 's1',
            title: 'Fold session',
            blank: false,
            running: true,
          ),
        ],
        initialTimeline: <TimelineItem>[
          TimelineTurnBoundary(
            1,
            startedAtEpochMs: DateTime.now().millisecondsSinceEpoch - 5000,
          ),
          _message('u1', 'go', role: MessageRole.user),
          _tool('t1', 'bash', 'a'),
          _tool('t2', 'read', 'b'),
        ],
      );

  @override
  Future<void> openSession(String sessionId) async {
    // The base fake replaces the timeline with its offline fixture here; this
    // route serves the running Turn it was built with.
    openedSessionIds.add(sessionId);
  }

  void prependHistory(int page, {int size = 8}) {
    timeline.value = <TimelineItem>[
      for (int i = 0; i < size; i++)
        _message('h$page-$i', 'history $page/$i', role: MessageRole.user),
      ...timeline.value,
    ];
  }

  void appendLive(String id) {
    timeline.value = <TimelineItem>[
      ...timeline.value,
      _message(id, 'live $id'),
    ];
  }
}

ChatUiState _screenState(List<TimelineItem> timeline) => ChatUiState(
  sessions: const <SessionSummary>[
    SessionSummary(id: 's1', title: 'Fold session', blank: false),
  ],
  selectedSessionId: 's1',
  timeline: timeline,
);

Future<void> _pumpScreen(
  WidgetTester tester,
  List<TimelineItem> timeline, {
  FakeChatLocalState? localState,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dshRpcClientProvider(Uri.parse(kDshBaseUrl))
            .overrideWithValue(_FakeRpc()),
        dshEventSocketProvider(Uri.parse(kDshBaseUrl))
            .overrideWithValue(_QuietSocket()),
      ],
      child: l10nApp(
        home: ChatScreen(
          uiState: _screenState(timeline),
          onAction: (_) {},
          localState: localState,
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Advances frames without waiting for quiescence: the running row's sweep and
/// the open Turn's shimmer never settle, so `pumpAndSettle` would time out.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Finder _clockText() => find.descendant(
  of: find.byType(RunningStatusRow),
  matching: find.byType(Text),
);

void main() {
  test('a row identity is the item, never its status', () {
    const TimelineToolCall running = TimelineToolCall(
      id: 't1',
      name: 'bash',
      arguments: '{}',
      status: ToolRunStatus.running,
    );
    // Same call, different status: one row, one identity.
    expect(timelineKey(running), timelineKey(_tool('t1', 'bash', 'a')));
    expect(timelineKey(running), 'tool:t1');

    const TimelineMessage streaming = TimelineMessage(
      ChatMessage(
        id: 'm1',
        sessionId: 's1',
        role: MessageRole.assistant,
        text: 'half',
        streaming: true,
      ),
    );
    const TimelineMessage settled = TimelineMessage(
      ChatMessage(
        id: 'm1',
        sessionId: 's1',
        role: MessageRole.assistant,
        text: 'half done',
      ),
    );
    expect(timelineKey(streaming), timelineKey(settled));
    expect(timelineKey(settled), isNot(timelineKey(_tool('t2', 'read', 'b'))));
  });

  testWidgets('an insert folding into a phase head keeps its open fold', (
    tester,
  ) async {
    final TimelineMessage anchor = _message('u1', 'go', role: MessageRole.user);
    final FakeChatLocalState localState = FakeChatLocalState();

    await _pumpScreen(tester, <TimelineItem>[
      anchor,
      _tool('t1', 'bash', 'a'),
      _tool('t2', 'read', 'b'),
    ], localState: localState);
    await tester.tap(find.byType(ProcessGroupHeader));
    await tester.pump();
    expect(find.byType(ToolCallRow), findsNWidgets(2));
    final State<StatefulWidget> state = tester.state<State<StatefulWidget>>(
      find.byType(ActivityGroupRow),
    );

    // An older page whose tail folds into the phase's head.
    await _pumpScreen(tester, <TimelineItem>[
      anchor,
      _tool('t3', 'edit', 'c'),
      _tool('t1', 'bash', 'a'),
      _tool('t2', 'read', 'b'),
    ], localState: localState);
    expect(
      identical(
        tester.state<State<StatefulWidget>>(find.byType(ActivityGroupRow)),
        state,
      ),
      isTrue,
      reason: 'the phase keeps its element when a step folds into its head',
    );
    expect(find.byType(ToolCallRow), findsNWidgets(3));

    // A non-foldable insert above changes nothing either.
    await _pumpScreen(tester, <TimelineItem>[
      _message('older', 'history', role: MessageRole.user),
      anchor,
      _tool('t3', 'edit', 'c'),
      _tool('t1', 'bash', 'a'),
      _tool('t2', 'read', 'b'),
    ], localState: localState);
    expect(
      identical(
        tester.state<State<StatefulWidget>>(find.byType(ActivityGroupRow)),
        state,
      ),
      isTrue,
    );

    // The window was cut mid-phase: the older page's tail is a *message* that
    // lands directly above the phase, so the row above it changes.
    await _pumpScreen(tester, <TimelineItem>[
      _message('mid', 'history tail', role: MessageRole.user),
      anchor,
      _tool('t3', 'edit', 'c'),
      _tool('t1', 'bash', 'a'),
      _tool('t2', 'read', 'b'),
    ], localState: localState);
    expect(
      identical(
        tester.state<State<StatefulWidget>>(find.byType(ActivityGroupRow)),
        state,
      ),
      isTrue,
      reason: 'a message landing above the phase does not re-key it',
    );
    expect(find.byType(ToolCallRow), findsNWidgets(3));

    // The Turn boundary entering the loaded window re-parents the phase into a
    // Turn block: a brand-new element whatever key it carries. The reader's
    // fold survives because it is stored by identity.
    await _pumpScreen(tester, <TimelineItem>[
      TimelineTurnBoundary(
        1,
        startedAtEpochMs: DateTime.now().millisecondsSinceEpoch - 5000,
      ),
      _message('mid', 'history tail', role: MessageRole.user),
      anchor,
      _tool('t3', 'edit', 'c'),
      _tool('t1', 'bash', 'a'),
      _tool('t2', 'read', 'b'),
    ], localState: localState);
    await tester.pump();
    expect(find.byType(ActivityGroupRow), findsOneWidget);
    expect(
      find.byType(ToolCallRow),
      findsNWidgets(3),
      reason: 'the fold the reader opened survives the boundary arriving',
    );
  });

  testWidgets('a stored fold is restored once settled, and only if stored', (
    tester,
  ) async {
    final TimelineMessage anchor = _message('u1', 'go', role: MessageRole.user);
    final List<TimelineItem> timeline = <TimelineItem>[
      anchor,
      _tool('t1', 'bash', 'a'),
      _tool('t2', 'read', 'b'),
    ];
    final FakeChatLocalState store = FakeChatLocalState();
    await store
        .forSession('s1')
        .setExpanded('activity-group:window:phase:0', true);

    await _pumpScreen(tester, timeline, localState: store);
    // The restore is asynchronous but lands within the mount frame here: the
    // stored entry is applied by the time the row has been pumped, so the
    // reader never sees a closed card flash open.
    expect(
      find.byType(ToolCallRow),
      findsNWidgets(2),
      reason: 'a stored fold is restored by the time the row is pumped',
    );
    await tester.pump();

    // A phase with no stored entry keeps its default (closed): an async restore
    // never opens something the reader did not touch. The phase is remounted
    // first (an empty window), so this is a fresh row against an empty store.
    await _pumpScreen(
      tester,
      <TimelineItem>[],
      localState: FakeChatLocalState(),
    );
    await _pumpScreen(tester, timeline, localState: FakeChatLocalState());
    await tester.pump();
    expect(find.byType(ToolCallRow), findsNothing);
  });

  testWidgets('a duplicate identity inside a phase fails loud', (tester) async {
    await _pumpScreen(tester, <TimelineItem>[
      _tool('dup', 'bash', 'a'),
      _tool('dup', 'read', 'b'),
    ]);
    final Object? error = tester.takeException();
    expect(error, isA<FlutterError>());
    expect(
      error.toString(),
      contains('Two transcript rows share the identity'),
    );
  });

  testWidgets('a merged thought renders one member, not two', (tester) async {
    TimelineMessage thought(String id, String reasoning) => TimelineMessage(
      ChatMessage(
        id: id,
        sessionId: 's1',
        role: MessageRole.assistant,
        text: '',
        reasoning: reasoning,
      ),
    );
    await _pumpScreen(tester, <TimelineItem>[
      thought('m1', 'think 1'),
      thought('m2', 'think 2'),
    ]);
    expect(tester.takeException(), isNull);
    // One phase of one member renders as that member: the merged thought is one
    // ReasoningRow, never two rows sharing the newest chunk's id.
    expect(find.byType(ReasoningRow), findsOneWidget);
  });

  testWidgets('a history page keeps the fold and the running row intact', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _FoldRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendStoreProvider.overrideWith((ref) async => _testStore()),
          chatRepositoryProvider('default').overrideWithValue(repository),
          dshRpcClientProvider(Uri.parse(kDshBaseUrl))
              .overrideWithValue(_FakeRpc()),
          dshEventSocketProvider(Uri.parse(kDshBaseUrl))
              .overrideWithValue(_QuietSocket()),
        ],
        child: l10nApp(home: const ChatRoute()),
      ),
    );
    for (var i = 0; i < 30 && find.text('Ungrouped').evaluate().isEmpty; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump();
    }
    await tester.tap(find.text('Ungrouped'));
    await _settle(tester);
    await tester.tap(find.text('Fold session'));
    await _settle(tester);

    expect(find.byType(RunningStatusRow), findsOneWidget);
    expect(find.byType(ActivityGroupRow), findsOneWidget);
    expect(find.text('Bash'), findsNothing);
    await tester.tap(find.byType(ProcessGroupHeader));
    await _settle(tester);
    expect(find.text('Bash'), findsOneWidget);

    final Element rowElement = tester.element(find.byType(RunningStatusRow));
    final State<StatefulWidget> rowState = tester.state<State<StatefulWidget>>(
      find.byType(RunningStatusRow),
    );
    final Element clockElement = tester.element(_clockText().last);
    final Element groupElement = tester.element(find.byType(ActivityGroupRow));
    final State<StatefulWidget> groupState = tester
        .state<State<StatefulWidget>>(find.byType(ActivityGroupRow));
    final String clockBefore =
        (tester.widget<Text>(_clockText().last)).data ?? '';

    // (a) A history page arrives above everything on screen.
    repository.prependHistory(0);
    await _settle(tester);

    expect(find.byType(RunningStatusRow), findsOneWidget);
    expect(
      identical(tester.element(find.byType(RunningStatusRow)), rowElement),
      isTrue,
      reason: 'the running row keeps its element across the insert',
    );
    expect(
      identical(
        tester.state<State<StatefulWidget>>(find.byType(RunningStatusRow)),
        rowState,
      ),
      isTrue,
      reason: 'the running row keeps its State, so its clock and timer live on',
    );
    expect(
      identical(tester.element(_clockText().last), clockElement),
      isTrue,
      reason: 'the clock text node is the same element',
    );
    expect(
      identical(tester.element(find.byType(ActivityGroupRow)), groupElement),
      isTrue,
    );
    expect(
      identical(
        tester.state<State<StatefulWidget>>(find.byType(ActivityGroupRow)),
        groupState,
      ),
      isTrue,
    );
    expect(find.text('Bash'), findsOneWidget);

    // The timer is still armed: a real second plus its tick moves the clock.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 1200));
    });
    await tester.pump(const Duration(seconds: 1));
    final String clockAfter =
        (tester.widget<Text>(_clockText().last)).data ?? '';
    expect(clockAfter, isNot(clockBefore));

    // (b) A live item appended below the tail: the same rows keep their state.
    repository.appendLive('live-1');
    await _settle(tester);
    expect(find.byType(RunningStatusRow), findsOneWidget);
    expect(
      identical(
        tester.state<State<StatefulWidget>>(find.byType(RunningStatusRow)),
        rowState,
      ),
      isTrue,
    );
    expect(find.text('Bash'), findsOneWidget);

    // (c) The reader closes the fold: the same State follows the tap, and the
    // members go away because the fold closed, not because the row was reset.
    await tester.tap(find.byType(ProcessGroupHeader));
    await _settle(tester);
    expect(find.text('Bash'), findsNothing);
    expect(
      identical(
        tester.state<State<StatefulWidget>>(find.byType(ActivityGroupRow)),
        groupState,
      ),
      isTrue,
    );
  });
}
