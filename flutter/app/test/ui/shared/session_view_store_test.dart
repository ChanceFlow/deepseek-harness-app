/// The session browser's persisted viewing state: each action the reference
/// carries, the pin that writes a saved position as well as the Host fact, and
/// the two legacy keys an existing install still has.
library;

import 'dart:io';

import 'package:app/local_state/local_state_store.dart';
import 'package:app/ui/shared/archived_filter.dart';
import 'package:app/ui/shared/session_view_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// A loaded store over a throwaway file, plus a second reader over the same
/// file so a restored value is proved to have been written rather than kept in
/// memory.
({LocalStateStore store, File file}) _emptyStore() {
  final Directory dir = Directory.systemTemp.createTempSync('session-view');
  addTearDown(() => dir.deleteSync(recursive: true));
  final File file = File('${dir.path}/state.json');
  return (store: LocalStateStore(file), file: file);
}

Future<LocalStateStore> _loaded(File file) async {
  final LocalStateStore store = LocalStateStore(file);
  await store.load();
  return store;
}

const Map<String, SessionOrderFacts> _facts = <String, SessionOrderFacts>{
  'a': (updatedAt: 10, parentId: null),
  'b': (updatedAt: 30, parentId: null),
  'c': (updatedAt: 20, parentId: null),
  'fork': (updatedAt: 40, parentId: 'c'),
  'gone': (updatedAt: 50, parentId: null),
};

