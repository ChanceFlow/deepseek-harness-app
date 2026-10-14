/// Document-preview registry — which body renders a path, chosen from the
/// path's file suffix.
///
/// The rule is the reference's. A registration claims the suffixes it declares,
/// and a path's candidates are every registration matching its basename by a
/// declared suffix, ordered by matched-suffix length
/// (`reference/deepseek-harness/packages/client/ui-sidebar-documentpreview/src/client/document/registry.ts:36-49`
/// and `.../document/suffix.ts:31-36`). The plain-text viewer is the `fallback`
/// band: it is a candidate for every path no registration declares binary
/// (`binaryDocumentPath` at `registry.ts:57-63`), so a rendered file keeps a
/// source view beside its renderer. A suffix no registration matches that the
/// reference's own unviewable list names is the unsupported state
/// (`.../document/unviewable.ts:10-37`), consulted only when nothing matched.
///
/// The app folds the reference's `markdown`, `code` and `text` bodies into one
/// text lane, because its renderer already dispatches on the same suffixes:
/// a markdown path passes through the markdown surface and every other path
/// takes the code surface. The registry therefore carries only the renderers
/// that need a body of their own.
library;

/// One renderer the preview sheet can draw, or the text fallback.
enum PreviewRenderer {
  /// A complete HTML document, rendered as a static document.
  html,

  /// Complete image bytes, including `svg`, which the bitmap decoder cannot
  /// draw and the document frame renders instead.
  image,

  /// A worksheet built from complete file bytes: a delimited file, or an
  /// `xlsx` workbook.
  spreadsheet,

  /// A complete PDF document, drawn page by page through the platform
  /// renderer.
  pdf,

  /// An office document the host converts before the PDF body draws it.
  office,

  /// The plain-text viewer: markdown for a markdown path, a fenced code block
  /// otherwise. This is the fallback band and has no suffix of its own.
  text,
}

/// How a renderer is handed its content.
enum PreviewLoadMode {
  /// A window of decoded lines (`workspaceFiles/read`).
  textPages,

  /// The complete file bytes (`workspaceFiles/readBytes`).
  bytesComplete,

  /// The renderer loads its own content, because the host must convert it
  /// first (`officeToPdf/render`).
  renderer,
}

/// One renderer registration.
class PreviewDefinition {
  const PreviewDefinition({
    required this.renderer,
    required this.extensions,
    this.binaryExtensions = const <String>[],
    this.load = PreviewLoadMode.textPages,
  });

  final PreviewRenderer renderer;

  /// Suffixes without a leading dot; a compound suffix such as `tar.gz` is one
  /// entry.
  final List<String> extensions;

  /// Suffixes among [extensions] whose bytes are not readable text. A path
  /// matching one loses the plain-text fallback among its candidates, which is
  /// how a rendered binary is kept out of the text lane.
  final List<String> binaryExtensions;

  final PreviewLoadMode load;
}

/// One candidate for a path: the renderer and how it loads its content.
class PreviewCandidate {
  const PreviewCandidate(this.renderer, this.load);

  final PreviewRenderer renderer;
  final PreviewLoadMode load;

  @override
  bool operator ==(Object other) =>
      other is PreviewCandidate &&
      other.renderer == renderer &&
      other.load == load;

  @override
  int get hashCode => Object.hash(renderer, load);

  @override
  String toString() => 'PreviewCandidate(${renderer.name}, ${load.name})';
}

/// Registrations in the order the reference's assembly registers them.
const List<PreviewDefinition> _definitions = <PreviewDefinition>[
  PreviewDefinition(
    renderer: PreviewRenderer.html,
    extensions: <String>['html', 'htm'],
    load: PreviewLoadMode.bytesComplete,
  ),
  // The reference's `IMAGE_EXTENSIONS` (`.../src/client/image/index.ts:16`);
  // `svg` stays out of the binary list because its XML source is readable text
  // and a reader may want it, which is what keeps it a source-view candidate.
  PreviewDefinition(
    renderer: PreviewRenderer.image,
    extensions: <String>[
      'png',
      'jpg',
      'jpeg',
      'gif',
      'webp',
      'bmp',
      'wbmp',
      'ico',
      'svg',
    ],
    binaryExtensions: <String>[
      'png',
      'jpg',
      'jpeg',
      'gif',
      'webp',
      'bmp',
      'wbmp',
      'ico',
    ],
    load: PreviewLoadMode.bytesComplete,
  ),
  // The reference's excel registration (`.../src/client/excel/index.ts:17-20`)
  // covers `xlsx`, `xls`, `csv` and `tsv`; `xls` is not read here yet, so its
  // suffix stays in the unviewable list rather than promising a body that does
  // not exist. A delimited file is readable text, which keeps its source view.
  PreviewDefinition(
    renderer: PreviewRenderer.spreadsheet,
    extensions: <String>['xlsx', 'csv', 'tsv'],
    binaryExtensions: <String>['xlsx'],
    load: PreviewLoadMode.bytesComplete,
  ),
  // The reference's pdf registration (`.../src/client/pdf/index.ts:23`): one
  // suffix, declared binary, so a document has no source alternative.
  PreviewDefinition(
    renderer: PreviewRenderer.pdf,
    extensions: <String>['pdf'],
    binaryExtensions: <String>['pdf'],
    load: PreviewLoadMode.bytesComplete,
  ),
  // The reference's office registration (`.../src/client/office/index.ts:33,41-45`):
  // `doc`, `docx`, `ppt` and `pptx`, all declared binary, and the one renderer
  // that loads its own content — the host converts the document, and the body
  // it hands back is the PDF one.
  PreviewDefinition(
    renderer: PreviewRenderer.office,
    extensions: <String>['doc', 'docx', 'ppt', 'pptx'],
    binaryExtensions: <String>['doc', 'docx', 'ppt', 'pptx'],
    load: PreviewLoadMode.renderer,
  ),
];

