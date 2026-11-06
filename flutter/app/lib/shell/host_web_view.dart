/// One backend host's WebView: the dsh web UI, untouched.
///
/// The shell renders the host's own client, so the surface always matches the
/// host's version. Nothing is injected: the notification pipeline reads the
/// host's API on its own socket, and the page keeps its own navigation state.
library;

import 'dart:async';

import 'package:domain/model/backend.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// A host's page inside the shell.
class HostWebView extends StatefulWidget {
  const HostWebView({required this.backend, super.key});

  final BackendConfig backend;

  @override
  State<HostWebView> createState() => _HostWebViewState();
}

class _HostWebViewState extends State<HostWebView> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController();
    unawaited(_configure());
  }

  Future<void> _configure() async {
    await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await _controller.setBackgroundColor(Colors.transparent);
    await _controller.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: (_) => setState(() => _loading = true),
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
        onWebResourceError: (error) {
          if ((error.isForMainFrame ?? false) && mounted) {
            // The main frame failed: stop promising a loading state; the
            // WebView paints its own error page.
            setState(() => _loading = false);
          }
        },
      ),
    );
    await _controller.loadRequest(widget.backend.baseUri);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
      ],
    );
  }
}
