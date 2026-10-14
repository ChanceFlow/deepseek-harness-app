/// The PDF body: one page image per document page, drawn as it is reached.
///
/// The reference renders a PDF into one canvas per page, lazily, over the
/// document's complete bytes
/// (`reference/deepseek-harness/packages/client/ui-sidebar-documentpreview/src/client/pdf/pdf.tsx:92-98,144`),
/// and keeps a Retry on both the document load and each page
/// (`.../pdf/pdf.tsx:86-91,196-199`). The phone's counterpart is the platform
/// renderer behind [PdfPageRenderer] and a list that asks for a page when it
/// builds one, so a long document costs the pages a reader actually reaches.
///
/// A page is rastered to [kPdfPageMaxPixels] rather than its natural size: the
/// reference caps a page at 16 777 216 device pixels
/// (`.../pdf/document.ts:54-58`), which is a desktop canvas, and one page of a
/// phone preview does not need it.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../platform/pdf_page_renderer.dart';

/// The pixel budget one page is rastered to. The renderer keeps the page's
/// aspect ratio inside it.
const int kPdfPageMaxPixels = 4 * 1024 * 1024;

/// One rendered PDF document.
class PdfPageView extends StatefulWidget {
  const PdfPageView({
    required this.data,
    required this.renderer,
    required this.failureLabel,
    required this.passwordLabel,
    required this.pageFailureLabel,
    required this.retryLabel,
    super.key,
  });

  /// The document's complete bytes.
  final Uint8List data;

  final PdfPageRenderer renderer;

  /// Shown when the document could not be opened at all.
  final String failureLabel;

  /// Shown instead of [failureLabel] when the document is encrypted, which the
  /// reference names as its own state
  /// (`.../src/client/pdf/locales.ts:6-8,23-25`).
  final String passwordLabel;

  /// Shown on a page the renderer refused; it carries [retryLabel].
  final String pageFailureLabel;

  final String retryLabel;

  @override
  State<PdfPageView> createState() => _PdfPageViewState();
}

class _PdfPageViewState extends State<PdfPageView> {
  PdfDocument? _document;
  bool _loading = true;
  bool _failed = false;
  late String _failureLabel = widget.failureLabel;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    final document = await widget.renderer.open(widget.data);
    // The reason lives on the renderer, because `open` answers null for every
    // one of them; an encrypted document reads as its own state.
    final reason = document == null ? widget.renderer.lastOpenFailure : null;
    if (!mounted) {
      await document?.close();
      return;
    }
    setState(() {
      _loading = false;
      _document = document;
      _failed = document == null;
      _failureLabel = reason == PdfRenderFailure.password
          ? widget.passwordLabel
          : widget.failureLabel;
    });
  }

  @override
  void dispose() {
    final document = _document;
    if (document != null) unawaited(document.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final document = _document;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_failed || document == null) {
      return _PdfFailure(
        label: _failureLabel,
        retryLabel: widget.retryLabel,
        onRetry: _open,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: document.pageCount,
      itemBuilder: (context, index) => _PdfPage(
        document: document,
        index: index,
        failureLabel: widget.pageFailureLabel,
        retryLabel: widget.retryLabel,
      ),
    );
  }
}

/// One page: its image once the renderer answers, its own spinner before, and
/// its own Retry after a refusal.
class _PdfPage extends StatefulWidget {
  const _PdfPage({
    required this.document,
    required this.index,
    required this.failureLabel,
    required this.retryLabel,
  });

  final PdfDocument document;
  final int index;
  final String failureLabel;
  final String retryLabel;

  @override
  State<_PdfPage> createState() => _PdfPageState();
}

class _PdfPageState extends State<_PdfPage> {
  PdfPageImage? _image;
  bool _loading = true;
  bool _failed = false;
  bool _requested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The raster width needs the view's density, which only a dependency read
    // can give.
    if (_requested) return;
    _requested = true;
    unawaited(_render());
  }

  Future<void> _render() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    // A page's own 72 dpi size is too coarse for a dense screen, so the raster
    // is asked for at the width the reader will see.
    final media = MediaQuery.of(context);
    final image = await widget.document.renderPage(
      widget.index,
      targetWidth: (media.size.width * media.devicePixelRatio).round(),
      maxPixels: kPdfPageMaxPixels,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _image = image;
      _failed = image == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (_loading) {
      return const SizedBox(
        height: 360,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_failed || image == null) {
      return SizedBox(
        height: 240,
        child: _PdfFailure(
          label: widget.failureLabel,
          retryLabel: widget.retryLabel,
          onRetry: _render,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Image.memory(image.bytes, fit: BoxFit.contain),
    );
  }
}

/// One failure state with its Retry: the document's, or one page's.
class _PdfFailure extends StatelessWidget {
  const _PdfFailure({
    required this.label,
    required this.retryLabel,
    required this.onRetry,
  });

  final String label;
  final String retryLabel;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.picture_as_pdf_outlined, size: 32, color: scheme.error),
          const SizedBox(height: 12),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => unawaited(onRetry()),
            icon: const Icon(Icons.refresh, size: 16),
            label: Text(retryLabel),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: scheme.outlineVariant),
            ),
          ),
        ],
      ),
    );
  }
}
