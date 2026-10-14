/// File preview sheet — the surface behind a tool row's "Preview" action.
///
/// The path's suffix picks the renderer, through the registry that mirrors the
/// reference's own
/// (`reference/deepseek-harness/packages/client/ui-sidebar-documentpreview/src/client/document/registry.ts`):
/// a complete HTML document is prepared and drawn in a static frame
/// ([basicHtmlDocument]), an image is drawn from its bytes — an `svg` through
/// the same frame ([svgImageDocument]) — and a path no renderer claims reads a
/// page of lines (`workspaceFiles/read`) and renders through the app's
/// existing markdown/code surface. A suffix the reference's own list names a
/// binary container gets a notice with the path to copy, and spends no call.
///
/// When more than one renderer claims the path, the sheet offers the chooser
/// the reference calls "Open with", so a rendered document keeps its source
/// view. The static frame is the application's own seam
/// ([DocumentFrameBuilder]): the app ships the platform WebView, and a pump
/// that owns none passes its own.
///
/// A read the host refuses renders the state it refused for — a page that is
/// not text, a page over the host's byte cap, a vanished path — and offers
/// Retry only where the same request can plausibly succeed later. Every
/// refused read is reported with its host code and path through the app's
/// diagnostic seam, so the error log names the cause. The host's own paging
/// signal (`eof == false`) surfaces the window's line count.
library;

import 'dart:async';
import 'dart:convert';

import 'package:app/l10n/app_localizations.dart';
import 'package:dev/dev.dart' show DebugTelemetry;
import 'package:domain/model/office_pdf.dart';
import 'package:domain/model/workspace_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../logging/error_log_collector.dart';
import '../../logging/error_log_entry.dart' show ErrorLogLevel;
import '../../platform/pdf_page_renderer.dart';
import '../theme/theme.dart';
import 'markdown/markdown_text.dart';
import 'preview/document_frame.dart';
import 'preview/document_preview_registry.dart';
import 'preview/html_document.dart';
import 'preview/pdf_page_view.dart';
import 'preview/spreadsheet.dart';
import 'preview/spreadsheet_grid.dart';
import 'preview/webview_document_frame.dart';
import 'preview/workbook.dart';
import 'tool_row_model.dart' show DiffLineKind, EditDiffModel;

/// Reads a text window of [path] inside [sessionId]'s workspace.
typedef WorkspaceFileReader = Future<WorkspaceFileContent> Function(
  String sessionId,
  String path,
);

/// Reads a complete file's raw bytes from [sessionId]'s workspace.
typedef WorkspaceFileBytesReader = Future<WorkspaceFileBytes> Function(
  String sessionId,
  String path,
);

/// Converts one office document to PDF bytes through the host
/// (`officeToPdf/render`). The call can take about a minute, so the sheet
/// shows its loading state meanwhile.
typedef OfficePdfLoader = Future<OfficePdfDocument> Function(
  String sessionId,
  String path,
);

/// Opens the preview sheet for [path]. [readFile] and [readFileBytes] are the
/// chat surface's repository seams; the sheet never reaches past them.
/// [frameBuilder] draws a prepared document — the platform WebView in the app,
/// and a pump's own stand-in where no platform view can exist.
/// [pdfPageRenderer] draws PDF pages; null uses the platform renderer.
Future<void> showFilePreviewSheet(
  BuildContext context, {
  required String sessionId,
  required String path,
  required WorkspaceFileReader readFile,
  required WorkspaceFileBytesReader readFileBytes,
  DocumentFrameBuilder frameBuilder = buildWebViewDocumentFrame,
  PdfPageRenderer? pdfPageRenderer,
  OfficePdfLoader? loadOfficePdf,
  EditDiffModel? initialDiff,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    // The card is the surface: Material's own sheet fill and elevation would
    // otherwise paint a second shadow behind the card's `prominent` ring.
    backgroundColor: Colors.transparent,
    elevation: 0,
    sheetAnimationStyle: const AnimationStyle(
      duration: DshMotion.durationMedium,
      curve: DshMotion.curveEmphasized,
      reverseCurve: DshMotion.curveExit,
    ),
    builder: (sheetContext) => FilePreviewSheet(
      sessionId: sessionId,
      path: path,
      readFile: readFile,
      readFileBytes: readFileBytes,
      frameBuilder: frameBuilder,
      pdfPageRenderer: pdfPageRenderer,
      loadOfficePdf: loadOfficePdf,
      initialDiff: initialDiff,
    ),
  );
}

enum _FilePreviewTab { diff, full }

class FilePreviewSheet extends StatefulWidget {
  const FilePreviewSheet({
    required this.sessionId,
    required this.path,
    required this.readFile,
    this.readFileBytes = _noWorkspaceFileBytes,
    this.frameBuilder = buildWebViewDocumentFrame,
    this.pdfPageRenderer,
    this.loadOfficePdf,
    this.initialDiff,
    super.key,
  });

  final String sessionId;
  final String path;
  final WorkspaceFileReader readFile;
  final WorkspaceFileBytesReader readFileBytes;

  /// Draws a prepared document (HTML, SVG). The default is the platform
  /// WebView; a pump without one passes its own.
  final DocumentFrameBuilder frameBuilder;

  /// Draws PDF pages. Null uses the platform renderer; a pump without a
  /// platform side passes its own.
  final PdfPageRenderer? pdfPageRenderer;

  /// Converts an office document through the host; null refuses, which is
  /// what a pump that owns no host wants.
  final OfficePdfLoader? loadOfficePdf;
  final EditDiffModel? initialDiff;

