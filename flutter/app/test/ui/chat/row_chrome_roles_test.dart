/// The 0.2.0 row-chrome roles: the disclosure tone a row wears at rest and on
/// hover, the label-only sweep the group header carries, and the toggle's
/// accessible name.
///
/// The reference's `DisclosureRow` (`ui-primitives/src/DisclosureRow.module.css`)
/// paints its row `label-tertiary` and steps to `label-secondary` on hover, and
/// its leading box, title and collapsed content all inherit that tone rather
/// than naming a role of their own. `ChatGroupSeat`'s group header and
/// `GenericCommandCard` inherit the same rule, and `ReasoningRow`'s summary
/// drops its own tone for it. The app maps `label-tertiary` onto
/// `onSurfaceVariant` and `label-secondary` onto `onSurface`.
library;

import 'package:app/ui/chat/chat_screen.dart';
import 'package:app/ui/chat/process_activity.dart';
import 'package:app/ui/chat/process_disclosure.dart';
import 'package:app/ui/chat/reasoning_row.dart';
import 'package:app/ui/chat/sweep_highlight.dart';
import 'package:app/ui/theme/theme.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';

final ColorScheme _scheme = DshTheme.light().colorScheme;

/// Hovers the centre of [finder] and settles the rebuild it triggers. The rows
/// carry a repeating sweep, so this pumps a frame instead of settling.
Future<void> _hover(WidgetTester tester, Finder finder) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  addTearDown(gesture.removePointer);
  await tester.pump();
  await gesture.moveTo(tester.getCenter(finder));
  await tester.pump();
}

/// The settled summary of two categories, the shape a finished phase leaves.
ProcessActivitySummary _settled() => const ProcessActivitySummary(
  counts: <ProcessActivityCount>[
    ProcessActivityCount(ProcessActivity.commands, 2),
    ProcessActivityCount(ProcessActivity.read, 1),
  ],
);

