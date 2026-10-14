/// Document sources — the complete documents a preview frame draws.
///
/// Both builders mirror the reference's static HTML mode
/// (`reference/deepseek-harness/packages/client/ui-sidebar-documentpreview/src/client/html/basic-document.ts:10-21`):
/// the document is stripped of everything that could load or run something,
/// and a restrictive `Content-Security-Policy` is prepended as the first head
/// child. The frame that draws it adds the second half of that mode — no
/// script execution and no navigation — so the pair is what makes previewing a
/// file the agent wrote safe on a phone.
///
/// The reference sanitizes with DOMPurify and keeps its default `FORBID_TAGS`
/// plus `noscript`, `base`, `link`, `meta`, `iframe`, `frame`, `object`,
/// `embed`, `set` and the SVG animation elements, and its `FORBID_ATTR`
/// (`href`, `xlink:href`); this file declares the same sets over an HTML5
/// parse, which is what the reference's own `DOMParser` call does.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// The policy every prepared document carries. It is the reference's string
/// verbatim (`.../html/basic-document.ts:19`): no network of any kind, no
/// scripts, inline styles and `data:` media only.
const String kStaticDocumentCsp =
    "default-src 'none'; script-src 'none'; style-src 'unsafe-inline'; "
    'img-src data:; font-src data:; media-src data:; connect-src \'none\'; '
    "frame-src 'none'; form-action 'none'; base-uri 'none'";

/// The policy for a document that is only an image: it needs `img-src data:`.
const String kImageDocumentCsp =
    "default-src 'none'; img-src data:; style-src 'unsafe-inline'";

/// Elements the static mode never keeps. `script` and `noscript` are
/// DOMPurify's own defaults; the rest are the reference's `FORBID_TAGS`.
const List<String> _forbiddenElements = <String>[
  'script',
  'noscript',
  'base',
  'link',
  'meta',
  'iframe',
  'frame',
  'object',
  'embed',
  'set',
  'animate',
  'animateMotion',
  'animateTransform',
];

/// Prepares one complete UTF-8 HTML file into the static document.
///
/// [bytes] that are not valid UTF-8 throw [FormatException]: the reference's
/// document has no text to parse there, and the caller renders its own failed
/// state instead (`.../html/HtmlBody.tsx:99-101`).
String basicHtmlDocument(Uint8List bytes) {
  final document = html_parser.parse(utf8.decode(bytes));
  for (final name in _forbiddenElements) {
    for (final element in document.querySelectorAll(name)) {
      element.remove();
    }
  }
  for (final element in document.querySelectorAll('*')) {
    element.attributes.removeWhere(
      (name, _) => _forbiddenAttribute(name.toString()),
    );
  }
  final root = document.documentElement;
  if (root == null) {
    // A parse of any text yields an `html` element; a document without one is
    // not something to hand the frame.
    throw const FormatException('the document has no root element');
  }
  final head = root.querySelector('head');
  if (head == null) {
    // A parse of any text yields a head; a document without one would lose the
    // policy, so it is built rather than dropped.
    root.nodes.insert(0, dom.Element.tag('head')..nodes.add(_policyElement()));
  } else {
    head.nodes.insert(0, _policyElement());
  }
  return '<!doctype html>${root.outerHtml}';
}

/// The document that draws one complete SVG file: the file's own bytes as an
/// `<img>` `data:` source, which no engine executes scripts from.
///
/// [alt] is what the image is announced as; the file's name is the reference's
/// own choice for it (`.../image/locales.ts:4-24`).
String svgImageDocument(Uint8List bytes, {required String alt}) {
  final source = base64Encode(bytes);
  return '<!doctype html><html><head><meta charset="utf-8">'
      '<meta http-equiv="Content-Security-Policy" content="$kImageDocumentCsp">'
      '<style>html,body{margin:0;height:100%;background:transparent}'
      'body{display:flex;align-items:center;justify-content:center}'
      'img{max-width:100%;max-height:100%;object-fit:contain}</style></head>'
      '<body><img alt="${_escapeAttribute(alt)}" '
      'src="data:image/svg+xml;base64,$source"></body></html>';
}

/// Escapes the characters that would end the attribute, or start markup
/// inside it.
String _escapeAttribute(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('"', '&quot;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

/// Whether one attribute is dropped from every element: the reference's
/// `FORBID_ATTR` plus the event handlers a script-less document can only
/// ignore.
bool _forbiddenAttribute(String name) {
  final lower = name.toLowerCase();
  return lower == 'href' || lower == 'xlink:href' || lower.startsWith('on');
}

/// The policy element, built the way the reference builds it: first in the
/// head, so no document resource is requested before it is read.
dom.Element _policyElement() {
  return dom.Element.tag('meta')
    ..attributes['http-equiv'] = 'Content-Security-Policy'
    ..attributes['content'] = kStaticDocumentCsp;
}
