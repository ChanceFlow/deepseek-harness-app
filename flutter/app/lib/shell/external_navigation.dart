/// Links that do not belong to the host leave the app.
///
/// The shell shows one host's page; a link to another site is not part of
/// that page's world, so it opens in the system browser instead of becoming
/// a second, unmanaged document inside the same WebView.
library;

import 'package:url_launcher/url_launcher.dart';

/// Whether [url] points outside the host's own origin.
///
/// Same-origin means scheme, host and port all equal [base]'s; a different
/// scheme (`https` on an `http` host included), host or port is external.
/// Non-navigational schemes (`mailto:`, `tel:`, `intent:`) are external too,
/// and the in-page-only schemes (`about:`, `data:`, `blob:`) are not.
bool isExternalUrl(String url, Uri base) {
  final parsed = Uri.tryParse(url);
  if (parsed == null) return true;
  switch (parsed.scheme) {
    case 'about':
    case 'data':
    case 'blob':
      return false;
    case 'http':
    case 'https':
      return parsed.scheme != base.scheme ||
          parsed.host != base.host ||
          parsed.port != base.port;
    default:
      return true;
  }
}

/// Opens [uri] in whichever app the system resolves for it. Failures are
/// swallowed: a page with an unlaunchable link must not break the page.
Future<void> openExternalLink(Uri uri) async {
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    // No handler, or the system refused: the click simply does nothing.
  }
}
