/// File preview sheet — the surface behind a tool row's "Preview" action.
///
/// Dispatches one path to the renderer its file type has, the way the
/// reference preview does
/// (`reference/deepseek-harness/packages/client/ui-sidebar-documentpreview/src/client/TextPreview.tsx`):
/// a text-like path reads a page of lines (`workspaceFiles/read`) and renders
/// through the app's existing markdown/code renderer, an image path reads
/// whole bytes (`workspaceFiles/readBytes`) and renders them, and a format with
/// no renderer gets a notice with the path to copy. A type the suffix cannot
/// settle falls back to the host's own answer: the text read's
/// `workspace-file/not-text` refusal proves the content is not text, and the
/// bytes themselves then decide image or unrenderable. A bottom sheet is the
/// natural Material 3 fit: the action is invoked from an expanded transcript
/// row, so the content opens as a modal surface over the same context instead
/// of a route push that hides the conversation.
///
/// A read the host refuses renders the state it refused for — a page that is
/// not text, a page over the host's byte cap, a vanished path — and offers
/// Retry only where the same request can plausibly succeed later. Every
/// refused read is reported with its host code and path through the app's
/// diagnostic seam, so the error log names the cause. The host's own paging
/// signal (`eof == false`) surfaces the window's line count.
library;

import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:dev/dev.dart' show DebugTelemetry;
import 'package:domain/model/workspace_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../logging/error_log_collector.dart';
import '../../logging/error_log_entry.dart' show ErrorLogLevel;
import '../theme/theme.dart';
import 'markdown/markdown_text.dart';
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

/// Opens the preview sheet for [path]. [readFile] and [readFileBytes] are the
/// chat surface's repository seams; the sheet never reaches past them.
Future<void> showFilePreviewSheet(
  BuildContext context, {
  required String sessionId,
  required String path,
  required WorkspaceFileReader readFile,
  required WorkspaceFileBytesReader readFileBytes,
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
    this.initialDiff,
    super.key,
  });

  final String sessionId;
  final String path;
  final WorkspaceFileReader readFile;
  final WorkspaceFileBytesReader readFileBytes;
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
  /// (`_unrenderableSuffixes`), or bytes that are not an image the app can
  /// decode. The state offers the path to copy instead of a Retry that cannot
  /// change the format.
  unsupported,

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

/// The renderer a path's file type selects, by the reference's longest-suffix
/// rule (`reference/.../src/client/document/suffix.ts`).
enum _PreviewKind { text, image, unsupported }

/// The unrenderable state, which never came from a host failure.
const _PreviewFailure _unsupportedFailure = _PreviewFailure(
  kind: _PreviewFailureKind.unsupported,
  code: null,
  retryable: false,
);

class _FilePreviewSheetState extends State<FilePreviewSheet> {
  _PreviewLoad _outcome = const _PreviewLoading();
  late _FilePreviewTab _selectedTab = widget.initialDiff != null
      ? _FilePreviewTab.diff
      : _FilePreviewTab.full;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  /// Reads the page, the bytes, or nothing at all, depending on the renderer
  /// the path's file type selects.
  Future<void> _read() async {
    setState(() => _outcome = const _PreviewLoading());
    switch (_previewKindOf(widget.path)) {
      case _PreviewKind.text:
        await _readText();
      case _PreviewKind.image:
        await _readBytes();
      case _PreviewKind.unsupported:
        // No renderer exists for this format, so no read can change the
        // answer; the state names the path instead of spending a call.
        setState(() => _outcome = const _PreviewFailed(_unsupportedFailure));
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
        final image = await _readImageBytes();
        if (!mounted) return;
        if (image != null) {
          setState(() => _outcome = _PreviewImage(image));
          return;
        }
      }
      if (!mounted) return;
      setState(() => _outcome = _PreviewFailed(failure));
    }
  }

  /// Reads a whole file's bytes for the image renderer, refusing bytes that
  /// are not an image rather than handing them to the decoder.
  Future<void> _readBytes() async {
    try {
      final bytes = await widget.readFileBytes(widget.sessionId, widget.path);
      if (!mounted) return;
      setState(
        () => _outcome = _looksImageBytes(bytes.data)
            ? _PreviewImage(bytes.data)
            : const _PreviewFailed(_unsupportedFailure),
      );
    } catch (error, stackTrace) {
      final failure = _classifyFailure(error);
      _reportRefusal(error, stackTrace, failure);
      if (!mounted) return;
      setState(() => _outcome = _PreviewFailed(failure));
    }
  }

  /// The bytes of a file the text read refused, when they are an image; null
  /// for every other content and for a byte read that fails, because the
  /// refusal is already reported and has a state of its own.
  Future<Uint8List?> _readImageBytes() async {
    try {
      final bytes = await widget.readFileBytes(widget.sessionId, widget.path);
      return _looksImageBytes(bytes.data) ? bytes.data : null;
    } catch (error) {
      ErrorLogCollector.instance.addBreadcrumb(
        'filePreview: byte fallback for ${widget.path} failed: $error',
        level: 'warning',
      );
      return null;
    }
  }

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

