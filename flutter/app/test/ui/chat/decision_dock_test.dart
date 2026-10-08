/// Decision-seat geometry: the dock's one-line decision cards and the surfaces
/// their detail moved to.
///
/// The card → detail pattern takes the whole card out of the composer seat: a
/// pending plan review and a pending question are each one line
/// (`CardDetailRow`), the plan keeps its primary action on the row, the ask
/// keeps its chip, and the answers live on the pushed route or the large sheet
/// the row opens. What must stay inside the viewport is therefore the row's own
/// action and the sheet's pinned footer — not the card body, which is the block
/// this pattern exists to remove.
///
/// The history is the point of this file: its first version asserted that the
/// plan card's warn strip, scrollable plan body and three action buttons all
/// fitted the dock, and that a long question's own footer stayed on screen.
/// Those are no longer the surfaces; these tests assert the new contract at the
/// same panel heights, with and without the keyboard.
library;

import 'package:app/ui/chat/card_detail.dart';
import 'package:app/ui/chat/chat_screen.dart';
import 'package:app/ui/chat/chat_ui_state.dart';
import 'package:app/ui/theme/theme.dart';
import 'package:domain/model/schedule.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';

const SessionSummary _session = SessionSummary(
  id: 's1',
  title: 'plan',
  blank: false,
);

/// A long plan: the document must open on its own surface, never in the dock.
const String _longPlan =
    '## 步骤\n\n'
    '1. 把 `deliverables/presented` 折到 `present` 调用自己的行上；\n'
    '2. 回合收尾处新增「交付文件」卡片行，超过 4 个折叠；\n'
    '3. `present` 工具行改用「交付文件」标题与 `files[].path` 摘要；\n'
    '4. 补单测与 before/after 设计图；\n'
    '5. 补一份决策记录，说明为什么不是底部弹层；\n'
    '6. 风险：主桌面打开动作不做，只走应用内预览；\n'
    '7. 风险：折叠阈值以后可能要跟宿主对齐。\n';

ChatUiState _planReviewState({
  List<ScheduleReminder> schedules = const <ScheduleReminder>[],
}) => ChatUiState(
  sessions: const <SessionSummary>[_session],
  selectedSessionId: 's1',
  schedules: schedules,
  timeline: const <TimelineItem>[
    TimelineQuestionRequest(
      requestId: 'rpc-plan',
      questions: <QuestionItem>[
        QuestionItem(
          id: 'plan-1',
          question: '执行这份计划吗？',
          detail: _longPlan,
          options: <String>['确认执行', '继续规划'],
          intent: QuestionIntent(kind: 'plan-review', approve: '确认执行'),
        ),
      ],
    ),
  ],
);

ChatUiState _questionState() => const ChatUiState(
  sessions: <SessionSummary>[_session],
  selectedSessionId: 's1',
  timeline: <TimelineItem>[
    TimelineQuestionRequest(
      requestId: 'rpc-q',
      questions: <QuestionItem>[
        QuestionItem(
          id: 'q1',
          question: '侧边栏要哪种归档？',
          detail: _longPlan,
          options: <String>['会话行归档', '工作区组头归档', '两者都要'],
        ),
      ],
    ),
  ],
);

const List<ScheduleReminder> _reminders = <ScheduleReminder>[
  ScheduleReminder(
    id: 'r1',
    kind: ScheduleReminderKind.after,
    prompt: '十分钟后提醒我看构建结果',
    scheduledAt: '2026-10-07T04:00:00Z',
    afterSeconds: 600,
  ),
  ScheduleReminder(
    id: 'r2',
    kind: ScheduleReminderKind.every,
    prompt: '每小时同步一次进度',
    scheduledAt: '2026-10-07T04:00:00Z',
    everySeconds: 3600,
  ),
];

