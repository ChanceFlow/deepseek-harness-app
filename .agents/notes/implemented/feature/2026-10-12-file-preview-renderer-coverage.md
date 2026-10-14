# Agent Note: File previews render what the reference renders

Status: implemented

## Problem

The preview sheet dispatched on three lanes of its own — text, image,
unsupported — over suffix tables inside the widget, so a file the agent wrote
as a report was shown as source: `.html` and `.htm` landed in the text lane and
rendered as an `html`-tagged fenced block, and `.svg` was readable only as XML.
The reference client has always dispatched by longest declared suffix through a
registry of renderers (`reference/deepseek-harness/packages/client/ui-sidebar-documentpreview/src/client/document/registry.ts:36-49`)
and defaults an HTML file to a static document in a sandboxed frame
(`.../src/client/html/index.ts:20`, `.../src/client/html/HtmlBody.tsx:86,102`).
[The byte-preview note](2026-09-28-workspace-file-byte-preview.md#consequences)
recorded that gap as deferred. This change closes the part of it the system
browser engine can render safely.

## Decision

- Suffix matching moves out of the sheet into a registry that states the
  reference's rule once: candidates in longest-suffix order, the plain-text
  viewer appended where neither a declaration nor the reference's unviewable
  list calls the bytes binary, and no candidate at all — so no read and the
  plain statement — for a binary container nothing claims.
- A complete HTML file reads whole bytes and is drawn in the platform WebView
  under the reference's static mode: the markup is parsed and stripped of
  everything that could run or load something (`script`, `noscript`, `base`,
  `link`, `meta`, `iframe`, `frame`, `object`, `embed`, the SVG animation
  elements; `href`, `xlink:href` and `on*` attributes), the restrictive policy
  becomes the first head child, scripts are off, `file:` and `content:` access
  is off, media waits for a gesture, and every navigation the document asks for
  is refused. Bytes that are not UTF-8 get the reference's own failed state.
- An SVG reads whole bytes and is drawn as an `img` `data:` source in the same
  frame, so no engine ever executes its scripts. Both ignore the raster decoder
  and the suffix decides which body runs.
- More than one candidate offers the viewer chooser the reference calls "Open
  with", which is what keeps a rendered document's source one tap away.
- The frame is a seam (`DocumentFrameBuilder`): the app ships the WebView, and
  a pump that owns no platform view injects a stand-in. No test builds a real
  one.
- Two dependencies: `webview_flutter` with `webview_flutter_android` for the
  Android-only settings, and `html` for the parse and the strip. Both are
  source-only for F-Droid's rule — the WebView is the one already in the OS.

## Alternatives considered

`flutter_html` and hand-built widget rendering were rejected: a subset
renderer has no CSS layout truth, and neither has a policy or sandbox
equivalent to the mode being ported. A hand-written Kotlin platform view was
rejected for the maintained plugin over the same system engine. Regex
sanitization was rejected because the reference sanitizes a parsed tree, which
is what an HTML5 parse gives here. Keeping HTML on the text lane with a label
was rejected: the file was produced for a reader, and the source view is a
chooser tap away instead. The reference's interactive mode — script execution
with relative classic `.js`/`.css` packed through `baseFile` reads — is not
ported: the reference itself gates it behind developer tools and defaults to
static, and it needs the asset packer, its per-asset limits and resource
tracking.

## Consequences

An HTML or SVG file the agent wrote opens as a document on the phone, and a
rendered file keeps its source view. A declared-binary suffix loses that view,
which is the reference's own rule. A WebView now enters the APK, which the
Android build and Kotlin gates cover.

The reference's spreadsheet (`xlsx`, `xls`, `csv`, `tsv`), PDF and Office
renderers are still not ported: those suffixes either stay on the text lane
(`csv`, `tsv`) or state that the app cannot preview them (`pdf`, `xlsx`,
`xls`, `doc*`, `ppt*`). This note owns the coverage as the remaining bodies
land.