void main() {
  test('reads nothing before the document is loaded', () async {
    final ({LocalStateStore store, File file}) fixture = _emptyStore();
    final SessionViewStore view = SessionViewStore(fixture.store);
    expect(view.read(), isNull);
    await fixture.store.load();
    expect(view.read(), isNotNull);
  });

  test('a fold survives a remount', () async {
    final ({LocalStateStore store, File file}) fixture = _emptyStore();
    await fixture.store.load();
    final SessionViewStore view = SessionViewStore(fixture.store);
    view.setGroupExpanded(view.read()!, 'workspace:one', false);
    await fixture.store.flush();

    final LocalStateStore reopened = await _loaded(fixture.file);
    expect(
      SessionViewStore(reopened).read()!.groupExpansion['workspace:one'],
      isFalse,
    );
  });

  test(
    'switching to manual seeds the shown order, away from it drops it',
    () async {
      final ({LocalStateStore store, File file}) fixture = _emptyStore();
      await fixture.store.load();
      final SessionViewStore view = SessionViewStore(fixture.store);
      SessionViewState state = view.read()!;
      expect(state.orderBy, SessionOrderBy.updated);

      state = view.setOrderBy(
        state,
        SessionOrderBy.manual,
        <String, List<String>>{
          'one': <String>['b', 'a'],
        },
      );
      expect(state.orderBy, SessionOrderBy.manual);
      expect(state.sessionOrderByAccount['one'], <String>['b', 'a']);

      // An unchanged mode is a no-op, not a re-seed.
      final SessionViewState same = view.setOrderBy(
        state,
        SessionOrderBy.manual,
        <String, List<String>>{
          'one': <String>['a'],
        },
      );
      expect(same.sessionOrderByAccount['one'], <String>['b', 'a']);

      state = view.setOrderBy(
        state,
        SessionOrderBy.updated,
        <String, List<String>>{},
      );
      expect(state.sessionOrderByAccount, isEmpty);
    },
  );

  test(
    'syncSessionOrders only writes while the manual mode is in effect',
    () async {
      final ({LocalStateStore store, File file}) fixture = _emptyStore();
      await fixture.store.load();
      final SessionViewStore view = SessionViewStore(fixture.store);
      SessionViewState state = view.read()!;

      final SessionViewState ignored = view.syncSessionOrders(
        state,
        <String, List<String>>{
          'one': <String>['a'],
        },
      );
      expect(ignored.sessionOrderByAccount, isEmpty);

      state = view.setOrderBy(
        state,
        SessionOrderBy.manual,
        <String, List<String>>{},
      );
      final SessionViewState merged = view.syncSessionOrders(
        state,
        <String, List<String>>{
          'one': <String>['a', 'b'],
        },
      );
      expect(merged.sessionOrderByAccount['one'], <String>['a', 'b']);
    },
  );

  test('setSessionOrder replaces the map when it was not manual yet', () async {
    final ({LocalStateStore store, File file}) fixture = _emptyStore();
    await fixture.store.load();
    final SessionViewStore view = SessionViewStore(fixture.store);
    SessionViewState state = view.read()!;
    state = view.setOrderBy(
      state,
      SessionOrderBy.manual,
      <String, List<String>>{
        'stale': <String>['gone'],
      },
    );

    // Back to recency, then a drag: the saved orders are reseeded from what is
    // shown rather than merged with the stale account.
    state = view.setOrderBy(
      state,
      SessionOrderBy.updated,
      <String, List<String>>{},
    );
    state = view.setSessionOrder(
      state,
      'one',
      <String>['c', 'a'],
      <String, List<String>>{
        'one': <String>['b', 'c', 'a'],
      },
    );
    expect(state.orderBy, SessionOrderBy.manual);
    expect(state.sessionOrderByAccount.containsKey('stale'), isFalse);
    expect(state.sessionOrderByAccount['one'], <String>['c', 'a']);
  });

  test('retainAccountKeys drops a removed account from both maps', () async {
    final ({LocalStateStore store, File file}) fixture = _emptyStore();
    await fixture.store.load();
    final SessionViewStore view = SessionViewStore(fixture.store);
    SessionViewState state = view.read()!;
    state = view.setGroupExpanded(state, 'kept', true);
    state = view.setGroupExpanded(state, 'removed', true);
    state = view.setOrderBy(
      state,
      SessionOrderBy.manual,
      <String, List<String>>{
        'kept': <String>['a'],
        'removed': <String>['b'],
      },
    );

    state = view.retainAccountKeys(state, <String>{'kept'});
    expect(state.groupExpansion.keys, <String>['kept']);
    expect(state.sessionOrderByAccount.keys, <String>['kept']);
  });

  test('a pin writes the saved position as well as the Host fact', () async {
    final ({LocalStateStore store, File file}) fixture = _emptyStore();
    await fixture.store.load();
    final SessionViewStore view = SessionViewStore(fixture.store);
    SessionViewState state = view.read()!;
    state = view.setOrderBy(
      state,
      SessionOrderBy.manual,
      <String, List<String>>{
        'one': <String>['b', 'a', 'c'],
      },
    );

    state = view.pinSessionOrder(
      state,
      'c',
      <String>{'one'},
      <String, List<String>>{
        'one': <String>['a', 'b', 'c'],
      },
      _facts,
      pinnedSessionIds: <String>['c'],
    );

    // The pinned row leads the selected account's order, and the rows that are
    // still members keep their saved positions behind it.
    expect(state.sessionOrderByAccount['one'], <String>['c', 'b', 'a']);
  });

  test('reconcile places pins, then saved order, then recency, archives last', () {
    final List<String> order = reconcileManualOrder(
      <String>['a', 'b', 'c'],
      <String>['a'],
      _facts,
      pinnedSessionIds: <String>['c'],
      archivedSessionIds: <String>['b'],
    );
    // `c` is pinned so it leads; `a` keeps its saved slot; `b` is archived and
    // therefore trails.
    expect(order, <String>['c', 'a', 'b']);
  });

  test('reconcile drops a saved id that is no longer a member and seats a fork '
      'beside its parent', () {
    final List<String> order = reconcileManualOrder(
      <String>['a', 'b', 'c', 'fork'],
      <String>['gone', 'a'],
      _facts,
    );
    expect(order.contains('gone'), isFalse);
    // `fork` (updatedAt 40) sorts ahead of `c` (20) by recency, then moves up
    // to sit directly above its parent.
    expect(order.indexOf('fork'), order.indexOf('c') - 1);
  });

  test(
    'an install with only the two legacy keys keeps its expansion',
    () async {
      final ({LocalStateStore store, File file}) fixture = _emptyStore();
      await fixture.store.load();
      fixture.store.write(
        SessionViewStore.legacyGroupOverridesKey,
        <String, Object?>{'workspace:one': false},
      );
      fixture.store.write(SessionViewStore.legacyOverflowExpandedKey, <String>[
        'workspace:two',
      ]);

      final SessionViewStore view = SessionViewStore(fixture.store);
      final SessionViewState migrated = view.read()!;
      expect(migrated.groupExpansion['workspace:one'], isFalse);
      expect(migrated.groupExpansion['workspace:two'], isTrue);
      await fixture.store.flush();

      // The migration is written, so the next read takes the new document.
      final LocalStateStore reopened = await _loaded(fixture.file);
      expect(
        SessionViewStore(reopened).read()!.groupExpansion['workspace:two'],
        isTrue,
      );
    },
  );

  test('the archived filter persists', () async {
    final ({LocalStateStore store, File file}) fixture = _emptyStore();
    await fixture.store.load();
    final SessionViewStore view = SessionViewStore(fixture.store);
    view.setArchivedFilter(view.read()!, ArchivedFilter.only);
    await fixture.store.flush();

    final LocalStateStore reopened = await _loaded(fixture.file);
    expect(
      SessionViewStore(reopened).read()!.archivedFilter,
      ArchivedFilter.only,
    );
  });

  test('a corrupt field falls back without losing the others', () {
    final SessionViewState state = SessionViewState.fromJson(<String, Object?>{
      'orderBy': 'not-a-mode',
      'groupExpansion': <String, Object?>{'kept': true, 'bad': 'yes'},
      'sessionOrderByAccount': <String, Object?>{
        'one': <Object?>['a', 3],
      },
    });
    expect(state.orderBy, SessionOrderBy.updated);
    expect(state.groupExpansion, <String, bool>{'kept': true});
    expect(state.sessionOrderByAccount['one'], <String>['a']);
    expect(state.archivedFilter, ArchivedFilter.hide);
  });
}
