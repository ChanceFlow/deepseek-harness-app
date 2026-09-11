import 'package:app/ui/chat/markdown/markdown_text.dart';
import 'package:app/ui/theme/theme.dart';
import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../l10n_app.dart';

Future<void> _pump(WidgetTester tester, String body) {
  return tester.pumpWidget(
    l10nApp(
      theme: DshTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: MarkdownText(text: body),
          ),
        ),
      ),
    ),
  );
}

/// Pumps the same tree under one brightness, so a colour assertion can be made
/// twice: a value baked into the widget passes one and fails the other. The
/// settle pump is the theme lerp `MaterialApp` runs between two themes — read
/// the colours before it ends and the old scheme is still on screen.
Future<void> _pumpThemed(
  WidgetTester tester,
  String body,
  ThemeData theme,
) async {
  await tester.pumpWidget(
    l10nApp(
      theme: theme,
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: MarkdownText(text: body),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The ink a rendered code body carries: [ink] is the body's own style — what
/// a span with no override inherits — and [spans] is the colour painted per
/// span, `null` where the span deliberately overrides nothing.
({Color? ink, Map<String, Color?> spans}) _codeColors(
  WidgetTester tester,
  String plain,
) {
  final rich = tester
      .widgetList<RichText>(find.byType(RichText))
      .firstWhere((widget) => widget.text.toPlainText() == plain);
  final spans = <String, Color?>{};
  rich.text.visitChildren((span) {
    if (span is TextSpan && span.text != null) {
      spans[span.text!] = span.style?.color;
    }
    return true;
  });
  return (ink: rich.text.style?.color, spans: spans);
}

void main() {
  testWidgets('a numbered list renders the source numbers', (tester) async {
    await _pump(tester, '3. third\n4. fourth');

    expect(find.text('3.'), findsOneWidget);
    expect(find.text('4.'), findsOneWidget);
  });

  testWidgets('a wrapped item hangs under its own text', (tester) async {
    await _pump(tester, '1. one\n2. two');

    // The marker holds a column of its own: item text starts to the right
    // of the widest marker, not at the paragraph's left edge.
    final marker = tester.getTopLeft(find.text('1.'));
    final body = tester.getTopLeft(find.text('one'));
    expect(body.dx, greaterThan(marker.dx + 20));
  });

  testWidgets('paragraphs separate by more than a line', (tester) async {
    await _pump(tester, 'first paragraph\n\nsecond paragraph');

    final first = tester.getRect(find.text('first paragraph'));
    final second = tester.getRect(find.text('second paragraph'));
    expect(second.top - first.bottom, greaterThanOrEqualTo(8));
  });

  testWidgets('a code block copies its body, not the message', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add(
            (call.arguments as Map<Object?, Object?>)['text']! as String,
          );
        }
        return null;
      },
    );
    await _pump(tester, 'intro\n\n```dart\nvar a = 1;\n```');

    await tester.tap(find.byIcon(Icons.copy_outlined));
    await tester.pump();
    expect(copied, ['var a = 1;']);
  });

  testWidgets('an unclosed fence names itself streaming', (tester) async {
    await _pump(tester, '```dart\nvar a = 1;');

    expect(find.text('streaming'), findsOneWidget);
  });

  testWidgets('a closed fence paints its tokens from the scheme roles', (
    tester,
  ) async {
    // Same body, both brightnesses: a token colour baked into the widget
    // would pass one of these and fail the other.
    for (final theme in [DshTheme.light(), DshTheme.dark()]) {
      final scheme = theme.colorScheme;
      await _pumpThemed(tester, '```dart\nfinal n = 42; // note\n```', theme);

      final painted = _codeColors(tester, 'final n = 42; // note');
      expect(
        painted.spans['final'],
        scheme.syntaxKeyword,
        reason: 'keyword ink for ${theme.brightness}',
      );
      expect(
        painted.spans['42'],
        scheme.syntaxNumber,
        reason: 'number ink for ${theme.brightness}',
      );
      expect(
        painted.spans['// note'],
        scheme.onSurfaceVariant,
        reason: 'comment ink for ${theme.brightness}',
      );
      // An identifier overrides nothing and so keeps the body's own ink,
      // which is what holds the rest of the code unemphasised.
      expect(
        painted.spans['n '],
        isNull,
        reason: 'identifier carries no override for ${theme.brightness}',
      );
      expect(
        painted.ink,
        scheme.onSurface,
        reason: 'body ink for ${theme.brightness}',
      );
    }
  });

  testWidgets('a string literal takes the string token colour', (tester) async {
    final theme = DshTheme.dark();
    await _pumpThemed(tester, '```json\n{"a": "b"}\n```', theme);

    final painted = _codeColors(tester, '{"a": "b"}');
    expect(painted.spans['"a"'], theme.colorScheme.syntaxString);
    expect(painted.spans['"b"'], theme.colorScheme.syntaxString);
  });

  testWidgets('an unknown fence keeps the plain body ink', (tester) async {
    final theme = DshTheme.light();
    await _pumpThemed(tester, '```brainfuck\n+++[>+<]\n```', theme);

    // No tokenizer means no guessed colour: the body renders as one run on
    // the same ink it had before highlighting existed.
    final painted = _codeColors(tester, '+++[>+<]');
    expect(painted.spans.values.toSet(), {theme.colorScheme.onSurface});
    expect(painted.ink, theme.colorScheme.onSurface);
  });

  testWidgets('a streaming fence stays plain until it closes', (tester) async {
    final theme = DshTheme.light();
    await _pumpThemed(tester, '```dart\nfinal n = 42;', theme);

    // The tail is exactly the text still moving, so it is not re-lexed on
    // every chunk.
    final painted = _codeColors(tester, 'final n = 42;');
    expect(painted.spans.values.toSet(), {theme.colorScheme.onSurface});
    expect(painted.ink, theme.colorScheme.onSurface);
  });

  testWidgets('a long fence grows a line-number gutter', (tester) async {
    final lines = [for (var i = 1; i <= 9; i++) 'var v$i = $i;'].join('\n');
    await _pump(tester, '```dart\n$lines\n```');

    final gutter = find.text([for (var i = 1; i <= 9; i++) '$i'].join('\n'));
    expect(gutter, findsOneWidget);

    // The gutter holds a column of its own, left of the body: a reader
    // locating a line must not have to scroll it away.
    final body = tester
        .widgetList<RichText>(find.byType(RichText))
        .firstWhere((widget) => widget.text.toPlainText() == lines);
    expect(
      tester.getRect(gutter).right,
      lessThanOrEqualTo(tester.getRect(find.byWidget(body)).left),
    );
  });

  testWidgets('a short fence spends no column on numbers', (tester) async {
    await _pump(tester, '```dart\nvar a = 1;\nvar b = 2;\n```');

    expect(find.text('1\n2'), findsNothing);
  });

  testWidgets('the body is selectable', (tester) async {
    await _pump(tester, 'a path lives at lib/main.dart');

    expect(find.byType(SelectionArea), findsOneWidget);
  });

  testWidgets('streaming appends render the settled document', (tester) async {
    const settled =
        'first paragraph\n\n- item one\n- item two\n\n'
        '```dart\nvar a = 1;\n```\n\nlast paragraph still growing';
    var body = '';
    for (final chunk in settled.split('\n\n')) {
      body = body.isEmpty ? chunk : '$body\n\n$chunk';
      await _pump(tester, body);
    }

    expect(find.text('first paragraph'), findsOneWidget);
    expect(find.text('item two'), findsOneWidget);
    expect(find.text('var a = 1;'), findsOneWidget);
    expect(find.text('last paragraph still growing'), findsOneWidget);
    // The closed fence's language label replaced the streaming label.
    expect(find.text('streaming'), findsNothing);
    expect(find.text('dart'), findsOneWidget);
  });

  testWidgets('a theme change re-renders cached block widgets', (tester) async {
    await _pump(tester, 'one\n\ntwo');
    final light = tester.widget<Text>(find.text('one')).style;

    await tester.pumpWidget(
      l10nApp(
        theme: DshTheme.dark(),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: MarkdownText(text: 'one\n\ntwo'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The block widgets bake the theme in at build time; the cached
    // widgets must have been discarded, not reused, on the swap.
    final dark = tester.widget<Text>(find.text('one')).style;
    expect(dark, isNot(light));
  });

  testWidgets(
    'a multi-column table wraps in horizontal scroll on narrow view',
    (tester) async {
      const tableText =
          '| Col 1 | Col 2 | Col 3 | Col 4 | Col 5 |\n'
          '| --- | --- | --- | --- | --- |\n'
          '| Alpha | Beta | Gamma | Delta | Epsilon |';
      await _pump(tester, tableText);

      expect(find.text('Col 1'), findsOneWidget);
      expect(find.text('Delta'), findsOneWidget);
      // Finds the horizontal scroll view hosting the wide table.
      final horizontalScroll = find.byWidgetPredicate(
        (widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal,
      );
      expect(horizontalScroll, findsOneWidget);
    },
  );
}
