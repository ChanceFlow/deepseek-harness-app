/// Composer prompt vocabulary.
library;

import 'attachment.dart';
import 'file_upload.dart';

enum PromptMode { queue, steer }

final class SendMessageRequest {
  const SendMessageRequest({
    required this.sessionId,
    required this.text,
    this.mode = PromptMode.queue,
    this.images = const <PendingImage>[],
    this.files = const <UploadedFile>[],
  });

  final String sessionId;
  final String text;
  final PromptMode mode;

  /// Inline image parts appended after the text part, web-composer parity.
  final List<PendingImage> images;

  /// Staged file uploads cited as `{type: 'file', receiptId}` parts, after
  /// every image part. Only files whose upload settled ready reach here —
  /// the composer refuses to submit an in-flight or failed attachment.
  final List<UploadedFile> files;

  @override
  bool operator ==(Object other) =>
      other is SendMessageRequest &&
      other.sessionId == sessionId &&
      other.text == text &&
      other.mode == mode &&
      _listEquals(other.images, images) &&
      _listEquals(other.files, files);

  @override
  int get hashCode => Object.hash(
    sessionId,
    text,
    mode,
    Object.hashAll(images),
    Object.hashAll(files),
  );
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
