/// Incremental parse behavior: feeding an append-only stream through
/// [IncrementalMarkdownParse] must equal a full [MarkdownParser.parse] of
/// the accumulated text at every step, frozen prefix blocks must keep
/// their instances, and a non-append change must reset the freeze.
library;

import 'dart:convert';

import 'package:app/ui/chat/markdown/incremental.dart';
import 'package:app/ui/chat/markdown/markdown_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('incremental appends equal a full parse at every step', () {
    final documents = <String>[
      'Plain paragraph that keeps growing line by line\n',
      '```dart\nvoid main() {\n  print("hi");\n}\n```\n',
      '# Heading\n\n- one\n- two\n  wrapped tail\n\n1. first\n2. second\n',
      '| a | b |\n| --- | --- |\n| 1 | 2 |\n| 3 | 4 |\n',
      '> quote line\n> another quote line\n\nafter the quote\n',
      'para before table\n| h |\n| --- |\n| r |\n',
      '- list\n\ntrailing paragraph grows here',
    ];
    for (final document in documents) {
      final incremental = IncrementalMarkdownParse();
      var accumulated = '';
      for (var size = 1; size <= document.length; size++) {
        accumulated = document.substring(0, size);
        expect(
          incremental.update(accumulated),
          MarkdownParser.parse(accumulated),
          reason: 'divergence at prefix length $size of:\n$document',
        );
      }
    }
  });

  test('chunked word-by-word appends equal a full parse', () {
    const document =
        'Start of the reply.\n\n'
        '## Notes\n\n'
        '- the first item\n'
        '- the second item with `code` and **bold**\n\n'
        '```yaml\n'
        'key: value\n'
        '```\n\n'
        'Final paragraph. <https://example.com>';
    final incremental = IncrementalMarkdownParse();
    var accumulated = '';
    for (final word in document.split(' ')) {
      accumulated = accumulated.isEmpty ? word : '$accumulated $word';
      expect(
        incremental.update(accumulated),
        MarkdownParser.parse(accumulated),
      );
    }
  });

  test('frozen prefix blocks keep their instances across appends', () {
    final incremental = IncrementalMarkdownParse();
    final step1 = incremental.update(
      'First paragraph.\n\nSecond paragraph.\n\nThird paragraph.\n\n',
    );
    final step2 = incremental.update(
      'First paragraph.\n\nSecond paragraph.\n\nThird paragraph.\n\n'
      'Fourth paragraph.\n\n',
    );
    final step3 = incremental.update(
      'First paragraph.\n\nSecond paragraph.\n\nThird paragraph.\n\n'
      'Fourth paragraph.\n\nFifth paragraph still streaming',
    );
    // Blocks frozen by step 2 (everything behind the trailing margin)
    // keep their instances at step 3; the unstable tail re-parses.
    for (var i = 0; i < 2; i++) {
      expect(identical(step2[i], step3[i]), isTrue, reason: 'block $i');
    }
    expect(step3, MarkdownParser.parse(
      'First paragraph.\n\nSecond paragraph.\n\nThird paragraph.\n\n'
      'Fourth paragraph.\n\nFifth paragraph still streaming',
    ));
    expect(step1.length, 3);
    expect(step2.length, 4);
    expect(step3.length, 5);
  });

  test('identical input returns the cached result', () {
    final incremental = IncrementalMarkdownParse();
    final first = incremental.update('one\n\ntwo\n');
    final second = incremental.update('one\n\ntwo\n');
    expect(identical(first, second), isTrue);
  });

  test('a non-append change resets the frozen prefix', () {
    final incremental = IncrementalMarkdownParse();
    incremental.update('alpha\n\nbeta\n\ngamma\n');
    final reset = incremental.update('different text entirely\n');
    expect(reset, MarkdownParser.parse('different text entirely\n'));
    // After the reset, appends resume incrementally from the new base.
    final grown = incremental.update('different text entirely\nplus more\n');
    expect(grown, MarkdownParser.parse('different text entirely\nplus more\n'));
  });

  test('linesWithStarts matches LineSplitter on boundary shapes', () {
    final inputs = <String>[
      '',
      '\n',
      '\r',
      '\r\n',
      'a',
      'a\n',
      'a\r\nb\rc\nd',
      '\n\n\n',
      'a\n\nb',
      'no terminator at end',
    ];
    for (final input in inputs) {
      final (lines, starts) = MarkdownParser.linesWithStarts(input);
      expect(
        lines,
        const LineSplitter().convert(input),
        reason: 'line split mismatch for ${input.codeUnits}',
      );
      expect(starts.length, lines.length);
      for (var i = 0; i < lines.length; i++) {
        expect(
          input.substring(starts[i], starts[i] + lines[i].length),
          lines[i],
          reason: 'offset mismatch at line $i',
        );
      }
    }
  });

  test('parseSpanned blocks equal parse and spans tile the source', () {
    const document =
        '# Title\n\n'
        'paragraph one\ncontinuing\n\n'
        '- item\n- item two\n\n'
        '```sh\nls -la\n```\n\n'
        '| a | b |\n| --- | --- |\n| 1 | 2 |\n\n'
        '> quoted\n\nlast paragraph\n';
    final spanned = MarkdownParser.parseSpanned(document);
    expect(
      spanned.map((s) => s.block).toList(),
      MarkdownParser.parse(document),
    );
    for (var i = 0; i < spanned.length; i++) {
      final block = spanned[i];
      expect(block.start, lessThanOrEqualTo(block.end));
      expect(block.start, greaterThanOrEqualTo(0));
      expect(block.end, lessThanOrEqualTo(document.length));
      if (i > 0) {
        expect(
          spanned[i - 1].end,
          lessThanOrEqualTo(block.start),
          reason: 'spans must not overlap',
        );
      }
    }
  });
}