void main() {
  group('ProcessGroupHeader', () {
    Future<void> pump(
      WidgetTester tester, {
      bool open = false,
      AnimationController? sweep,
      bool reducedMotion = false,
    }) async {
      await tester.pumpWidget(
        l10nApp(
          theme: DshTheme.light(),
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(disableAnimations: reducedMotion),
              child: ProcessGroupHeader(
                summary: _settled(),
                closed: true,
                open: open,
                sweep: sweep,
                onTap: () {},
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('wears the tertiary tone at rest and the secondary on hover', (
      tester,
    ) async {
      await pump(tester);
      final label = tester.widget<Text>(find.byType(Text));
      expect(label.style?.color, _scheme.onSurfaceVariant);
      // The leading box inherits the row's tone instead of naming a role.
      for (final icon in tester.widgetList<Icon>(find.byType(Icon))) {
        expect(icon.color, _scheme.onSurfaceVariant);
      }

      await _hover(tester, find.byType(ProcessGroupHeader));
      expect(
        tester.widget<Text>(find.byType(Text)).style?.color,
        _scheme.onSurface,
      );
      for (final icon in tester.widgetList<Icon>(find.byType(Icon))) {
        expect(icon.color, _scheme.onSurface);
      }
    });

    testWidgets('sweeps the label and leaves the leading box outside it', (
      tester,
    ) async {
      final controller = AnimationController(
        vsync: const TestVSync(),
        duration: kSweepCycle,
      )..repeat();
      addTearDown(controller.dispose);
      await pump(tester, sweep: controller);

      final mask = find.byType(ShaderMask);
      expect(mask, findsOneWidget);
      expect(
        find.descendant(of: mask, matching: find.byType(Text)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: mask, matching: find.byType(Icon)),
        findsNothing,
      );
      expect(
        tester.widget<SweepHighlight>(find.byType(SweepHighlight)).controller,
        same(controller),
      );
      controller.stop();
    });

    testWidgets('reduced motion leaves the label still', (tester) async {
      final controller = AnimationController(
        vsync: const TestVSync(),
        duration: kSweepCycle,
      );
      addTearDown(controller.dispose);
      await pump(tester, sweep: controller, reducedMotion: true);

      expect(find.byType(ShaderMask), findsNothing);
    });

    testWidgets('names the toggle after its label', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);

      expect(find.bySemanticsLabel(RegExp('commands')), findsOneWidget);
      final node = tester.getSemantics(
        find.bySemanticsLabel(RegExp('commands')),
      );
      expect(node.flagsCollection.isButton, isTrue);
      semantics.dispose();
    });

    testWidgets('an open header keeps an 8px tail', (tester) async {
      await pump(tester, open: true);

      final padding = tester.widget<Padding>(
        find
            .ancestor(of: find.byType(Row), matching: find.byType(Padding))
            .first,
      );
      expect(padding.padding, const EdgeInsets.only(bottom: 8));
    });

    testWidgets('paints no tile in any state', (tester) async {
      await pump(tester);

      // The reference's group title is a flat button — `background: none`,
      // `padding: 0` (`ChatGroupSeat.module.css:12`, :10) — so a press changes
      // only the label's tone. Material's ink overlay would paint a fill
      // across the row, so every overlay colour is off.
      final ThemeData inner = Theme.of(
        tester.element(find.byType(SweepHighlight)),
      );
      expect(inner.highlightColor, Colors.transparent);
      expect(inner.splashColor, Colors.transparent);
      expect(inner.hoverColor, Colors.transparent);

      // Nothing in the row carries a surface of its own.
      for (final Material material in tester.widgetList<Material>(
        find.descendant(
          of: find.byType(ProcessGroupHeader),
          matching: find.byType(Material),
        ),
      )) {
        expect(material.color, isNull);
      }
    });
  });

  group('CommandRow', () {
    Future<void> pump(WidgetTester tester, TimelineCommand command) async {
      await tester.pumpWidget(
        l10nApp(
          theme: DshTheme.light(),
          home: CommandRow(command: command),
        ),
      );
    }

    testWidgets('wears the shared tones, not a tone per status', (
      tester,
    ) async {
      await pump(
        tester,
        const TimelineCommand(
          commandId: 'c1',
          name: 'goal',
          text: 'Compacted 120 history items.',
          status: CommandRunStatus.success,
        ),
      );
      Color? titleColor() =>
          tester.widget<Text>(find.text('/goal')).style?.color;
      expect(titleColor(), _scheme.onSurfaceVariant);
      expect(
        tester
            .widget<Text>(find.text('Compacted 120 history items.'))
            .style
            ?.color,
        _scheme.onSurfaceVariant,
      );

      await _hover(tester, find.byType(CommandRow));
      expect(titleColor(), _scheme.onSurface);
      expect(
        tester
            .widget<Text>(find.text('Compacted 120 history items.'))
            .style
            ?.color,
        _scheme.onSurface,
      );
    });

    testWidgets('a failed run keeps the error tone', (tester) async {
      await pump(
        tester,
        const TimelineCommand(
          commandId: 'c2',
          name: 'compact',
          text: 'This operation was aborted',
          status: CommandRunStatus.failed,
        ),
      );

      expect(
        tester.widget<Text>(find.text('/compact')).style?.color,
        _scheme.error,
      );
      await _hover(tester, find.byType(CommandRow));
      expect(
        tester
            .widget<Text>(find.text('This operation was aborted'))
            .style
            ?.color,
        _scheme.error,
      );
    });
  });

  group('ReasoningRow', () {
    testWidgets('the summary inherits the row tone', (tester) async {
      await tester.pumpWidget(
        l10nApp(
          theme: DshTheme.light(),
          home: const ReasoningRow(
            text: 'first line\nsecond line',
            running: false,
          ),
        ),
      );

      Color? summaryColor() =>
          tester.widget<Text>(find.text('first line')).style?.color;
      expect(summaryColor(), _scheme.onSurfaceVariant);
      expect(
        tester.widget<Text>(find.text('Think')).style?.color,
        _scheme.onSurfaceVariant,
      );

      await _hover(tester, find.byType(ReasoningRow));
      expect(summaryColor(), _scheme.onSurface);
      expect(
        tester.widget<Text>(find.text('Think')).style?.color,
        _scheme.onSurface,
      );
    });

    testWidgets('an open body carries the reference indent and no rule', (
      tester,
    ) async {
      await tester.pumpWidget(
        l10nApp(
          theme: DshTheme.light(),
          home: const Scaffold(
            body: ReasoningRow(text: 'first line\nsecond line', running: false),
          ),
        ),
      );
      await tester.tap(find.text('Think'));
      await tester.pumpAndSettle();

      // `.thinkBody` is an indent and nothing else
      // (`ReasoningRow.module.css:74-78`): no border, and the 22px left is the
      // body's own padding rather than a `childrenPadding` plus a margin.
      final body = find.ancestor(
        of: find.text('first line\nsecond line'),
        matching: find.byType(Container),
      );
      expect(body, findsWidgets);
      final padded = tester
          .widgetList<Container>(body)
          .map((container) => container.padding)
          .whereType<EdgeInsets>()
          .toList();
      expect(padded, contains(const EdgeInsets.fromLTRB(22, 4, 0, 4)));
      for (final container in tester.widgetList<Container>(body)) {
        expect(container.decoration, isNull);
      }
    });
  });

  group('ProcessGroupBody', () {
    testWidgets('keeps its edge mask in the tree when nothing scrolls', (
      tester,
    ) async {
      await tester.pumpWidget(
        l10nApp(
          theme: DshTheme.light(),
          home: const Scaffold(
            body: SizedBox(
              height: 120,
              child: ProcessGroupBody(
                child: Column(
                  children: <Widget>[
                    SizedBox(height: 20, child: Text('member 1')),
                    SizedBox(height: 20, child: Text('member 2')),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // A body that fits still carries the mask, opaque at both ends. The mask
      // is the scroller's own widget from the first frame: inserting it only
      // once an edge opens changes the scroller's position in the tree,
      // rebuilds it and drops the offset the group is holding.
      final ShaderMask mask = tester.widget<ShaderMask>(
        find.ancestor(
          of: find.byType(SingleChildScrollView),
          matching: find.byType(ShaderMask),
        ),
      );
      expect(mask.blendMode, BlendMode.dstIn);
      expect(find.byType(ShaderMask), findsOneWidget);
    });
  });
}
