/// Chat-surface local persistence — the KV seam for composer drafts,
/// reading offsets, expansion states, and the busy-send preference.
///
/// Keys live in the shared LocalStateStore vocabulary (plain JSON
/// values); a null seam disables every feature here, which is the state
/// of a ChatScreen mounted without a store (tests inject a fake).
library;

import '../../local_state/local_state_store.dart';

/// Busy-send preference values: 'queue' (default) or 'steer'.
const String kBusyEnterQueue = 'queue';
const String kBusyEnterSteer = 'steer';

/// Draft text of one session; absent (null or empty) when none is saved.
String chatDraftKey(String sessionId) => 'chat.draft.$sessionId';

/// Reading offset (scroll pixels from the top) of one session's timeline.
String chatReadOffsetKey(String sessionId) => 'chat.readOffset.$sessionId';

/// Timeline keys of one session's tool rows whose details stand expanded.
String chatExpandedToolsKey(String sessionId) =>
    'chat.expandedTools.$sessionId';

/// Turn numbers of one session's outline groups kept collapsed.
String chatCollapsedTurnsKey(String sessionId) =>
    'chat.collapsedTurns.$sessionId';

/// Busy-send preference: the delivery mode the composer's send action
/// uses while the session's turn runs.
const String chatBusyEnterBehaviorKey = 'chat.busyEnterBehavior';

/// Tool-row expansion persistence: restore on mount, persist on toggle.
/// The key is the row's [timelineKey] value.
abstract class ToolExpansionPersistence {
  /// Whether the row keyed [key] stands expanded; false until restored.
  Future<bool> expanded(String key);

  /// Persist one row's expansion state.
  Future<void> setExpanded(String key, bool expanded);
}

/// One session's persisted view state.
abstract class ChatSessionLocalState implements ToolExpansionPersistence {
  /// Saved composer draft; null when none exists.
  Future<String?> readDraft();

  /// Persist the composer draft; an empty string clears it.
  Future<void> writeDraft(String text);

  /// Saved reading offset; null when none exists.
  Future<double?> readReadOffset();

  /// Persist the reading offset (scroll pixels from the top).
  Future<void> writeReadOffset(double offset);

  /// Turn numbers the outline keeps collapsed.
  Future<Set<int>> readCollapsedTurns();

  /// Persist the outline's collapsed turn set.
  Future<void> writeCollapsedTurns(Set<int> turns);
}

/// Chat-surface persistence handle: the busy-send preference plus
/// per-session views.
abstract class ChatLocalState {
  /// The persisted busy-send behavior ('queue' default | 'steer').
  Future<String> busyEnterBehavior();

  /// The per-session view for [sessionId]; call once per selected
  /// session and keep the result.
  ChatSessionLocalState forSession(String sessionId);
}

/// [ChatLocalState] over the shared [LocalStateStore]; every consumer
/// of the store must share one instance, or the whole-document flushes
/// overwrite each other's keys.
class StoreChatLocalState implements ChatLocalState {
  StoreChatLocalState(this._store);

  final LocalStateStore _store;

  @override
  Future<String> busyEnterBehavior() async {
    final stored = _store.read(chatBusyEnterBehaviorKey);
    return stored == kBusyEnterSteer ? kBusyEnterSteer : kBusyEnterQueue;
  }

  @override
  ChatSessionLocalState forSession(String sessionId) =>
      StoreChatSessionLocalState(_store, sessionId);
}

/// One session's KV view: typed reads/writes over the shared store's
/// plain-JSON values.
class StoreChatSessionLocalState implements ChatSessionLocalState {
  StoreChatSessionLocalState(this._store, this.sessionId);

  final LocalStateStore _store;
  final String sessionId;

  List<String> _readExpandedTools() {
    final raw = _store.read(chatExpandedToolsKey(sessionId));
    if (raw is! List) return const <String>[];
    return raw.whereType<String>().toList();
  }

  @override
  Future<bool> expanded(String key) async =>
      _readExpandedTools().contains(key);

  @override
  Future<void> setExpanded(String key, bool expanded) {
    final next = _readExpandedTools().toSet();
    if (expanded) {
      next.add(key);
    } else {
      next.remove(key);
    }
    _store.write(chatExpandedToolsKey(sessionId), next.toList());
    return Future<void>.value();
  }

  @override
  Future<String?> readDraft() async {
    final raw = _store.read(chatDraftKey(sessionId));
    return raw is String && raw.isNotEmpty ? raw : null;
  }

  @override
  Future<void> writeDraft(String text) {
    // An empty draft is the cleared marker: delete the key.
    _store.write(chatDraftKey(sessionId), text.isEmpty ? null : text);
    return Future<void>.value();
  }

  @override
  Future<double?> readReadOffset() async {
    final raw = _store.read(chatReadOffsetKey(sessionId));
    return raw is num ? raw.toDouble() : null;
  }

  @override
  Future<void> writeReadOffset(double offset) {
    _store.write(chatReadOffsetKey(sessionId), offset);
    return Future<void>.value();
  }

  @override
  Future<Set<int>> readCollapsedTurns() async {
    final raw = _store.read(chatCollapsedTurnsKey(sessionId));
    if (raw is! List) return const <int>{};
    return raw.whereType<num>().map((value) => value.toInt()).toSet();
  }

  @override
  Future<void> writeCollapsedTurns(Set<int> turns) {
    _store.write(chatCollapsedTurnsKey(sessionId), turns.toList());
    return Future<void>.value();
  }
}
