/// The renderer-death seam between the shell and the Android WebView.
///
/// Android runs a WebView's renderer in its own process. When that process
/// dies the WebView cannot be reused; the native side keeps the app alive and
/// reports the death through the `dsh/webview` channel. One renderer can own
/// several WebViews, so one death arrives as one report per WebView — the
/// shell coalesces that burst into a single page rebuild.
///
/// [RendererWatch] is the seam a widget test drives without a platform
/// channel: the shell accepts an injected watch, and production constructs a
/// [PlatformRendererWatch].
library;

import 'dart:async';

import 'package:flutter/services.dart';

/// The channel the native side answers on. It also carries the shell's other
/// WebView asks (permissions, downloads); this library uses the renderer
/// methods.
const MethodChannel _channel = MethodChannel('dsh/webview');

/// One report that the renderer behind a WebView is gone.
///
/// The native side reports the death once per WebView attached to the dead
/// renderer, so a single renderer death can produce several [RendererGone]
/// values. [didCrash] distinguishes a crashed renderer from a normal exit;
/// [priority] carries the renderer priority at exit.
final class RendererGone {
  const RendererGone({required this.didCrash, required this.priority});

  /// Whether the renderer died from a crash rather than a normal teardown.
  final bool didCrash;

  /// The renderer priority at exit, as the platform reported it.
  final int priority;
}

/// A source of renderer-death reports.
///
/// The shell subscribes once for its lifetime and disposes the watch with the
/// shell. Tests implement this interface and push [RendererGone] values
/// directly.
abstract interface class RendererWatch {
  /// Renderer-death reports; a broadcast stream with one event per WebView.
  Stream<RendererGone> get events;

  /// Detaches the platform handler and closes [events].
  void dispose();
}

/// The `dsh/webview` channel as a [RendererWatch].
///
/// Constructing the watch installs the channel's method-call handler, and
/// [dispose] removes it, so exactly one watch owns the channel for the life of
/// one shell.
class PlatformRendererWatch implements RendererWatch {
  PlatformRendererWatch() {
    _channel.setMethodCallHandler(_onMethodCall);
  }

  final StreamController<RendererGone> _reports =
      StreamController<RendererGone>.broadcast();

  bool _disposed = false;

  @override
  Stream<RendererGone> get events => _reports.stream;

  Future<void> _onMethodCall(MethodCall call) async {
    if (call.method != 'rendererGone' || _disposed) return;
    final Object? arguments = call.arguments;
    final Map<Object?, Object?> args = arguments is Map<Object?, Object?>
        ? arguments
        : const <Object?, Object?>{};
    final Object? didCrash = args['didCrash'];
    final Object? priority = args['priority'];
    _reports.add(
      RendererGone(
        didCrash: didCrash is bool && didCrash,
        priority: priority is int ? priority : 0,
      ),
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _channel.setMethodCallHandler(null);
    unawaited(_reports.close());
  }
}

/// Asks the platform to guard every existing WebView against renderer death.
///
/// The native guard keeps the process alive when a renderer dies and reports
/// the death on the channel, so the shell rebuilds the page instead of
/// painting a dead pane. The call is idempotent: a WebView already guarded is
/// skipped natively, which makes a call per page load cheap. Widget tests and
/// non-Android hosts have no `dsh/webview` handler; the call then reports
/// nothing and the page keeps its normal behavior.
Future<void> installRendererGuards() async {
  try {
    await _channel.invokeMethod<void>('installRendererGuards');
  } on PlatformException {
    // A host without the handler cannot guard its WebViews.
  } on MissingPluginException {
    // Widget tests and non-Android hosts have no activity channel.
  }
}
