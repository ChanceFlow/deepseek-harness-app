import 'dart:io';

import 'package:domain/model/connection_state.dart';
import 'package:network/http_dsh_rpc_client.dart';
import 'package:network/web_socket_dsh_event_socket.dart';
import 'package:test/test.dart';

import 'package:harness_adapter/src/dsh_connection_manager.dart';
import 'package:harness_adapter/src/harness_repository_impl.dart';

/// Opt-in read-only smoke test against a real `dsh web` host.
///
/// Set `DSH_E2E_URL` (for example `http://127.0.0.1:3080`) when running
/// local harness tests. The test never creates sessions or sends prompts.
void main() {
  final endpoint = Platform.environment['DSH_E2E_URL'];
  final enabled = endpoint != null && endpoint.trim().isNotEmpty;

  test('realHostReadOnlySmoke', () async {
    if (!enabled) {
      // JUnit Assume mirror: mark skipped when the env var is absent.
      markTestSkipped('DSH_E2E_URL is not set; skipping real-host smoke');
      return;
    }
    final base = Uri.parse(endpoint);

    final rpc = HttpDshRpcClient(base);
    final socket = WebSocketDshEventSocket(base);
    final manager = DshConnectionManager(
      rpc,
      socket,
      exponentialDshBackoffDelay,
    );
    try {
      manager.start();
      final connected = await manager.state.stream
          .firstWhere((state) => state.phase == ConnectionPhase.connected)
          .timeout(const Duration(seconds: 15));
      expect(connected.hostDescription?.version.trim().isNotEmpty, isTrue);

      final repository = HarnessRepositoryImpl(rpc, manager);
      await repository.refreshSessions();
      await repository.refreshWorkspaces();

      final directory = await repository.listDirectory(null);
      expect(directory.home.trim().isNotEmpty, isTrue);
      // Loopback callers may read the settings plane; the snapshot only
      // needs to decode, whatever namespaces this host declares.
      final settings = await repository.describeSettings();
      expect(settings.namespaces.every((ns) => ns.ns.trim().isNotEmpty), isTrue);
      final credentials =
          await repository.describeCredentials(settings.credentialRefs);
      expect(credentials.every((status) => status.ref.trim().isNotEmpty), isTrue);
      final sessions = await repository.observeSessions().first;
      final workspaces = await repository.observeWorkspaces().first;
      final firstSession = sessions.isEmpty ? null : sessions.first;
      if (firstSession != null) {
        await repository.openSession(firstSession.id);
        await repository.observeTimelineWindow(firstSession.id).first;
      }
      expect(workspaces.isEmpty ? true : workspaces.first.path.trim().isNotEmpty,
          isTrue);
    } finally {
      manager.stop();
    }
  }, timeout: const Timeout(Duration(seconds: 60)));
}