/// Suffixes whose bytes are never readable text and that no registration above
/// claims: the reference's `UNVIEWABLE_BINARY_EXTENSIONS`
/// (`.../document/unviewable.ts:10-28`) plus `pdf`, `apk`, `aar` and `dex`,
/// which the reference renders or ships compiled. A registration for a suffix
/// takes precedence, because this list is consulted only when nothing matched.
/// A suffix whose bytes might be text stays out and keeps the text lane.
const List<String> _unviewableBinaryExtensions = <String>[
  'pdf',
  'apk',
  'aar',
  'dex',
  'jar',
  'zip',
  'gz',
  'tgz',
  'bz2',
  'xz',
  'zst',
  '7z',
  'rar',
  'tar',
  'mp4',
  'mov',
  'avi',
  'mkv',
  'webm',
  'flv',
  'wmv',
  'm4v',
  'mp3',
  'wav',
  'flac',
  'ogg',
  'm4a',
  'aac',
  'wma',
  'opus',
  'doc',
  'docx',
  'xls',
  'xlsx',
  'ppt',
  'pptx',
  'odt',
  'ods',
  'odp',
  'pages',
  'numbers',
  'exe',
  'dll',
  'so',
  'dylib',
  'bin',
  'o',
  'class',
  'pyc',
  'wasm',
  'ttf',
  'otf',
  'woff',
  'woff2',
  'eot',
  'dmg',
  'iso',
  'img',
  'sqlite',
  'db',
  'psd',
  'ai',
  'sketch',
  'tiff',
  'tif',
  'heic',
  'heif',
  'avif',
];

/// The candidates for [path] in automatic-selection order: every registration
/// matching the basename, longest declared suffix first, then the text
/// fallback where the bytes are readable text at all.
///
/// The fallback needs both answers: a registration that declares the suffix
/// binary (`binaryDocumentPath`) and the reference's unviewable list
/// (`unviewableBinaryPath`) each mean the text lane has nothing to read. An
/// empty list is the unsupported state.
List<PreviewCandidate> previewCandidates(String path) {
  final name = documentFileName(path);
  final matched = <(int, int, PreviewCandidate)>[];
  for (var order = 0; order < _definitions.length; order++) {
    final definition = _definitions[order];
    final length = matchedSuffixLength(name, definition.extensions);
    if (length == 0) continue;
    matched.add((
      length,
      order,
      PreviewCandidate(definition.renderer, definition.load),
    ));
  }
  matched.sort((left, right) {
    final byLength = right.$1.compareTo(left.$1);
    return byLength != 0 ? byLength : left.$2.compareTo(right.$2);
  });
  final candidates = <PreviewCandidate>[for (final entry in matched) entry.$3];
  if (!binaryDocumentPath(path) && !unviewableBinaryPath(path)) {
    candidates.add(
      const PreviewCandidate(PreviewRenderer.text, PreviewLoadMode.textPages),
    );
  }
  return candidates;
}

/// Whether a registered implementation declares the path's suffix binary.
bool binaryDocumentPath(String path) {
  final name = documentFileName(path);
  return _definitions.any(
    (definition) => matchedSuffixLength(name, definition.binaryExtensions) > 0,
  );
}

/// Whether [path]'s suffix is a known binary container that no renderer claims.
/// It suppresses the text fallback and, with no registration matching, leaves
/// the path with no candidate at all — the unsupported state.
bool unviewableBinaryPath(String path) =>
    matchedSuffixLength(documentFileName(path), _unviewableBinaryExtensions) >
    0;

/// The filename a path's suffixes are matched against: the lowercased final
/// path segment, with `\` accepted as a separator
/// (`.../document/suffix.ts:20-23`).
String documentFileName(String path) {
  final normalized = path.replaceAll(r'\', '/').toLowerCase();
  return normalized.substring(normalized.lastIndexOf('/') + 1);
}

/// The longest declared suffix ending [name], or 0 when none matches
/// (`.../document/suffix.ts:31-36`). A compound suffix such as `tar.gz` matches
/// as a unit.
int matchedSuffixLength(String name, List<String> extensions) {
  var longest = 0;
  for (final extension in extensions) {
    final normalized = normalizeSuffix(extension);
    if (name.endsWith('.$normalized') && normalized.length > longest) {
      longest = normalized.length;
    }
  }
  return longest;
}

/// One declared suffix lowercased with any leading dot dropped
/// (`.../document/suffix.ts:11-13`).
String normalizeSuffix(String extension) =>
    extension.toLowerCase().replaceFirst(RegExp(r'^\.'), '');
