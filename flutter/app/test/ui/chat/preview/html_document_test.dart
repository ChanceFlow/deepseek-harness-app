/// Static document tests: what the preview frame is handed for a complete
/// HTML file, and for an SVG.
///
/// The contract is the reference's static mode
/// (`reference/deepseek-harness/packages/client/ui-sidebar-documentpreview/src/client/html/basic-document.ts:10-21`):
/// the document loses everything that could run or load something, and the
/// restrictive policy becomes its first head child, so no resource is
/// requested before it is read.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:app/ui/chat/preview/html_document.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  test('the policy is the first head child', () {
    final document = basicHtmlDocument(
      _bytes('<html><head><title>t</title></head><body>x</body></html>'),
    );

    final policy = document.indexOf('Content-Security-Policy');
    expect(policy, greaterThan(-1));
    expect(document, contains("default-src 'none'"));
    expect(document, contains("script-src 'none'"));
    expect(document, startsWith('<!doctype html>'));
    // Before the document's own head content.
    expect(policy, lessThan(document.indexOf('<title>')));
  });

  test('elements that could run or load something are removed', () {
    final document = basicHtmlDocument(
      _bytes(
        '<html><head><base href="https://example.com/">'
        '<link rel="stylesheet" href="https://example.com/a.css">'
        '<meta http-equiv="refresh" content="0;url=https://example.com">'
        '</head><body>'
        '<script>alert(1)</script><noscript>x</noscript>'
        '<iframe src="https://example.com"></iframe>'
        '<object data="a.bin"></object><embed src="a.bin">'
        '<p>KEPT</p></body></html>',
      ),
    );

    expect(document, contains('KEPT'));
    for (final gone in <String>[
      'alert(1)',
      'iframe',
      'object',
      'embed',
      '<link',
      '<base',
      'example.com',
      'http-equiv="refresh"',
    ]) {
      expect(document, isNot(contains(gone)), reason: gone);
    }
    // The policy element itself is a meta element, so exactly one remains.
    expect('meta'.allMatches(document).length, 1);
  });

  test('links lose their destination and event handlers are dropped', () {
    final document = basicHtmlDocument(
      _bytes(
        '<html><body><a href="https://example.com" onclick="x()">link</a>'
        '<svg><use xlink:href="#i"/></svg></body></html>',
      ),
    );

    expect(document, contains('link'));
    expect(document, isNot(contains('https://example.com')));
    expect(document, isNot(contains('onclick')));
    expect(document, isNot(contains('xlink:href')));
  });

  test('inline styles and content survive', () {
    final document = basicHtmlDocument(
      _bytes(
        '<html><head><style>body{color:red}</style></head>'
        '<body><h1>Title</h1></body></html>',
      ),
    );

    expect(document, contains('body{color:red}'));
    expect(document, contains('Title'));
  });

  test('bytes that are not UTF-8 throw instead of producing a document', () {
    expect(
      () => basicHtmlDocument(Uint8List.fromList(<int>[0xFF, 0xFE, 0x3C])),
      throwsFormatException,
    );
  });

  test('an SVG becomes an image document with its own policy', () {
    final source = _bytes('<svg xmlns="http://www.w3.org/2000/svg"></svg>');
    final document = svgImageDocument(source, alt: 'assets/logo.svg');

    expect(document, contains('data:image/svg+xml;base64,'));
    expect(document, contains(base64Encode(source)));
    expect(document, contains(kImageDocumentCsp));
    expect(document, contains('alt="assets/logo.svg"'));
  });

  test('an SVG name is escaped into the alt attribute', () {
    final document = svgImageDocument(_bytes('<svg/>'), alt: 'a"onload="x.svg');

    // The quote is escaped, so the name cannot end the attribute and start
    // another one.
    expect(document, contains('alt="a&quot;onload=&quot;x.svg"'));
    expect(document, isNot(contains('alt="a"onload')));
  });
}
