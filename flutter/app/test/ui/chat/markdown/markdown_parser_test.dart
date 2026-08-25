import 'package:flutter_test/flutter_test.dart';

import 'package:app/ui/chat/markdown/markdown_parser.dart';

void main() {
  test('plain paragraph stays one block', () {
    final blocks = MarkdownParser.parse('just plain text');

    final paragraph = blocks.single as ParagraphBlock;
    expect(paragraph.inlines, <MarkdownInline>[
      const TextInline('just plain text'),
    ]);
  });

  test('blank lines split paragraphs', () {
    final blocks = MarkdownParser.parse('first\n\nsecond');

    expect(blocks, hasLength(2));
    expect((blocks[0] as ParagraphBlock).inlines, <MarkdownInline>[
      const TextInline('first'),
    ]);
    expect((blocks[1] as ParagraphBlock).inlines, <MarkdownInline>[
      const TextInline('second'),
    ]);
  });

  test('a source wrap inside a paragraph folds to one space', () {
    final blocks = MarkdownParser.parse(
      'the dock stacks four strips\nabove the composer',
    );

    expect((blocks.single as ParagraphBlock).inlines, <MarkdownInline>[
      const TextInline('the dock stacks four strips above the composer'),
    ]);
  });

  test('a wrap between wide characters folds without a space', () {
    final blocks = MarkdownParser.parse('先把输入区封顶,\n再看待办条');

    expect((blocks.single as ParagraphBlock).inlines, <MarkdownInline>[
      const TextInline('先把输入区封顶,再看待办条'),
    ]);
  });

  test('two trailing spaces or a backslash keep the break', () {
    final spaces = MarkdownParser.parse('first  \nsecond');
    expect((spaces.single as ParagraphBlock).inlines, <MarkdownInline>[
      const TextInline('first\nsecond'),
    ]);

    final slash = MarkdownParser.parse('first\\\nsecond');
    expect((slash.single as ParagraphBlock).inlines, <MarkdownInline>[
      const TextInline('first\nsecond'),
    ]);
  });

  test('numbered lines group into one ordered list', () {
    final blocks = MarkdownParser.parse(
      '1. first **item**\n2) second item\n\nafter',
    );

    final list = blocks[0] as OrderedListBlock;
    expect(list.items, hasLength(2));
    expect(list.items[0].number, 1);
    expect(list.items[0].inlines, <MarkdownInline>[
      const TextInline('first '),
      const BoldInline(<MarkdownInline>[TextInline('item')]),
    ]);
    // The source's own numbers ride through: a list that starts at 2 is
    // not renumbered.
    expect(list.items[1].number, 2);
    expect(blocks[1], isA<ParagraphBlock>());
  });

  test('an indented line continues the item above it', () {
    final blocks = MarkdownParser.parse(
      '- a long item\n  wrapped by the source\n- second',
    );

    final list = blocks.single as BulletListBlock;
    expect(list.items, hasLength(2));
    expect(list.items[0].inlines, <MarkdownInline>[
      const TextInline('a long item wrapped by the source'),
    ]);
    expect(list.items[1].inlines, <MarkdownInline>[const TextInline('second')]);
  });

  test('switching marker kind closes the list before it', () {
    final blocks = MarkdownParser.parse('- bullet\n1. numbered');

    expect(blocks[0], isA<BulletListBlock>());
    expect(blocks[1], isA<OrderedListBlock>());
  });

  test('fenced code block keeps language and body', () {
    final blocks = MarkdownParser.parse(
      'before\n\n```kotlin\nval a = 1\nval b = 2\n```\nafter',
    );

    expect(blocks, hasLength(3));
    final code = blocks[1] as CodeBlock;
    expect(code.language, 'kotlin');
    expect(code.code, 'val a = 1\nval b = 2');
    expect(code.open, false);
    expect((blocks[0] as ParagraphBlock).inlines, <MarkdownInline>[
      const TextInline('before'),
    ]);
    expect((blocks[2] as ParagraphBlock).inlines, <MarkdownInline>[
      const TextInline('after'),
    ]);
  });

  test('unterminated fence renders open code block', () {
    final blocks = MarkdownParser.parse('```python\nprint(1)');

    final code = blocks.single as CodeBlock;
    expect(code.language, 'python');
    expect(code.code, 'print(1)');
    expect(code.open, isTrue);
  });

  test('inline code bold italic and link parse', () {
    final inlines = MarkdownParser.parseInlines(
      'run `gradlew test` with **full** *power* then see [docs](https://example.com)',
    );

    expect(inlines, <MarkdownInline>[
      const TextInline('run '),
      const CodeInline('gradlew test'),
      const TextInline(' with '),
      const BoldInline(<MarkdownInline>[TextInline('full')]),
      const TextInline(' '),
      const ItalicInline(<MarkdownInline>[TextInline('power')]),
      const TextInline(' then see '),
      const LinkInline(label: 'docs', url: 'https://example.com'),
    ]);
  });

  test('unmatched markers degrade to plain text', () {
    final inlines = MarkdownParser.parseInlines('a * b ** c ` d');

    expect(inlines, <MarkdownInline>[const TextInline('a * b ** c ` d')]);
  });

  test('headings parse level and inline runs', () {
    final blocks = MarkdownParser.parse('## Title with `code`');

    final heading = blocks.single as HeadingBlock;
    expect(heading.level, 2);
    expect(heading.inlines, <MarkdownInline>[
      const TextInline('Title with '),
      const CodeInline('code'),
    ]);
  });

  test('consecutive bullets group into one list and inline emphasis holds', () {
    final blocks = MarkdownParser.parse(
      '- first **bold** item\n- second item\n\nplain',
    );

    final list = blocks[0] as BulletListBlock;
    expect(list.items, hasLength(2));
    expect(
      list.items[0],
      const BulletEntry(
        inlines: <MarkdownInline>[
          TextInline('first '),
          BoldInline(<MarkdownInline>[TextInline('bold')]),
          TextInline(' item'),
        ],
        depth: 0,
      ),
    );
    expect(
      list.items[1],
      const BulletEntry(
        inlines: <MarkdownInline>[TextInline('second item')],
        depth: 0,
      ),
    );
    expect((blocks[1] as ParagraphBlock).inlines, <MarkdownInline>[
      const TextInline('plain'),
    ]);
  });

  test('indented bullets nest up to two levels', () {
    final blocks = MarkdownParser.parse(
      '- top\n  - nested\n    - deeper flattens\n      - beyond flattens',
    );

    final list = blocks.single as BulletListBlock;
    expect(list.items.map((entry) => entry.depth), <int>[0, 1, 2, 2]);
    expect(
      (list.items[3].inlines.single as TextInline).text,
      'beyond flattens',
    );
  });

  test('quote lines fold into one block quote', () {
    final blocks = MarkdownParser.parse(
      '> quoted **strong**\n> second line\n\nafter',
    );

    final quote = blocks[0] as BlockQuoteBlock;
    expect(quote.inlines, <MarkdownInline>[
      const TextInline('quoted '),
      const BoldInline(<MarkdownInline>[TextInline('strong')]),
      const TextInline(' second line'),
    ]);
    expect((blocks[1] as ParagraphBlock).inlines, <MarkdownInline>[
      const TextInline('after'),
    ]);
  });

  test('nested bold keeps inner code span', () {
    final inlines = MarkdownParser.parseInlines('**outer `inner` outer**');

    expect(inlines, <MarkdownInline>[
      const BoldInline(<MarkdownInline>[
        TextInline('outer '),
        CodeInline('inner'),
        TextInline(' outer'),
      ]),
    ]);
  });

  test('bullet lines inside paragraphs are not emphasized', () {
    final inlines = MarkdownParser.parseInlines('2 * 3 = 6 and a_b_c stay');

    expect(inlines, <MarkdownInline>[
      const TextInline('2 * 3 = 6 and a_b_c stay'),
    ]);
  });

  test('pipe table parses header and body rows with inline runs', () {
    final blocks = MarkdownParser.parse(
      'intro\n\n| Name | Notes |\n| --- | --- |\n| `code` | **bold** |\n| plain | b |\n\nafter',
    );

    expect(blocks, hasLength(3));
    final table = blocks[1] as TableBlock;
    expect(table.header, <List<MarkdownInline>>[
      <MarkdownInline>[const TextInline('Name')],
      <MarkdownInline>[const TextInline('Notes')],
    ]);
    expect(table.rows, hasLength(2));
    expect(table.rows[0][0], <MarkdownInline>[const CodeInline('code')]);
    expect(table.rows[0][1], <MarkdownInline>[
      const BoldInline(<MarkdownInline>[TextInline('bold')]),
    ]);
    expect(table.rows[1][0], <MarkdownInline>[const TextInline('plain')]);
    expect((blocks[2] as ParagraphBlock).inlines, <MarkdownInline>[
      const TextInline('after'),
    ]);
  });

  test('pipe row without delimiter line stays a paragraph', () {
    final blocks = MarkdownParser.parse('a | b\nc | d');

    final paragraph = blocks.single as ParagraphBlock;
    expect((paragraph.inlines.single as TextInline).text, 'a | b c | d');
  });

  test('short table rows render with missing cells', () {
    final blocks = MarkdownParser.parse('| a | b |\n| --- | --- |\n| only-one');

    final table = blocks.single as TableBlock;
    expect(table.rows, hasLength(1));
    expect(table.rows.single, hasLength(1));
    expect(table.rows.single.single, <MarkdownInline>[
      const TextInline('only-one'),
    ]);
  });

  test('bare http(s) URLs autolink at word boundaries', () {
    final blocks = MarkdownParser.parse(
      'See https://example.com/docs for details.',
    );
    final paragraph = blocks.single as ParagraphBlock;
    final link = paragraph.inlines.whereType<LinkInline>().single;
    expect(link.url, 'https://example.com/docs');
    expect(link.label, 'https://example.com/docs');

    // www. prefixes open http:// + the raw span, like the web reference.
    final www = MarkdownParser.parse('go to www.example.com now');
    final wwwLink = (www.single as ParagraphBlock).inlines
        .whereType<LinkInline>()
        .single;
    expect(wwwLink.url, 'http://www.example.com');
    expect(wwwLink.label, 'www.example.com');
  });

  test('URLs glued to CJK text autolink', () {
    final blocks = MarkdownParser.parse('详见https://example.com/a');
    final link = (blocks.single as ParagraphBlock).inlines
        .whereType<LinkInline>()
        .single;
    expect(link.url, 'https://example.com/a');
    expect(link.label, 'https://example.com/a');

    // CJK closing punctuation is span material, not a terminator.
    final wrapped = MarkdownParser.parse('（见https://example.com）ok');
    final wrappedLink = (wrapped.single as ParagraphBlock).inlines
        .whereType<LinkInline>()
        .single;
    expect(wrappedLink.url, 'https://example.com）ok');
  });

  test('digits and punctuation may precede an http(s) URL', () {
    final digits = MarkdownParser.parse('第2条https://example.com');
    expect(
      (digits.single as ParagraphBlock).inlines
          .whereType<LinkInline>()
          .single
          .url,
      'https://example.com',
    );

    final underscore = MarkdownParser.parse('see_https://example.com');
    expect(
      (underscore.single as ParagraphBlock).inlines
          .whereType<LinkInline>()
          .single
          .url,
      'https://example.com',
    );
  });

  test('www requires a start, whitespace, or punctuation predecessor', () {
    final glued = MarkdownParser.parse('详见www.example.com');
    expect(
      (glued.single as ParagraphBlock).inlines.whereType<LinkInline>(),
      isEmpty,
    );

    final wrapped = MarkdownParser.parse('（www.example.com）');
    expect(
      (wrapped.single as ParagraphBlock).inlines
          .whereType<LinkInline>()
          .single
          .url,
      'http://www.example.com）',
    );
  });

  test('trailing punctuation stays out of the autolink', () {
    final blocks = MarkdownParser.parse(
      'docs at https://example.com/a, then https://example.com/b.',
    );
    final links = (blocks.single as ParagraphBlock).inlines
        .whereType<LinkInline>();
    expect(links.map((l) => l.url).toList(), [
      'https://example.com/a',
      'https://example.com/b',
    ]);

    final trimmed = MarkdownParser.parse(
      'see https://example.com_"*]~ end and https://example.com/x&quot; now',
    );
    expect(
      (trimmed.single as ParagraphBlock).inlines
          .whereType<LinkInline>()
          .map((l) => l.url)
          .toList(),
      ['https://example.com', 'https://example.com/x'],
    );

    // Full-width punctuation is not in the ASCII trail set.
    final fullWidth = MarkdownParser.parse('去 https://example.com，看看');
    expect(
      (fullWidth.single as ParagraphBlock).inlines
          .whereType<LinkInline>()
          .single
          .url,
      'https://example.com，看看',
    );
  });

  test('balanced parens stay in, unbalanced close trims out', () {
    final keep = MarkdownParser.parse('ref (https://example.com/(a)) end');
    final keepLink = (keep.single as ParagraphBlock).inlines
        .whereType<LinkInline>()
        .single;
    expect(keepLink.url, 'https://example.com/(a)');

    final trim = MarkdownParser.parse('ref (https://example.com/a) end');
    final trimLink = (trim.single as ParagraphBlock).inlines
        .whereType<LinkInline>()
        .single;
    expect(trimLink.url, 'https://example.com/a');
  });

  test('mid-word scheme text does not autolink', () {
    final blocks = MarkdownParser.parse('foohttps://example.com bar');
    final inlines = (blocks.single as ParagraphBlock).inlines;
    expect(inlines.whereType<LinkInline>(), isEmpty);
  });

  test('underscore in the last two domain segments stays text', () {
    final rejected = MarkdownParser.parse('go https://foo_bar.com now');
    expect(
      (rejected.single as ParagraphBlock).inlines.whereType<LinkInline>(),
      isEmpty,
    );

    final deeper = MarkdownParser.parse('go https://foo_bar.example.com now');
    expect(
      (deeper.single as ParagraphBlock).inlines
          .whereType<LinkInline>()
          .single
          .url,
      'https://foo_bar.example.com',
    );

    final path = MarkdownParser.parse('go https://example.com/a_b now');
    expect(
      (path.single as ParagraphBlock).inlines
          .whereType<LinkInline>()
          .single
          .url,
      'https://example.com/a_b',
    );
  });

  test('a scheme must open a domain', () {
    final slashes = MarkdownParser.parse('see https:///foo');
    expect(
      (slashes.single as ParagraphBlock).inlines.whereType<LinkInline>(),
      isEmpty,
    );

    final fullWidth = MarkdownParser.parse('see https://，foo');
    expect(
      (fullWidth.single as ParagraphBlock).inlines.whereType<LinkInline>(),
      isEmpty,
    );
  });

  test('schemes match case-insensitively', () {
    final blocks = MarkdownParser.parse('see HTTP://EXAMPLE.COM');
    final link = (blocks.single as ParagraphBlock).inlines
        .whereType<LinkInline>()
        .single;
    expect(link.url, 'HTTP://EXAMPLE.COM');
    expect(link.label, 'HTTP://EXAMPLE.COM');
  });

  test('bare scheme alone is not a link', () {
    final blocks = MarkdownParser.parse('visit www. sometime');
    expect(
      (blocks.single as ParagraphBlock).inlines.whereType<LinkInline>(),
      isEmpty,
    );
  });

  test('an unclosed bracket does not eat a later link', () {
    final blocks = MarkdownParser.parse(
      '[see https://example.com] and [x](https://y.com)',
    );
    final links = (blocks.single as ParagraphBlock).inlines
        .whereType<LinkInline>()
        .toList();
    expect(links, hasLength(2));
    expect(links[0].url, 'https://example.com');
    expect(links[1].label, 'x');
    expect(links[1].url, 'https://y.com');
  });

  test('link labels close at the first depth-zero bracket', () {
    final inlines = MarkdownParser.parseInlines('[foo [bar]](baz)');
    expect(inlines.whereType<LinkInline>().single.label, 'foo [bar]');

    final plain = MarkdownParser.parseInlines('[x] y [z](w)');
    final links = plain.whereType<LinkInline>().toList();
    expect(links, hasLength(1));
    expect(links.single.label, 'z');
    expect(links.single.url, 'w');
  });
}