/// The renderer a path selects.
///
/// The suffix decides which read to make, never what the bytes are: a text
/// read that the host refuses still gets its bytes sniffed, and bytes that
/// carry no image signature take the unrenderable state. Matching is the
/// reference's longest declared suffix over the lowercased basename
/// (`documentFileName` at
/// `reference/deepseek-harness/packages/client/ui-sidebar-documentpreview/src/client/document/suffix.ts:20`
/// and `matchedSuffixLength` at `:31`), so a compound suffix such as `tar.gz`
/// matches as a unit.
_PreviewKind _previewKindOf(String path) {
  final name = _fileNameOf(path);
  if (_hasSuffix(name, _imageSuffixes)) return _PreviewKind.image;
  if (_hasSuffix(name, _unrenderableSuffixes)) return _PreviewKind.unsupported;
  return _PreviewKind.text;
}

String _fileNameOf(String path) {
  final normalized = path.replaceAll(r'\', '/').toLowerCase();
  return normalized.substring(normalized.lastIndexOf('/') + 1);
}

bool _hasSuffix(String name, List<String> suffixes) =>
    suffixes.any((suffix) => name.endsWith('.$suffix'));

/// Raster formats the app's image decoder reads: the reference's
/// `BINARY_IMAGE_EXTENSIONS` (png, jpg, jpeg, gif, webp, bmp, ico —
/// `reference/deepseek-harness/packages/client/ui-sidebar-documentpreview/src/client/image/index.ts:19`)
/// plus `wbmp`. SVG stays out because its XML source is readable text and the
/// decoder cannot draw it; the sibling `IMAGE_EXTENSIONS` at `:16` registers
/// SVG for the reference's own SVG renderer.
const List<String> _imageSuffixes = <String>[
  'png',
  'jpg',
  'jpeg',
  'gif',
  'webp',
  'bmp',
  'wbmp',
  'ico',
];

/// Suffixes whose bytes are never readable text and that have no renderer
/// here: the reference's `UNVIEWABLE_BINARY_EXTENSIONS`
/// (`reference/.../src/client/document/unviewable.ts:10-28`) plus `pdf`,
/// `apk`, `aar`, and `dex`, which the reference renders or ships compiled. A
/// suffix stays out when its bytes might be text, so `.svg`, `.html`, `.csv`,
/// and `.key` keep the text path.
const List<String> _unrenderableSuffixes = <String>[
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

/// Whether bytes start with an image signature the decoder reads.
///
/// The suffix is not evidence about content, so a byte read that the decoder
/// would reject is refused before it reaches `Image.memory`.
bool _looksImageBytes(Uint8List data) {
  final signature = _signature(data);
  if (signature == null) return false;
  return switch (signature) {
    'png' || 'jpeg' || 'gif' || 'webp' || 'bmp' || 'ico' => true,
    _ => false,
  };
}

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
