/// Code tokenizer tests: the fence languages the transcript claims to colour,
/// and the degradation it promises for everything else.
library;

import 'package:app/ui/chat/markdown/code_highlight.dart';
import 'package:flutter_test/flutter_test.dart';

/// The token stream as `kind:text` pairs, so a failure reads as the classes a
/// reader would see rather than as an object dump.
List<String> kinds(String code, String? language) => [
  for (final token in tokenizeCode(code, language))
    '${token.kind.name}:${token.text}',
];

/// The text every token carries, concatenated: tokenizing must never lose,
/// duplicate or reorder a character.
String roundTrip(String code, String? language) =>
    tokenizeCode(code, language).map((token) => token.text).join();

void main() {
  group('language lookup', () {
    test('known fence names resolve, and aliases fold onto them', () {
      expect(codeLanguageIsKnown('dart'), isTrue);
      expect(codeLanguageIsKnown('sh'), isTrue);
      expect(codeLanguageIsKnown('yml'), isTrue);
      expect(codeLanguageIsKnown('TSX'), isTrue);
    });

    test('an unknown, empty or absent fence has no tokenizer', () {
      expect(codeLanguageIsKnown(null), isFalse);
      expect(codeLanguageIsKnown(''), isFalse);
      expect(codeLanguageIsKnown('brainfuck'), isFalse);
      expect(codeLanguageIsKnown('dart title="main.dart"'), isTrue);
    });

    test('an unknown language degrades to one plain run', () {
      expect(kinds('a = 1 // x', 'brainfuck'), ['plain:a = 1 // x']);
    });
  });

  group('dart', () {
    test('classifies comments, strings, numbers and keywords', () {
      expect(kinds('final x = 42; // note', 'dart'), [
        'keyword:final',
        'plain: x = ',
        'number:42',
        'plain:; ',
        'comment:// note',
      ]);
      expect(kinds('var s = "hi";', 'dart'), [
        'keyword:var',
        'plain: s = ',
        'string:"hi"',
        'plain:;',
      ]);
    });

    test('a block comment spans newlines as one run', () {
      expect(kinds('a /* one\ntwo */ b', 'dart'), [
        'plain:a ',
        'comment:/* one\ntwo */',
        'plain: b',
      ]);
    });

    test('an unterminated block comment runs to the end', () {
      expect(kinds('a /* open', 'dart'), ['plain:a ', 'comment:/* open']);
    });

    test('an escape does not close a string', () {
      expect(kinds(r'var s = "a\"b";', 'dart'), [
        'keyword:var',
        'plain: s = ',
        r'string:"a\"b"',
        'plain:;',
      ]);
    });

    test('a number keeps its exponent and separators', () {
      expect(kinds('x = 1_000e-9', 'dart'), ['plain:x = ', 'number:1_000e-9']);
      expect(kinds('x = 0xFF', 'dart'), ['plain:x = ', 'number:0xFF']);
    });
  });

  group('json', () {
    test('has no line comment, so a // run stays plain', () {
      expect(kinds('{"a": 1} // not a comment', 'json'), [
        'plain:{',
        'string:"a"',
        'plain:: ',
        'number:1',
        'plain:} // not a comment',
      ]);
    });

    test('colours keys-as-strings and the literal keywords', () {
      expect(kinds('{"k": true, "n": null}', 'json'), [
        'plain:{',
        'string:"k"',
        'plain:: ',
        'keyword:true',
        'plain:, ',
        'string:"n"',
        'plain:: ',
        'keyword:null',
        'plain:}',
      ]);
    });
  });

  group('python and shell', () {
    test('python reads # comments and triple-quoted strings', () {
      expect(kinds('def f():  # go\n    return """x"""', 'python'), [
        'keyword:def',
        'plain: f():  ',
        'comment:# go',
        'plain:\n    ',
        'keyword:return',
        'plain: ',
        'string:"""x"""',
      ]);
    });

    test('shell reads # comments and keywords', () {
      expect(kinds('if [ -f x ]; then\n  echo 1  # yes\nfi', 'bash'), [
        'keyword:if',
        'plain: [ -f x ]; ',
        'keyword:then',
        'plain:\n  echo ',
        'number:1',
        'plain:  ',
        'comment:# yes',
        'plain:\n',
        'keyword:fi',
      ]);
    });
  });

  group('sql', () {
    test('keywords match whatever their case', () {
      expect(kinds('select 1 from t', 'sql'), [
        'keyword:select',
        'plain: ',
        'number:1',
        'plain: ',
        'keyword:from',
        'plain: t',
      ]);
    });
  });

  group('invariants', () {
    test('tokenizing preserves the body exactly', () {
      const bodies = <String>[
        'final x = 1; // c\nvar y = "s";',
        '{"a": [1, 2, {"b": null}]}',
        'def f():\n    return """\nmulti\n"""',
        'if x; then echo 0x1F; fi',
        'plain words with no punctuation at all',
      ];
      for (final language in <String>[
        'dart',
        'json',
        'python',
        'bash',
        'sql',
      ]) {
        for (final body in bodies) {
          expect(
            roundTrip(body, language),
            body,
            reason: 'lost text for $language',
          );
        }
      }
    });

    test('an empty body yields no tokens', () {
      expect(tokenizeCode('', 'dart'), isEmpty);
      expect(tokenizeCode('', null), isEmpty);
    });

    test('adjacent plain runs are coalesced into one token', () {
      final tokens = tokenizeCode('abc def', 'dart');
      expect(tokens.length, 1);
      expect(tokens.single.kind, CodeTokenKind.plain);
    });
  });
}