  @override
  State<FilePreviewSheet> createState() => _FilePreviewSheetState();
}

/// A pump that owns no repository: a byte read without a real reader surfaces
/// the localized failure instead of rendering nothing.
Future<WorkspaceFileBytes> _noWorkspaceFileBytes(
  String sessionId,
  String path,
) async {
  throw UnsupportedError('workspaceFiles/readBytes is not wired');
}

/// A pump that owns no host: an office document opened without a converter
/// says so instead of pretending the host refused it.
Future<OfficePdfDocument> _noOfficePdf(String sessionId, String path) async {
  throw UnsupportedError('officeToPdf/render is not wired');
}

/// One read's outcome. The sheet renders loading, the paged window, or the
/// refused state, and never a window it does not have.
sealed class _PreviewLoad {
  const _PreviewLoad();
}

final class _PreviewLoading extends _PreviewLoad {
  const _PreviewLoading();
}

final class _PreviewRead extends _PreviewLoad {
  const _PreviewRead(this.content);

  final WorkspaceFileContent content;
}

/// A whole-file byte read whose bytes are a format this sheet renders.
final class _PreviewImage extends _PreviewLoad {
  const _PreviewImage(this.data);

  final Uint8List data;
}

/// A prepared document the frame draws: a complete HTML file, or an `svg`
/// drawn as an image.
final class _PreviewDocument extends _PreviewLoad {
  const _PreviewDocument(this.document);

  final PreviewDocument document;
}

/// A parsed spreadsheet: the sheets of an `xlsx` workbook, or one sheet of a
/// delimited file.
final class _PreviewSpreadsheet extends _PreviewLoad {
  const _PreviewSpreadsheet(this.preview);

  final SpreadsheetPreview preview;
}

/// A complete PDF document's bytes, drawn page by page. An office document
/// arrives here after the host converted it, with the typefaces it could not
/// embed.
final class _PreviewPdf extends _PreviewLoad {
  const _PreviewPdf(this.data, {this.missingFonts = const <String>[]});

  final Uint8List data;

  final List<String> missingFonts;
}

final class _PreviewFailed extends _PreviewLoad {
  const _PreviewFailed(this.failure);

  final _PreviewFailure failure;
}

/// What a refused read means for the user, read off the host's machine code.
enum _PreviewFailureKind {
  /// The host refuses the text read (`workspace-file/not-text`): the page
  /// carries NUL bytes, or the backend refuses the non-UTF-8 stream. Also the
  /// state for content that decodes but carries NUL bytes, which is not text
  /// either.
  notText,

  /// The page exceeds the host's `maxBytes` cap (`workspace-file/too-large`).
  tooLarge,

  /// No entry at the path (`workspace-file/not-found`).
  notFound,

  /// The file's format has no renderer here: a known binary container
  /// (`_unviewableBinaryExtensions`), or bytes that are not an image the app
  /// can decode. The state offers the path to copy instead of a Retry that
  /// cannot change the format.
  unsupported,

  /// A complete HTML document the app cannot prepare: its bytes are not valid
  /// UTF-8, so there is no markup to parse. The reference's own HTML `failed`
  /// state (`.../html/HtmlBody.tsx:99-101`), which no retry can change.
  htmlFailed,

  /// A workbook or delimited file the parser refused: malformed, password
  /// protected, or not the format its suffix promised. The reference's
  /// spreadsheet `invalid` state (`.../excel/locales.ts:5`).
  spreadsheetInvalid,

  /// A spreadsheet over the byte, area or column limit
  /// (`.../excel/locales.ts:6`).
  spreadsheetTooLarge,

  /// A delimited file that is neither UTF-8 nor BOM-marked UTF-16
  /// (`.../excel/locales.ts:6`).
  spreadsheetEncoding,

  /// The host composes no office preview service, so no conversion can run
  /// (`.../office/locales.ts:8-9`).
  officeUnavailable,

  /// The document could not be converted: damaged, password protected, or not
  /// the format its suffix promised (`.../office/locales.ts:10-11`).
  officeInvalid,

  /// The document or the PDF it produced is over a conversion limit
  /// (`.../office/locales.ts:12-13`).
  officeTooLarge,

  /// The conversion ran and produced nothing usable
  /// (`.../office/locales.ts:14-15`).
  officeFailed,

  /// The conversion timed out (`.../office/locales.ts:16-17`).
  officeTimeout,

  /// The host was already converting as much as it allows
  /// (`.../office/locales.ts:18-19`).
  officeBusy,

  /// The file changed while the host read it (`.../office/locales.ts:20-21`).
  officeChanged,

  /// A failure carrying no code this sheet reads: a transport loss, or a code
  /// a newer host introduced.
  generic,
}

/// One refused read: the localized state to show, and whether a second
/// attempt can plausibly succeed.
class _PreviewFailure {
  const _PreviewFailure({
    required this.kind,
    required this.code,
    required this.retryable,
  });

  final _PreviewFailureKind kind;

  /// The host's machine code when the failure carried one, else null.
  final String? code;

  /// Whether retrying the same read can plausibly succeed. A refusal the host
  /// repeats — a binary page, a byte cap, a path that is gone — is final; a
  /// transport loss or an unread code may not be.
  final bool retryable;
}

/// The unrenderable state, which never came from a host failure.
const _PreviewFailure _unsupportedFailure = _PreviewFailure(
  kind: _PreviewFailureKind.unsupported,
  code: null,
  retryable: false,
);

/// A complete HTML document the app cannot prepare.
const _PreviewFailure _htmlFailedFailure = _PreviewFailure(
  kind: _PreviewFailureKind.htmlFailed,
  code: null,
  retryable: false,
);

