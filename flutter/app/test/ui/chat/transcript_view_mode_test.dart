/// Transcript view mode tests — the preference the reference persists as
/// `ui-chat.transcriptView`, the policy each mode selects, and the fold
/// default the transcript reads from it.
library;

import 'dart:convert';

import 'package:app/config.dart';
import 'package:app/di/providers.dart';
import 'package:app/ui/chat/chat_screen.dart';
import 'package:app/ui/chat/chat_ui_state.dart';
import 'package:app/ui/chat/process_disclosure.dart';
import 'package:app/ui/chat/transcript_view_mode.dart';
import 'package:app/ui/chat/turn_process.dart';
import 'package:domain/model/chat_message.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/settings.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:domain/repository/chat_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';

/// The bare transport: an empty successful reply.
class _FakeRpc implements DshRpcClient {
  @override
  Future<RpcResult> call(
    String endpoint,
    String method,
    JsonMap payload, {
    Duration? timeout,
  }) async => RpcResult(ok: true, value: <String, Object?>{});

  @override
  Future<void> respond(String rpcId, RpcResult result) async {}
}

/// A socket that never speaks: these surfaces need no host events.
class _NeverSocket implements DshEventSocket {
  @override
  Stream<ServerRequest> connect(String path, {void Function()? onOpen}) =>
      const Stream<ServerRequest>.empty();
}

TimelineMessage _message({
  required String id,
  String text = '',
  MessageRole role = MessageRole.assistant,
  int? seq,
}) => TimelineMessage(
  ChatMessage(id: id, sessionId: 's1', role: role, text: text, seq: seq),
);

/// One completed Turn: the human's ask, one tool call, then the reply that
/// closed it. The call is the work the fold owns; the reply stays out of it.
List<TimelineItem> _completedTurnItems(int turn) => <TimelineItem>[
  TimelineTurnBoundary(
    turn,
    startedAtEpochMs: 1000,
    endedAtEpochMs: 3000,
    endSeq: turn * 10 + 3,
  ),
  _message(
    id: 'u$turn',
    role: MessageRole.user,
    text: 'run turn $turn',
    seq: turn * 10 + 1,
  ),
  TimelineToolCall(
    id: 't$turn',
    name: 'read',
    arguments: '{"file_path":"a.dart"}',
    status: ToolRunStatus.completed,
    startedAtEpochMs: 1500,
  ),
  _message(id: 'a$turn', text: 'done $turn', seq: turn * 10 + 3),
];

/// The sections one mode produces for [turns] completed Turns.
List<TurnProcessSection> _sections(bool foldCompletedTurns, {int turns = 1}) =>
    <int>[for (var turn = 1; turn <= turns; turn++) turn]
        .expand(
          (turn) => foldTurnProcesses(
            _completedTurnItems(turn),
            foldCompletedTurns: foldCompletedTurns,
          ).whereType<TurnProcessSection>(),
        )
        .toList();

/// Renders the sections' controls, one row per Turn, over a mode's policy.
Widget _rows(List<TurnProcessSection> sections) => l10nApp(
  home: Scaffold(
    body: Column(
      children: <Widget>[
        for (final section in sections)
          TurnProcessRow(
            key: ValueKey<int>(section.facts.turn),
            section: section,
            buildRow: (Object row) => Text(switch (row) {
              TimelineToolCall(:final name) => 'ran $name',
              _ => 'row',
            }),
          ),
      ],
    ),
  ),
);

/// The control's own tap target: the row's first InkWell.
Finder _control(int index) => find
    .descendant(
      of: find.byType(TurnProcessRow).at(index),
      matching: find.byType(InkWell),
    )
    .first;

/// A Host that answers the two settings calls this feature uses, and records
/// the writes so the CAS guard and the wire value can be read back.
class _RecordingSettingsHost implements ChatRepository {
  _RecordingSettingsHost({
    this.stored = 'standard',
    this.exposeNamespace = true,
  });

  /// The value the `ui-chat` namespace holds; the last write replaces it, the
  /// way the Host document does.
  Object? stored;

  /// Whether the Host answers for the namespace at all.
  final bool exposeNamespace;

