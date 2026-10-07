/// Decision-seat geometry: the input dock's question and plan-review cards
/// must keep their own action row on screen.
///
/// The dock sits directly above the root navigation bar, and the panel it
/// lives in is already shorter than the screen (app bar, tab bar, system
/// insets). A card that sized itself against the raw screen therefore grew
/// past the panel's bottom edge, and its actions — the only way to answer —
/// were painted under the tab bar where no tap lands. These tests pump the
/// real chat screen at the panel heights that produce that, with and without
/// the keyboard, and assert both that the actions are inside the viewport and
/// that pressing them dispatches.
library;

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

/// A long plan: the body must scroll, never push the actions off-panel.
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
  testWidgets('a plan card keeps every action on a short phone panel', (
    tester,
  ) async {
    final actions = <ChatAction>[];
    await _pump(tester, _planReviewState(), actions: actions);

    expect(tester.takeException(), isNull);
    _expectInsidePanel(tester, 'Approve', 0);
    _expectInsidePanel(tester, 'Chat about it', 0);
    _expectInsidePanel(tester, 'Refuse', 0);

    await tester.tap(find.text('Approve'));
    await tester.pump();
    expect(actions.whereType<AnswerQuestionAction>(), hasLength(1));
  });

  testWidgets('a keyboard-shrunk panel still shows the plan actions', (
    tester,
  ) async {
    // A 700dp phone (564dp of panel once the app bar and tab bar are out)
    // with a 300dp keyboard: the actions must sit above the keyboard.
    await _pump(
      tester,
      _planReviewState(),
      view: const Size(360, 564),
      keyboardDp: 300,
    );

    expect(tester.takeException(), isNull);
    _expectInsidePanel(tester, 'Approve', 300);
    _expectInsidePanel(tester, 'Chat about it', 300);
  });

  testWidgets('reminder strips above the card do not push its actions out', (
    tester,
  ) async {
    await _pump(
      tester,
      _planReviewState(schedules: _reminders),
      view: const Size(360, 400),
    );

    expect(tester.takeException(), isNull);
    _expectInsidePanel(tester, 'Approve', 0);
    _expectInsidePanel(tester, 'Chat about it', 0);
  });

  testWidgets('a long question keeps its footer buttons inside', (
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
    _expectInsidePanel(tester, 'Submit', 0);
    _expectInsidePanel(tester, 'Skip', 0);

    await tester.tap(find.text('Skip'));
    await tester.pump();
    expect(
      actions.whereType<AnswerQuestionAction>(),
      hasLength(1),
      reason: 'the footer button the user pressed is the one that answered',
    );
  });
}
