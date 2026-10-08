/// The card → detail pattern itself: one line in place, the content one surface
/// deeper, and the host exactly where the reader left it.
///
/// The per-card tests live with their cards (`chat_screen_test.dart`,
/// `decision_dock_test.dart`, `approval_panel_test.dart`). This file holds what
/// is true of the pattern rather than of one card: the row's anatomy, the typed
/// payload a detail route carries, the pushed document with its actions pinned,
/// the tool payload's own surface, and — the rule that would rot silently — the
/// host's scroll position surviving the round trip.
library;

import 'package:app/ui/chat/card_detail.dart';
import 'package:app/ui/chat/chat_ui_state.dart';
import 'package:app/ui/chat/plan_detail_surface.dart';
import 'package:app/ui/chat/tool_detail_surface.dart';
import 'package:app/ui/chat/tool_row_model.dart';
import 'package:domain/model/timeline_item.dart' show QuestionAnswer;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';

/// A scrolling transcript with one card row at its tail, which is the shape
/// every host of this pattern has.
class _TranscriptHost extends StatelessWidget {
  const _TranscriptHost({required this.controller, required this.onOpen});

  final ScrollController controller;
  final void Function(BuildContext context) onOpen;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        controller: controller,
        children: <Widget>[
          for (int index = 0; index < 60; index++)
            SizedBox(height: 60, child: Text('transcript row $index')),
          Builder(
            builder: (rowContext) => Padding(
              padding: const EdgeInsets.all(8),
              child: CardDetailRow(
                icon: Icons.description_outlined,
                title: 'The card',
                summary: 'one line of summary',
                openLabel: 'Open',
                onOpen: () => onOpen(rowContext),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The content a detail surface renders in these tests.
class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) =>
      CardDetailScaffold(title: 'Detail', child: Text(text));
}

const EditDiffModel _diff = EditDiffModel(
  filePath: 'lib/main.dart',
  oldString: 'old',
  newString: 'new',
  lines: <ToolDiffLine>[
    ToolDiffLine(kind: DiffLineKind.equal, text: 'void main() {'),
    ToolDiffLine(kind: DiffLineKind.delete, text: '  runApp(old);'),
    ToolDiffLine(kind: DiffLineKind.insert, text: '  runApp(new);'),
  ],
);

void main() {
  testWidgets('the row is one line: title, summary and the open seat', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(
      l10nApp(
        home: Scaffold(
          body: CardDetailRow(
            icon: Icons.checklist_outlined,
            title: 'Plan ready for review',
            summary: 'the plan\'s first line',
            openLabel: 'Open',
            onOpen: () => opened++,
          ),
        ),
      ),
    );

    expect(find.text('Plan ready for review'), findsOneWidget);
    expect(find.text('the plan\'s first line'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    // One line: the row is 60px, the pin's own card height
    // (`PlanPreview.module.css` `.card`, :6).
    expect(tester.getSize(find.byType(CardDetailRow)).height, 60);

    await tester.tap(find.text('Plan ready for review'));
    await tester.pump();
    expect(opened, 1);
  });

  testWidgets('a pushed detail surface leaves the host scroll alone', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      l10nApp(
        home: _TranscriptHost(
          controller: controller,
          onOpen: (context) => showCardDetailSheet<void>(
            context,
            builder: (_) => const _DetailBody(text: 'the detail'),
          ),
        ),
      ),
    );

    // The reader has scrolled to the card, which is where a decision is read.
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    final offset = controller.offset;
    expect(offset, greaterThan(0));
    expect(find.text('The card'), findsOneWidget);

    await tester.tap(find.text('The card'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('the detail'), findsOneWidget);

    // Dismissing the sheet returns to the same card with the reading place
    // intact: the detail was a surface of its own, not a state reset.
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('the detail'), findsNothing);
    expect(controller.offset, offset);
    expect(find.text('The card'), findsOneWidget);
  });

  testWidgets('a content-shaped card pushes a route with its typed payload', (
    tester,
  ) async {
    final actions = <ChatAction>[];
    await tester.pumpWidget(
      l10nApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showPlanDetail(
                context,
                args: const PlanDetailArgs(
                  requestId: 'rpc-plan',
                  questionId: 'plan-1',
                  title: 'Ship the detail surface',
                  description: 'One sentence of summary.',
                  plan: '## Ship it\n\nThe whole document.',
                ),
                approveLabel: 'Approve',
                declineLabel: 'Keep planning',
                onAction: actions.add,
              ),
              child: const Text('open the plan'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open the plan'));
    await tester.pumpAndSettle();

    // The route carries the typed payload, so a restore rebuilds the surface
    // from it rather than from widget state.
    final route = ModalRoute.of(tester.element(find.byType(PlanDetailSurface)));
    expect(route?.settings.name, 'card-detail:plan');
    expect(route?.settings.arguments, isA<PlanDetailArgs>());
    final args = route!.settings.arguments! as PlanDetailArgs;
    expect(args.requestId, 'rpc-plan');
    expect(args.questionId, 'plan-1');
    expect(args.plan, contains('The whole document.'));

    // The app bar names the document, its first paragraph is the subtitle, and
    // the document scrolls under an action bar pinned at the bottom.
    expect(find.text('Ship the detail surface'), findsOneWidget);
    expect(find.text('One sentence of summary.'), findsOneWidget);
    expect(find.textContaining('The whole document.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Approve'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Refuse'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Chat about it'), findsOneWidget);

    // Opening answered nothing; the pinned action does.
    expect(actions, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await tester.pumpAndSettle();
    expect(
      actions.single,
      const AnswerQuestionAction(
        requestId: 'rpc-plan',
        answers: [
          QuestionAnswer(questionId: 'plan-1', selectedOptions: ['Approve']),
        ],
      ),
    );
    expect(find.byType(PlanDetailSurface), findsNothing);
  });

  testWidgets('the tool payload gets its own surface with pinned actions', (
    tester,
  ) async {
    final previews = <String>[];
    await tester.pumpWidget(
      l10nApp(
        home: ToolDetailSurface(
          args: const ToolDetailArgs(
            title: 'Edit',
            diff: _diff,
            input: '{"file_path":"lib/main.dart"}',
            output: 'applied',
            path: 'lib/main.dart',
          ),
          onPreviewFile: (path, {diff}) => previews.add(path),
        ),
      ),
    );

    // The whole payload, not the row's bounded peek: every diff line and both
    // IO sections.
    expect(find.text('void main() {'), findsOneWidget);
    expect(find.text('  runApp(old);'), findsOneWidget);
    expect(find.text('  runApp(new);'), findsOneWidget);
    expect(find.text('{"file_path":"lib/main.dart"}'), findsOneWidget);
    expect(find.text('applied'), findsOneWidget);
    // The edited file's own view is one action away, not another surface.
    expect(find.widgetWithText(OutlinedButton, 'Preview'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Copy'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Preview'));
    await tester.pump();
    expect(previews, <String>['lib/main.dart']);
  });
}
