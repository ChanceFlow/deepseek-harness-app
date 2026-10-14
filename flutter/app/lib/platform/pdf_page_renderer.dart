/// Platform bridge for rendering PDF pages with Android's own `PdfRenderer`.
///
/// The preview sheet cannot draw a PDF from Dart: the format needs a real
/// renderer, and the repository forbids prebuilt native libraries, so the
/// platform side hands the complete bytes to `android.graphics.pdf.PdfRenderer`
/// (AOSP, API 21+) and answers one page at a time as PNG
/// (`PdfPageRendererBridge.kt`, channel `dsh/pdf_page_renderer`). A page is
/// rastered at its natural size and shrunk only when that exceeds a
/// caller-supplied pixel budget, because a full-size page is more memory than
/// a phone should spend on a preview.
///
/// Every call is non-throwing. Where no host implements the channel (widget
/// tests, desktop, a build that never registered the bridge)
/// [PdfPageRenderer.open] answers null — the sheet's cannot-preview state —
/// and [PdfPageRenderer.lastOpenFailure] says [PdfRenderFailure.unsupported]. A
/// page that fails to render answers null too, which the sheet shows as that
/// page's own retryable state.
library;

import 'package:flutter/services.dart';

/// Method channel name; must match `PdfPageRendererBridge.kt`.
const String kPdfPageRendererChannel = 'dsh/pdf_page_renderer';

/// One rendered PDF page: PNG bytes and the pixel size they decode to.
class PdfPageImage {
  const PdfPageImage({
    required this.bytes,
    required this.width,
    required this.height,
  });

  /// The page as a PNG, at the size the caller's pixel budget allowed.
  final Uint8List bytes;

  /// Pixel width of the image [bytes] decodes to.
  final int width;

  /// Pixel height of the image [bytes] decodes to.
  final int height;
}

/// Why a PDF could not be opened or rendered, as the frame reports it.
enum PdfRenderFailure {
  /// This build has no PDF renderer for the file: the platform side is absent
  /// (widget tests, desktop), or the host refused the document as
  /// unrenderable — more memory than it could hold. The sheet's
  /// cannot-preview state.
  unsupported,

  /// The bytes are not a document the renderer can read — truncated, not a PDF
  /// at all, or a container the platform's renderer rejects.
  invalid,

  /// The document is encrypted and needs a password, which a preview sheet has
  /// no surface to ask for. Android's `PdfRenderer` reports this state with a
  /// `SecurityException`.
  password,

  /// The host reported a failure this contract does not name, or answered a
  /// reply the contract does not describe.
  failed,
}

/// An open document. Pages are 0-based.
abstract class PdfDocument {
  /// The page count the host reported when the document was opened.
  int get pageCount;

  /// Renders page [index] as a PNG whose width is [targetWidth] pixels.
  ///
  /// The host rasters the page at its natural size — its PDF size in points,
  /// 72 dpi — scales it to [targetWidth] with the aspect ratio kept, and then
  /// scales further down when the result exceeds the [maxPixels] ceiling. The
  /// ceiling therefore bounds memory; [targetWidth] is what makes a page crisp
  /// on a dense screen, because a page is never left at its 72 dpi size.
  ///
  /// Answers null when the page cannot be drawn: a [targetWidth] below one, an
  /// index outside the document, a host failure, or a reply this contract does
  /// not describe. The sheet shows that as the page's own retryable state.
  /// Never throws.
  Future<PdfPageImage?> renderPage(
    int index, {
    required int targetWidth,
    required int maxPixels,
  });

  /// Releases the host's renderer, its file descriptor and its cache-file
  /// copy.
  ///
  /// Safe to call more than once: a second call answers without touching the
  /// channel. Never throws.
  Future<void> close();
}

/// The platform seam. Overridden in tests; the real one is
/// [PlatformPdfPageRenderer]. `open` returns null when this build has no
/// renderer.
abstract class PdfPageRenderer {
  const PdfPageRenderer();

  /// Opens [bytes] — the complete file — as a document.
  ///
  /// Answers null when the host has no renderer, the bytes are not a readable
  /// PDF, or the document is encrypted; [lastOpenFailure] then carries the
  /// reason. Never throws.
  Future<PdfDocument?> open(Uint8List bytes);

