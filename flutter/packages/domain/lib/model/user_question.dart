/// Timed `ask_user_question` state, as the host publishes it.
///
/// Wire truth:
/// `reference/deepseek-harness/packages/interaction/user-questions/src/types.ts`
/// (`PendingUserQuestion`, `UserQuestionState`) and the `userQuestions` entry
/// in that package's `SessionProjectionMap`.
library;

import 'timeline_item.dart';

/// Whether a timed question can still take an answer.
enum UserQuestionState {
  /// The host's foreground wait is still open, so the ordinary waterfall
  /// answer settles the call.
  open,

  /// The wait ended and the host continued the turn. The call's own result
  /// recorded the timeout; only a late reply, sent through
  /// `userQuestions/answer`, answers it now.
  continued,
}

/// One unanswered timed `ask_user_question` call the host still holds.
final class PendingUserQuestion {
  const PendingUserQuestion({
    required this.callId,
    required this.questions,
    required this.state,
  });

  /// Tool-call identity the answer is keyed by.
  final String callId;

  /// The questions that call asked, in ask order.
  final List<QuestionItem> questions;

  final UserQuestionState state;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingUserQuestion &&
          other.callId == callId &&
          other.state == state &&
          _sameQuestions(other.questions, questions));

  @override
  int get hashCode => Object.hash(callId, state, Object.hashAll(questions));

  static bool _sameQuestions(List<QuestionItem> a, List<QuestionItem> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
