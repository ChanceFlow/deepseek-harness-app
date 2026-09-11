/// Dynamic-Cordis approval surface — the live deadlock: a `cordis_run` /
/// `cordis_define` tool blocks host-side on a `cordis/request-run` a person
/// must clear, and rejection is the only decision this client can deliver
/// honestly (an approval names a browser-runtime activation).
///
/// Every test drives the real [ChatController] over the shared
/// [FakeChatRepository] and the real [ChatScreen], so the card's mount, the
/// repository call, and the localized failure all ride production paths.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:app/ui/chat/chat_controller.dart';
import 'package:app/ui/chat/chat_screen.dart';
import 'package:app/ui/chat/chat_ui_state.dart';
import 'package:app/ui/chat/cordis_request_panel.dart';
import 'package:domain/model/cordis.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';
import 'chat_controller_test.dart';
import 'chat_local_state_fake.dart';

const _request = CordisRunRequest(
  requestId: 'req-1',
  sessionId: 'session-1',
  pluginId: 'plugin-vision',
  packageId: 'dsh-plugin-vision@1.2.0',
  mode: CordisRunMode.run,
  name: 'Vision tools',
  purpose: 'Add describe-image tools to this session',
  requiresApproval: true,
);

/// Advance the controller's upstream publish window and land the rebuild.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(kUiPublishWindow + const Duration(milliseconds: 16));
  await tester.pump();
}

void main() {
  late FakeChatRepository repository;
  late ChatController controller;

  Future<void> pump(WidgetTester tester, {Locale? locale}) async {
    repository = FakeChatRepository();
    controller = ChatController(repository);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: l10nApp(
          locale: locale,
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
  }

  testWidgets('a pending request mounts the card with its identity', (
    tester,
  ) async {
    await pump(tester);
    repository.cordisRequests.value = const <CordisRunRequest>[_request];
    await _settle(tester);

    expect(find.byType(CordisRequestPanel), findsOneWidget);
    expect(find.text('Vision tools'), findsOneWidget);
    expect(
      find.text('Add describe-image tools to this session'),
      findsOneWidget,
    );
    expect(find.text('plugin-vision'), findsOneWidget);
    expect(find.text('dsh-plugin-vision@1.2.0'), findsOneWidget);
    // The lifecycle intent rides the header chip.
    expect(find.text('Run'), findsOneWidget);
    // The honest limitation is stated on the card.
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(find.text(l10n.cordisRejectOnlyNotice), findsOneWidget);
    // No approval affordance anywhere.
    expect(find.text('Allow once'), findsNothing);
  });

  testWidgets('Reject answers the repository with a rejected resolution', (
    tester,
  ) async {
    await pump(tester);
    repository.cordisRequests.value = const <CordisRunRequest>[_request];
    await _settle(tester);

    await tester.tap(find.text('Reject'));
    await _settle(tester);

    expect(repository.cordisResolutions, hasLength(1));
    final (requestId, resolution) = repository.cordisResolutions.single;
    expect(requestId, 'req-1');
    expect(resolution, const CordisRunRejected());
  });

  testWidgets('a resolved event clears the card and returns the composer', (
    tester,
  ) async {
    await pump(tester);
    repository.cordisRequests.value = const <CordisRunRequest>[_request];
    await _settle(tester);
    expect(find.byType(CordisRequestPanel), findsOneWidget);

    // `cordis/request-run-resolved` drops the request from the pending list;
    // the settled state is the card leaving the composer seat.
    repository.cordisRequests.value = const <CordisRunRequest>[];
    await _settle(tester);

    expect(find.byType(CordisRequestPanel), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('a refused answer surfaces the localized failure', (
    tester,
  ) async {
    await pump(tester);
    repository
      ..refuseCordisResolution = true
      ..cordisRequests.value = const <CordisRunRequest>[_request];
    await _settle(tester);

    await tester.tap(find.text('Reject'));
    await _settle(tester);

    expect(repository.cordisResolutions, isEmpty);
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(find.text(l10n.cordisAnswerFailed), findsOneWidget);
    // The request stays pending: the reader can try again.
    expect(find.byType(CordisRequestPanel), findsOneWidget);
  });

  testWidgets('a request that needs no approval mounts no card', (
    tester,
  ) async {
    await pump(tester);
    // requiresApproval false is not a pending decision: the host already
    // started its own half and only needs a browser page to attach the
    // Client half. A Reject would cancel a run nobody asked about.
    repository.cordisRequests.value = const <CordisRunRequest>[
      CordisRunRequest(
        requestId: 'req-2',
        sessionId: 'session-1',
        pluginId: 'plugin-quiet',
        packageId: 'dsh-plugin-quiet@0.1.0',
        mode: CordisRunMode.update,
        name: 'Quiet plugin',
        purpose: 'Update an already-running plugin',
        requiresApproval: false,
      ),
    ];
    await _settle(tester);

    expect(find.byType(CordisRequestPanel), findsNothing);
    expect(find.text('Quiet plugin'), findsNothing);
    // The composer seat is free.
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('the card renders under the Chinese locale', (tester) async {
    await pump(tester, locale: const Locale('zh'));
    repository.cordisRequests.value = const <CordisRunRequest>[_request];
    await _settle(tester);

    final l10nZh = lookupAppLocalizations(const Locale('zh'));
    expect(find.byType(CordisRequestPanel), findsOneWidget);
    expect(find.text(l10nZh.cordisApprovalHeader), findsOneWidget);
    expect(find.text(l10nZh.cordisRejectOnlyNotice), findsOneWidget);
    expect(find.text(l10nZh.reject), findsOneWidget);
  });

  test('the controller publishes the pending request as state', () async {
    repository = FakeChatRepository();
    controller = ChatController(repository);
    addTearDown(controller.dispose);
    await pumpEventQueue();

    repository.cordisRequests.value = const <CordisRunRequest>[_request];
    // Upstream facts publish on a real publish-window trailing edge.
    await Future<void>.delayed(
      kUiPublishWindow + const Duration(milliseconds: 16),
    );

    expect(controller.state.cordisRunRequests, const <CordisRunRequest>[
      _request,
    ]);
    expect(controller.state.cordisAnswerFailed, isFalse);
  });
}
