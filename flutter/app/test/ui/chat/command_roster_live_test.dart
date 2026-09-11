/// Live slash-command roster — `commands/list` replaces the frozen static
/// list as the authority for discovery and dispatch, so a host- or
/// plugin-registered command the client never hard-codes is both visible and
/// runnable. The static list survives only as the pre-first-pull fallback,
/// which is what a `session/agent-busy` refusal degrades to.
///
/// The controller-level tests drive the real [ChatController]; the widget
/// tests drive the real [ChatScreen] over the same controller and the shared
/// [FakeChatRepository].
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:app/ui/chat/chat_controller.dart';
import 'package:app/ui/chat/chat_screen.dart';
import 'package:app/ui/chat/chat_ui_state.dart';
import 'package:app/ui/chat/command_roster.dart';
import 'package:domain/model/attachment.dart';
import 'package:domain/model/command.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';
import 'chat_controller_test.dart';
import 'chat_local_state_fake.dart';

/// A live-only command: nothing in [kHostCommandNames] names `deploy`.
const CommandDescriptor _deploy = CommandDescriptor(
  name: 'deploy',
  description: 'Deploy a target',
  inputHint: '<target>',
);

/// A second live-only command that is bare-only (no advertised input).
const CommandDescriptor _status = CommandDescriptor(
  name: 'status',
  description: 'Show deployment status',
);

const CommandExecution _success = CommandExecution(
  commandId: 'cmd-1',
  kind: CommandOutcomeKind.success,
);

const PendingImage _image = PendingImage(
  id: 'content://media/1',
  mediaType: 'image/png',
  base64Data: 'aGk=',
  name: 'shot.png',
  byteSize: 2,
);

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(kUiPublishWindow + const Duration(milliseconds: 16));
  await tester.pump();
}

