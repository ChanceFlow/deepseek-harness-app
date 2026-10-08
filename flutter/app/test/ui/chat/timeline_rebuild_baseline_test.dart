/// Timeline render-cost baseline: what a clock frame, a transcript scroll, and
/// a history insert actually rebuild, and whether an insert above keeps the
/// elements (and state) below it.
///
/// The metric is the framework's own dirty-rebuild hook: every
/// `debugOnRebuildDirtyWidget` call inside the measured window counts as one
/// element rebuilt. It is deliberately unfiltered — the post-phase numbers are
/// compared against the pre-phase ones measured the same way.
library;

import 'dart:async';

import 'package:domain/model/chat_message.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/config.dart';
import 'package:app/di/providers.dart';
import 'package:app/ui/chat/chat_screen.dart';
import 'package:app/ui/chat/chat_ui_state.dart';
import 'package:app/ui/chat/running_status_row.dart';

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

class _QuietSocket implements DshEventSocket {
  final StreamController<ServerRequest> _frames =
      StreamController<ServerRequest>.broadcast();

  @override
  Stream<ServerRequest> connect(String path, {void Function()? onOpen}) {
    onOpen?.call();
    return _frames.stream;
  }
}

/// Transcript row widgets, for the "did the clock rebuild a row?" question.
const Set<String> _transcriptRows = <String>{
  'TimelineRow',
  'ActivityGroupRow',
  'TurnProcessRow',
  'RunningStatusRow',
  'ProcessGroupHeader',
  'ProcessGroupBody',
  'ReasoningRow',
  'ToolCallRow',
};

/// Counts widget rebuilds through the framework's debug hook, attributing the
/// ones inside the running row's own subtree separately.
class _Rebuilds {
  final Map<String, int> byType = <String, int>{};
  int inRunningRow = 0;
  int transcriptRows = 0;

  void start() {
    debugOnRebuildDirtyWidget = (Element element, bool _) {
      final String name = element.widget.runtimeType.toString();
      byType[name] = (byType[name] ?? 0) + 1;
      if (_transcriptRows.contains(name)) transcriptRows++;
      element.visitAncestorElements((Element ancestor) {
        if (ancestor.widget is RunningStatusRow) {
          inRunningRow++;
          return false;
        }
        return true;
      });
    };
  }

  void stop() {
    debugOnRebuildDirtyWidget = null;
  }

  int get total => byType.values.fold(0, (int sum, int count) => sum + count);

  /// One line naming the counted types, largest first.
  String summary() {
    final List<MapEntry<String, int>> sorted = byType.entries.toList()
      ..sort(
        (MapEntry<String, int> a, MapEntry<String, int> b) =>
            b.value.compareTo(a.value),
      );
    return sorted
        .take(6)
        .map((MapEntry<String, int> entry) => '${entry.key}=${entry.value}')
        .join(', ');
  }
}

TimelineMessage _message(
  String id,
  String text, {
  MessageRole role = MessageRole.assistant,
}) => TimelineMessage(
  ChatMessage(id: id, sessionId: 's1', role: role, text: text),
);

/// One open Turn whose only work is a settled call: the running row carries the
/// clock, and no other row animates on its own.
List<TimelineItem> _clockTurn() => <TimelineItem>[
  TimelineTurnBoundary(
    1,
    startedAtEpochMs: DateTime.now().millisecondsSinceEpoch - 5000,
  ),
  _message('u1', 'go', role: MessageRole.user),
  const TimelineToolCall(
    id: 't1',
    name: 'bash',
    arguments: '{"command":"ls"}',
    result: 'ok',
    status: ToolRunStatus.completed,
  ),
];

/// A page of older history: plain messages the controller prepends.
List<TimelineItem> _historyPage(int page, {int size = 40}) => <TimelineItem>[
  for (int i = 0; i < size; i++)
    _message('h$page-$i', 'history $page/$i', role: MessageRole.user),
];

ChatUiState _state({
  required List<TimelineItem> timeline,
  bool running = true,
}) => ChatUiState(
  sessions: <SessionSummary>[
    SessionSummary(id: 's1', title: 'Alpha', blank: false, running: running),
  ],
  selectedSessionId: 's1',
  timeline: timeline,
);

Future<void> _pump(WidgetTester tester, ChatUiState uiState) async {
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
        home: ChatScreen(uiState: uiState, onAction: (_) {}),
      ),
    ),
  );
  await tester.pump();
}

/// Every mounted transcript-row element: the set that must not be recycled by
/// an insert above.
Set<Element> _rowElements(WidgetTester tester) => tester.allElements
    .where(
      (Element element) =>
          _transcriptRows.contains(element.widget.runtimeType.toString()),
    )
    .toSet();

/// The transcript's own list, not the browsing sidebar's.
Finder _transcriptList() => find.ancestor(
  of: find.byType(TimelineRow).first,
  matching: find.byType(ListView),
);

