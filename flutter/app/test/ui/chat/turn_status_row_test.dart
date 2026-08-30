/// Tests for the turn status activity row: letter-by-letter hop, text shimmer
/// ShaderMask, dual-brightness theme glint verification, and reduced motion.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:app/ui/chat/turn_status_row.dart';
import 'package:app/ui/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';

void main() {
  testWidgets('renders hopping letters under a text shimmer ShaderMask', (
    tester,
  ) async {
    await tester.pumpWidget(
      l10nApp(home: const Scaffold(body: TurnStatusRow())),
    );
    await tester.pump();

    // The ShaderMask wraps the letter Row for the glint shimmer.
    final maskFinder = find.descendant(
      of: find.byType(TurnStatusRow),
      matching: find.byType(ShaderMask),
    );
    expect(maskFinder, findsOneWidget);

    final shaderMask = tester.widget<ShaderMask>(maskFinder);
    expect(shaderMask.blendMode, BlendMode.srcATop);

    // Calling shaderCallback with a non-empty rect produces a valid shader.
    final shader = shaderMask.shaderCallback(
      const Rect.fromLTWH(0, 0, 120, 26),
    );
    expect(shader, isNotNull);

    // Letter split: joined text matches the l10n copy.
    final letters = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(TurnStatusRow),
            matching: find.byType(Text),
          ),
        )
        .map((t) => t.data ?? '')
        .join();
    expect(letters, 'Deep diving…');

    // Ticking the clock advances the animation.
    await tester.pump(const Duration(milliseconds: 300));
    final shader2 = tester
        .widget<ShaderMask>(maskFinder)
        .shaderCallback(const Rect.fromLTWH(0, 0, 120, 26));
    expect(shader2, isNotNull);
  });

  testWidgets(
    'dual-brightness glint colors resolve distinct from primary base',
    (tester) async {
      for (final theme in [DshTheme.light(), DshTheme.dark()]) {
        await tester.pumpWidget(
          l10nApp(
            theme: theme,
            home: const Scaffold(body: TurnStatusRow()),
          ),
        );
        await tester.pump();

        final scheme = theme.colorScheme;
        final glint = scheme.statusGlint;
        final primary = scheme.primary;

        // Glint must be distinctly brighter than the base primary in both brightnesses.
        expect(glint, isNot(equals(primary)));
        expect(
          glint.computeLuminance(),
          greaterThan(primary.computeLuminance()),
        );

        final maskFinder = find.descendant(
          of: find.byType(TurnStatusRow),
          matching: find.byType(ShaderMask),
        );
        final shaderMask = tester.widget<ShaderMask>(maskFinder);
        final shader = shaderMask.shaderCallback(
          const Rect.fromLTWH(0, 0, 100, 26),
        );
        expect(shader, isNotNull);
      }
    },
  );

  testWidgets('reduced motion renders whole static text without ShaderMask', (
    tester,
  ) async {
    await tester.pumpWidget(
      l10nApp(
        home: const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(body: TurnStatusRow()),
        ),
      ),
    );
    await tester.pump();

    // In reduced motion, ShaderMask is omitted and text is whole.
    expect(
      find.descendant(
        of: find.byType(TurnStatusRow),
        matching: find.byType(ShaderMask),
      ),
      findsNothing,
    );
    expect(find.text('Deep diving…'), findsOneWidget);
  });

  testWidgets('turn status semantics expose the running state', (tester) async {
    await tester.pumpWidget(
      l10nApp(home: const Scaffold(body: TurnStatusRow())),
    );
    await tester.pump();

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == l10n.semanticsRunning,
      ),
      findsOneWidget,
    );
  });
}
