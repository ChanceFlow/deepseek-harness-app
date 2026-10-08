/// Markdown-to-plain-text projection for a card's one-line summary.
///
/// The port of the reference's `extractMarkdownPlainText`
/// (`ui-primitives/src/markdown/plain-text.ts:106-118`), which parses the same
/// GFM grammar the renderer draws and then strips exactly the markup it would
/// paint: raw HTML stays literal, links keep their labels, images keep alt
/// text, code keeps its source. It reads the app's own
/// [MarkdownParser] rather than a second grammar, so a summary can never show
/// markup the transcript below it rendered away.
///
/// Two boundaries are ported because the pin's plan review uses both
/// (`PlanReviewPanel.tsx:48-51`): `first-line` for the card's title and
/// `first-paragraph` for its description.
library;

import 'markdown_parser.dart';

/// The projection's boundary, the pin's `MarkdownPlainTextMode`.
enum MarkdownPlainTextMode {
  /// The whole document, one block per line group.
  all,

  /// The first non-empty line of [MarkdownPlainTextMode.all].
  firstLine,

  /// The first paragraph's text, falling back to the first line.
  firstParagraph,
}

/// Projects [markdown] onto plain text at [mode]'s boundary.
String extractMarkdownPlainText(
  String markdown, {
  MarkdownPlainTextMode mode = MarkdownPlainTextMode.all,
}) {
  final blocks = MarkdownParser.parse(markdown);
  final all = _fullText(blocks);
  return switch (mode) {
    MarkdownPlainTextMode.all => all,
    MarkdownPlainTextMode.firstLine => _firstNonEmptyLine(all),
    MarkdownPlainTextMode.firstParagraph =>
      _firstParagraph(blocks) ?? _firstNonEmptyLine(all),
  };
}

/// A plan review's one-line pair: the document's first line as the title and
/// its first paragraph as the description; the description is empty when it is
/// the title itself (`PlanReviewPanel.tsx:48-51`).
({String title, String description}) planSummary(String markdown) {
  final title = extractMarkdownPlainText(
    markdown,
    mode: MarkdownPlainTextMode.firstLine,
  );
  final paragraph = extractMarkdownPlainText(
    markdown,
    mode: MarkdownPlainTextMode.firstParagraph,
  );
  return (title: title, description: paragraph == title ? '' : paragraph);
}

/// The first non-empty line, the pin's `first-line`
/// (`plain-text.ts:114`).
String _firstNonEmptyLine(String text) {
  for (final line in text.split('\n')) {
    if (line.isNotEmpty) return line;
  }
  return '';
}

/// The first paragraph block's text, the pin's `findFirstParagraph`
/// (`plain-text.ts:84-91`).
String? _firstParagraph(List<MarkdownBlock> blocks) {
  for (final block in blocks) {
    if (block is ParagraphBlock) {
      final text = _compact(_inlineText(block.inlines));
      if (text.isNotEmpty) return text;
    }
  }
  return null;
}

/// One block's text, the pin's `blockText` (`plain-text.ts:37-66`).
String _blockText(MarkdownBlock block) => switch (block) {
  CodeBlock(:final code) => code.trim(),
  HeadingBlock(:final inlines) => _compact(_inlineText(inlines)),
  ParagraphBlock(:final inlines) => _compact(_inlineText(inlines)),
  BlockQuoteBlock(:final inlines) => _compact(_inlineText(inlines)),
  BulletListBlock(:final items) =>
    items
        .map((item) => _compact(_inlineText(item.inlines)))
        .where((text) => text.isNotEmpty)
        .join('\n'),
  OrderedListBlock(:final items) =>
    items
        .map((item) => _compact(_inlineText(item.inlines)))
        .where((text) => text.isNotEmpty)
        .join('\n'),
  TableBlock(:final header, :final rows) => <String>[
    header.map(_compactCell).join('\t'),
    for (final row in rows) row.map(_compactCell).join('\t'),
  ].join('\n'),
};

String _compactCell(List<MarkdownInline> inlines) =>
    _compact(_inlineText(inlines));

/// One inline run's text, the pin's `inlineText` (`plain-text.ts:21-35`).
String _inlineText(List<MarkdownInline> inlines) => inlines
    .map(
      (inline) => switch (inline) {
        TextInline(:final text) => text,
        CodeInline(:final code) => code,
        BoldInline(:final inlines) => _inlineText(inlines),
        ItalicInline(:final inlines) => _inlineText(inlines),
        LinkInline(:final label) => label,
      },
    )
    .join();

/// Collapse runs of whitespace, the pin's `compactInline`
/// (`plain-text.ts:32-34`).
String _compact(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

/// The document's whole text, the pin's `fullText` (`plain-text.ts:93-100`).
String _fullText(List<MarkdownBlock> blocks) => blocks
    .map(_blockText)
    .where((text) => text.isNotEmpty)
    .join('\n\n')
    .split('\n')
    .map((line) => line.trim())
    .join('\n')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();