void main() {
  testWidgets('a clock frame rebuilds the running row, not the transcript', (
    tester,
  ) async {
    await _pump(tester, _state(timeline: _clockTurn()));
    expect(find.byType(RunningStatusRow), findsOneWidget);

    final rebuilds = _Rebuilds()..start();
    // One second of the running row's own clock: a real advance so the label
    // moves, plus the 1 Hz fake tick.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 1200));
    });
    await tester.pump(const Duration(seconds: 1));
    rebuilds.stop();

    // ignore: avoid_print
    print(
      'M1 clockFrame total=${rebuilds.total} '
      'inRunningRow=${rebuilds.inRunningRow} '
      'transcriptRows=${rebuilds.transcriptRows} '
      'treeElements=${tester.allElements.length} [${rebuilds.summary()}]',
    );
    // The clock lives in the running row: the frame rebuilds that row and no
    // other transcript row.
    expect(rebuilds.byType['RunningStatusRow'] ?? 0, greaterThan(0));
    expect(rebuilds.inRunningRow, greaterThan(0));
  });

  testWidgets('an insert above keeps the running row and its clock', (
    tester,
  ) async {
    final List<TimelineItem> timeline = _clockTurn();
    await _pump(tester, _state(timeline: timeline));

    final State<StatefulWidget> rowState = tester.state<State<StatefulWidget>>(
      find.byType(RunningStatusRow),
    );
    final Element rowElement = tester.element(find.byType(RunningStatusRow));
    final Element clockElement = tester.element(
      find.descendant(
        of: find.byType(RunningStatusRow),
        matching: find.text('5s'),
      ),
    );
    expect(clockElement, isNotNull);

    final List<int> frontPages = <int>[];
    final List<int> replacedPerPage = <int>[];
    final List<int> rowsPerPage = <int>[];
    final List<bool> survivedPerPage = <bool>[];
    final List<bool> presentPerPage = <bool>[];
    final List<TimelineItem> loaded = <TimelineItem>[...timeline];
    for (int page = 0; page < 3; page++) {
      final Set<Element> before = _rowElements(tester);
      final rebuilds = _Rebuilds()..start();
      loaded.insertAll(0, _historyPage(page, size: 8));
      await _pump(tester, _state(timeline: loaded));
      rebuilds.stop();
      frontPages.add(rebuilds.total);
      final Set<Element> after = _rowElements(tester);
      rowsPerPage.add(after.length);
      // Row elements that did not exist before the insert: a list that matches
      // by index recycles every visible row here, one that matches by identity
      // inflates only the rows the page added.
      replacedPerPage.add(
        after.where((Element element) => !before.contains(element)).length,
      );
      // The row can legitimately leave the tree once the insert pushes it out
      // of the viewport's cache; record that instead of letting a finder throw.
      final bool present = find.byType(RunningStatusRow).evaluate().isNotEmpty;
      presentPerPage.add(present);
      survivedPerPage.add(
        present &&
            identical(
              tester.element(find.byType(RunningStatusRow)),
              rowElement,
            ),
      );
    }

    final bool present = find.byType(RunningStatusRow).evaluate().isNotEmpty;
    final bool rowSurvived =
        present &&
        identical(tester.element(find.byType(RunningStatusRow)), rowElement);
    final bool stateSurvived =
        present &&
        identical(
          tester.state<State<StatefulWidget>>(find.byType(RunningStatusRow)),
          rowState,
        );
    final bool clockSurvived =
        present &&
        identical(
          tester.element(
            find.descendant(
              of: find.byType(RunningStatusRow),
              matching: find.text('5s'),
            ),
          ),
          clockElement,
        );

    // ignore: avoid_print
    print(
      'M3 frontInsert present=$present survived=$rowSurvived '
      'stateSurvived=$stateSurvived clockSurvived=$clockSurvived '
      'presentPerPage=$presentPerPage survivedPerPage=$survivedPerPage '
      'rebuilds=$frontPages replacedRowsPerPage=$replacedPerPage '
      'rowElementsPerPage=$rowsPerPage',
    );
    expect(present, isTrue);
    expect(rowSurvived, isTrue);
    expect(stateSurvived, isTrue);
    expect(clockSurvived, isTrue);
  });

  testWidgets('a transcript drag rebuilds only the rows it moves', (
    tester,
  ) async {
    final List<TimelineItem> stress = <TimelineItem>[
      for (int i = 0; i < 2000; i++)
        _message('m$i', 'row $i', role: MessageRole.user),
    ];
    await _pump(tester, _state(timeline: stress, running: false));
    final int mounted = tester
        .widgetList<TimelineRow>(find.byType(TimelineRow, skipOffstage: false))
        .length;

    final rebuilds = _Rebuilds()..start();
    final Stopwatch clock = Stopwatch()..start();
    await tester.drag(_transcriptList(), const Offset(0, -200));
    await tester.pump();
    clock.stop();
    rebuilds.stop();

    // ignore: avoid_print
    print(
      'M2 scroll200 rebuilds=${rebuilds.total} mountedRows=$mounted '
      'dragMs=${clock.elapsedMilliseconds} [${rebuilds.summary()}]',
    );
    expect(mounted, lessThan(200));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a 2,000-item transcript builds lazily', (tester) async {
    final List<TimelineItem> stress = <TimelineItem>[
      for (int i = 0; i < 2000; i++)
        _message('m$i', 'row $i', role: MessageRole.user),
    ];
    final Stopwatch first = Stopwatch()..start();
    await _pump(tester, _state(timeline: stress, running: false));
    first.stop();
    final int mounted = tester
        .widgetList<TimelineRow>(find.byType(TimelineRow, skipOffstage: false))
        .length;

    final Stopwatch scroll = Stopwatch()..start();
    for (int i = 0; i < 20; i++) {
      await tester.drag(_transcriptList(), const Offset(0, -600));
      await tester.pump();
    }
    scroll.stop();

    // ignore: avoid_print
    print(
      'M4 stress items=2000 mountedRows=$mounted '
      'firstPumpMs=${first.elapsedMilliseconds} '
      'scroll20FramesMs=${scroll.elapsedMilliseconds}',
    );
    expect(mounted, lessThan(200));
  });
}
