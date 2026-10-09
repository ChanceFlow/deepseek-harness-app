/// The host's `turnOutline` projection: every started turn's rail facts,
/// independent of what this client has paged in.
///
/// `reference/deepseek-harness/packages/session/session-turn-outline/src/
/// types.ts:15-24` (`TurnOutlineEntry`) and `projection.ts:61-71`: the wire
/// view is the entry array itself, strictly increasing by turn.
library;

/// One started turn's outline facts.
final class TurnOutlineEntry {
  const TurnOutlineEntry({
    required this.turn,
    required this.seq,
    required this.prompt,
    required this.response,
  });

  /// Host-assigned turn number, the `turn/start` payload.
  final int turn;

  /// The turn's `turn/start` event seq: paging a window back through it loads
  /// the whole turn.
  final int seq;

  /// Bounded first-human-prompt preview; `''` until an eligible prompt lands.
  final String prompt;

  /// Bounded final-response preview; `''` until the turn ends with assistant
  /// text.
  final String response;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TurnOutlineEntry &&
          other.turn == turn &&
          other.seq == seq &&
          other.prompt == prompt &&
          other.response == response);

  @override
  int get hashCode => Object.hash(turn, seq, prompt, response);

  @override
  String toString() =>
      'TurnOutlineEntry(turn: $turn, seq: $seq, prompt: $prompt, '
      'response: $response)';
}
