import 'dart:io';

import 'package:domain/model/connection_state.dart';
import 'package:network/http_dsh_rpc_client.dart';
import 'package:network/web_socket_dsh_event_socket.dart';
import 'package:test/test.dart';

import 'package:harness_adapter/src/dsh_connection_manager.dart';
import 'package:harness_adapter/src/harness_repository_impl.dart';

/// Opt-in read-only smoke test against a real `dsh web` host.
///
/// Pass the target as a dart define (for example
/// `--dart-define=DSH_E2E_URL=http://127.0.0.1:3080`) when running local
/// harness tests. The test never creates sessions or sends prompts.
///
/// The define is the form that works everywhere: `flutter test` forwards only
/// a fixed set of environment variables to the test process, so a bare
/// `DSH_E2E_URL=… flutter test` reaches nothing. A plain process environment
/// is still read as a fallback, which is what `dart test` supplies.
///
/// A host answers every `/api` request only for a caller holding its
/// authority-bound browser cookie, so `DSH_E2E_COOKIE` carries the
/// `name=value` pair when the target is such a host:
///
/// ```sh
/// curl -c jar "http://127.0.0.1:3080/?token=$(...)"   # URL dsh web prints
/// flutter test --dart-define=DSH_E2E_URL=http://127.0.0.1:3080 \
///   --dart-define=DSH_E2E_COOKIE="$(awk '!/^#/ && NF {print $6"="$7}' jar)" \
///   packages/harness_adapter/test/local_dsh_e2e_test.dart
/// ```
///
/// An `https` target works when its certificate verifies under the platform
/// trust store. A self-signed one is out of scope here: the app's per-host
/// trust toggle is the shipped path for those, and this smoke keeps the
/// platform default rather than teaching the test double a second policy.
const String _kEndpointDefine = String.fromEnvironment('DSH_E2E_URL');
const String _kCookieDefine = String.fromEnvironment('DSH_E2E_COOKIE');

void main() {
  final endpoint = _kEndpointDefine.trim().isNotEmpty
      ? _kEndpointDefine
      : Platform.environment['DSH_E2E_URL'];
  final enabled = endpoint != null && endpoint.trim().isNotEmpty;
  final cookie = _kCookieDefine.trim().isNotEmpty
      ? _kCookieDefine
      : Platform.environment['DSH_E2E_COOKIE'];
  final headers = cookie == null || cookie.isEmpty
      ? const <String, String>{}
      : <String, String>{'Cookie': cookie};

  test('realHostReadOnlySmoke', () async {
    if (!enabled) {
      // JUnit Assume mirror: mark skipped when the env var is absent.
      markTestSkipped('DSH_E2E_URL is not set; skipping real-host smoke');
      return;
    }
    final base = Uri.parse(endpoint);

    final rpc = HttpDshRpcClient(base, headers: headers);
    final socket = WebSocketDshEventSocket(base, headers: headers);
    final manager = DshConnectionManager(socket, exponentialDshBackoffDelay);
    try {
      manager.start();
      final connected = await manager.state.stream
          .firstWhere((state) => state.phase == ConnectionPhase.connected)
          .timeout(const Duration(seconds: 15));
      // The `$events` ready frame's host facts are the handshake's payload;
      // no pinned route publishes a host version.
      expect(connected.hostDescription?.home.trim().isNotEmpty, isTrue);

      final repository = HarnessRepositoryImpl(rpc, manager);
      await repository.refreshSessions();
      await repository.refreshWorkspaces();

      final directory = await repository.listDirectory(null);
      expect(directory.home.trim().isNotEmpty, isTrue);
      // Loopback callers may read the settings plane; the snapshot only
      // needs to decode, whatever namespaces this host declares.
      final settings = await repository.describeSettings();
      expect(
        settings.namespaces.every((ns) => ns.ns.trim().isNotEmpty),
        isTrue,
      );
      final credentials = await repository.describeCredentials(
        settings.credentialRefs,
      );
      expect(
        credentials.every((status) => status.ref.trim().isNotEmpty),
        isTrue,
      );
      final sessions = await repository.observeSessions().first;
      final workspaces = await repository.observeWorkspaces().first;
      // The sidebar's rule (`session_panel.dart`): a blank placeholder and a
      // subagent child are never a root transcript — `openSession` refuses the
      // latter, and the subagent catalog is its route.
      final roots = sessions
          .where((session) => !session.blank && session.origin != 'subagent')
          .toList();
      final root = roots.isEmpty ? null : roots.first;
      if (root != null) {
        await repository.openSession(root.id);
        final window = await repository.observeTimelineWindow(root.id).first;
        expect(
          window.items,
          isNotEmpty,
          reason: 'Chat timeline items must load for a non-blank root session',
        );
        final skills = await repository.listSkills(root.id);
        expect(skills.every((skill) => skill.name.trim().isNotEmpty), isTrue);
        // The preview surface: a workspace listing names a real file, and
        // `stat` plus a paged `read` agree on it. These three calls carry the
        // `workspaceFileScopeId` scope argument, so a renamed wire field fails
        // here instead of only in the UI.
        final listing = await repository.listWorkspaceDirectory(root.id, '.');
        expect(listing.path, isEmpty, reason: '`.` lists the workspace root');
        final file = listing.entries
            .where((entry) => entry.type == 'file')
            .firstOrNull;
        if (file != null) {
          final stat = await repository.statWorkspaceFile(root.id, file.name);
          expect(stat.absolutePath.trim().isNotEmpty, isTrue);
          expect(stat.version.trim().isNotEmpty, isTrue);
          final content = await repository.readWorkspaceFile(
            root.id,
            file.name,
            limit: 5,
          );
          expect(content.absolutePath, stat.absolutePath);
          expect(content.offset, 1);
          expect(content.lines, greaterThanOrEqualTo(1));
          if ((stat.bytes ?? 0) > 0) {
            expect(content.text, isNotEmpty);
          }
        }
      }
      // The roster read: 0.1.7 deleted `subagents/list`, so a parent's child
      // tree comes from the `subagentCatalog` projection through
      // `session/projections`. One readable parent proves the route, and a
      // wire mismatch fails every one of them. A roster can also name a parent
      // this host no longer resolves — an id recorded in an older, unprefixed
      // form, or a Session whose log was removed — and that is the host's own
      // `gateway/internal`, not contract drift, so the smoke requires a
      // success rather than all-successes.
      final parents = sessions
          .where((session) => session.parentSessionId != null)
          .map((session) => session.parentSessionId!)
          .toSet();
      var readableCatalogs = 0;
      Object? firstCatalogFailure;
      for (final parentId in parents) {
        try {
          final catalog = await repository.loadSubagents(parentId);
          expect(catalog.parentSessionId, parentId);
          readableCatalogs++;
        } catch (error) {
          firstCatalogFailure ??= error;
        }
      }
      if (parents.isNotEmpty) {
        expect(
          readableCatalogs,
          greaterThan(0),
          reason:
              'no parent catalog read; the first failure was '
              '$firstCatalogFailure',
        );
      }
      final presets = await repository.listAgentPresets();
      expect(presets.entries.isNotEmpty, isTrue);
      expect(workspaces.isNotEmpty, isTrue);
    } finally {
      manager.stop();
    }
  }, timeout: const Timeout(Duration(seconds: 60)));
}
