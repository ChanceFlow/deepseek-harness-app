/// The production document frame: the platform WebView under the static mode.
///
/// The reference's static mode is an iframe with `sandbox=""` and a
/// restrictive CSP
/// (`reference/deepseek-harness/packages/client/ui-sidebar-documentpreview/src/client/html/HtmlBody.tsx:86,102`;
/// `.../html/basic-document.ts:10-21`). The phone's counterpart is the system
/// WebView with scripts disabled, file and content access off, media held for
/// a gesture, and every navigation the document asks for refused — the
/// prepared document
/// ([basicHtmlDocument]/[svgImageDocument]) supplies the sanitized markup and
/// the policy.
///
/// No host state enters the frame: the document string is complete, so the
/// WebView is a leaf that never reaches a repository, a session or a path.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'document_frame.dart';

/// The document frame the app ships.
Widget buildWebViewDocumentFrame(
  BuildContext context,
  PreviewDocument document,
) => WebViewDocumentFrame(document: document);

/// One prepared document in one WebView.
class WebViewDocumentFrame extends StatefulWidget {
  const WebViewDocumentFrame({required this.document, super.key});

  final PreviewDocument document;

  @override
  State<WebViewDocumentFrame> createState() => _WebViewDocumentFrameState();
}

class _WebViewDocumentFrameState extends State<WebViewDocumentFrame> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = _createController();
  }

  @override
  void didUpdateWidget(covariant WebViewDocumentFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document.html != widget.document.html) {
      unawaited(_controller.loadHtmlString(widget.document.html));
    }
  }

  WebViewController _createController() {
    final controller = WebViewController();
    unawaited(_configure(controller));
    return controller;
  }

  /// Applies the static mode before the document is loaded: scripts off, every
  /// navigation refused, and — on the platform this app ships for — file and
  /// content access off with media held for a gesture.
  Future<void> _configure(WebViewController controller) async {
    await controller.setJavaScriptMode(JavaScriptMode.disabled);
    await controller.setBackgroundColor(Colors.transparent);
    await controller.setNavigationDelegate(
      NavigationDelegate(
        // A prepared document is loaded as `about:blank`. Everything else is
        // a navigation the document asked for, and the static mode has none:
        // `href` attributes are already gone, so this is the second half of
        // the guarantee rather than the only one.
        onNavigationRequest: (request) =>
            request.isMainFrame && request.url == 'about:blank'
            ? NavigationDecision.navigate
            : NavigationDecision.prevent,
      ),
    );
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      // `file:` and `content:` loads, and media that starts without a gesture,
      // are the two things the policy alone would leave to the engine's
      // judgement.
      await platform.setAllowFileAccess(false);
      await platform.setAllowContentAccess(false);
      await platform.setMediaPlaybackRequiresUserGesture(true);
    }
    await controller.loadHtmlString(widget.document.html);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.document.semanticLabel,
      container: true,
      child: WebViewWidget(controller: _controller),
    );
  }
}
