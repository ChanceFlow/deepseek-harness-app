/// Terminal attachment behavior: the frame contract (a generation opens with a
/// snapshot, output numbers strictly from it, a jump is a gap that only a new
/// snapshot repairs), the dimension clamp, and what the page states about a
/// host that composes no terminal service.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:app/ui/terminal/terminal_controller.dart';
import 'package:app/ui/terminal/terminal_screen_buffer.dart';
import 'package:app/ui/terminal/terminal_screen.dart';
import 'package:domain/model/terminal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';

final AppLocalizations _l10n = lookupAppLocalizations(const Locale('en'));

TerminalInfo _info({
  String state = 'running',
  String? controllerId,
  int cols = 80,
  int rows = 24,
  int? exitCode,
}) => TerminalInfo(
  id: 'term-1',
  title: 'bash',
  shell: const TerminalShell(path: '/bin/bash', name: 'bash'),
  cwd: '/home/tester/project',
  cols: cols,
  rows: rows,
  state: switch (state) {
    'exited' => TerminalState.exited,
    'failed' => TerminalState.failed,
    _ => TerminalState.running,
  },
  exitCode: exitCode,
  controllerId: controllerId,
);

void main() {
  group('TerminalAttachment', () {
    test('a snapshot resets the emulator and anchors the sequence', () {
      final attachment = TerminalAttachment(terminalId: 'term-1');

      expect(
        attachment.applyTerminalFrame(
          TerminalSnapshot(
            sequence: 5,
            screen: 'old screen',
            info: _info(controllerId: 'att-1'),
          ),
        ),
        isTrue,
      );
      attachment.attachmentId = 'att-1';
      expect(attachment.expectedSequence, 5);
      expect(attachment.phase, TerminalPhase.connected);
      expect(attachment.hasScreen, isTrue);
      expect(attachment.writable, isTrue);
      expect(attachment.text, contains('old screen'));

      // A second snapshot replaces the screen rather than appending to it —
      // a reconnect has no resume offset.
      attachment.applyTerminalFrame(
        TerminalSnapshot(
          sequence: 1,
          screen: 'fresh',
          info: _info(controllerId: 'att-1'),
        ),
      );
      expect(attachment.expectedSequence, 1);
      expect(attachment.text.trim(), 'fresh');
    });

    test('output must continue the anchor exactly', () {
      final attachment = TerminalAttachment(terminalId: 'term-1')
        ..attachmentId = 'att-1';
      attachment.applyTerminalFrame(
        TerminalSnapshot(
          sequence: 10,
          screen: 'start',
          info: _info(controllerId: 'att-1'),
        ),
      );

      expect(
        attachment.applyTerminalFrame(
          const TerminalOutput(sequence: 11, data: 'next'),
        ),
        isTrue,
      );
      expect(attachment.expectedSequence, 11);
      expect(attachment.text, contains('next'));

      // A jump means frames were lost; the frame is rejected and the
      // attachment drops out of the connected phase.
      expect(
        attachment.applyTerminalFrame(
          const TerminalOutput(sequence: 13, data: 'skipped'),
        ),
        isFalse,
      );
      expect(attachment.sawGap, isTrue);
      expect(attachment.phase, TerminalPhase.disconnected);
      expect(attachment.text, isNot(contains('skipped')));
    });

    test('a state frame carries no sequence', () {
      final attachment = TerminalAttachment(terminalId: 'term-1');
      attachment.applyTerminalFrame(
        TerminalSnapshot(
          sequence: 3,
          screen: '',
          info: _info(controllerId: 'att-1'),
        ),
      );

      expect(
        attachment.applyTerminalFrame(
          TerminalStateChange(info: _info(state: 'exited', exitCode: 0)),
        ),
        isTrue,
      );
      expect(attachment.expectedSequence, 3);
      expect(attachment.info?.state, TerminalState.exited);
      // A dead shell is never writable, whoever holds control.
      expect(attachment.writable, isFalse);
    });

    test('control is this attachment only', () {
      final attachment = TerminalAttachment(terminalId: 'term-1')
        ..attachmentId = 'att-1'
        ..phase = TerminalPhase.connected;

      attachment.applyTerminalFrame(TerminalStateChange(info: _info()));
      // No controller yet: another window may be about to attach.
      expect(attachment.writable, isFalse);

      attachment.applyTerminalFrame(
        TerminalStateChange(info: _info(controllerId: 'att-2')),
      );
      expect(attachment.writable, isFalse);

      attachment.applyTerminalFrame(
        TerminalStateChange(info: _info(controllerId: 'att-1')),
      );
      expect(attachment.writable, isTrue);
    });

    test('dimensions clamp to the host maximum, never to zero', () {
      const environment = TerminalEnvironment(
        cwd: '/tmp',
        maxInputBytes: 1024,
        maxCols: 120,
        maxRows: 40,
        scrollback: 100,
      );

      expect(TerminalAttachment.clampDimensions(200, 100, environment), (
        120,
        40,
      ));
      expect(TerminalAttachment.clampDimensions(0, 0, environment), (2, 1));
      // Without an environment the proposal stands, still never degenerate.
      expect(TerminalAttachment.clampDimensions(90, 30, null), (90, 30));
    });
  });

  group('TerminalScreenBuffer', () {
    test('attributes are consumed, not printed', () {
      final buffer = TerminalScreenBuffer()
        ..reset('\u001b[1mbold\u001b[0m and \u001b[32mgreen\u001b[0m');

      expect(buffer.text, 'bold and green');
      expect(buffer.text, isNot(contains('\u001b')));
    });

    test('an erase-display sequence clears the text', () {
      final buffer = TerminalScreenBuffer()
        ..reset('old prompt')
        ..append('\u001b[2J\u001b[Hnew prompt');

      expect(buffer.text, 'new prompt');
    });

    test('a carriage return rewrites its line instead of appending', () {
      final buffer = TerminalScreenBuffer()
        ..reset('')
        ..append('0%\r')
        ..append('50%\r')
        ..append('100%\r\ndone\r\n');

      // A progress line reads as one line, and the completed line stays.
      expect(buffer.text, '100%\ndone\n');
    });

    test('a cursor-headless escape and a bell are dropped', () {
      final buffer = TerminalScreenBuffer()
        ..reset('a\u0007\u001b[?25lb\u001b]0;title\u0007c');

      expect(buffer.text, 'abc');
    });

    test('backspace removes the character it steps over', () {
      final buffer = TerminalScreenBuffer()..reset('ab\u0008c');

      expect(buffer.text, 'ac');
    });

    test('a snapshot replaces the screen and output appends to it', () {
      final buffer = TerminalScreenBuffer()
        ..reset('first')
        ..append('\r\nsecond');

      expect(buffer.text, 'first\nsecond');
      // A new generation's snapshot is the whole screen again.
      buffer.reset('fresh');
      expect(buffer.text, 'fresh');
    });

    test('the text is bounded to the tail', () {
      final buffer = TerminalScreenBuffer(limit: 8)..reset('0123456789abc');

      expect(buffer.text, '56789abc');
      expect(buffer.text.length, 8);
    });
  });

  testWidgets('a host without a terminal service says so', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      l10nApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => Text(
              terminalStatusLabel(
                const TerminalUiState(unavailable: true),
                AppLocalizations.of(context)!,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text(_l10n.terminalStatusDetached), findsOneWidget);
    expect(
      terminalNoticeLabel('unavailable', _l10n),
      _l10n.terminalUnavailable,
    );
    expect(
      terminalNoticeLabel('limit:4', _l10n),
      _l10n.terminalLimitReached(4),
    );
    expect(terminalNoticeLabel('output gap', _l10n), _l10n.terminalOutputGap);
  });

  testWidgets('a page with no terminal states the next step', (
    WidgetTester tester,
  ) async {
    final controller = _StubTerminalController();
    await tester.pumpWidget(
      l10nApp(
        home: TerminalPage(
          controller: controller,
          state: const TerminalUiState(),
        ),
      ),
    );

    expect(find.text(_l10n.terminalNoTerminal), findsOneWidget);
    // A new-terminal action is the only thing to do, so it is offered.
    expect(find.byIcon(Icons.add), findsOneWidget);
  });

  testWidgets('an exited tab offers a fresh terminal, not a reconnect', (
    WidgetTester tester,
  ) async {
    final controller = _StubTerminalController();
    final attachment = TerminalAttachment(terminalId: 'term-1')
      ..attachmentId = 'att-1';
    attachment.applyTerminalFrame(
      TerminalSnapshot(
        sequence: 1,
        screen: 'bye',
        info: _info(state: 'exited', controllerId: 'att-1'),
      ),
    );
    controller.attachments['term-1'] = attachment;
    await tester.pumpWidget(
      l10nApp(
        home: TerminalPage(
          controller: controller,
          state: TerminalUiState(
            terminals: <TerminalInfo>[_info(state: 'exited')],
            selectedTerminalId: 'term-1',
            phase: TerminalPhase.connected,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text(_l10n.terminalStatusExited(0)), findsOneWidget);
    expect(find.text(_l10n.terminalReconnect), findsNothing);
    expect(find.text(_l10n.terminalNew), findsWidgets);
  });

  testWidgets('a detached attachment offers a reconnect', (
    WidgetTester tester,
  ) async {
    final controller = _StubTerminalController();
    controller.attachments['term-1'] = TerminalAttachment(terminalId: 'term-1')
      ..attachmentId = 'att-1'
      ..phase = TerminalPhase.disconnected
      ..info = _info(controllerId: 'att-1');
    await tester.pumpWidget(
      l10nApp(
        home: TerminalPage(
          controller: controller,
          state: TerminalUiState(
            terminals: <TerminalInfo>[_info()],
            selectedTerminalId: 'term-1',
            phase: TerminalPhase.disconnected,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text(_l10n.terminalStatusDisconnected), findsOneWidget);
    expect(find.text(_l10n.terminalReconnect), findsOneWidget);
  });
}

/// A surface double: the page reads its selected attachment and calls back,
/// and these tests never touch the wire.
class _StubTerminalController implements TerminalSurface {
  final Map<String, TerminalAttachment> attachments =
      <String, TerminalAttachment>{};

  @override
  TerminalAttachment? get selectedAttachment =>
      attachments.values.isEmpty ? null : attachments.values.first;

  @override
  void refresh() {}

  @override
  void write(String data) {}

  @override
  Future<void> attach(String terminalId) async {}

  @override
  Future<void> close(String terminalId) async {}

  @override
  Future<void> createTerminal({String? shellPath}) async {}

  @override
  Future<void> rename(String terminalId, String title) async {}

  @override
  Future<void> resize(int cols, int rows) async {}

  @override
  void select(String terminalId) {}
}
