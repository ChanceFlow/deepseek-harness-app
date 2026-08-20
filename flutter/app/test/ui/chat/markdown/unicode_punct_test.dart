import 'package:flutter_test/flutter_test.dart';

import 'package:app/ui/chat/markdown/unicode_punct.dart';

void main() {
  test('ranges are sorted and non-overlapping', () {
    for (var i = 0; i < kPunctSymbolRanges.length; i++) {
      final (start, end) = kPunctSymbolRanges[i];
      expect(start, lessThanOrEqualTo(end), reason: 'range $i is empty');
      if (i > 0) {
        final (_, previousEnd) = kPunctSymbolRanges[i - 1];
        expect(start, greaterThan(previousEnd), reason: 'range $i overlaps');
      }
    }
  });

  test('ASCII punctuation and symbols classify, alphanumerics do not', () {
    for (var char = 0x21; char <= 0x7E; char++) {
      final alnum = (char >= 0x30 && char <= 0x39) ||
          (char >= 0x41 && char <= 0x5A) ||
          (char >= 0x61 && char <= 0x7A);
      expect(isPunctOrSymbol(char), !alnum, reason: 'U+${char.toRadixString(16)}');
    }
  });

  test('CJK punctuation and full-width forms classify', () {
    const punct = ['、', '。', '〈', '《', '「', '『', '【', '〜', '！', '？',
        '，', '；', '：', '）', '］', '｝'];
    for (final char in punct) {
      expect(isPunctOrSymbol(char.codeUnitAt(0)), isTrue,
          reason: char);
    }
  });

  test('CJK ideographs and full-width alphanumerics do not classify', () {
    const notPunct = ['详', '见', '文', '中', 'Ａ', 'ｂ', '１', '２'];
    for (final char in notPunct) {
      expect(isPunctOrSymbol(char.codeUnitAt(0)), isFalse, reason: char);
    }
  });

  test('general punctuation and math symbols classify', () {
    const punct = ['—', '…', '“', '”', '‘', '’', '±', '×', '÷', '→', '★'];
    for (final char in punct) {
      expect(isPunctOrSymbol(char.codeUnitAt(0)), isTrue, reason: char);
    }
  });

  test('whitespace and control characters never classify', () {
    const never = [0x00, 0x09, 0x0A, 0x0D, 0x20, 0xA0, 0x2028, 0x3000,
        0xFEFF];
    for (final char in never) {
      expect(isPunctOrSymbol(char), isFalse, reason: 'U+${char.toRadixString(16)}');
    }
  });
}
