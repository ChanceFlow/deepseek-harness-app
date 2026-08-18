import 'package:flutter_test/flutter_test.dart';

import 'package:app/ui/chat/markdown/markdown_parser.dart';

void main() {
  test('plain paragraph stays one block', () {
    final blocks = MarkdownParser.parse('just plain text');

    final paragraph = blocks.single as ParagraphBlock;
    expect(paragraph.inlines, <MarkdownInline>[const TextInline('just plain text')]);
  });

  test('blank lines split paragraphs', () {
    final blocks = MarkdownParser.parse('first\n\nsecond');

    expect(blocks, hasLength(2));
    expect(
      (blocks[0] as ParagraphBlock).inlines,
      <MarkdownInline>[const TextInline('first')],
    );
    expect(
      (blocks[1] as ParagraphBlock).inlines,
      <MarkdownInline>[const TextInline('second')],
    );
  });

  test('fenced code block keeps language and body', () {
    final blocks =
        MarkdownParser.parse('before\n\n```kotlin\nval a = 1\nval b = 2\n```\nafter');

    expect(blocks, hasLength(3));
    final code = blocks[1] as CodeBlock;
    expect(code.language, 'kotlin');
    expect(code.code, 'val a = 1\nval b = 2');
    expect(code.open, false);
    expect(
      (blocks[0] as ParagraphBlock).inlines,
      <MarkdownInline>[const TextInline('before')],
    );
    expect(
      (blocks[2] as ParagraphBlock).inlines,
      <MarkdownInline>[const TextInline('after')],
    );
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
        'run `gradlew test` with **full** *power* then see [docs](https://example.com)');

    expect(
      inlines,
      <MarkdownInline>[
        const TextInline('run '),
        const CodeInline('gradlew test'),
        const TextInline(' with '),
        const BoldInline(<MarkdownInline>[TextInline('full')]),
        const TextInline(' '),
        const ItalicInline(<MarkdownInline>[TextInline('power')]),
        const TextInline(' then see '),
        const LinkInline(label: 'docs', url: 'https://example.com'),
      ],
    );
  });

  test('unmatched markers degrade to plain text', () {
    final inlines = MarkdownParser.parseInlines('a * b ** c ` d');

    expect(inlines, <MarkdownInline>[const TextInline('a * b ** c ` d')]);
  });

  test('headings parse level and inline runs', () {
    final blocks = MarkdownParser.parse('## Title with `code`');

    final heading = blocks.single as HeadingBlock;
    expect(heading.level, 2);
    expect(
      heading.inlines,
      <MarkdownInline>[const TextInline('Title with '), const CodeInline('code')],
    );
  });

  test('consecutive bullets group into one list and inline emphasis holds', () {
    final blocks =
        MarkdownParser.parse('- first **bold** item\n- second item\n\nplain');

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
    expect(
      (blocks[1] as ParagraphBlock).inlines,
      <MarkdownInline>[const TextInline('plain')],
    );
  });

  test('indented bullets nest up to two levels', () {
    final blocks = MarkdownParser
        .parse('- top\n  - nested\n    - deeper flattens\n      - beyond flattens');

    final list = blocks.single as BulletListBlock;
    expect(list.items.map((entry) => entry.depth), <int>[0, 1, 2, 2]);
    expect((list.items[3].inlines.single as TextInline).text, 'beyond flattens');
  });

  test('quote lines fold into one block quote', () {
    final blocks = MarkdownParser.parse('> quoted **strong**\n> second line\n\nafter');

    final quote = blocks[0] as BlockQuoteBlock;
    expect(
      quote.inlines,
      <MarkdownInline>[
        const TextInline('quoted '),
        const BoldInline(<MarkdownInline>[TextInline('strong')]),
        const TextInline('\nsecond line'),
      ],
    );
    expect(
      (blocks[1] as ParagraphBlock).inlines,
      <MarkdownInline>[const TextInline('after')],
    );
  });

  test('nested bold keeps inner code span', () {
    final inlines = MarkdownParser.parseInlines('**outer `inner` outer**');

    expect(
      inlines,
      <MarkdownInline>[
        const BoldInline(<MarkdownInline>[
          TextInline('outer '),
          CodeInline('inner'),
          TextInline(' outer'),
        ]),
      ],
    );
  });

  test('bullet lines inside paragraphs are not emphasized', () {
    final inlines = MarkdownParser.parseInlines('2 * 3 = 6 and a_b_c stay');

    expect(inlines, <MarkdownInline>[const TextInline('2 * 3 = 6 and a_b_c stay')]);
  });

  test('pipe table parses header and body rows with inline runs', () {
    final blocks = MarkdownParser.parse(
        'intro\n\n| Name | Notes |\n| --- | --- |\n| `code` | **bold** |\n| plain | b |\n\nafter');

    expect(blocks, hasLength(3));
    final table = blocks[1] as TableBlock;
    expect(
      table.header,
      <List<MarkdownInline>>[
        <MarkdownInline>[const TextInline('Name')],
        <MarkdownInline>[const TextInline('Notes')],
      ],
    );
    expect(table.rows, hasLength(2));
    expect(table.rows[0][0], <MarkdownInline>[const CodeInline('code')]);
    expect(
      table.rows[0][1],
      <MarkdownInline>[const BoldInline(<MarkdownInline>[TextInline('bold')])],
    );
    expect(table.rows[1][0], <MarkdownInline>[const TextInline('plain')]);
    expect(
      (blocks[2] as ParagraphBlock).inlines,
      <MarkdownInline>[const TextInline('after')],
    );
  });

  test('pipe row without delimiter line stays a paragraph', () {
    final blocks = MarkdownParser.parse('a | b\nc | d');

    final paragraph = blocks.single as ParagraphBlock;
    expect((paragraph.inlines.single as TextInline).text, 'a | b\nc | d');
  });

  test('short table rows render with missing cells', () {
    final blocks = MarkdownParser.parse('| a | b |\n| --- | --- |\n| only-one');

    final table = blocks.single as TableBlock;
    expect(table.rows, hasLength(1));
    expect(table.rows.single, hasLength(1));
    expect(table.rows.single.single, <MarkdownInline>[const TextInline('only-one')]);
  });
}
