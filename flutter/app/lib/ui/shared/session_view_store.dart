/// The session browser's viewing state, persisted the way the reference
/// persists its own: one document, restored on launch, so a fold, an order
/// choice, an archived filter or a pin's position survives a restart.
///
/// The reference keeps this in a single client store
/// (`ui-workspace/src/client/stores.ts`, `persist: 'dsh.workspace.view.v5'`)
/// and treats pinning as two facts together: the Host owns the pin
/// (`workspace/follow`'s `pinnedSessionIds`, written through
/// `workspace/pinSession`), and the browser records where the pinned row goes
/// in that account's saved order (`pinSessionOrder`). This client persisted
/// only two keys before this store existed — `sidebar.groupOverrides` and
/// `sidebar.overflowExpanded` — so with a manual order it could not place a
/// pinned row the way the reference does. Both are read through here so an
/// install that has them keeps its expansion.
///
/// `groupBy` is deliberately absent: the reference carries it because its
/// browser switches between workspace, workspace-tree and flat views, and our
/// panel renders one shape. Persisting a mode nothing reads would be dead
/// state.
library;

import 'package:app/local_state/local_state_store.dart';
import 'package:app/ui/shared/archived_filter.dart';

/// The order a session group is shown in.
enum SessionOrderBy {
  /// The user's own saved positions, which a pin also writes.
  manual,

  /// Most recently updated first.
  updated,
}

/// What the order needs to know about one session: the recency it ranks by,
/// and the parent it sits beside when it was forked.
typedef SessionOrderFacts = ({int updatedAt, String? parentId});

/// Ranks [sessionIds] most-recently-updated first, with the id as the
/// tie-break so the order is stable. Mirrors the reference's
/// `orderByRecency` (`ui-workspace/src/client/tree.ts`).
List<String> orderByRecency(
  Iterable<String> sessionIds,
  Map<String, SessionOrderFacts> facts,
) {
  final List<String> ranked = sessionIds
      .where((String id) => facts.containsKey(id))
      .toList(growable: false);
  ranked.sort((String a, String b) {
    final int byRecency = facts[b]!.updatedAt.compareTo(facts[a]!.updatedAt);
    if (byRecency != 0) return byRecency;
    return a.compareTo(b);
  });
  return ranked;
}

/// Reconciles one account's saved manual order against the sessions it
/// actually holds now. Mirrors the reference's `reconcileManualOrder`
/// (`ui-workspace/src/client/tree.ts`): the saved positions of members that
/// still exist come first, then the pinned rows that are not already placed,
/// then the rest by recency, then archived rows last — and a forked session
/// moves up to sit beside its parent.
///
/// [savedOrder] is the persisted order; [pinnedSessionIds] is the Host's pin
/// list for this account; [archivedSessionIds] is the Host's archive list.
List<String> reconcileManualOrder(
  Iterable<String> memberIds,
  Iterable<String>? savedOrder,
  Map<String, SessionOrderFacts> facts, {
  Iterable<String> pinnedSessionIds = const <String>[],
  Iterable<String> archivedSessionIds = const <String>[],
}) {
  final Set<String> members = memberIds.toSet();
  final Set<String> included = <String>{};
  final List<String> ordered = <String>[];
  for (final String key in savedOrder ?? const <String>[]) {
    if (!members.contains(key) || included.contains(key)) continue;
    ordered.add(key);
    included.add(key);
  }
  final Set<String> archived = archivedSessionIds.toSet();
  final List<String> pins = <String>[];
  for (final String id in pinnedSessionIds) {
    if (!members.contains(id) ||
        included.contains(id) ||
        archived.contains(id) ||
        !facts.containsKey(id)) {
      continue;
    }
    pins.add(id);
    included.add(id);
  }
  final List<String> ordinary = <String>[];
  final List<String> archives = <String>[];
  for (final String id in orderByRecency(
    members.where((String id) => !included.contains(id)),
    facts,
  )) {
    (archived.contains(id) ? archives : ordinary).add(id);
  }
  final List<String> result = <String>[
    ...pins,
    ...ordered,
    ...ordinary,
    ...archives,
  ];
  final Set<String> pending = ordinary.toSet();
  void placeFork(String id) {
    if (!pending.remove(id)) return;
    final String? parentId = facts[id]?.parentId;
    if (parentId == null || parentId == id || !result.contains(parentId)) {
      return;
    }
    placeFork(parentId);
    result.remove(id);
    result.insert(result.indexOf(parentId), id);
  }

  for (final String id in ordinary.reversed) {
    placeFork(id);
  }
  return result;
}

/// The persisted viewing state of one session browser.
class SessionViewState {
  const SessionViewState({
    this.orderBy = SessionOrderBy.updated,
    this.groupExpansion = const <String, bool>{},
    this.sessionOrderByAccount = const <String, List<String>>{},
    this.archivedFilter = ArchivedFilter.hide,
  });

