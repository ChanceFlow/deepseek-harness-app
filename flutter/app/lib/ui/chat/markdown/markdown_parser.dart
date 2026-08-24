/// Minimal markdown vocabulary for assistant/user message bodies.
///
/// Scope: fenced code blocks, headings, bullet and ordered lists, block
/// quotes, GFM pipe tables, and paragraphs with inline code, bold, italic,
/// links, and GFM bare-URL autolinks. A single newline inside a block is a
/// soft wrap and folds away, so a body wrapped at 80 columns reflows to the
/// phone's column width. The parser is pure Dart so plain tests pin its
/// behavior; the widget layer owns every style decision.
library;

import 'unicode_punct.dart';

sealed class MarkdownBlock {
  const MarkdownBlock();
}

/// One top-level [MarkdownBlock] with its source span: [start] inclusive
/// and [end] exclusive, both character offsets into the parsed text. The
/// span is what lets a streaming render freeze every block behind the
/// unstable tail and re-parse only the remainder.
final class SpannedMarkdownBlock {
  const SpannedMarkdownBlock({
    required this.block,
    required this.start,
    required this.end,
  });

  final MarkdownBlock block;
  final int start;
  final int end;
}

final class CodeBlock extends MarkdownBlock {
  const CodeBlock({
    required this.language,
    required this.code,
    this.open = false,
  });

  final String? language;
  final String code;

  /// True while a streaming body has not closed the fence yet.
  final bool open;

  @override
  bool operator ==(Object other) =>
      other is CodeBlock &&
      other.language == language &&
      other.code == code &&
      other.open == open;

  @override
  int get hashCode => Object.hash(language, code, open);
}

final class HeadingBlock extends MarkdownBlock {
  const HeadingBlock({required this.level, required this.inlines});

  final int level;
  final List<MarkdownInline> inlines;

  @override
  bool operator ==(Object other) =>
      other is HeadingBlock &&
      other.level == level &&
      _listEquals(other.inlines, inlines);

  @override
  int get hashCode => Object.hash(level, Object.hashAll(inlines));
}

/// One bullet row; depth 0 is top level, each two-space indent adds one.
final class BulletEntry {
  const BulletEntry({required this.inlines, required this.depth});

  final List<MarkdownInline> inlines;
  final int depth;

  @override
  bool operator ==(Object other) =>
      other is BulletEntry &&
      other.depth == depth &&
      _listEquals(other.inlines, inlines);

  @override
  int get hashCode => Object.hash(depth, Object.hashAll(inlines));
}

final class BulletListBlock extends MarkdownBlock {
  const BulletListBlock({required this.items});

  final List<BulletEntry> items;

  @override
  bool operator ==(Object other) =>
      other is BulletListBlock && _listEquals(other.items, items);

  @override
  int get hashCode => Object.hashAll(items);
}

/// One numbered row. [number] is the marker the source wrote, so a list
/// that starts at 3 renders from 3; the renderer never renumbers.
final class OrderedEntry {
  const OrderedEntry({
    required this.inlines,
    required this.depth,
    required this.number,
  });

  final List<MarkdownInline> inlines;
  final int depth;
  final int number;

  @override
  bool operator ==(Object other) =>
      other is OrderedEntry &&
      other.depth == depth &&
      other.number == number &&
      _listEquals(other.inlines, inlines);

  @override
  int get hashCode => Object.hash(depth, number, Object.hashAll(inlines));
}

final class OrderedListBlock extends MarkdownBlock {
  const OrderedListBlock({required this.items});

  final List<OrderedEntry> items;

  @override
  bool operator ==(Object other) =>
      other is OrderedListBlock && _listEquals(other.items, items);

  @override
  int get hashCode => Object.hashAll(items);
}

/// `>`-prefixed consecutive lines; the markers drop, inlines remain.
final class BlockQuoteBlock extends MarkdownBlock {
  const BlockQuoteBlock({required this.inlines});

  final List<MarkdownInline> inlines;

  @override
  bool operator ==(Object other) =>
      other is BlockQuoteBlock && _listEquals(other.inlines, inlines);

  @override
  int get hashCode => Object.hashAll(inlines);
}

/// GFM pipe table; column count follows the header, short rows pad empty.
final class TableBlock extends MarkdownBlock {
  const TableBlock({required this.header, required this.rows});

