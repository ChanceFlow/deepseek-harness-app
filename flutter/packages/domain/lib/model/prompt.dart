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
}