  /// The order choice; `manual` means [sessionOrderByAccount] decides.
  final SessionOrderBy orderBy;

  /// Explicit fold state per group key. A group with no entry follows the
  /// browser's default rather than a value invented here.
  final Map<String, bool> groupExpansion;

  /// The saved manual order per account key.
  final Map<String, List<String>> sessionOrderByAccount;

  /// Which archived rows are visible.
  final ArchivedFilter archivedFilter;

  SessionViewState copyWith({
    SessionOrderBy? orderBy,
    Map<String, bool>? groupExpansion,
    Map<String, List<String>>? sessionOrderByAccount,
    ArchivedFilter? archivedFilter,
  }) => SessionViewState(
    orderBy: orderBy ?? this.orderBy,
    groupExpansion: groupExpansion ?? this.groupExpansion,
    sessionOrderByAccount: sessionOrderByAccount ?? this.sessionOrderByAccount,
    archivedFilter: archivedFilter ?? this.archivedFilter,
  );

  /// The document this state is stored as. Keys stay stable: a rename loses
  /// the reader's folds.
  Map<String, Object?> toJson() => <String, Object?>{
    'orderBy': orderBy.name,
    'groupExpansion': groupExpansion,
    'sessionOrderByAccount': sessionOrderByAccount,
    'archivedFilter': archivedFilter.name,
  };

  /// Decodes a stored document, falling back per field rather than failing the
  /// whole read: this is regenerable UI state, and one bad field must not cost
  /// the reader every other fold.
  static SessionViewState fromJson(Object? raw) {
    if (raw is! Map<Object?, Object?>) return const SessionViewState();
    final Object? orderBy = raw['orderBy'];
    final Object? archived = raw['archivedFilter'];
    return SessionViewState(
      orderBy: SessionOrderBy.values.firstWhere(
        (SessionOrderBy mode) => mode.name == orderBy,
        orElse: () => SessionOrderBy.updated,
      ),
      groupExpansion: _decodeBoolMap(raw['groupExpansion']),
      sessionOrderByAccount: _decodeOrderMap(raw['sessionOrderByAccount']),
      archivedFilter: ArchivedFilter.values.firstWhere(
        (ArchivedFilter filter) => filter.name == archived,
        orElse: () => ArchivedFilter.hide,
      ),
    );
  }

  static Map<String, bool> _decodeBoolMap(Object? raw) {
    if (raw is! Map<Object?, Object?>) return const <String, bool>{};
    final Map<String, bool> decoded = <String, bool>{};
    raw.forEach((Object? key, Object? value) {
      if (key is String && value is bool) decoded[key] = value;
    });
    return decoded;
  }

  static Map<String, List<String>> _decodeOrderMap(Object? raw) {
    if (raw is! Map<Object?, Object?>) return const <String, List<String>>{};
    final Map<String, List<String>> decoded = <String, List<String>>{};
    raw.forEach((Object? key, Object? value) {
      if (key is String && value is List<Object?>) {
        decoded[key] = value.whereType<String>().toList(growable: false);
      }
    });
    return decoded;
  }
}

/// Reads and writes [SessionViewState] through the shared [LocalStateStore],
/// carrying the reference's own actions so a pin, an order choice and a fold
/// all land in one document.
class SessionViewStore {
  SessionViewStore(this._store);

  final LocalStateStore _store;

  /// The single key this state lives under.
  static const String key = 'sidebar.view';

  /// The two keys this client wrote before this store existed. Read once, so
  /// an install that has them keeps its expansion.
  static const String legacyGroupOverridesKey = 'sidebar.groupOverrides';
  static const String legacyOverflowExpandedKey = 'sidebar.overflowExpanded';

  /// The persisted state, with the legacy keys folded in when the new document
  /// is absent. Returns null before the store has loaded: the caller keeps its
  /// live defaults rather than being reset by a not-yet-read file.
  SessionViewState? read() {
    if (!_store.isLoaded) return null;
    final Object? current = _store.read(key);
    if (current == null) return _migrateLegacy();
    return SessionViewState.fromJson(current);
  }

  SessionViewState _migrateLegacy() {
    final Object? overrides = _store.read(legacyGroupOverridesKey);
    final Object? overflow = _store.read(legacyOverflowExpandedKey);
    final Map<String, bool> expansion = SessionViewState._decodeBoolMap(
      overrides,
    );
    final List<String> expandedOverflow = overflow is List<Object?>
        ? overflow.whereType<String>().toList(growable: false)
        : const <String>[];
    if (expansion.isEmpty && expandedOverflow.isEmpty) {
      return const SessionViewState();
    }
    // The overflow rows were expanded, so they seed as expanded groups.
    final Map<String, bool> seeded = <String, bool>{
      ...expansion,
      for (final String group in expandedOverflow) group: true,
    };
    final SessionViewState migrated = SessionViewState(groupExpansion: seeded);
    write(migrated);
    return migrated;
  }

