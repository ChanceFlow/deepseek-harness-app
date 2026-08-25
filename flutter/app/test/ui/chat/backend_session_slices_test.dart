/// The backend-session-slices provider's render economics: a slice is
/// selected out of its host's chat state on roster facts only, so a
/// timeline-only publish on ANY backend (every backend's restored session
/// streams while the app is open) recomputes nothing, while a real roster
/// change or an active-backend switch does.
library;

import 'dart:async';

import 'package:domain/model/backend.dart';
import 'package:domain/model/chat_message.dart';
import 'package:domain/model/session.dart';
import 'package:domain/model/timeline_item.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/di/providers.dart';
import 'package:app/ui/chat/chat_ui_state.dart';

final _laptop = BackendConfig(
  id: 'default',
  label: 'Laptop',
  baseUri: Uri.parse('http://10.0.2.2:3080'),
);

final _buildBox = BackendConfig(
  id: 'b1',
  label: 'Build box',
  baseUri: Uri.parse('http://10.0.2.2:3081'),
);

final _registry = BackendRegistryState(
  backends: <BackendConfig>[_laptop, _buildBox],
  activeId: 'default',
);

const _laptopSessions = <SessionSummary>[
  SessionSummary(id: 's1', title: 'Alpha on laptop', blank: false),
];

const _buildBoxSessions = <SessionSummary>[
  SessionSummary(id: 'sB1', title: 'Beta on buildbox', blank: false),
];

ChatUiState _state(
  List<SessionSummary> sessions, {
  List<TimelineItem> timeline = const <TimelineItem>[],
}) => ChatUiState(sessions: sessions, timeline: timeline);

/// A growing streaming partial — the timeline-only publish shape.
TimelineItem _streamingText(String text) => TimelineMessage(
  ChatMessage(
    id: 'partial-1',
    sessionId: 'sB1',
    role: MessageRole.assistant,
    text: text,
    streaming: true,
  ),
);

/// Let Riverpod's batched scheduler settle: timer turns for stream
/// delivery plus microtask drains for the provider rebuilds each one
/// schedules (a bare single flush loses updates when a second stream
/// event lands inside the same batch as the first).
Future<void> _settle() async {
  for (var i = 0; i < 3; i++) {
    await Future<void>.delayed(Duration.zero);
    await pumpEventQueue();
  }
}

/// A container with the registry and both backends' chat states driven by
/// stream controllers, with the rosters already landed. The slices
/// provider is held by a listener — a read alone does not keep a
/// Riverpod 3 stream provider subscribed.
Future<ProviderContainer> _slicesContainer(
  StreamController<BackendRegistryState> registryStates,
  StreamController<ChatUiState> laptopStates,
  StreamController<ChatUiState> buildBoxStates,
) async {
  final container = ProviderContainer(
    overrides: [
      backendRegistryStateProvider.overrideWith(
        (ref) => registryStates.stream,
      ),
      chatUiStateProvider('default').overrideWith(
        (ref) => laptopStates.stream,
      ),
      chatUiStateProvider('b1').overrideWith((ref) => buildBoxStates.stream),
    ],
  );
  container.listen(backendSessionSlicesProvider('default'), (_, _) {});
  registryStates.add(_registry);
  await _settle();
  laptopStates.add(_state(_laptopSessions));
  await _settle();
  buildBoxStates.add(_state(_buildBoxSessions));
  await _settle();
  return container;
}

void main() {
  test('timeline-only publishes keep the slice list identical', () async {
    final registryStates = StreamController<BackendRegistryState>.broadcast();
    final laptopStates = StreamController<ChatUiState>.broadcast();
    final buildBoxStates = StreamController<ChatUiState>.broadcast();
    final container = await _slicesContainer(
      registryStates,
      laptopStates,
      buildBoxStates,
    );
    addTearDown(() => buildBoxStates.close());
    addTearDown(() => laptopStates.close());
    addTearDown(() => registryStates.close());
    addTearDown(container.dispose);

    final settled = container.read(backendSessionSlicesProvider('default'));
    expect(settled, hasLength(2));
    expect(settled[0].active, isTrue);
    expect(settled[1].active, isFalse);
    expect(settled[1].sessions, _buildBoxSessions);

    // The build box's conversation streams: same roster, growing timeline.
    buildBoxStates.add(
      _state(_buildBoxSessions, timeline: <TimelineItem>[_streamingText('a')]),
    );
    await _settle();
    expect(
      identical(
        settled,
        container.read(backendSessionSlicesProvider('default')),
      ),
      isTrue,
      reason: 'a timeline-only publish must not recompute the slices',
    );

    buildBoxStates.add(
      _state(_buildBoxSessions, timeline: <TimelineItem>[_streamingText('ab')]),
    );
    await _settle();
    expect(
      identical(
        settled,
        container.read(backendSessionSlicesProvider('default')),
      ),
      isTrue,
    );

    // A real roster change (a session appears) recomputes the list.
    buildBoxStates.add(
      _state(<SessionSummary>[
        ..._buildBoxSessions,
        const SessionSummary(id: 'sB2', title: 'New on buildbox', blank: false),
      ]),
    );
    await _settle();
    final changed = container.read(backendSessionSlicesProvider('default'));
    expect(identical(settled, changed), isFalse);
    expect(changed[1].sessions, hasLength(2));

    // The active flag follows the provider's key, not the registry's.
    final forBuildBox = container.read(backendSessionSlicesProvider('b1'));
    expect(forBuildBox[0].active, isFalse);
    expect(forBuildBox[1].active, isTrue);
  });

  test('a registry change rebuilds the slice list', () async {
    final registryStates = StreamController<BackendRegistryState>.broadcast();
    final laptopStates = StreamController<ChatUiState>.broadcast();
    final buildBoxStates = StreamController<ChatUiState>.broadcast();
    final container = await _slicesContainer(
      registryStates,
      laptopStates,
      buildBoxStates,
    );
    addTearDown(() => buildBoxStates.close());
    addTearDown(() => laptopStates.close());
    addTearDown(() => registryStates.close());
    addTearDown(container.dispose);

    final before = container.read(backendSessionSlicesProvider('default'));
    expect(before, hasLength(2));

    // A backend is removed: the registry change recomputes the list.
    registryStates.add(
      BackendRegistryState(
        backends: <BackendConfig>[_laptop],
        activeId: 'default',
      ),
    );
    await _settle();
    final after = container.read(backendSessionSlicesProvider('default'));
    expect(identical(before, after), isFalse);
    expect(after, hasLength(1));
    expect(after.single.backend.id, 'default');
  });
}
