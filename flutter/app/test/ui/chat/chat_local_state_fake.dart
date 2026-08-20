/// In-memory [ChatLocalState] double for widget tests: same KV key
/// vocabulary as the seam, no disk.
library;

import 'package:app/ui/chat/chat_local_state.dart';

/// Full KV-key → JSON-value map shared by every session view.
class FakeChatLocalState implements ChatLocalState {
  FakeChatLocalState({this.busyEnter = kBusyEnterQueue})
    : values = <String, Object?>{};

  /// Value served for 'chat.busyEnterBehavior'.
  String busyEnter;

  /// Raw KV contents, keyed exactly like the seam's key builders.
  final Map<String, Object?> values;

  final Map<String, FakeChatSessionLocalState> _sessions =
      <String, FakeChatSessionLocalState>{};

  @override
  Future<String> busyEnterBehavior() async => busyEnter;

  @override
  ChatSessionLocalState forSession(String sessionId) => _sessions
      .putIfAbsent(
        sessionId,
        () => FakeChatSessionLocalState(this, sessionId),
      );
}

class FakeChatSessionLocalState implements ChatSessionLocalState {
  FakeChatSessionLocalState(this._owner, this.sessionId);

  final FakeChatLocalState _owner;
  final String sessionId;

  Set<String> _expandedTools = const <String>{};

  @override
  Future<bool> expanded(String key) async => _expandedTools.contains(key);

  @override
  Future<void> setExpanded(String key, bool expanded) async {
    final next = Set<String>.of(_expandedTools);
    if (expanded) {
      next.add(key);
    } else {
      next.remove(key);
    }
    _expandedTools = next;
    _owner.values[chatExpandedToolsKey(sessionId)] = next.toList();
  }

  @override
  Future<String?> readDraft() async =>
      _owner.values[chatDraftKey(sessionId)] as String?;

  @override
  Future<void> writeDraft(String text) async {
    // Mirrors StoreChatSessionLocalState: an empty draft deletes the key.
    if (text.isEmpty) {
      _owner.values.remove(chatDraftKey(sessionId));
    } else {
      _owner.values[chatDraftKey(sessionId)] = text;
    }
  }

  @override
  Future<double?> readReadOffset() async =>
      _owner.values[chatReadOffsetKey(sessionId)] as double?;

  @override
  Future<void> writeReadOffset(double offset) async {
    _owner.values[chatReadOffsetKey(sessionId)] = offset;
  }

  @override
  Future<Set<int>> readCollapsedTurns() async {
    final raw = _owner.values[chatCollapsedTurnsKey(sessionId)];
    if (raw is! List) return const <int>{};
    return raw.whereType<num>().map((n) => n.toInt()).toSet();
  }

  @override
  Future<void> writeCollapsedTurns(Set<int> turns) async {
    _owner.values[chatCollapsedTurnsKey(sessionId)] = turns.toList();
  }
}
