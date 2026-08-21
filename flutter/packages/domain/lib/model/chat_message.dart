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
    this.seq,
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

  /// Position of this message in the session's event log — the anchor a
  /// fork cuts at (the host resolves it to the end of the turn that
  /// contains it). Null for a message the client composed locally, which
  /// has no logged position to fork from.
  final int? seq;

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
      other.seq == seq &&
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
    seq,
  );
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