/// Pumps the real chat panel at a phone-shaped viewport. [keyboardDp] is the
/// soft keyboard's logical height; the Scaffold insets the panel for it the
/// way the app does.
Future<void> _pump(
  WidgetTester tester,
  ChatUiState state, {
  Size view = const Size(360, 400),
  double keyboardDp = 0,
  List<ChatAction>? actions,
}) async {
  tester.view.physicalSize = view * 2;
  tester.view.devicePixelRatio = 2;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboardDp * 2);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
  await tester.pumpWidget(
    l10nApp(
      theme: DshTheme.light(),
      home: ChatScreen(
        uiState: state,
        onAction: (action) => actions?.add(action),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
}

/// Opens the decision surface the card row holds, by tapping its title.
Future<void> _openCardDetail(WidgetTester tester, String title) async {
  await tester.tap(find.text(title));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// The action's rect and the space it must stay inside.
void _expectInsidePanel(WidgetTester tester, String label, double keyboardDp) {
  final rect = tester.getRect(find.text(label));
  final viewHeight = tester.view.physicalSize.height / 2;
  expect(
    rect.bottom,
    lessThanOrEqualTo(viewHeight - keyboardDp - 4),
    reason: '"$label" must stay above the tab bar (and the keyboard)',
  );
  expect(rect.top, greaterThanOrEqualTo(0), reason: '"$label" above the top');
}

void main() {
  testWidgets('the plan row keeps its action on a short phone panel', (
    tester,
  ) async {
    final actions = <ChatAction>[];
    await _pump(tester, _planReviewState(), actions: actions);

    expect(tester.takeException(), isNull);
    // The card is one line, and the document is not in it.
    expect(find.byType(CardDetailRow), findsOneWidget);
    expect(find.textContaining('把 `deliverables'), findsNothing);
    _expectInsidePanel(tester, 'Plan ready for review', 0);
    _expectInsidePanel(tester, 'Approve', 0);

    // The row's action answers without opening anything.
    await tester.tap(find.text('Approve'));
    await tester.pump();
    expect(actions.whereType<AnswerQuestionAction>(), hasLength(1));

    // And the row itself opens the document, whose actions are pinned in the
    // route's bottom bar rather than in the dock.
    await _openCardDetail(tester, 'Plan ready for review');
    expect(tester.takeException(), isNull);
    expect(find.byType(CardDetailScaffold), findsOneWidget);
    _expectInsidePanel(tester, 'Chat about it', 0);
    _expectInsidePanel(tester, 'Refuse', 0);
    _expectInsidePanel(tester, 'Approve', 0);
  });

  testWidgets('a keyboard-shrunk panel still shows the plan row and action', (
    tester,
  ) async {
    // A 700dp phone (564dp of panel once the app bar and tab bar are out)
    // with a 300dp keyboard: the row must sit above the keyboard.
    await _pump(
      tester,
      _planReviewState(),
      view: const Size(360, 564),
      keyboardDp: 300,
    );

    expect(tester.takeException(), isNull);
    _expectInsidePanel(tester, 'Plan ready for review', 300);
    _expectInsidePanel(tester, 'Approve', 300);
  });

  testWidgets('reminder strips above the row do not push its action out', (
    tester,
  ) async {
    await _pump(tester, _planReviewState(schedules: _reminders));

    expect(tester.takeException(), isNull);
    _expectInsidePanel(tester, 'Approve', 0);
    _expectInsidePanel(tester, 'Plan ready for review', 0);
  });

  testWidgets('the ask row opens a sheet whose footer stays on screen', (
    tester,
  ) async {
    final actions = <ChatAction>[];
    await _pump(
      tester,
      _questionState(),
      view: const Size(360, 480),
      actions: actions,
    );

    expect(tester.takeException(), isNull);
    // The question is the card's line; the options are one surface deeper.
    expect(find.byType(CardDetailRow), findsOneWidget);
    expect(find.text('侧边栏要哪种归档？'), findsOneWidget);
    expect(find.text('会话行归档'), findsNothing);

    await _openCardDetail(tester, '侧边栏要哪种归档？');
    expect(tester.takeException(), isNull);
    expect(find.text('会话行归档'), findsOneWidget);
    _expectInsidePanel(tester, 'Submit', 0);
    _expectInsidePanel(tester, 'Skip', 0);

    await tester.tap(find.text('Skip'));
    await tester.pump();
    expect(
      actions.whereType<AnswerQuestionAction>(),
      hasLength(1),
      reason: 'the sheet button the user pressed is the one that answered',
    );
  });
}