class _FilePreviewSheetState extends State<FilePreviewSheet> {
  _PreviewLoad _outcome = const _PreviewLoading();

  /// Every renderer claiming the path, in automatic-selection order. Empty
  /// means the format has no renderer and no text to read.
  late final List<PreviewCandidate> _candidates = previewCandidates(
    widget.path,
  );

  /// The selected renderer: the first candidate until the reader chooses
  /// another, then that choice.
  late PreviewCandidate? _candidate = _candidates.isEmpty
      ? null
      : _candidates.first;

  late _FilePreviewTab _selectedTab = widget.initialDiff != null
      ? _FilePreviewTab.diff
      : _FilePreviewTab.full;

  /// The PDF page renderer the body draws through: the platform one unless a
  /// pump supplied its own.
  late final PdfPageRenderer _pdfRenderer =
      widget.pdfPageRenderer ?? PlatformPdfPageRenderer();

  /// The office conversion seam: the sheet's own refusal unless a caller
  /// wired a host.
  late final OfficePdfLoader _officePdf = widget.loadOfficePdf ?? _noOfficePdf;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  /// Reads through the selected renderer's loading mode. A path with no
  /// candidate spends no call: no read can change the answer.
  Future<void> _read() async {
    final candidate = _candidate;
    setState(() => _outcome = const _PreviewLoading());
    if (candidate == null) {
      setState(() => _outcome = const _PreviewFailed(_unsupportedFailure));
      return;
    }
    switch (candidate.load) {
      case PreviewLoadMode.textPages:
        await _readText();
      case PreviewLoadMode.bytesComplete:
        await _readBytes(candidate.renderer);
      case PreviewLoadMode.renderer:
        await _readOffice();
    }
  }

  /// Reads the first page of lines. A `not-text` refusal falls back to the
  /// bytes, which is the only host fact that can still name the content.
  Future<void> _readText() async {
    try {
      final content = await widget.readFile(widget.sessionId, widget.path);
      if (!mounted) return;
      setState(() => _outcome = _PreviewRead(content));
    } catch (error, stackTrace) {
      final failure = _classifyFailure(error);
      _reportRefusal(error, stackTrace, failure);
      if (failure.kind == _PreviewFailureKind.notText) {
        final fallback = await _readImageFallback();
        if (!mounted) return;
        if (fallback != null) {
          setState(() => _outcome = fallback);
          return;
        }
      }
      if (!mounted) return;
      setState(() => _outcome = _PreviewFailed(failure));
    }
  }

  /// Reads a whole file's bytes for a renderer that wants them whole — the
  /// document frame or the image body — refusing bytes neither can draw.
  Future<void> _readBytes(PreviewRenderer renderer) async {
    try {
      final bytes = await widget.readFileBytes(widget.sessionId, widget.path);
      if (!mounted) return;
      setState(() => _outcome = _bytesOutcome(renderer, bytes.data));
    } catch (error, stackTrace) {
      final failure = _classifyFailure(error);
      _reportRefusal(error, stackTrace, failure);
      if (!mounted) return;
      setState(() => _outcome = _PreviewFailed(failure));
    }
  }

  /// Reads a document the host converts first. The reference's office body
  /// owns this lifecycle rather than the document host
  /// (`reference/deepseek-harness/packages/client/ui-sidebar-documentpreview/src/client/office/index.ts:41-45`),
  /// so the sheet runs the call and renders its refusal.
  Future<void> _readOffice() async {
    try {
      final document = await _officePdf(widget.sessionId, widget.path);
      if (!mounted) return;
      setState(
        () => _outcome = _PreviewPdf(
          document.data,
          missingFonts: document.missingFonts,
        ),
      );
    } catch (error, stackTrace) {
      final failure = _officeFailure(error);
      _reportRefusal(error, stackTrace, failure);
      if (!mounted) return;
      setState(() => _outcome = _PreviewFailed(failure));
    }
  }

  /// One refused conversion as the state it earns.
  ///
  /// The host names the cause twice: the code is `document-render/failed`, and
  /// `details.reason` carries the kind the reference maps to its own lines
  /// (`.../src/client/office/index.ts:121-130`). Both are read off the
  /// failure's `toString()`, because `app` outside `lib/di/` cannot name
  /// `DshBusinessException`; a wrapped or reworded failure falls to the
  /// generic office state rather than to a wrong one. The reference keeps its
  /// Retry on every one of these, because the host may be able to convert the
  /// next time.
  _PreviewFailure _officeFailure(Object error) {
    final code = _hostCodeOf(error);
    final reason = _hostReasonOf(error);
    return _PreviewFailure(
      kind: switch ((code, reason)) {
        ('gateway/invocation-unavailable', _) ||
        (
          'gateway/service-unavailable',
          _,
        ) => _PreviewFailureKind.officeUnavailable,
        (_, 'input-too-large') ||
        (_, 'output-too-large') => _PreviewFailureKind.officeTooLarge,
        (_, 'invalid-document') ||
        (_, 'unsupported-format') ||
        (_, 'invalid-output') => _PreviewFailureKind.officeInvalid,
        (_, 'timeout') => _PreviewFailureKind.officeTimeout,
        (_, 'busy') => _PreviewFailureKind.officeBusy,
        (_, 'unavailable') => _PreviewFailureKind.officeUnavailable,
        (_, 'source-changed') => _PreviewFailureKind.officeChanged,
        _ => _PreviewFailureKind.officeFailed,
      },
      code: code,
      retryable: true,
    );
  }

