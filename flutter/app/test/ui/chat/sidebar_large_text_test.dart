/// The sidebar at the platform's text steps: the brand wordmark row and the
/// workspace group header both survive the largest one.
///
/// Both are rows of intrinsic-width parts, so the platform's text scale used to
/// stripe them — the wordmark from 1.3× and the group header's label/caption
/// pair from 2.0× — because a fixed row cannot express "this text needs more
/// room than the sidebar has". The rows now yield: the wordmark's runs are
/// flexible and ellipsize inside their share, and the group header moves its
/// caption onto a second line when the pair no longer fits beside each other.
/// These tests pump the real panel at every step the platform offers and assert
/// nothing overflows, so the next change that pins a row to an intrinsic width
/// fails here instead of on a phone.
library;

import 'dart:io';

import 'package:domain/model/session.dart';
import 'package:domain/model/workspace.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/local_state/local_state_providers.dart';
import 'package:app/local_state/local_state_store.dart';
import 'package:app/ui/chat/brand_wordmark.dart';
import 'package:app/ui/chat/session_panel.dart';
import 'package:app/ui/theme/theme.dart';

import '../../l10n_app.dart';

/// Every step the platform's text-size setting offers, smallest to largest.
const List<double> _kSteps = <double>[1.0, 1.3, 1.5, 2.0, 2.5, 3.0];

/// The sidebar's mounted width (the drawer and the rail-hosted pane share it).
const double _kSidebarWidth = 320;

/// The brand row's slot inside the sidebar: the panel width less the rail
/// toggle and its gap.
const double _kBrandSlot = 264;

/// One group with a long title and a second with a short one, so the header's
/// one-line and two-line forms are both exercised.
const List<WorkspaceSummary> _kWorkspaces = <WorkspaceSummary>[
  WorkspaceSummary(
    workspaceId: 'w1',
    path: '/tmp/proj',
    title: 'a workspace whose title wants the whole header row',
    sessionIds: <String>['s1', 's2', 's3', 's4', 's5', 's6', 's7'],
  ),
  WorkspaceSummary(
    workspaceId: 'w2',
    path: '/tmp/other',
    title: 'other',
    sessionIds: <String>['o1'],
  ),
];

final List<SessionSummary> _kSessions = <SessionSummary>[
  for (var i = 1; i <= 7; i++)
    SessionSummary(
      id: 's$i',
      title: 'session $i',
      blank: false,
      updatedAtEpochMs: 1000 * i,
      cwd: '/tmp/proj',
    ),
  const SessionSummary(
    id: 'o1',
    title: 'other session',
    blank: false,
    updatedAtEpochMs: 8000,
    cwd: '/tmp/other',
  ),
];

/// Runs [body] with Flutter's error sink captured, and returns what it caught:
/// a striped row reports an overflow through this sink, not as a thrown
/// exception.
Future<List<FlutterErrorDetails>> _caught(Future<void> Function() body) async {
  final List<FlutterErrorDetails> errors = <FlutterErrorDetails>[];
  final FlutterExceptionHandler? previous = FlutterError.onError;
  FlutterError.onError = errors.add;
  try {
    await body();
  } finally {
    FlutterError.onError = previous;
  }
  return errors;
}

/// Fails with the overflow's own text (which names the widget and its file).
void _expectNoErrors(List<FlutterErrorDetails> errors) {
  expect(
    errors.map((details) => details.exception.toString()).toList(),
    isEmpty,
    reason: 'a row outgrew its slot at this text step',
  );
}

Future<void> _setScale(WidgetTester tester, double scale) async {
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// Pumps the real panel at the sidebar's width and [scale].
Future<ProviderContainer> _pumpSidebar(
  WidgetTester tester, {
  required double scale,
  required bool inDrawer,
}) async {
  tester.view.physicalSize = const Size(800, 1280);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await _setScale(tester, scale);

  final dir = Directory.systemTemp.createTempSync('sidebar_scale');
  addTearDown(() => dir.deleteSync(recursive: true));
  final container = ProviderContainer(
    overrides: [
      localStateStoreProvider.overrideWith(
        (ref) async => LocalStateStore(File('${dir.path}/local_state.json')),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: l10nApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: _kSidebarWidth,
              height: 1200,
              child: SessionPanel(
                inDrawer: inDrawer,
                sessions: _kSessions,
                workspaces: _kWorkspaces,
                searchResults: const <SessionSearchResult>[],
                selectedSessionId: 's1',
                onSelectSession: (_) {},
                onCreateSession: (_) {},
                onSearchSessions: (_) {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// The brand row alone, in the slot the sidebar gives it: the row under test,
/// without the rest of the panel.
Future<void> _pumpBrandSlot(WidgetTester tester, double scale) async {
  await _setScale(tester, scale);
  await tester.pumpWidget(
    MaterialApp(
      theme: DshTheme.light(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: _kBrandSlot,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: InkWell(
                      onTap: () {},
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: BrandWordmark(height: 22),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final double scale in _kSteps) {
    testWidgets('the drawer holds at ${scale}x text scale', (tester) async {
      final List<FlutterErrorDetails> errors = await _caught(
        () => _pumpSidebar(tester, scale: scale, inDrawer: true),
      );
      _expectNoErrors(errors);
      // Both rows are still on screen with their text: the fix yields room, it
      // does not drop the row.
      expect(find.byType(BrandWordmark), findsOneWidget);
      expect(find.text('other'), findsOneWidget);
    });

    testWidgets('the embedded sidebar holds at ${scale}x text scale', (
      tester,
    ) async {
      final List<FlutterErrorDetails> errors = await _caught(
        () => _pumpSidebar(tester, scale: scale, inDrawer: false),
      );
      _expectNoErrors(errors);
    });

    testWidgets('the brand row holds at ${scale}x text scale', (tester) async {
      final List<FlutterErrorDetails> errors = await _caught(
        () => _pumpBrandSlot(tester, scale),
      );
      _expectNoErrors(errors);
      // The wordmark's runs are painted, not dropped.
      expect(find.text('DeepSeek'), findsOneWidget);
      expect(find.text('HARNESS'), findsOneWidget);
    });
  }

  testWidgets('the brand row keeps a 48dp target at the largest step', (
    tester,
  ) async {
    await _pumpSidebar(tester, scale: 3.0, inDrawer: true);
    final Size target = tester.getSize(
      find.ancestor(
        of: find.byType(BrandWordmark),
        matching: find.byType(InkWell),
      ),
    );
    expect(target.height, greaterThanOrEqualTo(kMinInteractiveDimension));
  });

  testWidgets('the group header keeps its caption beside the label at 1.0x', (
    tester,
  ) async {
    // The one-line form is the shipped look: the caption sits at the row's far
    // edge at the default step, and only a step it cannot fit at moves it.
    await _pumpSidebar(tester, scale: 1.0, inDrawer: true);
    final Rect label = tester.getRect(
      find.text('a workspace whose title wants the whole header row'),
    );
    final Rect caption = tester.getRect(find.text('7 sessions'));
    expect(caption.center.dy, closeTo(label.center.dy, 1.0));
    expect(caption.left, greaterThan(label.left));
  });
}