  /// Persists [state] as the single document.
  void write(SessionViewState state) => _store.write(key, state.toJson());

  /// The reference's `setGroupExpanded`: an explicit fold for one group key.
  SessionViewState setGroupExpanded(
    SessionViewState state,
    String groupKey,
    bool expanded,
  ) {
    final SessionViewState next = state.copyWith(
      groupExpansion: <String, bool>{
        ...state.groupExpansion,
        groupKey: expanded,
      },
    );
    write(next);
    return next;
  }

  /// The reference's `setOrderBy`: switching to `manual` seeds every account
  /// from the order currently shown, switching away drops the saved orders,
  /// and an unchanged mode does nothing.
  SessionViewState setOrderBy(
    SessionViewState state,
    SessionOrderBy mode,
    Map<String, List<String>> initialOrders,
  ) {
    if (mode == state.orderBy) return state;
    final SessionViewState next = state.copyWith(
      orderBy: mode,
      sessionOrderByAccount: mode == SessionOrderBy.manual
          ? _copyOrders(initialOrders)
          : const <String, List<String>>{},
    );
    write(next);
    return next;
  }

  /// The reference's `retainAccountKeys`: drop the fold and order entries of
  /// accounts that no longer exist, so a deleted workspace's order cannot come
  /// back if its key is reused.
  SessionViewState retainAccountKeys(
    SessionViewState state,
    Set<String> accountKeys,
  ) {
    final SessionViewState next = state.copyWith(
      groupExpansion: <String, bool>{
        for (final MapEntry<String, bool> entry in state.groupExpansion.entries)
          if (accountKeys.contains(entry.key)) entry.key: entry.value,
      },
      sessionOrderByAccount: <String, List<String>>{
        for (final MapEntry<String, List<String>> entry
            in state.sessionOrderByAccount.entries)
          if (accountKeys.contains(entry.key)) entry.key: entry.value,
      },
    );
    write(next);
    return next;
  }

  /// The reference's `syncSessionOrders`: the shown order becomes the saved
  /// one, and only while the manual mode is in effect.
  SessionViewState syncSessionOrders(
    SessionViewState state,
    Map<String, List<String>> orders,
  ) {
    if (state.orderBy != SessionOrderBy.manual) return state;
    final SessionViewState next = state.copyWith(
      sessionOrderByAccount: <String, List<String>>{
        ...state.sessionOrderByAccount,
        ..._copyOrders(orders),
      },
    );
    write(next);
    return next;
  }

  /// The reference's `setSessionOrder`: a drag or a drop saves the account's
  /// order and puts the browser into the manual mode.
  SessionViewState setSessionOrder(
    SessionViewState state,
    String accountKey,
    List<String> order,
    Map<String, List<String>> initialOrders,
  ) {
    final SessionViewState next = state.copyWith(
      orderBy: SessionOrderBy.manual,
      sessionOrderByAccount: <String, List<String>>{
        ...(state.orderBy == SessionOrderBy.updated
            ? _copyOrders(initialOrders)
            : state.sessionOrderByAccount),
        accountKey: List<String>.of(order),
      },
    );
    write(next);
    return next;
  }

  /// The reference's `pinSessionOrder`: pinning is the Host's fact **and** a
  /// saved position, so the pinned row leads every selected account's order.
  /// Each account is reconciled first, which keeps the rows that are still
  /// there in their saved positions and re-seats everything else.
  SessionViewState pinSessionOrder(
    SessionViewState state,
    String sessionId,
    Set<String> accountKeys,
    Map<String, List<String>> members,
    Map<String, SessionOrderFacts> facts, {
    Iterable<String> pinnedSessionIds = const <String>[],
    Iterable<String> archivedSessionIds = const <String>[],
  }) {
    final Map<String, List<String>> orders = <String, List<String>>{};
    for (final MapEntry<String, List<String>> entry in members.entries) {
      final List<String> reconciled = reconcileManualOrder(
        entry.value,
        state.sessionOrderByAccount[entry.key],
        facts,
        pinnedSessionIds: pinnedSessionIds,
        archivedSessionIds: archivedSessionIds,
      );
      orders[entry.key] = accountKeys.contains(entry.key)
          ? <String>[
              sessionId,
              ...reconciled.where((String id) => id != sessionId),
            ]
          : reconciled;
    }
    final SessionViewState next = state.copyWith(sessionOrderByAccount: orders);
    write(next);
    return next;
  }

  /// The reference's `setArchivedFilter`.
  SessionViewState setArchivedFilter(
    SessionViewState state,
    ArchivedFilter filter,
  ) {
    final SessionViewState next = state.copyWith(archivedFilter: filter);
    write(next);
    return next;
  }

  static Map<String, List<String>> _copyOrders(
    Map<String, List<String>> orders,
  ) => <String, List<String>>{
    for (final MapEntry<String, List<String>> entry in orders.entries)
      entry.key: List<String>.of(entry.value),
  };
}