  /// The outcome complete [data] earns from [renderer]. The suffix selected
  /// the renderer, never the content: bytes it cannot draw take a state
  /// instead of the decoder.
  _PreviewLoad _bytesOutcome(PreviewRenderer renderer, Uint8List data) {
    switch (renderer) {
      case PreviewRenderer.html:
        try {
          return _PreviewDocument(_htmlDocument(data));
        } on FormatException {
          return const _PreviewFailed(_htmlFailedFailure);
        }
      case PreviewRenderer.image:
        return switch (_imageKind(data)) {
          _ImageKind.raster => _PreviewImage(data),
          _ImageKind.svg => _PreviewDocument(_svgDocument(data)),
          null => const _PreviewFailed(_unsupportedFailure),
        };
      case PreviewRenderer.spreadsheet:
        try {
          return _PreviewSpreadsheet(_spreadsheet(data));
        } on SpreadsheetException catch (error) {
          return _PreviewFailed(_spreadsheetFailure(error.failure));
        }
      case PreviewRenderer.pdf:
        // Whether these bytes are a document the platform renderer can draw is
        // its own answer, so the body asks it and renders its refusal.
        return _PreviewPdf(data);
      case PreviewRenderer.office:
        // The office renderer is registered with `renderer`: it never receives
        // source bytes, and a registry that sent them would be a wiring
        // mistake worth failing on.
        throw StateError('the office renderer converts through the host');
      case PreviewRenderer.text:
        // The text renderer is registered with `textPages`; a registry that
        // asks it for whole bytes would be a wiring mistake, and showing a
        // state instead would hide it.
        throw StateError('the text renderer reads pages, not bytes');
    }
  }

  /// The parsed sheets of complete [data]: the workbook reader for an `xlsx`
  /// path, and the delimited reader for the comma- or tab-separated one, which
  /// is the same pair of parsers the reference selects between
  /// (`.../excel/format.ts:12-16`).
  SpreadsheetPreview _spreadsheet(Uint8List data) {
    final name = documentFileName(widget.path);
    if (name.endsWith('.xlsx')) return parseWorkbook(data);
    final tab = name.endsWith('.tsv');
    return parseDelimited(
      data,
      delimiter: tab ? '\t' : ',',
      sheetName: tab ? 'TSV' : 'CSV',
    );
  }

  /// One parser failure as the state it earns. The reference offers its Retry
  /// for every spreadsheet parse failure, because the file may have been
  /// rewritten on the host since the read.
  _PreviewFailure _spreadsheetFailure(
    SpreadsheetFailure failure,
  ) => _PreviewFailure(
    kind: switch (failure) {
      SpreadsheetFailure.invalid => _PreviewFailureKind.spreadsheetInvalid,
      SpreadsheetFailure.tooLarge => _PreviewFailureKind.spreadsheetTooLarge,
      SpreadsheetFailure.encoding => _PreviewFailureKind.spreadsheetEncoding,
    },
    code: null,
    retryable: true,
  );

  /// The bytes of a file the text read refused, when they are content a
  /// renderer here can draw; null for every other content and for a byte read
  /// that fails, because the refusal is already reported and has a state of
  /// its own.
  Future<_PreviewLoad?> _readImageFallback() async {
    try {
      final bytes = await widget.readFileBytes(widget.sessionId, widget.path);
      return switch (_imageKind(bytes.data)) {
        _ImageKind.raster => _PreviewImage(bytes.data),
        _ImageKind.svg => _PreviewDocument(_svgDocument(bytes.data)),
        null => null,
      };
    } catch (error) {
      ErrorLogCollector.instance.addBreadcrumb(
        'filePreview: byte fallback for ${widget.path} failed: $error',
        level: 'warning',
      );
      return null;
    }
  }

  /// The static document for complete HTML bytes ([basicHtmlDocument]).
  PreviewDocument _htmlDocument(Uint8List data) => PreviewDocument(
    html: basicHtmlDocument(data),
    semanticLabel: AppLocalizations.of(context)!.previewHtmlFrame,
  );

  /// The document that draws complete SVG bytes, announced by file name the
  /// way the reference announces an image
  /// (`.../src/client/image/locales.ts:4-24`).
  PreviewDocument _svgDocument(Uint8List data) => PreviewDocument(
    html: svgImageDocument(data, alt: widget.path),
    semanticLabel: AppLocalizations.of(context)!.previewImageFrame(widget.path),
  );

