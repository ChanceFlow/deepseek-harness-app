/// Assembly wiring — the ONLY app file allowed to import the harness
/// adapter (import-gate exemption, mirroring the legacy `app/di`).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:domain/repository/chat_repository.dart';
import 'package:harness_adapter/harness_adapter.dart';
import 'package:network/dsh_event_socket.dart';
import 'package:network/dsh_rpc_client.dart';
import 'package:network/http_dsh_rpc_client.dart';
import 'package:network/web_socket_dsh_event_socket.dart';

import '../config.dart';
import '../ui/chat/chat_controller.dart';
import '../ui/chat/chat_ui_state.dart';

/// Raw transport seams, overridable in tests.
final dshRpcClientProvider = Provider<DshRpcClient>(
  (ref) => HttpDshRpcClient(Uri.parse(kDshBaseUrl)),
  name: 'dshRpcClient',
);

final dshEventSocketProvider = Provider<DshEventSocket>(
  (ref) => WebSocketDshEventSocket(Uri.parse(kDshBaseUrl)),
  name: 'dshEventSocket',
);

final dshConnectionManagerProvider = Provider<DshConnectionManager>((ref) {
  final manager = DshConnectionManager(
    ref.watch(dshRpcClientProvider),
    ref.watch(dshEventSocketProvider),
    exponentialDshBackoffDelay,
  );
  ref.onDispose(manager.stop);
  return manager;
});

/// The domain-facing repository the whole UI consumes.
final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return HarnessRepositoryImpl(
    ref.watch(dshRpcClientProvider),
    ref.watch(dshConnectionManagerProvider),
  );
});

/// Chat screen controller (UDF).
final chatControllerProvider = Provider<ChatController>((ref) {
  final controller = ChatController(ref.watch(chatRepositoryProvider));
  ref.onDispose(controller.dispose);
  return controller;
});

/// Chat UI state stream for widgets.
final chatUiStateProvider = StreamProvider<ChatUiState>(
  (ref) => ref.watch(chatControllerProvider).uiState,
);
