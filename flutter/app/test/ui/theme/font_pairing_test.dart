/// One voice for Latin and Han: the UI chain the theme declares, and the proof
/// that a paragraph carrying both scripts resolves to it.
///
/// The app used to declare no family at all (`theme.dart` named only the code
/// face), so Latin and Han were both resolved by the platform's own defaults and
/// nothing recorded which pair that was — which is how a mismatch could reach a
/// screenshot review and still be argued about. The reference states one stack
/// for both scripts (`--dsw-font-family`, `base.css:7-8`): Latin faces first,
/// the Han faces inside the same list. These tests pin the ported chain.
library;

import 'package:app/ui/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The paragraph the widget test paints: a Han run and a Latin run in one block.
const String _latinRun = 'The dock is capped — ';
const String _hanRun = '下一步把输入区封顶。';

/// Every style the theme publishes, so none can carry a family of its own.
List<TextStyle> _styles(TextTheme theme) => <TextStyle?>[
  theme.displayLarge,
  theme.displayMedium,
  theme.displaySmall,
  theme.headlineLarge,
  theme.headlineMedium,
  theme.headlineSmall,
  theme.titleLarge,
  theme.titleMedium,
  theme.titleSmall,
  theme.bodyLarge,
  theme.bodyMedium,
  theme.bodySmall,
  theme.labelLarge,
  theme.labelMedium,
  theme.labelSmall,
].whereType<TextStyle>().toList();

/// The one style the paragraph inherits when a run names none.
TextStyle _ambient(WidgetTester tester) =>
    DefaultTextStyle.of(tester.element(find.byType(Text).first)).style;

/// The app's three appearances, built once per test.
final Map<String, ThemeData Function()> _themes =
    <String, ThemeData Function()>{
      'light': DshTheme.light,
      'dark': DshTheme.dark,
      'oled': DshTheme.oled,
    };

void main() {
  for (final MapEntry<String, ThemeData Function()> entry in _themes.entries) {
    test('${entry.key}: every text style carries the one UI chain', () {
      final ThemeData theme = entry.value();
      final List<TextStyle> styles = _styles(theme.textTheme);
      expect(styles, isNotEmpty);
      for (final TextStyle style in styles) {
        expect(
          style.fontFamily,
          kUiFontFamily,
          reason:
              'a style with a family of its own puts one script back on a '
              'second voice',
        );
        expect(style.fontFamilyFallback, kUiFontFamilyFallback);
      }
      // The one text a reader sees without a `TextTheme` role of its own.
      expect(theme.primaryTextTheme.bodyMedium?.fontFamily, kUiFontFamily);
      expect(
        theme.primaryTextTheme.bodyMedium?.fontFamilyFallback,
        kUiFontFamilyFallback,
      );
    });
  }

  test('the Han faces are the platform\'s, behind the Latin face', () {
    // The reference's stack order, ported: the Latin face first, the Han faces
    // inside the same list, a generic last (`base.css:7-8`). A Han family no
    // device ships would be a request the platform cannot answer.
    expect(kUiFontFamily, 'Roboto');
    expect(kUiFontFamilyFallback.first, 'Noto Sans CJK SC');
    expect(kUiFontFamilyFallback, contains('Noto Sans SC'));
    expect(kUiFontFamilyFallback, contains('Source Han Sans SC'));
    expect(kUiFontFamilyFallback.last, 'sans-serif');
    // Two scripts, one chain: the Han names are not the Latin one.
    expect(kUiFontFamilyFallback, isNot(contains(kUiFontFamily)));
  });

  for (final String name in <String>['light', 'dark']) {
    testWidgets('$name: a Han run and a Latin run share one resolved chain', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: _themes[name]!(),
          home: const Scaffold(
            body: Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(text: _latinRun),
                  TextSpan(text: _hanRun),
                ],
              ),
            ),
          ),
        ),
      );

      final RichText rich = tester.widget<RichText>(
        find
            .descendant(of: find.byType(Text), matching: find.byType(RichText))
            .first,
      );

      // One paragraph, both scripts. Neither run names a family of its own, so
      // both resolve through the one ambient chain: the effective family and
      // fallback list of a Han run and of a Latin run are the same, and a theme
      // that left either script to the platform default fails here rather than
      // only looking wrong in a PNG.
      final List<InlineSpan> runs = <InlineSpan>[];
      void visit(InlineSpan span) {
        if (span is! TextSpan) return;
        if (span.text != null) runs.add(span);
        for (final InlineSpan child in span.children ?? const <InlineSpan>[]) {
          visit(child);
        }
      }

      visit(rich.text);
      expect(runs.map((run) => run.toPlainText()), <String>[
        _latinRun,
        _hanRun,
      ]);

      final TextStyle ambient = _ambient(tester);
      expect(ambient.fontFamily, kUiFontFamily);
      expect(ambient.fontFamilyFallback, kUiFontFamilyFallback);
      for (final InlineSpan run in runs) {
        expect(
          run.style?.fontFamily ?? ambient.fontFamily,
          kUiFontFamily,
          reason: 'run "${run.toPlainText()}" resolves its family',
        );
        expect(
          run.style?.fontFamilyFallback ?? ambient.fontFamilyFallback,
          kUiFontFamilyFallback,
          reason: 'run "${run.toPlainText()}" resolves its Han fallbacks',
        );
      }
    });
  }
}