  /// Why the most recent [open] answered null, and null when it opened a
  /// document.
  ///
  /// A substitute with no renderer (a test fake, another platform) inherits
  /// null, which reads as "no reason to report". The value describes the most
  /// recent [open] on this instance, so concurrent opens make it ambiguous.
  PdfRenderFailure? get lastOpenFailure => null;
}

/// The failure a host error code names.
///
/// The codes are `PdfPageRendererBridge.kt`'s: `unsupported` — this build has
/// no PDF renderer for the file, or the host could not hold it in memory;
/// `invalid` — the bytes are not a PDF the renderer can read; `password` — the
/// document is encrypted, which Android's `PdfRenderer` reports as a
/// `SecurityException`; `failed` — every other host failure. Any other code,
/// including null, reads as [PdfRenderFailure.failed]. Never throws.
PdfRenderFailure pdfRenderFailureFromCode(Object? code) {
  switch (code) {
    case 'unsupported':
      return PdfRenderFailure.unsupported;
    case 'invalid':
      return PdfRenderFailure.invalid;
    case 'password':
      return PdfRenderFailure.password;
    default:
      return PdfRenderFailure.failed;
  }
}

/// The production seam: talks to [kPdfPageRendererChannel].
///
/// Not const: the instance remembers what its most recent [open] reported.
class PlatformPdfPageRenderer extends PdfPageRenderer {
  PlatformPdfPageRenderer({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(kPdfPageRendererChannel);

  final MethodChannel _channel;

  PdfRenderFailure? _lastOpenFailure;

  @override
  PdfRenderFailure? get lastOpenFailure => _lastOpenFailure;

  @override
  Future<PdfDocument?> open(Uint8List bytes) async {
    _lastOpenFailure = null;
    try {
      final Map<String, Object?>? reply = await _channel
          .invokeMapMethod<String, Object?>('open', <String, Object>{
            'bytes': bytes,
          });
      final Object? token = reply?['token'];
      final Object? count = reply?['count'];
      if (token is! String || token.isEmpty || count is! int || count < 0) {
        // A reply the contract does not describe; a document with no usable
        // handle is no better than a refused one.
        _lastOpenFailure = PdfRenderFailure.failed;
        return null;
      }
      return _PlatformPdfDocument(_channel, token, pageCount: count);
    } on MissingPluginException {
      // No platform side registered the channel: a build without the bridge
      // shows the sheet's cannot-preview state.
      _lastOpenFailure = PdfRenderFailure.unsupported;
      return null;
    } on PlatformException catch (error) {
      _lastOpenFailure = pdfRenderFailureFromCode(error.code);
      return null;
    }
  }
}

/// One open document on the host, addressed by the token `open` answered.
class _PlatformPdfDocument implements PdfDocument {
  _PlatformPdfDocument(this._channel, this._token, {required this.pageCount});

  final MethodChannel _channel;
  final String _token;

  @override
  final int pageCount;

  bool _closed = false;

  @override
  Future<PdfPageImage?> renderPage(
    int index, {
    required int targetWidth,
    required int maxPixels,
  }) async {
    if (_closed || index < 0 || index >= pageCount || targetWidth < 1) {
      return null;
    }
    final Map<String, Object?>? reply = await _invoke(
      'renderPage',
      <String, Object>{
        'token': _token,
        'index': index,
        'targetWidth': targetWidth,
        'maxPixels': maxPixels,
      },
    );
    final Object? bytes = reply?['bytes'];
    final Object? width = reply?['width'];
    final Object? height = reply?['height'];
    if (bytes is! Uint8List || bytes.isEmpty) return null;
    if (width is! int || width <= 0 || height is! int || height <= 0) {
      return null;
    }
    return PdfPageImage(bytes: bytes, width: width, height: height);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    // Marked before the await so a second close cannot reach the channel.
    _closed = true;
    await _invoke('close', <String, Object>{'token': _token});
  }

  /// Invokes [method] with [arguments], answering null on any host failure.
  Future<Map<String, Object?>?> _invoke(
    String method,
    Map<String, Object> arguments,
  ) async {
    try {
      return await _channel.invokeMapMethod<String, Object?>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
