/// Per-message and per-session human feedback vocabulary.
///
/// Mirrors the two host surfaces in
/// `reference/deepseek-harness/packages/feedback/`: one durable judgment per
/// finalized assistant message (`message-feedback/src/types.ts`
/// `MessageFeedbackItem`) and one free-text remark about a Session
/// (`command-feedback/src/types.ts` `FeedbackRecord`). Both are log-only:
/// feedback never enters model history.
///
/// The host owns the compare-and-set: every mutation carries the item version
/// the caller last observed, and a `version-conflict` refusal answers the
/// authoritative item, so a lost race reconciles from the refusal itself
/// instead of refetching the Session.
library;

/// The human's overall judgment of one assistant message
/// (wire: `positive` / `negative`).
enum MessageFeedbackRating { positive, negative }

/// Parses one wire rating; an unknown value fails loud naming it.
MessageFeedbackRating messageFeedbackRatingFromWire(String wire) =>
    switch (wire) {
      'positive' => MessageFeedbackRating.positive,
      'negative' => MessageFeedbackRating.negative,
      _ => throw FormatException('unknown message feedback rating: $wire'),
    };

/// One of the fixed feedback categories; the ids are durable log vocabulary
/// (`command-feedback/src/types.ts` `FeedbackCategory`).
enum MessageFeedbackCategory {
  taskResult,
  instructionFollowing,
  productInteraction,
  serviceStability,
  resourceCost,
  securityPrivacyPermission,
  other,
}

/// Parses one wire category id; an unknown id fails loud naming it.
MessageFeedbackCategory messageFeedbackCategoryFromWire(String wire) =>
    switch (wire) {
      'task-result' => MessageFeedbackCategory.taskResult,
      'instruction-following' => MessageFeedbackCategory.instructionFollowing,
      'product-interaction' => MessageFeedbackCategory.productInteraction,
      'service-stability' => MessageFeedbackCategory.serviceStability,
      'resource-cost' => MessageFeedbackCategory.resourceCost,
      'security-privacy-permission' =>
        MessageFeedbackCategory.securityPrivacyPermission,
      'other' => MessageFeedbackCategory.other,
      _ => throw FormatException('unknown feedback category: $wire'),
    };

/// One current feedback value for one assistant message, with the opaque
/// version token every mutation compares against.
final class MessageFeedbackItem {
  const MessageFeedbackItem({
    required this.messageId,
    required this.rating,
    required this.version,
    required this.createdAtEpochMs,
    required this.updatedAtEpochMs,
    this.note,
    this.category,
  });

  /// Stable identity of the assistant message inside its owning Session.
  final String messageId;

  final MessageFeedbackRating rating;

  /// Optional explanation, preserved verbatim by the host.
  final String? note;

  /// Category the human filed the judgment under; null when uncategorized.
  final MessageFeedbackCategory? category;

  /// Equality-only token replaced by every material create or update.
  final String version;

  /// Host-assigned creation time in Unix epoch milliseconds.
  final int createdAtEpochMs;

  /// Host-assigned time of the most recent material update.
  final int updatedAtEpochMs;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MessageFeedbackItem &&
          other.messageId == messageId &&
          other.rating == rating &&
          other.note == note &&
          other.category == category &&
          other.version == version &&
          other.createdAtEpochMs == createdAtEpochMs &&
          other.updatedAtEpochMs == updatedAtEpochMs);

  @override
  int get hashCode => Object.hash(
    messageId,
    rating,
    note,
    category,
    version,
    createdAtEpochMs,
    updatedAtEpochMs,
  );
}

/// The settled outcome of one feedback write (`messageFeedback/put` or
/// `messageFeedback/delete`).
///
/// A refusal is a value, not an exception: the host answers these as its own
/// success-branch business result, and the surface states the reason beside
/// the control that raised it.
sealed class MessageFeedbackWrite {
  const MessageFeedbackWrite();
}

/// The host committed the write. [item] is the durable value it answered;
/// null when the write was a delete, which leaves the message unrated.
final class MessageFeedbackCommitted extends MessageFeedbackWrite {
  const MessageFeedbackCommitted(this.item);

  final MessageFeedbackItem? item;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MessageFeedbackCommitted && other.item == item);

  @override
  int get hashCode => item.hashCode;
}

/// The host refused the write with a stable business code. [current] is the
/// authoritative item a `version-conflict` refusal carries (`null` when the
/// item was removed elsewhere); every other code leaves it null.
final class MessageFeedbackRefused extends MessageFeedbackWrite {
  const MessageFeedbackRefused(this.code, {this.current});

  /// The host's stable refusal code: `session-not-found`,
  /// `target-not-found`, `version-conflict`, `note-blank`, or
  /// `note-too-large`.
  final String code;

  final MessageFeedbackItem? current;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MessageFeedbackRefused &&
          other.code == code &&
          other.current == current);

  @override
  int get hashCode => Object.hash(code, current);
}
