/// The preview's document frame: the seam a prepared document is drawn
/// through, so a widget test owns no platform view.
library;

import 'package:flutter/widgets.dart';

/// One prepared document for a frame to draw.
///
/// [html] is complete and already carries its own policy
/// ([basicHtmlDocument]/[svgImageDocument]); the frame adds the other half of
/// the static mode — scripts off, and every navigation the document asks for
/// refused.
class PreviewDocument {
  const PreviewDocument({required this.html, required this.semanticLabel});

  final String html;

  /// What the frame is announced as to accessibility services.
  final String semanticLabel;

  @override
  bool operator ==(Object other) =>
      other is PreviewDocument &&
      other.html == html &&
      other.semanticLabel == semanticLabel;

  @override
  int get hashCode => Object.hash(html, semanticLabel);
}

/// Draws one prepared document. The production implementation is
/// `buildWebViewDocumentFrame`; a pump that owns no WebView passes its own.
typedef DocumentFrameBuilder = Widget Function(
  BuildContext context,
  PreviewDocument document,
);
