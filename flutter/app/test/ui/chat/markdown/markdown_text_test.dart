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

  testWidgets('a code block copies its body, not the message', (
    tester,
  ) async {
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

  testWidgets('the body is selectable', (tester) async {
    await _pump(tester, 'a path lives at lib/main.dart');

    expect(find.byType(SelectionArea), findsOneWidget);
  });

  testWidgets('streaming appends render the settled document', (
    tester,
  ) async {
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

  testWidgets('a theme change re-renders cached block widgets', (
    tester,
  ) async {
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
}