  final List<(String, String, String, int?)> writes =
      <(String, String, String, int?)>[];

  @override
  Future<SettingsSnapshot> describeSettings() async => SettingsSnapshot(
    writable: true,
    hasDocument: true,
    namespaces: <SettingsNamespace>[
      if (exposeNamespace)
        SettingsNamespace(
          ns: kChatSettingsNamespace,
          applies: SettingsApplies.live,
          revision: 7,
          hasUserLayer: true,
          secretCount: 0,
          schema: SettingsSchema.empty,
          value: <String, Object?>{
            if (stored != null) kTranscriptViewField: stored,
          },
        ),
    ],
    credentialRefs: const <String>[],
  );

  @override
  Future<SettingsNamespace> updateSetting(
    String ns,
    String key,
    String jsonValue, {
    int? expectedRevision,
  }) async {
    writes.add((ns, key, jsonValue, expectedRevision));
    stored = jsonDecode(jsonValue);
    return (await describeSettings()).namespaces.single;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}

void main() {
  group('presentationPolicyFor', () {
    test('is the reference table, mode for mode', () {
      const expected = <TranscriptViewMode, (bool, StepGrouping, bool, bool)>{
        TranscriptViewMode.compact: (
          true,
          StepGrouping.collapsed,
          false,
          false,
        ),
        TranscriptViewMode.standard: (true, StepGrouping.collapsed, true, true),
        TranscriptViewMode.detailed: (true, StepGrouping.history, true, true),
        // The one mode that does not fold a completed Turn.
        TranscriptViewMode.verbose: (false, StepGrouping.none, false, true),
      };
      for (final entry in expected.entries) {
        final policy = presentationPolicyFor(entry.key);
        expect(policy.mode, entry.key);
        expect(
          (
            policy.foldCompletedTurns,
            policy.stepGrouping,
            policy.liveProcessDetail,
            policy.settledReasoningPreview,
          ),
          entry.value,
          reason: '${entry.key}',
        );
      }
      // A device that never chose a mode keeps today's folded transcript.
      expect(kDefaultChatPresentationPolicy, kDetailedPresentation);
    });

    test('the stored value set is the pin\'s, legacy values included', () {
      for (final mode in TranscriptViewMode.values) {
        expect(TranscriptViewMode.fromStored(mode.wireName), mode);
      }
      // The older two-mode generation reads as detailed, unnamed and
      // unwritten.
      expect(
        TranscriptViewMode.fromStored('normal'),
        TranscriptViewMode.detailed,
      );
      expect(
        TranscriptViewMode.fromStored('expanded'),
        TranscriptViewMode.detailed,
      );
      // An unknown value leaves the client default standing.
      expect(TranscriptViewMode.fromStored('nonsense'), isNull);
      expect(TranscriptViewMode.fromStored(null), isNull);
    });
  });

  group('the mode decides the fold', () {
    test('a completed Turn folds in every mode but verbose', () {
      for (final mode in TranscriptViewMode.values) {
        final section = _sections(mode.policy.foldCompletedTurns).single;
        expect(section.hasContent, isTrue, reason: '$mode has work to fold');
        expect(
          section.defaultOpen,
          mode == TranscriptViewMode.verbose,
          reason: '$mode default',
        );
      }
    });

    test('a Turn that cannot fold stays open in every mode', () {
      // A stopped Turn: the reference's `turnProcessAlwaysOpen`. The policy
      // never reaches it.
      final items = <TimelineItem>[
        const TimelineTurnBoundary(1, endSeq: 13, endReason: 'aborted'),
        ..._completedTurnItems(1).skip(1),
      ];
      for (final mode in TranscriptViewMode.values) {
        final facts = turnProcessFacts(
          items.first as TimelineTurnBoundary,
          items,
          foldCompletedTurns: mode.policy.foldCompletedTurns,
        );
        expect(facts.alwaysOpen, isTrue);
        expect(
          TurnProcessSection(
            facts: facts,
            members: const <TurnProcessMember>[],
          ).defaultOpen,
          isTrue,
          reason: '$mode',
        );
      }
    });

    testWidgets(
      'the transcript shows a completed Turn\'s work only in verbose',
      (tester) async {
        await tester.pumpWidget(_rows(_sections(true)));
        await tester.pump();
        expect(find.text('ran read'), findsNothing);
        expect(find.text('Completed in 2s'), findsOneWidget);

        await tester.pumpWidget(_rows(_sections(false)));
        await tester.pump();
        expect(find.text('ran read'), findsOneWidget);
      },
    );

    testWidgets('a reader override survives a mode change while untouched '
        'Turns follow it', (tester) async {
      // Two completed Turns: the reader opens the first, then the mode
      // changes under them.
      await tester.pumpWidget(_rows(_sections(true, turns: 2)));
      await tester.pump();
      expect(find.text('ran read'), findsNothing);

      await tester.tap(_control(0));
      await tester.pump();
      expect(find.text('ran read'), findsOneWidget);

      // detailed → verbose: the untouched second Turn opens with the mode,
      // the first keeps the reader's open.
      await tester.pumpWidget(_rows(_sections(false, turns: 2)));
      await tester.pump();
      expect(find.text('ran read'), findsNWidgets(2));

      // back to a folding mode: the untouched Turn folds again, the reader's
      // override stands.
      await tester.pumpWidget(_rows(_sections(true, turns: 2)));
      await tester.pump();
      expect(find.text('ran read'), findsOneWidget);
    });

    testWidgets('the screen folds by the policy its caller passes', (
      tester,
    ) async {
      final state = ChatUiState(
        sessions: const <SessionSummary>[
          SessionSummary(
            id: 's1',
            title: 'view mode',
            blank: false,
            updatedAtEpochMs: 1700000000000,
          ),
        ],
        selectedSessionId: 's1',
        timeline: _completedTurnItems(1),
      );
      Future<void> pump(TranscriptViewMode mode) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              dshRpcClientProvider(Uri.parse(kDshBaseUrl))
                  .overrideWithValue(_FakeRpc()),
              dshEventSocketProvider(Uri.parse(kDshBaseUrl))
                  .overrideWithValue(_NeverSocket()),
            ],
            child: l10nApp(
              home: ChatScreen(
                uiState: state,
                onAction: (_) {},
                presentation: presentationPolicyFor(mode),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));
      }

      await pump(TranscriptViewMode.detailed);
      expect(find.byType(ToolCallRow), findsNothing);

      await pump(TranscriptViewMode.verbose);
      expect(find.byType(ToolCallRow), findsOneWidget);
    });
  });

  group('TranscriptViewController', () {
    test('reads the Host field', () async {
      final host = _RecordingSettingsHost(stored: 'compact');
      final controller = TranscriptViewController(host);
      await pumpEventQueue();

      expect(controller.state.mode, TranscriptViewMode.compact);
      expect(controller.state.exposed, isTrue);
      expect(controller.state.revision, 7);
      controller.dispose();
    });

    test('legacy saved values read as detailed', () async {
      final controller = TranscriptViewController(
        _RecordingSettingsHost(stored: 'expanded'),
      );
      await pumpEventQueue();

      expect(controller.state.mode, TranscriptViewMode.detailed);
      controller.dispose();
    });

    test(
      'a Host that never answered leaves the client default standing',
      () async {
        final controller = TranscriptViewController(
          _RecordingSettingsHost(exposeNamespace: false),
        );
        await pumpEventQueue();

        expect(controller.state.mode, kDefaultTranscriptViewMode);
        expect(controller.state.exposed, isFalse);
        controller.dispose();
      },
    );

    test(
      'select writes the field with the described revision as CAS',
      () async {
        final host = _RecordingSettingsHost(stored: 'detailed');
        final controller = TranscriptViewController(host);
        await pumpEventQueue();

        await controller.select(TranscriptViewMode.verbose);

        // The pin's namespace and field, the wire value, and the revision the
        // last describe reported as the write's guard.
        expect(host.writes, <(String, String, String, int?)>[
          ('ui-chat', 'transcriptView', '"verbose"', 7),
        ]);
        expect(controller.state.mode, TranscriptViewMode.verbose);
        controller.dispose();
      },
    );
  });
}
