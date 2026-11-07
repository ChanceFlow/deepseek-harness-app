/// One backend host's WebView: the dsh web UI, untouched.
///
/// The shell renders the host's own client, so the surface always matches the
/// host's version. Nothing is injected: the notification pipeline reads the
/// host's API on its own socket, and the page keeps its own navigation state.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:domain/model/backend.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'external_navigation.dart';
import 'webview_file_chooser.dart';
import 'webview_permissions.dart';

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
    // The host page owns its own microphone/camera prompts (getUserMedia and
    // <input capture>): the WebView asks, the activity grants the runtime
    // permission, and only then does the page win the resource. A host served
    // over plain HTTP still cannot use getUserMedia — that is the WebView's
    // secure-context rule, not ours.
    if (!kIsWeb && Platform.isAndroid) {
      final platform = _controller.platform;
      if (platform is AndroidWebViewController) {
        await platform.setOnPlatformPermissionRequest((request) async {
          final granted = await WebViewPermissions.ensure(request.types);
          if (granted) {
            await request.grant();
          } else {
            await request.deny();
          }
        });
        // The page's `<input type=file>` (and its `capture` variant) opens
        // the system picker; the chosen absolute paths go straight back to
        // the WebView, and an empty list is the cancel the page expects.
        await platform.setOnShowFileSelector(
          (params) => WebViewFileChooser.choose(params),
        );
        // Downloads have no plugin API: the native side attaches its
        // DownloadListener to the WebView once the view exists.
        unawaited(WebViewPermissions.attachDownloads());
      }
    }
    await _controller.setBackgroundColor(Colors.transparent);
    await _controller.setNavigationDelegate(
      NavigationDelegate(
        // The host's own origin stays in the page; anything else is a link
        // to the outside world and belongs to the system browser.
        onNavigationRequest: (request) {
          if (!isExternalUrl(request.url, widget.backend.baseUri)) {
            return NavigationDecision.navigate;
          }
          final uri = Uri.tryParse(request.url);
          if (uri != null) unawaited(openExternalLink(uri));
          return NavigationDecision.prevent;
        },
        onPageStarted: (_) => setState(() => _loading = true),
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
          if (!kIsWeb && Platform.isAndroid) {
            unawaited(WebViewPermissions.attachDownloads());
          }
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