  /// Reports one refused read through the app's diagnostic seam: the error log
  /// keeps the host code, the session, and the path for the next bug report,
  /// and debug telemetry carries the same fact where the facade exists. A
  /// refusal the app can explain is a warning; an unexplained failure is an
  /// error.
  void _reportRefusal(
    Object error,
    StackTrace stackTrace,
    _PreviewFailure failure,
  ) {
    ErrorLogCollector.instance.captureError(
      error,
      stackTrace: stackTrace,
      level: failure.retryable ? ErrorLogLevel.error : ErrorLogLevel.warning,
      context: <String, Object?>{
        'component': 'filePreview',
        'sessionId': widget.sessionId,
        'path': widget.path,
        'code': failure.code ?? 'none',
      },
    );
    DebugTelemetry.instance?.log(
      'filePreview ${failure.code ?? error.runtimeType}: ${widget.path}',
      level: failure.retryable ? 'error' : 'warn',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final content = switch (_outcome) {
      _PreviewRead(:final content) => content,
      _ => null,
    };
    final binary = content != null && _looksBinary(content.text);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Container(
        decoration: BoxDecoration(
          // The pin's modal (`ui-primitives/Modal.module.css` `.dialog`,
          // :33-46): the panel radius, `bg-layer-2`, `border: 0` and
          // `--dsw-elevation-prominent`. The half-pixel ring rides the shadow,
          // so the old 1px `outlineVariant` border and the M3 elevation-3
          // shadow both go — that is the weight difference on every sheet.
          color: scheme.bgLayer2,
          borderRadius: BorderRadius.circular(kRadiusPanel),
          boxShadow: DshElevation.prominent(scheme),
        ),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(
                  context,
                  l10n,
                  copyable:
                      (content != null && !binary) ||
                      widget.initialDiff != null,
                ),
                if (_candidates.length > 1) _viewerChooser(context, l10n),
                if (widget.initialDiff != null) _tabBar(context, l10n),
                Divider(height: 1, color: scheme.outlineVariant),
                Flexible(child: _body(context, l10n)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(
    BuildContext context,
    AppLocalizations l10n, {
    required bool copyable,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Icon(Icons.description_outlined, size: 20, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.previewFile, style: theme.textTheme.titleSmall),
                Text(
                  widget.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontFamily: kCodeFontFamily,
                    fontFamilyFallback: kCodeFontFamilyFallback,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (copyable)
            IconButton(
              tooltip: l10n.copyContent,
              onPressed: _copyContent,
              icon: Icon(Icons.copy_outlined, color: scheme.onSurfaceVariant),
            ),
          IconButton(
            tooltip: l10n.close,
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.close, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  /// The viewer chooser: the reference's "Open with" menu
  /// (`.../src/client/TextPreview.tsx:267-284`), which is the reader's only way
  /// from a rendered document back to its source. Material's segmented control
  /// is the phone's form of the same choice.
  Widget _viewerChooser(BuildContext context, AppLocalizations l10n) {
    final selected = _candidate;
    if (selected == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: SegmentedButton<PreviewRenderer>(
        segments: [
          for (final candidate in _candidates)
            ButtonSegment(
              value: candidate.renderer,
              label: Text(_viewerLabel(l10n, candidate.renderer)),
              icon: Icon(_viewerIcon(candidate.renderer), size: 14),
            ),
        ],
        selected: {selected.renderer},
        onSelectionChanged: (choice) {
          final next = _candidates.firstWhere(
            (candidate) => candidate.renderer == choice.first,
          );
          setState(() => _candidate = next);
          unawaited(_read());
        },
      ),
    );
  }

  /// One candidate's own name, which is what the reference's chooser lists.
  String _viewerLabel(AppLocalizations l10n, PreviewRenderer renderer) =>
      switch (renderer) {
        PreviewRenderer.html => l10n.previewViewerHtml,
        PreviewRenderer.image => l10n.previewViewerImage,
        PreviewRenderer.spreadsheet => l10n.previewViewerSpreadsheet,
        PreviewRenderer.pdf => l10n.previewViewerPdf,
        PreviewRenderer.office => l10n.previewViewerOffice,
        PreviewRenderer.text => l10n.previewViewerSource,
      };

  IconData _viewerIcon(PreviewRenderer renderer) => switch (renderer) {
    PreviewRenderer.html => Icons.language,
    PreviewRenderer.image => Icons.image_outlined,
    PreviewRenderer.spreadsheet => Icons.table_chart_outlined,
    PreviewRenderer.pdf => Icons.picture_as_pdf_outlined,
    PreviewRenderer.office => Icons.description_outlined,
    PreviewRenderer.text => Icons.code,
  };

  Widget _tabBar(BuildContext context, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: SegmentedButton<_FilePreviewTab>(
        segments: [
          ButtonSegment(
            value: _FilePreviewTab.diff,
            label: Text(l10n.viewDiff),
            icon: const Icon(Icons.difference_outlined, size: 14),
          ),
          ButtonSegment(
            value: _FilePreviewTab.full,
            label: Text(l10n.viewFullFile),
            icon: const Icon(Icons.description_outlined, size: 14),
          ),
        ],
        selected: {_selectedTab},
        onSelectionChanged: (selected) {
          setState(() => _selectedTab = selected.first);
        },
      ),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final diff = widget.initialDiff;
    if (_selectedTab == _FilePreviewTab.diff && diff != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in diff.lines)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: switch (line.kind) {
                      DiffLineKind.delete => scheme.errorContainer.withValues(
                        alpha: 0.35,
                      ),
                      DiffLineKind.insert => scheme.primaryContainer.withValues(
                        alpha: 0.35,
                      ),
                      DiffLineKind.equal => Colors.transparent,
                    },
                    borderRadius: BorderRadius.circular(kShapeChip),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        child: Text(
                          switch (line.kind) {
                            DiffLineKind.delete => '-',
                            DiffLineKind.insert => '+',
                            DiffLineKind.equal => ' ',
                          },
                          style: TextStyle(
                            fontFamily: kCodeFontFamily,
                            fontFamilyFallback: kCodeFontFamilyFallback,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: switch (line.kind) {
                              DiffLineKind.delete => scheme.error,
                              DiffLineKind.insert => scheme.primary,
                              DiffLineKind.equal => scheme.onSurfaceVariant,
                            },
                          ),
                        ),
                      ),
                      Text(
                        line.text,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: kCodeFontFamily,
                          fontFamilyFallback: kCodeFontFamilyFallback,
                          color: scheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return switch (_outcome) {
      _PreviewLoading() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      ),
      _PreviewFailed(:final failure) => _refusedState(context, l10n, failure),
      _PreviewImage(:final data) => _imageBody(context, l10n, data),
      _PreviewDocument(:final document) => _documentBody(context, document),
      _PreviewSpreadsheet(:final preview) => _spreadsheetBody(
        context,
        l10n,
        preview,
      ),
      _PreviewPdf(:final data, :final missingFonts) => _pdfBody(
        context,
        l10n,
        data,
        missingFonts,
      ),
      // Content that decodes but carries NUL bytes or replacement runs takes
      // the same state as the host's own refusal: it is not text either.
      _PreviewRead(:final content) =>
        _looksBinary(content.text)
            ? _refusedState(
                context,
                l10n,
                const _PreviewFailure(
                  kind: _PreviewFailureKind.notText,
                  code: null,
                  retryable: false,
                ),
              )
            : _textWindow(context, l10n, content),
    };
  }

  /// The state for a read the host refused, or for content the renderer cannot
  /// show. Retry appears only when [failure] says the same request can
  /// plausibly succeed later, and the path to copy stands in its place for a
  /// format no read can change.
  Widget _refusedState(
    BuildContext context,
    AppLocalizations l10n,
    _PreviewFailure failure,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (IconData icon, Color color, String message) = switch (failure.kind) {
      _PreviewFailureKind.notText => (
        Icons.data_object,
        scheme.onSurfaceVariant,
        l10n.filePreviewBinary,
      ),
      _PreviewFailureKind.tooLarge => (
        Icons.warning_amber_rounded,
        scheme.warning,
        l10n.filePreviewTooLarge,
      ),
      _PreviewFailureKind.notFound => (
        Icons.search_off,
        scheme.onSurfaceVariant,
        l10n.filePreviewNotFound,
      ),
      _PreviewFailureKind.unsupported => (
        Icons.visibility_off_outlined,
        scheme.onSurfaceVariant,
        l10n.filePreviewUnsupported,
      ),
      _PreviewFailureKind.htmlFailed => (
        Icons.error_outline,
        scheme.error,
        l10n.previewHtmlFailed,
      ),
      _PreviewFailureKind.spreadsheetInvalid => (
        Icons.error_outline,
        scheme.error,
        l10n.previewSpreadsheetInvalid,
      ),
      _PreviewFailureKind.spreadsheetTooLarge => (
        Icons.warning_amber_rounded,
        scheme.warning,
        l10n.previewSpreadsheetTooLarge,
      ),
      _PreviewFailureKind.spreadsheetEncoding => (
        Icons.text_fields,
        scheme.onSurfaceVariant,
        l10n.previewSpreadsheetEncoding,
      ),
      _PreviewFailureKind.officeUnavailable => (
        Icons.cloud_off_outlined,
        scheme.onSurfaceVariant,
        l10n.previewOfficeUnavailable,
      ),
      _PreviewFailureKind.officeInvalid => (
        Icons.error_outline,
        scheme.error,
        l10n.previewOfficeInvalid,
      ),
      _PreviewFailureKind.officeTooLarge => (
        Icons.warning_amber_rounded,
        scheme.warning,
        l10n.previewOfficeTooLarge,
      ),
      _PreviewFailureKind.officeFailed => (
        Icons.error_outline,
        scheme.error,
        l10n.previewOfficeFailed,
      ),
      _PreviewFailureKind.officeTimeout => (
        Icons.timer_off_outlined,
        scheme.warning,
        l10n.previewOfficeTimeout,
      ),
      _PreviewFailureKind.officeBusy => (
        Icons.hourglass_empty,
        scheme.onSurfaceVariant,
        l10n.previewOfficeBusy,
      ),
      _PreviewFailureKind.officeChanged => (
        Icons.sync_problem_outlined,
        scheme.warning,
        l10n.previewOfficeChanged,
      ),
      _PreviewFailureKind.generic => (
        Icons.error_outline,
        scheme.error,
        l10n.filePreviewFailed,
      ),
    };
    final copyPath =
        failure.kind == _PreviewFailureKind.notText ||
        failure.kind == _PreviewFailureKind.unsupported;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 32, color: color),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: color),
          ),
          if (failure.retryable) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _read,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(l10n.retry),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: scheme.outlineVariant),
              ),
            ),
          ],
          if (copyPath) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _copyPath,
              icon: Icon(
                Icons.copy_outlined,
                size: 14,
                color: scheme.onSurfaceVariant,
              ),
              label: Text(l10n.copyPath),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                side: BorderSide(color: scheme.outlineVariant),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The whole-file image: bytes the sheet already checked for an image
  /// signature, with the cannot-preview state as the decoder's own backstop.
  Widget _imageBody(
    BuildContext context,
    AppLocalizations l10n,
    Uint8List data,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Center(
        child: Image.memory(
          data,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) =>
              _refusedState(context, l10n, _unsupportedFailure),
        ),
      ),
    );
  }

  /// The prepared document in its frame.
  ///
  /// A platform view needs bounded constraints, and the sheet's column gives
  /// its body loose ones, so the document seat names its own height: the
  /// reference's document pane fills a sidebar that is always as tall as the
  /// window, and three fifths of the screen is the phone's version of that
  /// seat under the 80% sheet ceiling.
  Widget _documentBody(BuildContext context, PreviewDocument document) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(kRadiusLg),
          child: widget.frameBuilder(context, document),
        ),
      ),
    );
  }

  /// The parsed sheets, with the formula notice the reference shows above them
  /// when any cell carries a formula
  /// (`.../src/client/excel/excel.tsx:50,58-62`). The grid owns its own
  /// scrolling, so it takes the body's remaining height.
  Widget _spreadsheetBody(
    BuildContext context,
    AppLocalizations l10n,
    SpreadsheetPreview preview,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasFormulas = preview.sheets.any((sheet) => sheet.hasFormulas);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasFormulas)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.bgLayer2,
                borderRadius: BorderRadius.circular(kRadiusLg),
                boxShadow: DshElevation.prominent(scheme),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.functions,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.previewSpreadsheetFormulas,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(kRadiusLg),
              child: SpreadsheetGrid(preview: preview),
            ),
          ),
        ],
      ),
    );
  }

  /// The document's pages through the platform renderer.
  ///
  /// This body owns no failure state of its own: the renderer reports a
  /// document it cannot open and each page it cannot draw, and both carry
  /// their own Retry — which is the reference's PDF body
  /// (`.../src/client/pdf/pdf.tsx:86-91,196-199`).
  Widget _pdfBody(
    BuildContext context,
    AppLocalizations l10n,
    Uint8List data,
    List<String> missingFonts,
  ) {
    final pages = PdfPageView(
      data: data,
      renderer: _pdfRenderer,
      failureLabel: l10n.previewPdfFailed,
      passwordLabel: l10n.previewPdfPassword,
      pageFailureLabel: l10n.previewPdfPageFailed,
      retryLabel: l10n.retry,
    );
    if (missingFonts.isEmpty) return pages;
    // The reference offers the missing families in a dialog from its toolbar
    // (`.../office/FontNotice.tsx`); the phone states the same fact inline,
    // because the note is the whole recourse a reader has here.
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: scheme.bgLayer2,
            borderRadius: BorderRadius.circular(kRadiusLg),
            boxShadow: DshElevation.prominent(scheme),
          ),
          child: Row(
            children: [
              Icon(
                Icons.font_download_off_outlined,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.previewOfficeMissingFonts(missingFonts.length),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: pages),
      ],
    );
  }

  /// Copies the path the header shows, the recourse a format with no renderer
  /// leaves the reader.
  Future<void> _copyPath() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    await Clipboard.setData(ClipboardData(text: widget.path));
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.copiedFeedback),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// The paged text window: the host's truncation signal, then the rendered
  /// document.
  Widget _textWindow(
    BuildContext context,
    AppLocalizations l10n,
    WorkspaceFileContent content,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = content.text;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The host pages large files: a window that is not the end of the
          // file reports how many lines it returned.
          if (!content.eof)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                // The pin's in-preview notice panel
                // (`ui-sidebar-documentpreview/.../office/FontNotice.module.css`
                // `.panel`, :14-31): `bg-layer-2`, `border: 0`,
                // `--dsw-radius-lg` and `--dsw-elevation-prominent`; the pdf
                // page surface takes the same shadow
                // (`.../pdf/PdfBody.module.css` `.surface`, :43-48). The
                // half-pixel ring rides the shadow, so the old flat
                // `surfaceContainerHigh` chip goes.
                color: scheme.bgLayer2,
                borderRadius: BorderRadius.circular(kRadiusLg),
                boxShadow: DshElevation.prominent(scheme),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.unfold_more,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.filePreviewTruncated(content.lines),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (text.trim().isEmpty)
            Text(
              l10n.filePreviewEmpty,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            )
          else
            MarkdownText(text: _renderable(widget.path, text)),
        ],
      ),
    );
  }

  Future<void> _copyContent() async {
    final diff = widget.initialDiff;
    final String textToCopy;
    if (_selectedTab == _FilePreviewTab.diff && diff != null) {
      textToCopy = [
        for (final line in diff.lines)
          '${line.kind == DiffLineKind.delete
              ? '-'
              : line.kind == DiffLineKind.insert
              ? '+'
              : ' '} ${line.text}',
      ].join('\n');
    } else {
      textToCopy = switch (_outcome) {
        _PreviewRead(:final content) => content.text,
        _ => '',
      };
    }
    if (textToCopy.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    await Clipboard.setData(ClipboardData(text: textToCopy));
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.copiedFeedback),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

