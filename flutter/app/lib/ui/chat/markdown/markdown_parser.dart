/// Minimal markdown vocabulary for assistant/user message bodies.
///
/// Scope mirrors the Android MVP slice: fenced code blocks, headings,
/// bullet lists, block quotes, GFM pipe tables, and paragraphs with inline
/// code, bold, italic, and links. The parser is pure Dart so plain tests
/// pin its behavior; the widget layer owns every style decision.
library;

import 'dart:convert';

sealed class MarkdownBlock {
  const MarkdownBlock();
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
  static final RegExp _heading = RegExp(r'^(#{1,6}) (.*)$');
  static final RegExp _quote = RegExp(r'^>\s?(.*)$');
  static final RegExp _delimiterCell = RegExp(r'^:?-+:?$');

  /// Parse one message body into ordered blocks.
  static List<MarkdownBlock> parse(String text) {
    final blocks = <MarkdownBlock>[];
    final lines = const LineSplitter().convert(text);
    var index = 0;

    var paragraph = <String>[];
    var bullets = <BulletEntry>[];

    void flushParagraph() {
      if (paragraph.isNotEmpty) {
        blocks.add(ParagraphBlock(inlines: parseInlines(paragraph.join('\n'))));
        paragraph = <String>[];
      }
    }

    void flushBullets() {
      if (bullets.isNotEmpty) {
        blocks.add(BulletListBlock(items: List.of(bullets)));
        bullets = <BulletEntry>[];
      }
    }

    while (index < lines.length) {
      final line = lines[index];
      final fenceMatch = _fence.firstMatch(line);
      if (fenceMatch != null) {
        flushParagraph();
        flushBullets();
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
          CodeBlock(language: language, code: code.toString(), open: !closed),
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
        final header = _splitTableRow(line);
        index += 2;
        final rows = <List<List<MarkdownInline>>>[];
        while (index < lines.length &&
            lines[index].contains('|') &&
            lines[index].trim().isNotEmpty) {
          rows.add(_splitTableRow(lines[index]));
          index++;
        }
        blocks.add(TableBlock(header: header, rows: rows));
        continue;
      }

      final quoteStart = _quote.firstMatch(line);
      if (quoteStart != null) {
        flushParagraph();
        flushBullets();
        final quoted = <String>[quoteStart.group(1)!];
        index++;
        while (index < lines.length) {
          final nextQuote = _quote.firstMatch(lines[index]);
          if (nextQuote == null) break;
          quoted.add(nextQuote.group(1)!);
          index++;
        }
        blocks.add(BlockQuoteBlock(inlines: parseInlines(quoted.join('\n'))));
        continue;
      }

      final headingMatch = _heading.firstMatch(line);
      if (headingMatch != null) {
        flushParagraph();
        flushBullets();
        blocks.add(
          HeadingBlock(
            level: headingMatch.group(1)!.length,
            inlines: parseInlines(headingMatch.group(2)!),
          ),
        );
        index++;
        continue;
      }

      final bulletMatch = _bullet.firstMatch(line);
      if (bulletMatch != null) {
        flushParagraph();
        final indent = ' '.allMatches(bulletMatch.group(1)!).length;
        bullets.add(
          BulletEntry(
            inlines: parseInlines(bulletMatch.group(2)!),
            depth: (indent ~/ 2) > maxBulletDepth
                ? maxBulletDepth
                : indent ~/ 2,
          ),
        );
        index++;
        continue;
      }

      flushBullets();
      paragraph.add(line.trimRight());
      index++;
    }
    flushParagraph();
    flushBullets();
    return blocks;
  }

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
      } else if (char == '[') {
        final labelEnd = text.indexOf('](', index + 1);
        var matched = false;
        if (labelEnd != -1) {
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
