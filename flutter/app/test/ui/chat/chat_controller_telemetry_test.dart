import 'package:dartastic_opentelemetry/testing.dart';
import 'package:dev/dev.dart' show DebugTelemetry, TelemetrySettings;
import 'package:domain/model/prompt.dart' show SendMessageRequest;
import 'package:flutter_test/flutter_test.dart';

import 'package:app/ui/chat/chat_controller.dart';
import 'package:app/ui/chat/chat_ui_state.dart';

import 'chat_controller_test.dart' show FakeChatRepository;

/// Drives real [ChatController] actions and asserts the debug telemetry
/// facade emits the expected OTel events through the real SDK (in-memory
/// exporters). `DebugTelemetry.instance` is a no-op unless the facade is
/// initialized, so this test initializes it over the test harness the same
/// way main() does over a live process.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestHarness harness;

  setUpAll(() async {
    harness = await maybeInitializeOtelForTest();
    await DebugTelemetry.initialize(
      const TelemetrySettings(
        endpoint: 'http://localhost:4318',
        serviceName: 'dsh-android',
        serviceVersion: '0.1.0-test',
      ),
    );
  });

  setUp(() => harness.clear());

  ChatController makeController() =>
      ChatController(FakeChatRepository(initialSessions: const [
        FakeChatRepository.initialSession,
      ]));

  List<String> eventNames() => harness.logs.records
      .map((r) => r.eventName ?? '')
      .where((n) => n.isNotEmpty)
      .toList();

  test('select session emits chat.session.select', () async {
    final controller = makeController();
    controller.onAction(SelectSession(FakeChatRepository.initialSession.id));
    await pumpEventQueue();
    expect(eventNames(), contains('chat.session.select'));
  });

  test('send prompt emits send + success (no failure) counters', () async {
    final controller = makeController();
    controller.onAction(SelectSession(FakeChatRepository.initialSession.id));
    await pumpEventQueue();
    controller.onAction(const SendPrompt('hello telemetry'));
    await pumpEventQueue();

    final names = eventNames();
    expect(names, contains('chat.message.send'));
    expect(names, isNot(contains('chat.message.send_failed')));
    await harness.collectMetrics();
    expect(
      harness.metrics.metrics.any((m) => m.name == 'chat.message.send'),
      isTrue,
      reason: 'send counter exported through the metric reader',
    );
  });

  test('cancel turn emits chat.turn.cancel', () async {
    final controller = makeController();
    controller.onAction(SelectSession(FakeChatRepository.initialSession.id));
    await pumpEventQueue();
    controller.onAction(const CancelTurnAction());
    await pumpEventQueue();
    expect(eventNames(), contains('chat.turn.cancel'));
  });

  test('failed send emits chat.message.send_failed + chat.error', () async {
    final controller = ChatController(_ThrowingRepository());
    controller.onAction(SelectSession(FakeChatRepository.initialSession.id));
    await pumpEventQueue();
    controller.onAction(const SendPrompt('boom'));
    await pumpEventQueue();
    final names = eventNames();
    expect(names, contains('chat.message.send_failed'));
    expect(names, contains('chat.error'));
  });
}

class _ThrowingRepository extends FakeChatRepository {
  @override
  Future<void> sendMessage(SendMessageRequest request) async {
    throw StateError('transport down');
  }
}