void main() {
  group('command_roster decision table', () {
    test('a live descriptor overrides the static membership check', () {
      final facts = hostCommandFacts(const <CommandDescriptor>[_deploy]);
      // The static fallback never routes an unknown name...
      expect(hostCommandLineFor('/deploy prod'), isNull);
      // ...but the live descriptor does, with its own hint driving the
      // bare-only rule.
      expect(hostCommandLineFor('/deploy prod', facts), '/deploy prod');
      expect(hostCommandLineFor('/deploy', facts), '/deploy');
      expect(hostCommandIsBare('/deploy', facts), isFalse);
    });

    test('a live bare-only descriptor executes bare only', () {
      final facts = hostCommandFacts(const <CommandDescriptor>[_status]);
      expect(hostCommandIsBare('/status', facts), isTrue);
      expect(hostCommandLineFor('/status now', facts), isNull);
    });

    test('a live descriptor without attachments refuses images', () {
      final facts = hostCommandFacts(const <CommandDescriptor>[_deploy]);
      expect(hostCommandImageRefusal('/deploy prod', facts), 'deploy');
      // A descriptor that declares image acceptance does not refuse.
      final accepting = hostCommandFacts(const <CommandDescriptor>[
        CommandDescriptor(
          name: 'deploy',
          description: 'Deploy a target',
          inputHint: '<target>',
          acceptsAttachments: true,
        ),
      ]);
      expect(hostCommandImageRefusal('/deploy prod', accepting), isNull);
    });
  });

  group('controller roster pulls', () {
    test('a live-only command dispatches through commands/execute', () async {
      final repository = FakeChatRepository()
        ..commandRoster = const <CommandDescriptor>[_deploy];
      repository.commandExecutions['/deploy prod'] = _success;
      final controller = ChatController(repository);
      addTearDown(controller.dispose);
      await pumpEventQueue();

      controller.onAction(const SelectSession('session-1'));
      await pumpEventQueue();

      expect(repository.commandListCalls, <String>['session-1']);
      expect(controller.state.commands, const <CommandDescriptor>[_deploy]);

      controller.onAction(const SendPrompt('/deploy prod'));
      await pumpEventQueue();

      expect(repository.commandDispatchImages.keys, contains('/deploy prod'));
      expect(repository.sentMessages, isEmpty);
    });

    test('commands/change invalidates and re-pulls the roster', () async {
      final repository = FakeChatRepository()
        ..commandRoster = const <CommandDescriptor>[_status];
      final controller = ChatController(repository);
      addTearDown(controller.dispose);
      await pumpEventQueue();

      controller.onAction(const SelectSession('session-1'));
      await pumpEventQueue();
      expect(controller.state.commands, const <CommandDescriptor>[_status]);

      // The registry changed: the tick clears the cache and re-pulls the
      // selected session.
      repository.commandRoster = const <CommandDescriptor>[_status, _deploy];
      repository.commandRosterChanges.add(null);
      await pumpEventQueue();

      expect(repository.commandListCalls, <String>['session-1', 'session-1']);
      expect(controller.state.commands, const <CommandDescriptor>[
        _status,
        _deploy,
      ]);

      repository.commandExecutions['/deploy prod'] = _success;
      controller.onAction(const SendPrompt('/deploy prod'));
      await pumpEventQueue();
      expect(repository.commandDispatchImages.keys, contains('/deploy prod'));
    });

    test('a refused pull keeps the static roster dispatchable', () async {
      // commandRoster null: `listCommands` throws `session/agent-busy`.
      final repository = FakeChatRepository();
      repository.commandExecutions['/compact'] = _success;
      final controller = ChatController(repository);
      addTearDown(controller.dispose);
      await pumpEventQueue();

      controller.onAction(const SelectSession('session-1'));
      await pumpEventQueue();

      expect(repository.commandListCalls, <String>['session-1']);
      expect(controller.state.commands, isNull);
      // No error strip: the refusal degrades silently to the built-ins.
      expect(controller.state.errorMessage, isNull);

      controller.onAction(const SendPrompt('/compact'));
      await pumpEventQueue();
      expect(repository.commandDispatchImages.keys, contains('/compact'));
    });
  });

  group('composer discovery and admission', () {
    late FakeChatRepository repository;
    late ChatController controller;

    Future<void> pump(
      WidgetTester tester, {
      List<CommandDescriptor>? roster,
    }) async {
      repository = FakeChatRepository()..commandRoster = roster;
      controller = ChatController(repository);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        ProviderScope(
          child: l10nApp(
            home: StreamBuilder<ChatUiState>(
              stream: controller.uiState,
              builder: (context, snapshot) => ChatScreen(
                uiState: snapshot.data ?? const ChatUiState(),
                onAction: controller.onAction,
                localState: FakeChatLocalState(),
              ),
            ),
          ),
        ),
      );
      await _settle(tester);
      controller.onAction(SelectSession(FakeChatRepository.initialSession.id));
      await _settle(tester);
    }

    testWidgets('a live-roster command is discoverable and dispatches', (
      tester,
    ) async {
      await pump(tester, roster: const <CommandDescriptor>[_deploy]);
      repository.commandExecutions['/deploy'] = _success;

      await tester.enterText(find.byType(TextField), '/dep');
      await tester.pump();

      // The candidate list comes from the live roster, not the static list.
      expect(find.text('/deploy'), findsOneWidget);

      await tester.tap(find.text('/deploy'));
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await _settle(tester);

      expect(repository.commandDispatchImages.keys, contains('/deploy'));
      expect(repository.sentMessages, isEmpty);
    });

    testWidgets('an attachment on a non-accepting live command is refused', (
      tester,
    ) async {
      await pump(tester, roster: const <CommandDescriptor>[_deploy]);
      controller.onAction(const ImagesLoaded(<PendingImage>[_image]));
      await _settle(tester);

      await tester.enterText(find.byType(TextField), '/deploy prod');
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await _settle(tester);

      // Nothing dispatched, the draft and the image stay in place.
      expect(repository.commandDispatchImages, isEmpty);
      expect(repository.sentMessages, isEmpty);
      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(
        find.text(l10n.commandImagesUnsupported('deploy')),
        findsOneWidget,
      );
    });

    testWidgets('a refused roster pull leaves the composer working', (
      tester,
    ) async {
      await pump(tester, roster: null);
      repository.commandExecutions['/compact'] = _success;

      await tester.enterText(find.byType(TextField), '/comp');
      await tester.pump();

      // The static fallback still offers the built-in command.
      expect(find.text('/compact'), findsOneWidget);

      await tester.tap(find.text('/compact'));
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await _settle(tester);

      expect(repository.commandDispatchImages.keys, contains('/compact'));
    });
  });
}