  final List<List<MarkdownInline>> header;
  final List<List<List<MarkdownInline>>> rows;

  @override
  bool operator ==(Object other) =>
      other is TableBlock &&
      _deepEquals(other.header, header) &&
      _deepDeepEquals(other.rows, rows);

  @override
  int get hashCode => Object.hashAll(header.expand((cell) => cell));
}

final class ParagraphBlock extends MarkdownBlock {
  const ParagraphBlock({required this.inlines});

  final List<MarkdownInline> inlines;

  @override
  bool operator ==(Object other) =>
      other is ParagraphBlock && _listEquals(other.inlines, inlines);

  @override
  int get hashCode => Object.hashAll(inlines);
}

sealed class MarkdownInline {
  const MarkdownInline();
}

final class TextInline extends MarkdownInline {
  const TextInline(this.text);

  final String text;

  @override
  bool operator ==(Object other) => other is TextInline && other.text == text;

  @override
  int get hashCode => text.hashCode;
}

final class CodeInline extends MarkdownInline {
  const CodeInline(this.code);

  final String code;

  @override
  bool operator ==(Object other) => other is CodeInline && other.code == code;

  @override
  int get hashCode => code.hashCode;
}

final class BoldInline extends MarkdownInline {
  const BoldInline(this.inlines);

  final List<MarkdownInline> inlines;

  @override
  bool operator ==(Object other) =>
      other is BoldInline && _listEquals(other.inlines, inlines);

  @override
  int get hashCode => Object.hashAll(inlines);
}

final class ItalicInline extends MarkdownInline {
  const ItalicInline(this.inlines);

  final List<MarkdownInline> inlines;

  @override
  bool operator ==(Object other) =>
      other is ItalicInline && _listEquals(other.inlines, inlines);

  @override
  int get hashCode => Object.hashAll(inlines);
}

final class LinkInline extends MarkdownInline {
  const LinkInline({required this.label, required this.url});

  final String label;
  final String url;

  @override
  bool operator ==(Object other) =>
      other is LinkInline && other.label == label && other.url == url;

  @override
  int get hashCode => Object.hash(label, url);
}

abstract final class MarkdownParser {
  /// Nesting levels the MVP renders; deeper indents flatten onto level two.
  static const int maxBulletDepth = 2;

  static final RegExp _fence = RegExp(r'^(`{3,})\s*([A-Za-z0-9_+-]*)\s*$');
  static final RegExp _bullet = RegExp(r'^(\s*)[*-] (\S.*)$');
  static final RegExp _ordered = RegExp(r'^(\s*)(\d{1,9})[.)] (\S.*)$');
  static final RegExp _heading = RegExp(r'^(#{1,6}) (.*)$');
  static final RegExp _quote = RegExp(r'^>\s?(.*)$');
  static final RegExp _delimiterCell = RegExp(r'^:?-+:?$');

  /// Parse one message body into ordered blocks.
  static List<MarkdownBlock> parse(String text) =>
      parseSpanned(text)
          .map((spanned) => spanned.block)
          .toList(growable: false);

  /// Split [text] into lines with each line's starting character offset,
  /// with the same line-boundary semantics as [LineSplitter] (`\n`, `\r\n`,
  /// and a lone `\r` end a line; a trailing terminator adds no empty line).
  static (List<String>, List<int>) linesWithStarts(String text) {
    final lines = <String>[];
    final starts = <int>[];
    var start = 0;
    var index = 0;
    while (index < text.length) {
      final char = text.codeUnitAt(index);
      if (char == 0x0A || char == 0x0D) {
        lines.add(text.substring(start, index));
        starts.add(start);
        if (char == 0x0D &&
            index + 1 < text.length &&
            text.codeUnitAt(index + 1) == 0x0A) {
          index++;
        }
        index++;
        start = index;
      } else {
        index++;
      }
    }
    if (start < text.length) {
      lines.add(text.substring(start));
      starts.add(start);
    }
    return (lines, starts);
  }

