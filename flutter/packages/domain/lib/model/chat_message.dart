/// UI-facing chat message vocabulary.
library;

import 'attachment.dart';

enum MessageRole { user, assistant }

/// UI-facing chat message.
///
/// Deliberately contains no dsh SessionEvent, ContentBlock, or MuxFrame type.
final class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.text,
    this.reasoning,
    this.streaming = false,
    this.createdAtEpochMs = 0,
    this.images = const <AttachmentRef>[],
  });

  final String id;
  final String sessionId;
  final MessageRole role;
  final String text;
  final String? reasoning;
  final bool streaming;
  final int createdAtEpochMs;

  /// Durable image references carried by this message's content blocks.
  final List<AttachmentRef> images;

  @override
  bool operator ==(Object other) =>
      other is ChatMessage &&
      other.id == id &&
      other.sessionId == sessionId &&
      other.role == role &&
      other.text == text &&
      other.reasoning == reasoning &&
      other.streaming == streaming &&
      other.createdAtEpochMs == createdAtEpochMs &&
      _listEquals(other.images, images);

  @override
  int get hashCode => Object.hash(
    id,
    sessionId,
    role,
    text,
    reasoning,
    streaming,
    createdAtEpochMs,
    Object.hashAll(images),
  );
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
