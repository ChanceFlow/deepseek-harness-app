/// Composer prompt vocabulary.
library;

import 'attachment.dart';

enum PromptMode { queue, steer }

final class SendMessageRequest {
  const SendMessageRequest({
    required this.sessionId,
    required this.text,
    this.mode = PromptMode.queue,
    this.images = const <PendingImage>[],
  });

  final String sessionId;
  final String text;
  final PromptMode mode;

  /// Inline image parts appended after the text part, web-composer parity.
  final List<PendingImage> images;

  @override
  bool operator ==(Object other) =>
      other is SendMessageRequest &&
      other.sessionId == sessionId &&
      other.text == text &&
      other.mode == mode &&
      _listEquals(other.images, images);

  @override
  int get hashCode =>
      Object.hash(sessionId, text, mode, Object.hashAll(images));
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