  /// Parse one message body into ordered blocks, each with the character
  /// span of its source lines. Spans tile the source: a block's [SpannedMarkdownBlock.end]
  /// is where the next block (or the trailing region) begins, so cutting a
  /// stream at a frozen block's end re-parses exactly the remainder.
  static List<SpannedMarkdownBlock> parseSpanned(String text) {
    final blocks = <SpannedMarkdownBlock>[];
    final (lines, lineStarts) = linesWithStarts(text);
    var index = 0;

    // Offset of the first line of the block being accumulated, for
    // flush-time emission (paragraphs and lists outlive their lines).
    var paragraphStart = 0;
    var listStart = 0;

    var paragraph = <String>[];
    var bullets = <BulletEntry>[];
    var ordered = <OrderedEntry>[];
    // Raw source of the item currently open, so an indented continuation
    // line folds into it before its inlines are parsed.
    var itemLines = <String>[];

    // Character offset of the first unconsumed line: the cursor's block
    // boundary (the end of whatever is emitted at this moment).
    int boundary() =>
        index < lines.length ? lineStarts[index] : text.length;

    void flushParagraph() {
      if (paragraph.isNotEmpty) {
        blocks.add(
          SpannedMarkdownBlock(
            block: ParagraphBlock(
              inlines: parseInlines(foldLines(paragraph)),
            ),
            start: paragraphStart,
            end: boundary(),
          ),
        );
        paragraph = <String>[];
      }
    }

    void closeItem() {
      if (itemLines.isEmpty) return;
      final inlines = parseInlines(foldLines(itemLines));
      if (bullets.isNotEmpty) {
        final open = bullets.removeLast();
        bullets.add(BulletEntry(inlines: inlines, depth: open.depth));
      } else if (ordered.isNotEmpty) {
        final open = ordered.removeLast();
        ordered.add(
          OrderedEntry(
            inlines: inlines,
            depth: open.depth,
            number: open.number,
          ),
        );
      }
      itemLines = <String>[];
    }

    void flushBullets() {
      closeItem();
      if (bullets.isNotEmpty) {
        blocks.add(
          SpannedMarkdownBlock(
            block: BulletListBlock(items: List.of(bullets)),
            start: listStart,
            end: boundary(),
          ),
        );
        bullets = <BulletEntry>[];
      }
      if (ordered.isNotEmpty) {
        blocks.add(
          SpannedMarkdownBlock(
            block: OrderedListBlock(items: List.of(ordered)),
            start: listStart,
            end: boundary(),
          ),
        );
        ordered = <OrderedEntry>[];
      }
    }

    void openListLine() {
      if (bullets.isEmpty && ordered.isEmpty) listStart = lineStarts[index];
    }

    while (index < lines.length) {
      final line = lines[index];
      final fenceMatch = _fence.firstMatch(line);
      if (fenceMatch != null) {
        flushParagraph();
        flushBullets();
        final start = lineStarts[index];
        final marker = fenceMatch.group(1)!;
        final language = fenceMatch.group(2)!.isEmpty
            ? null
            : fenceMatch.group(2);
        final code = StringBuffer();
        var closed = false;
        index++;
        while (index < lines.length) {
          final candidate = lines[index];
          if (candidate.trimRight().startsWith(marker) &&
              candidate.trim() == marker) {
            closed = true;
            index++;
            break;
          }
          if (code.isNotEmpty) code.write('\n');
          code.write(candidate);
          index++;
        }
        blocks.add(
          SpannedMarkdownBlock(
            block: CodeBlock(
              language: language,
              code: code.toString(),
              open: !closed,
            ),
            start: start,
            end: boundary(),
          ),
        );
        continue;
      }

      if (line.trim().isEmpty) {
        flushParagraph();
        flushBullets();
        index++;
        continue;
      }

      if (_isTableStart(lines, index)) {
        flushParagraph();
        flushBullets();
        final start = lineStarts[index];
        final header = _splitTableRow(line);
        index += 2;
        final rows = <List<List<MarkdownInline>>>[];
        while (index < lines.length &&
            lines[index].contains('|') &&
            lines[index].trim().isNotEmpty) {
          rows.add(_splitTableRow(lines[index]));
          index++;
        }
        blocks.add(
          SpannedMarkdownBlock(
            block: TableBlock(header: header, rows: rows),
            start: start,
            end: boundary(),
          ),
        );
        continue;
      }

      final quoteStart = _quote.firstMatch(line);
      if (quoteStart != null) {
        flushParagraph();
        flushBullets();
        final start = lineStarts[index];
        final quoted = <String>[quoteStart.group(1)!];
        index++;
        while (index < lines.length) {
          final nextQuote = _quote.firstMatch(lines[index]);
          if (nextQuote == null) break;
          quoted.add(nextQuote.group(1)!);
          index++;
        }
        blocks.add(
          SpannedMarkdownBlock(
            block: BlockQuoteBlock(inlines: parseInlines(foldLines(quoted))),
            start: start,
            end: boundary(),
          ),
        );
        continue;
      }

      final headingMatch = _heading.firstMatch(line);
      if (headingMatch != null) {
        flushParagraph();
        flushBullets();
        final start = lineStarts[index];
        final level = headingMatch.group(1)!.length;
        final inlines = parseInlines(headingMatch.group(2)!);
        index++;
        blocks.add(
          SpannedMarkdownBlock(
            block: HeadingBlock(level: level, inlines: inlines),
            start: start,
            end: boundary(),
          ),
        );
        continue;
      }

      final bulletMatch = _bullet.firstMatch(line);
      if (bulletMatch != null) {
        flushParagraph();
        if (ordered.isNotEmpty) flushBullets();
        closeItem();
        openListLine();
        final indent = ' '.allMatches(bulletMatch.group(1)!).length;
        bullets.add(
          BulletEntry(
            inlines: const <MarkdownInline>[],
            depth: (indent ~/ 2) > maxBulletDepth
                ? maxBulletDepth
                : indent ~/ 2,
          ),
        );
        itemLines.add(bulletMatch.group(2)!);
        index++;
        continue;
      }

      final orderedMatch = _ordered.firstMatch(line);
      if (orderedMatch != null) {
        flushParagraph();
        if (bullets.isNotEmpty) flushBullets();
        closeItem();
        openListLine();
        final indent = ' '.allMatches(orderedMatch.group(1)!).length;
        ordered.add(
          OrderedEntry(
            inlines: const <MarkdownInline>[],
            depth: (indent ~/ 2) > maxBulletDepth
                ? maxBulletDepth
                : indent ~/ 2,
            number: int.parse(orderedMatch.group(2)!),
          ),
        );
        itemLines.add(orderedMatch.group(3)!);
        index++;
        continue;
      }

      // An indented line under an open item is that item's own wrapped
      // text, not a new paragraph: source wrapping must not split a list.
      if (itemLines.isNotEmpty && line.startsWith('  ')) {
        itemLines.add(line.trimLeft());
        index++;
        continue;
      }

      flushBullets();
      if (paragraph.isEmpty) paragraphStart = lineStarts[index];
      paragraph.add(line);
      index++;
    }
    flushParagraph();
    flushBullets();
    return blocks;
  }

