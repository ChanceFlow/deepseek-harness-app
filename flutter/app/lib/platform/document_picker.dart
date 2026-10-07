/// Platform bridge that returns one document the reader picked.
///
/// Android has no browsable file path a plain Dart picker can hand back: the
/// Storage Access Framework owns the choice. The native side therefore opens
/// the system document picker (`ACTION_OPEN_DOCUMENT`) and reads the chosen
/// document's bytes through the returned `content://` handle. The size bound
/// is passed in so a pick above it fails before its bytes are read into
/// memory. Widget tests inject their own picker; [pickDocument] is the
/// production default.
library;

import 'package:flutter/services.dart';

/// Method channel name; must match `MainActivity.kt`.
const String kDocumentPickerChannel = 'dsh/document_picker';

/// One picked document: its display name and exact bytes.
final class PickedDocument {
  const PickedDocument({required this.name, required this.bytes});

  /// The document's display name, as the system provider reports it.
  final String name;

  /// The document's exact bytes.
  final Uint8List bytes;
}

/// The pick failed on the host: no channel (widget tests, unsupported hosts),
/// a platform error, or an unreadable document. A cancelled pick answers null
/// instead of this.
class DocumentPickException implements Exception {
  const DocumentPickException(this.message, {this.code = 'pick_failed'});

  /// The platform channel's stable error code (`too_large`, `read_failed`,
  /// `pick_unavailable`, `busy`, …); the composer branches on `too_large` to
  /// render the localized cap message.
  final String code;

  final String message;

  @override
  String toString() => 'DocumentPickException: $message';
}

/// Opens the system document picker and returns the chosen document, or null
/// when the reader cancelled.
///
/// [maxBytes] bounds the document the native side will read; a larger pick
/// fails with [DocumentPickException] rather than being buffered.
Future<PickedDocument?> pickDocument({
  required int maxBytes,
  MethodChannel? channel,
}) async {
  final MethodChannel bridge =
      channel ?? const MethodChannel(kDocumentPickerChannel);
  final Object? picked;
  try {
    picked = await bridge.invokeMethod<Object?>('pick', <String, Object>{
      'maxBytes': maxBytes,
    });
  } on MissingPluginException {
    throw const DocumentPickException('no document picker channel');
  } on PlatformException catch (error) {
    throw DocumentPickException(error.message ?? error.code, code: error.code);
  }
  if (picked == null) return null;
  if (picked is! Map) {
    throw const DocumentPickException('the host returned no document');
  }
  final name = picked['name'];
  final bytes = picked['bytes'];
  if (name is! String || name.isEmpty || bytes is! Uint8List) {
    throw const DocumentPickException('the host returned an invalid document');
  }
  return PickedDocument(name: name, bytes: bytes);
}

/// The pick a composer performs for its attach-file affordance. Injected so
/// tests drive the outcome without a platform channel.
typedef DocumentPicker = Future<PickedDocument?> Function({
  required int maxBytes,
});