/// Text the existing renderer understands: a markdown document passes
/// through, any other file is wrapped in a fenced block so it takes the
/// code surface (monospace, horizontal scroll) instead of being reflowed
/// as prose.
String _renderable(String path, String text) {
  if (_markdownExtensions.any(path.toLowerCase().endsWith)) return text;
  final language = _languageFor(path);
  return '```${language ?? ''}\n$text\n```';
}

/// Binary or undecodable content: a NUL byte, or a run of Unicode
/// replacement characters the JSON text decode produced for bytes that are
/// not valid UTF-8.
bool _looksBinary(String text) {
  if (text.isEmpty) return false;
  final sample = text.length > 4096 ? text.substring(0, 4096) : text;
  var replacement = 0;
  var total = 0;
  for (final rune in sample.runes) {
    total += 1;
    if (rune == 0) return true;
    if (rune == 0xFFFD) replacement += 1;
  }
  return total > 0 && replacement > total * 0.05;
}

/// The image content [data] carries, or null when it carries neither a raster
/// signature the decoder reads nor an SVG document to hand the frame.
///
/// The suffix selected the renderer, never the content: bytes `Image.memory`
/// would reject take a state instead of reaching it.
_ImageKind? _imageKind(Uint8List data) {
  if (_signature(data) != null) return _ImageKind.raster;
  return _looksSvgBytes(data) ? _ImageKind.svg : null;
}

