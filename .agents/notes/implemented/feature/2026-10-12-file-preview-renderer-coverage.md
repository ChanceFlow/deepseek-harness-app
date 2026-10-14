# Agent Note: File previews render what the reference renders

Status: implemented

## Problem

The preview sheet dispatched on three lanes of its own — text, image,
unsupported — over suffix tables inside the widget, so a file the agent wrote
opened as source: `.html` and `.htm` rendered as an `html`-tagged fenced block
and `.svg` was readable only as XML. The reference client has always dispatched
by longest declared suffix through a registry of renderers
(`reference/deepseek-harness/packages/client/ui-sidebar-documentpreview/src/client/document/registry.ts:36-49`)
and defaults an HTML file to a static document in a sandboxed frame
(`.../src/client/html/index.ts:20`, `.../src/client/html/HtmlBody.tsx:86,102`).
[The byte-preview note](2026-09-28-workspace-file-byte-preview.md#consequences)
recorded that gap as deferred.

## Decision

- Suffix matching moves out of the sheet into a registry that states the
  reference's rule once: candidates in longest-suffix order, the plain-text
  viewer where the bytes are readable text, and no candidate — so no read — for
  a binary container nothing claims.
- A complete HTML file reads whole bytes and is drawn in the platform WebView
  under the reference's static mode: the markup is parsed and stripped of
  everything that could run or load something (`script`, `noscript`, `base`,
  `link`, `meta`, `iframe`, `object`, `embed`; `href`, `xlink:href` and `on*`
  attributes), the restrictive policy becomes the first head child, scripts are
  off, `file:` and `content:` access is off, media waits for a gesture, and
  every navigation the document asks for is refused. Bytes that are not UTF-8
  get the reference's own failed state.
- An SVG reads whole bytes and is drawn as an `img` `data:` source in the same
  frame, so no engine executes its scripts. The suffix decides which body runs,
  never the bytes.
- A spreadsheet reads whole bytes and draws a read-only grid: one sheet for a
  delimited file, one tab per visible worksheet for an `xlsx` workbook, under
  the reference's byte and cell-area limits plus a column bound a widget grid
  needs. Fields are literal, the encoding is UTF-8 or BOM-marked UTF-16, and a
  formula cell shows its formula with the reference's notice, because nothing
  here evaluates it.
- A PDF reads whole bytes and draws one page per page, in a list that asks for
  a page when it is reached, with the reference's Retry on the document and on
  each page. Pages come from the platform side: Android's own `PdfRenderer`
  (AOSP, API 21+) behind a method channel, because the format needs a real
  renderer. A page is
  rastered at the width the reader sees under a pixel ceiling, since a page's
  own 72 dpi raster is too coarse for a dense screen.
- An office document converts through the host (`officeToPdf/render`, wired
  by [the wire note](2026-10-12-office-to-pdf-preview-wire.md)) and hands the
  PDF to the same page list, with the host's missing-font names stated above
  it. A conversion can take a minute, so the loading state is what the reader
  sees.
- More than one candidate offers the viewer chooser the reference calls "Open
  with", which keeps a rendered document's source one tap away.
- Two seams, because a widget test owns neither platform surface: the document
  frame (`DocumentFrameBuilder`, the WebView) and the PDF page renderer
  (`PdfPageRenderer`, the channel bridge). A pump injects a stand-in for each;
  the spreadsheet grid is plain widgets.
- Dependencies: `webview_flutter` with `webview_flutter_android` for the
  Android-only settings, `html` for the parse and the strip, and `excel` for
  the OOXML archive. All are source-only for F-Droid's rule — the WebView and
  the PDF renderer are the ones already in the OS.

## Alternatives considered

`flutter_html` and hand-built widget rendering were rejected: a subset renderer
has no CSS layout truth, and neither has a policy or sandbox equivalent. A
hand-written Kotlin platform view was rejected for the maintained plugin over
the same engine; a `pdfx`-style dependency was rejected for its prebuilt native
library. Regex sanitization was rejected because the
reference sanitizes a parsed tree, which is what an HTML5 parse gives here.
Keeping HTML on the text lane was rejected: the file was produced for a reader,
and the source view is a chooser tap away. The reference's interactive mode is
not ported: the reference gates it behind developer tools and defaults to
static, and it needs the asset packer, its limits and resource tracking.

## Consequences

An HTML, SVG, `csv`, `tsv`, `xlsx`, `pdf` or office file opens as the
document, image, grid or page list it is, and a rendered file keeps its source
view where the reference does (`html`, `htm`, `svg`, `csv`, `tsv`). A declared-binary suffix loses that view, which is the
reference's own rule. A WebView, a pure-Dart OOXML reader and an Android PDF
bridge now enter the APK, which the Android and Kotlin gates cover.

The reference's one remaining body is `xls` (BIFF): that suffix states the app
cannot preview it and spends no read. This note owns the coverage.