  /// Folds the source lines of one block into its text. A single newline is
  /// a soft wrap the author's editor made, so it joins with a space — or
  /// with nothing between two wide (CJK) characters, where a space would be
  /// a visible defect. A line ending in two spaces or a backslash keeps its
  /// break.
  static String foldLines(List<String> lines) {
    final buffer = StringBuffer();
    for (var i = 0; i < lines.length; i++) {
      final raw = lines[i];
      var body = raw.trimRight();
      final hardBreak = raw.endsWith('  ') || body.endsWith(r'\');
      if (body.endsWith(r'\')) body = body.substring(0, body.length - 1);
      if (i > 0) {
        final previous = buffer.isEmpty ? '' : buffer.toString();
        if (previous.endsWith('\n')) {
          // The previous line already wrote its break.
        } else if (previous.isEmpty ||
            body.isEmpty ||
            _joinsWithoutSpace(previous, body)) {
          // Two wide characters meet: no space between them.
        } else {
          buffer.write(' ');
        }
      }
      buffer.write(body);
      if (hardBreak && i < lines.length - 1) buffer.write('\n');
    }
    return buffer.toString();
  }

  /// True when either side of a folded line boundary is a wide character.
  /// CJK ideographs, kana, and hangul carry no inter-word space, and a
  /// space injected at the wrap point is visible in a way it never is
  /// between Latin words. One wide side is enough: CJK prose routinely
  /// runs half-width punctuation, so `封顶,` ending a line must still join
  /// its successor tight.
  static bool _joinsWithoutSpace(String previous, String next) {
    if (previous.isEmpty || next.isEmpty) return false;
    return _isWide(previous.runes.last) || _isWide(next.runes.first);
  }

  static bool _isWide(int rune) {
    return (rune >= 0x1100 && rune <= 0x11FF) ||
        (rune >= 0x2E80 && rune <= 0x303F) ||
        (rune >= 0x3040 && rune <= 0x33FF) ||
        (rune >= 0x3400 && rune <= 0x4DBF) ||
        (rune >= 0x4E00 && rune <= 0x9FFF) ||
        (rune >= 0xA960 && rune <= 0xA97F) ||
        (rune >= 0xAC00 && rune <= 0xD7FF) ||
        (rune >= 0xF900 && rune <= 0xFAFF) ||
        (rune >= 0xFE10 && rune <= 0xFE6F) ||
        (rune >= 0xFF00 && rune <= 0xFF60) ||
        (rune >= 0xFFE0 && rune <= 0xFFE6) ||
        (rune >= 0x20000 && rune <= 0x3FFFD);
  }

  /// Bare-URL autolink rules follow the dsh web reference's GFM
  /// autolink-literal stack (micromark's tokenizer plus
  /// mdast-util-gfm-autolink-literal's text transform):
  ///
  /// - `http(s)://` links unless an ASCII letter immediately precedes, so a
  ///   URL glued to CJK text (`详见https://…`) links while `foohttps://…`
  ///   stays text.
  /// - `www.` links only when preceded by start of text, whitespace, or a
  ///   punctuation/symbol character, and opens `http://` + the raw span.
  /// - The span runs to whitespace, keeping balanced parentheses; a run of
  ///   trailing ASCII punctuation (`!"'&*),.:;<=>?_]~` groups, `&word;`
  ///   entities, `]`) that reaches the end is trimmed. Full-width
  ///   punctuation is span material, not a terminator.
  /// - A domain whose last two non-empty dot segments carry `_` (e.g.
  ///   `https://foo_bar.com`) is rejected; path underscores are fine.
  /// - A bare `www.` with nothing behind it is not a link.
  static ({int end, String url})? _scanAutolink(String text, int index) {
    var isWww = false;
    var schemeLength = 0;
    if (_startsWithIgnoreCase(text, index, 'www.')) {
      isWww = true;
      schemeLength = 4;
    } else if (_startsWithIgnoreCase(text, index, 'https://')) {
      schemeLength = 8;
    } else if (_startsWithIgnoreCase(text, index, 'http://')) {
      schemeLength = 7;
    }
    if (schemeLength == 0) return null;

    if (index > 0) {
      final previous = text.codeUnitAt(index - 1);
      final allowed = isWww
          ? isPunctOrSymbol(previous) || _isUrlWhitespace(previous)
          : !_isAsciiLetter(previous);
      if (!allowed) return null;
    }

    // `www.` is domain material — parens and trail logic apply from the
    // first `w`. An `http(s)://` body must start with a non-punctuation,
    // non-whitespace character (`https:///x` and `https://，x` stay text).
    final bodyStart = isWww ? index : index + schemeLength;
    if (!isWww) {
      if (bodyStart >= text.length) return null;
      final first = text.codeUnitAt(bodyStart);
      if (_isUrlWhitespace(first) ||
          first < 0x20 ||
          first == 0x7F ||
          isPunctOrSymbol(first)) {
        return null;
      }
    }

    if (_domainHasTrailingUnderscore(text, bodyStart)) return null;

    var position = bodyStart;
    var openParens = 0;
    var closeParens = 0;
    while (position < text.length) {
      final char = text.codeUnitAt(position);
      if (_isUrlWhitespace(char)) break;
      if (char == 0x28) {
        openParens++;
      } else if (char == 0x29 && closeParens < openParens) {
        closeParens++;
      } else if (_trailMarkers.contains(char)) {
        if (_trailReachesEnd(text, position)) break;
        if (char == 0x29) closeParens++;
      }
      position++;
    }

    final raw = text.substring(index, position);
    if (isWww) {
      if (raw.length <= 4) return null;
      return (end: position, url: 'http://$raw');
    }
    return (end: position, url: raw);
  }

  /// ASCII characters that can end a URL as trailing punctuation: when a
  /// run of these (with `&word;` entities and `]` groups) reaches
  /// whitespace, end of text, or `<`, the run stays out of the URL.
  static const Set<int> _trailMarkers = <int>{
    0x21, // !
    0x22, // "
    0x26, // &
    0x27, // '
    0x29, // )
    0x2A, // *
    0x2C, // ,
    0x2E, // .
    0x3A, // :
    0x3B, // ;
    0x3C, // <
    0x3F, // ?
    0x5D, // ]
    0x5F, // _
    0x7E, // ~
  };

  /// Whether the trail candidate at [pos] runs through to end of text,
  /// whitespace, or `<`; `&` counts only as a whole `&word;` entity and a
  /// consumed `]` requires an end, `(`, `[`, or whitespace after it.
  static bool _trailReachesEnd(String text, int pos) {
    var index = pos;
    while (index < text.length) {
      final char = text.codeUnitAt(index);
      if (char == 0x26) {
        var scan = index + 1;
        while (scan < text.length && _isAsciiLetter(text.codeUnitAt(scan))) {
          scan++;
        }
        if (scan == index + 1 ||
            scan >= text.length ||
            text.codeUnitAt(scan) != 0x3B) {
          return false;
        }
        index = scan + 1;
        continue;
      }
      if (char == 0x5D) {
        index++;
        if (index >= text.length) return true;
        final next = text.codeUnitAt(index);
        if (next == 0x28 || next == 0x5B || _isUrlWhitespace(next)) {
          return true;
        }
        continue;
      }
      if (char == 0x3C || _isUrlWhitespace(char)) return true;
      if (_trailMarkers.contains(char)) {
        index++;
        continue;
      }
      return false;
    }
    return true;
  }

  /// GFM rejects a literal autolink whose domain carries `_` in either of
  /// its last two non-empty dot segments; the domain ends at the first
  /// whitespace or punctuation/symbol character other than `-`, `.`, `_`,
  /// and at a `.`/`_` that starts a trail to the end (trailing
  /// punctuation, not domain material).
  static bool _domainHasTrailingUnderscore(String text, int bodyStart) {
    var end = bodyStart;
    while (end < text.length) {
      final char = text.codeUnitAt(end);
      if (_isUrlWhitespace(char)) break;
      if (char == 0x2E || char == 0x5F) {
        if (_trailReachesEnd(text, end)) break;
      } else if (char != 0x2D && isPunctOrSymbol(char)) {
        break;
      }
      end++;
    }
    final segments = text
        .substring(bodyStart, end)
        .split('.')
        .where((segment) => segment.isNotEmpty)
        .toList();
    final tail = segments.length >= 2
        ? segments.sublist(segments.length - 2)
        : segments;
    return tail.any((segment) => segment.contains('_'));
  }

  /// Whether [prefix] appears at [index], ignoring ASCII-letter case.
  static bool _startsWithIgnoreCase(String text, int index, String prefix) {
    if (index + prefix.length > text.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (_lowerAscii(text.codeUnitAt(index + i)) != prefix.codeUnitAt(i)) {
        return false;
      }
    }
    return true;
  }

  /// Characters that end a URL span: markdown whitespace plus the Unicode
  /// whitespace set the reference's autolink rules test.
  static bool _isUrlWhitespace(int char) =>
      char == 0x20 ||
      (char >= 0x09 && char <= 0x0D) ||
      char == 0xA0 ||
      char == 0x1680 ||
      (char >= 0x2000 && char <= 0x200A) ||
      char == 0x2028 ||
      char == 0x2029 ||
      char == 0x202F ||
      char == 0x205F ||
      char == 0x3000 ||
      char == 0xFEFF;

  static bool _isAsciiLetter(int char) =>
      (char >= 0x41 && char <= 0x5A) || (char >= 0x61 && char <= 0x7A);

  static int _lowerAscii(int char) =>
      char >= 0x41 && char <= 0x5A ? char + 0x20 : char;

  /// Parse inline emphasis/code/link runs inside one paragraph line group.
  static List<MarkdownInline> parseInlines(String text) {
    final inlines = <MarkdownInline>[];
    final plain = StringBuffer();
    var index = 0;

    void flushPlain() {
      if (plain.isNotEmpty) {
        inlines.add(TextInline(plain.toString()));
        plain.clear();
      }
    }

    while (index < text.length) {
      final char = text[index];
      if (char == '`' && text.indexOf('`', index + 1) != -1) {
        final end = text.indexOf('`', index + 1);
        flushPlain();
        inlines.add(CodeInline(text.substring(index + 1, end)));
        index = end + 1;
      } else if (char == '*' && text.startsWith('**', index)) {
        final end = text.indexOf('**', index + 2);
        if (end != -1 && end > index + 2) {
          flushPlain();
          inlines.add(BoldInline(parseInlines(text.substring(index + 2, end))));
          index = end + 2;
        } else {
          plain.write(char);
          index++;
        }
      } else if (char == '*' &&
          index + 1 < text.length &&
          !_isWhitespace(text[index + 1])) {
        final close = _findSingleEmphasisClose(text, index + 1);
        if (close != -1) {
          flushPlain();
          inlines.add(
            ItalicInline(parseInlines(text.substring(index + 1, close))),
          );
          index = close + 1;
        } else {
          plain.write(char);
          index++;
        }
      } else if (_scanAutolink(text, index) case final autolink?) {
        flushPlain();
        inlines.add(
          LinkInline(
            label: text.substring(index, autolink.end),
            url: autolink.url,
          ),
        );
        index = autolink.end;
      } else if (char == '[') {
        // A link label ends at the first `]` that closes this `[` (inner
        // `[`/`]` pairs balance) and a link needs `](` + `)` right there —
        // never a `](` from a later bracket pair.
        final labelEnd = _linkLabelEnd(text, index);
        var matched = false;
        if (labelEnd != -1 &&
            labelEnd + 1 < text.length &&
            text.codeUnitAt(labelEnd + 1) == 0x28) {
          final urlEnd = text.indexOf(')', labelEnd + 2);
          if (urlEnd != -1) {
            flushPlain();
            inlines.add(
              LinkInline(
                label: text.substring(index + 1, labelEnd),
                url: text.substring(labelEnd + 2, urlEnd),
              ),
            );
            index = urlEnd + 1;
            matched = true;
          }
        }
        if (!matched) {
          plain.write(char);
          index++;
        }
      } else {
        plain.write(char);
        index++;
      }
    }
    flushPlain();
    return inlines;
  }

  /// Closing `]` of the link label opened by the `[` at [index]: the first
  /// `]` at bracket depth zero, or -1 when the label never closes.
  static int _linkLabelEnd(String text, int index) {
    var depth = 0;
    for (var scan = index + 1; scan < text.length; scan++) {
      final char = text.codeUnitAt(scan);
      if (char == 0x5B) {
        depth++;
      } else if (char == 0x5D) {
        if (depth == 0) return scan;
        depth--;
      }
    }
    return -1;
  }

  /// Closing single `*` that is not the start of a `**` pair.
  static int _findSingleEmphasisClose(String text, int from) {
    var index = from;
    while (index < text.length) {
      if (text[index] == '*') {
        if (text.startsWith('**', index)) {
          index += 2;
          continue;
        }
        if (!_isWhitespace(text[index - 1])) return index;
      }
      index++;
    }
    return -1;
  }

  /// A pipe row starts a table only when the next line is a delimiter row.
  static bool _isTableStart(List<String> lines, int index) {
    final line = lines[index];
    if (!line.contains('|')) return false;
    if (index + 1 >= lines.length) return false;
    final next = lines[index + 1];
    final cells = _splitTableRow(next);
    if (cells.isEmpty) return false;
    return cells.every((cell) {
      final cellText = _cellText(cell);
      return _delimiterCell.hasMatch(cellText.isEmpty ? '-' : cellText);
    });
  }

  /// Split one pipe row into inline cells; outer pipes optional.
  static List<List<MarkdownInline>> _splitTableRow(String line) {
    var trimmed = line.trim();
    if (trimmed.startsWith('|')) trimmed = trimmed.substring(1);
    if (trimmed.endsWith('|')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed.split('|').map((cell) => parseInlines(cell.trim())).toList();
  }

  /// Plain text of one parsed cell, for delimiter-row matching.
  static String _cellText(List<MarkdownInline> cell) {
    final buffer = StringBuffer();
    for (final inline in cell) {
      if (inline is TextInline) {
        buffer.write(inline.text);
      } else if (inline is CodeInline) {
        buffer.write(inline.code);
      }
    }
    return buffer.toString();
  }

  static bool _isWhitespace(String char) =>
      char == ' ' || char == '\t' || char == '\n' || char == '\r';
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _deepEquals(List<List<MarkdownInline>> a, List<List<MarkdownInline>> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!_listEquals(a[i], b[i])) return false;
  }
  return true;
}

bool _deepDeepEquals(
  List<List<List<MarkdownInline>>> a,
  List<List<List<MarkdownInline>>> b,
) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!_deepEquals(a[i], b[i])) return false;
  }
  return true;
}