/// Whether bytes start an SVG document: its root element, or an XML
/// declaration before it, after a byte-order mark and leading whitespace.
bool _looksSvgBytes(Uint8List data) {
  final sample = data.length > 4096 ? data.sublist(0, 4096) : data;
  final text = _decodedOrEmpty(sample).trimLeft().replaceFirst('\uFEFF', '');
  if (!text.startsWith('<')) return false;
  final lower = text.toLowerCase();
  return lower.startsWith('<svg') ||
      (lower.startsWith('<?xml') && lower.contains('<svg'));
}

/// Bytes decoded as UTF-8 for sniffing only, with malformed sequences
/// replaced. Nothing decoded here is ever rendered.
String _decodedOrEmpty(Uint8List data) =>
    utf8.decode(data, allowMalformed: true);

/// The image formats this sheet tells apart, because they take different
/// bodies: a raster the app's own decoder draws, and an SVG the document frame
/// does.
enum _ImageKind { raster, svg }

/// The image format [data]'s leading bytes name, or null when they name none
/// this sheet knows.
String? _signature(Uint8List data) {
  bool at(int index, List<int> bytes) {
    if (data.length < index + bytes.length) return false;
    for (var i = 0; i < bytes.length; i++) {
      if (data[index + i] != bytes[i]) return false;
    }
    return true;
  }

  if (at(0, <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return 'png';
  }
  if (at(0, <int>[0xFF, 0xD8, 0xFF])) return 'jpeg';
  if (at(0, <int>[0x47, 0x49, 0x46, 0x38])) return 'gif';
  if (at(0, <int>[0x52, 0x49, 0x46, 0x46]) &&
      at(8, <int>[0x57, 0x45, 0x42, 0x50])) {
    return 'webp';
  }
  if (at(0, <int>[0x42, 0x4D])) return 'bmp';
  if (at(0, <int>[0x00, 0x00, 0x01, 0x00])) return 'ico';
  return null;
}

/// Host codes naming a refusal the same read meets again.
///
/// The workspace-files service throws the file ones
/// (`reference/deepseek-harness/packages/api/workspace-files/src/index.ts`):
/// `read()` refuses a page carrying NUL (line 243) and `cutPage()`'s `admit()`
/// refuses a page over `maxBytes` (line 128); `locateFile()` refuses a vanished
/// entry (line 427) and a non-regular file (line 422); `confine()` refuses a
/// path outside the workspace (line 405).
///
/// The gateway throws the rest before dispatching anything
/// (`reference/deepseek-harness/packages/api/gateway/src/index.ts`):
/// `gateway/bad-request` and `gateway/arguments-invalid` refuse malformed
/// arguments; `gateway/lookup-not-found` (line 981) refuses a
/// `workspaceFileScopeId` that resolves to no Session — a disposed, archived,
/// or foreign session, or a host that restarted with a different roster;
/// `gateway/lookup-unavailable` (lines 943, 952) and
/// `gateway/provider-mismatch` (line 961) refuse a lookup provider the host
/// does not register or that disagrees with its strict definition. A compose,
/// a session roster, or a host build is what would have to change, not the
/// request, so a second identical read cannot succeed.
const Set<String> _repeatRefusals = <String>{
  'workspace-file/not-text',
  'workspace-file/too-large',
  'workspace-file/not-found',
  'workspace-file/not-regular-file',
  'workspace-file/outside-workspace',
  'gateway/bad-request',
  'gateway/arguments-invalid',
  'gateway/lookup-not-found',
  'gateway/lookup-unavailable',
  'gateway/provider-mismatch',
};

/// The host's machine code on [error], or null when the failure carried none.
///
/// `app` outside `lib/di/` cannot name `DshBusinessException` — the import
/// gate keeps `package:network/` behind the DI assembly — so the code is read
/// from the exception's `DshBusinessException: <code>: <message>`
/// `toString()`, the recognition `ChatController._formatUiError` already uses
/// for `session-persistence/already-owned`. The anchored pattern reaches the
/// code only on that exact prefix, so a wrapped or reworded failure falls
/// through to the generic state instead of taking a wrong one.
String? _hostCodeOf(Object error) =>
    _hostCodePattern.firstMatch(error.toString())?.group(1);

final RegExp _hostCodePattern = RegExp(
  r'^DshBusinessException: ([a-z][a-z0-9-]*\/[a-z0-9-]+): ',
);

/// The `details.reason` a refusal carried, or null when it carried none.
///
/// The host names a conversion failure's cause there
/// (`document-render/failed` with `{reason: <code>}`); the details map reaches
/// a widget only through the same `toString()` the code does, so the reason is
/// read the same way and an unreadable one falls to the generic state.
String? _hostReasonOf(Object error) =>
    _hostReasonPattern.firstMatch(error.toString())?.group(1);

final RegExp _hostReasonPattern = RegExp(r'reason: ([a-z][a-z0-9-]*)');

/// Classifies one failed read. The mapping is total: a code the sheet does not
/// know, and a failure that carries no code at all, take [generic].
_PreviewFailure _classifyFailure(Object error) {
  final code = _hostCodeOf(error);
  return _PreviewFailure(
    kind: switch (code) {
      'workspace-file/not-text' => _PreviewFailureKind.notText,
      'workspace-file/too-large' => _PreviewFailureKind.tooLarge,
      'workspace-file/not-found' => _PreviewFailureKind.notFound,
      _ => _PreviewFailureKind.generic,
    },
    code: code,
    retryable: code == null || !_repeatRefusals.contains(code),
  );
}

const List<String> _markdownExtensions = <String>['.md', '.markdown', '.mdx'];

String? _languageFor(String path) {
  final name = path.split('/').last;
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return null;
  return name.substring(dot + 1).toLowerCase();
}
