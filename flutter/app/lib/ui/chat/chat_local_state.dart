/// Chat-surface local persistence — the KV seam for composer drafts,
/// reading offsets, expansion states, and the busy-send preference.
///
/// Keys live in the shared LocalStateStore vocabulary (plain JSON
/// values); a null seam disables every feature here, which is the state
/// of a ChatScreen mounted without a store (tests inject a fake).
library;

import 'package:domain/model/model_catalog.dart';

import '../../local_state/local_state_store.dart';

/// Busy-send preference values: 'queue' (default) or 'steer'.
const String kBusyEnterQueue = 'queue';
const String kBusyEnterSteer = 'steer';

/// Remembered composer model-seat preferences: the last selection the
/// reader made, plus the reasoning effort they last chose for each
/// provider/model route. The host persists a session's own selection;
/// this is the client-side memory that pre-arms a fresh session and
/// prefills the effort when a model is picked again.
final class ModelSeatPreferences {
  const ModelSeatPreferences({
    this.lastSelection,
    this.effortByRoute = const <String, String>{},
  });

  /// The selection the reader last committed from the model seat.
  final ModelSelection? lastSelection;

  /// Last-chosen reasoning effort per `provider/model` route; a route
  /// absent here has no remembered effort (the model's default applies).
  final Map<String, String> effortByRoute;

  /// The remembered effort for one route, null when none is stored.
  String? effortFor(String provider, String model) =>
      effortByRoute['$provider/$model'];

  /// The preference that follows one committed selection: it becomes the
  /// last selection and overwrites its route's remembered effort.
  ModelSeatPreferences remembering(ModelSelection selection) =>
      ModelSeatPreferences(
        lastSelection: selection,
        effortByRoute: <String, String>{
          ...effortByRoute,
          if (selection.reasoningEffort case final String effort)
            '${selection.provider}/${selection.model}': effort,
        },
      );

  @override
  bool operator ==(Object other) =>
      other is ModelSeatPreferences &&
      other.lastSelection == lastSelection &&
      _mapEquals(other.effortByRoute, effortByRoute);

  @override
  int get hashCode => Object.hash(lastSelection, Object.hashAll(effortByRoute.values));

  static bool _mapEquals(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}

/// Composer model-seat preference persistence; null disables remembering
/// (the seat then always opens on the host's current selection).
abstract class ModelPreferencePersistence {
  /// The remembered preferences; empty when nothing was ever stored.
  Future<ModelSeatPreferences> read();

  /// Persist the remembered preferences.
  Future<void> write(ModelSeatPreferences preferences);
}

/// [ModelPreferencePersistence] over the shared [LocalStateStore], keyed
/// per backend scope: hosts own different catalogs, so a preference
/// remembered on one must not land on another's seat.
class StoreModelPreferencePersistence implements ModelPreferencePersistence {
  StoreModelPreferencePersistence(this._store, this._scope);

  final LocalStateStore _store;
  final String _scope;

  String get _lastKey => 'chat.modelPrefs.$_scope.last';
  String get _effortsKey => 'chat.modelPrefs.$_scope.efforts';

  @override
  Future<ModelSeatPreferences> read() async {
    return ModelSeatPreferences(
      lastSelection: _readSelection(_store.read(_lastKey)),
      effortByRoute: _readEfforts(_store.read(_effortsKey)),
    );
  }

  @override
  Future<void> write(ModelSeatPreferences preferences) {
    final last = preferences.lastSelection;
    _store.write(
      _lastKey,
      last == null
          ? null
          : <String, Object?>{
              'provider': last.provider,
              'model': last.model,
              if (last.reasoningEffort case final String effort)
                'reasoningEffort': effort,
            },
    );
    _store.write(_effortsKey, preferences.effortByRoute);
    return Future<void>.value();
  }

  static ModelSelection? _readSelection(Object? raw) {
    if (raw is! Map) return null;
    final provider = raw['provider'];
    final model = raw['model'];
    if (provider is! String || model is! String) return null;
    final effort = raw['reasoningEffort'];
    return ModelSelection(
      provider: provider,
      model: model,
      reasoningEffort: effort is String ? effort : null,
    );
  }

  static Map<String, String> _readEfforts(Object? raw) {
    if (raw is! Map) return const <String, String>{};
    return <String, String>{
      for (final entry in raw.entries)
        if (entry.key is String && entry.value is String)
          entry.key as String: entry.value as String,
    };
  }
}

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
