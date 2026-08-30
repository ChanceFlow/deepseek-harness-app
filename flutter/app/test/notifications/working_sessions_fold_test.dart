/// Working-session fold tests: the pure, stateless desired-state fold.
/// Every lifecycle edge is expressed through the domain facts the fold
/// reads (running, pendingInteraction, completed, blank), so each test is a
/// plain snapshot in, exact decisions out — no observer state to advance.
library;

import 'package:app/notifications/working_sessions_fold.dart';
import 'package:domain/model/session.dart';
import 'package:flutter_test/flutter_test.dart';

SessionSummary _session(
  String id, {
  String? title,
  bool running = false,
  bool blank = false,
  SessionPendingInteraction? pending,
  bool completed = false,
}) => SessionSummary(
  id: id,
  title: title,
  running: running,
  blank: blank,
  pendingInteraction: pending,
  completed: completed,
);

WorkingSessionDecision _decision(
  String id,
  String title,
  WorkingSessionState state, {
  SessionPendingInteraction? pending,
}) => WorkingSessionDecision(
  sessionId: id,
  sessionTitle: title,
  state: state,
  pending: pending,
);

List<WorkingSessionDecision> _fold(
  List<SessionSummary> sessions, {
  String? selected,
  bool foreground = true,
}) => foldWorkingSessions(
  sessions: sessions,
  selectedSessionId: selected,
  isForegrounded: foreground,
);

void main() {
  group('foldWorkingSessions', () {
    test('running → working', () {
      expect(_fold([_session('s1', title: 'Work', running: true)]), [
        _decision('s1', 'Work', WorkingSessionState.working),
      ]);
    });

    test('idle, nothing pending, nothing completed → gone', () {
      expect(_fold([_session('s1', title: 'Idle')]), [
        _decision('s1', 'Idle', WorkingSessionState.gone),
      ]);
    });

    test('blank placeholder is gone even with flags set', () {
      expect(
        _fold([
          _session(
            's1',
            blank: true,
            running: true,
            completed: true,
            pending: SessionPendingInteraction.approval,
          ),
        ]),
        [_decision('s1', 's1', WorkingSessionState.gone)],
      );
    });

    test('each pending interaction yields waiting with its substate', () {
      for (final pending in SessionPendingInteraction.values) {
        expect(
          _fold([
            _session('s1', title: 'Work', running: true, pending: pending),
          ]),
          [
            _decision(
              's1',
              'Work',
              WorkingSessionState.waiting,
              pending: pending,
            ),
          ],
          reason: '$pending must surface as waiting (question included)',
        );
        expect(_fold([_session('s1', title: 'Idle', pending: pending)]), [
          _decision(
            's1',
            'Idle',
            WorkingSessionState.waiting,
            pending: pending,
          ),
        ], reason: '$pending waits even on a non-running session');
      }
    });

    test('pending outranks completed', () {
      expect(
        _fold([
          _session(
            's1',
            title: 'Work',
            completed: true,
            pending: SessionPendingInteraction.question,
          ),
        ]),
        [
          _decision(
            's1',
            'Work',
            WorkingSessionState.waiting,
            pending: SessionPendingInteraction.question,
          ),
        ],
      );
    });

    test('running outranks a transient completed row', () {
      expect(
        _fold([_session('s1', title: 'Work', running: true, completed: true)]),
        [_decision('s1', 'Work', WorkingSessionState.working)],
      );
    });

    test('completed (running fell, unviewed) → done', () {
      expect(_fold([_session('s1', title: 'Work', completed: true)]), [
        _decision('s1', 'Work', WorkingSessionState.done),
      ]);
    });

    test('foregrounded selected session is silent for working and waiting', () {
      expect(
        _fold([
          _session('s1', title: 'Viewed', running: true),
          _session('s2', title: 'Other', running: true),
        ], selected: 's1'),
        [
          _decision('s1', 'Viewed', WorkingSessionState.gone),
          _decision('s2', 'Other', WorkingSessionState.working),
        ],
      );
      expect(
        _fold([
          _session(
            's1',
            title: 'Viewed',
            running: true,
            pending: SessionPendingInteraction.approval,
          ),
        ], selected: 's1'),
        [_decision('s1', 'Viewed', WorkingSessionState.gone)],
      );
    });

    test('backgrounded selected session still gets its ongoing row', () {
      expect(
        _fold(
          [_session('s1', title: 'Viewed', running: true)],
          selected: 's1',
          foreground: false,
        ),
        [_decision('s1', 'Viewed', WorkingSessionState.working)],
      );
    });

    test('done is not suppressed by the foregrounded selection', () {
      // The completed bit never arms for the open session, so this pair is
      // a transient only (selection stream ran ahead of the openSession
      // re-snapshot); the fold keeps showing done and the follow-up gone.
      expect(
        _fold([_session('s1', title: 'Done', completed: true)], selected: 's1'),
        [_decision('s1', 'Done', WorkingSessionState.done)],
      );
    });

    test('title falls back through displayTitle (cwd basename, then id)', () {
      expect(
        _fold([
          const SessionSummary(
            id: 's9',
            cwd: '/home/user/projects/my-repo',
            blank: false,
            running: true,
          ),
        ]),
        [_decision('s9', 'my-repo', WorkingSessionState.working)],
      );
    });

    test('lifecycle across snapshots: working → waiting → working → done → '
        'gone (read)', () {
      // The domain completed bit carries the running↓ edge and its
      // openSession consumption, so each step is just the next snapshot.
      expect(_fold([_session('s1', title: 'Work', running: true)]), [
        _decision('s1', 'Work', WorkingSessionState.working),
      ]);
      expect(
        _fold([
          _session(
            's1',
            title: 'Work',
            running: true,
            pending: SessionPendingInteraction.approval,
          ),
        ]),
        [
          _decision(
            's1',
            'Work',
            WorkingSessionState.waiting,
            pending: SessionPendingInteraction.approval,
          ),
        ],
      );
      expect(_fold([_session('s1', title: 'Work', running: true)]), [
        _decision('s1', 'Work', WorkingSessionState.working),
      ]);
      expect(_fold([_session('s1', title: 'Work', completed: true)]), [
        _decision('s1', 'Work', WorkingSessionState.done),
      ]);
      // openSession consumed the completed bit: nothing to show anymore.
      expect(_fold([_session('s1', title: 'Work')]), [
        _decision('s1', 'Work', WorkingSessionState.gone),
      ]);
    });
  });
}
