/// Host-unreachable banner tests: the chat surface names an unreachable
/// host, offers the manual reconnect, hides when the host is reachable, and
/// re-arms after a dismissed outage ends.
library;

import 'dart:async';
import 'dart:io';

import 'package:domain/model/connection_state.dart' as domain;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/backends/backend_store.dart';
import 'package:app/config.dart';
import 'package:app/di/providers.dart';
import 'package:app/ui/chat/chat_screen.dart';
import 'package:app/ui/chat/host_unreachable_banner.dart';

import '../../l10n_app.dart';

const _reconnecting = domain.ConnectionPhase.reconnecting;
const _connected = domain.ConnectionPhase.connected;

class _FakeRpc implements DshRpcClient {
  @override
  Future<RpcResult> call(
    String endpoint,
    String method,
    JsonMap payload, {
    Duration? timeout,
  }) async {
    return RpcResult(ok: true, value: <String, Object?>{});
  }

  @override
  Future<void> respond(String rpcId, RpcResult result) async {}
}

/// The `$events` registration answer the gateway sends over
/// `/api/remote.mux`
/// (`reference/deepseek-harness/packages/api/gateway/src/stream-protocol.ts`
/// `RemoteEventReadyFrame`); it is the connection generation handshake.
ServerRequest _readyFrame() => ServerRequest(
  rpcId: 'remote-events',
  method: 'item',
  payload: <String, Object?>{
    'type': 'ready',
    'clientId': 'client-1',
    'host': <String, Object?>{'home': '/home/tester'},
  },
);

class _CountingSocket implements DshEventSocket {
  final StreamController<ServerRequest> _frames =
      StreamController<ServerRequest>.broadcast();
  int connectCount = 0;

  @override
  Stream<ServerRequest> connect(String path, {void Function()? onOpen}) {
    connectCount += 1;
    onOpen?.call();
    // A broadcast controller drops events with no listener; the handshake
    // frame therefore lands after this call's listener attaches.
    scheduleMicrotask(() => _frames.add(_readyFrame()));
    return _frames.stream;
  }
}

BackendStore _testStore() {
  final dir = Directory.systemTemp.createTempSync('host_unreachable_test');
  addTearDown(() async {
    for (var i = 0; i < 50; i++) {
      try {
        dir.deleteSync(recursive: true);
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }
  });
  return BackendStore(
    File('${dir.path}/backends.json'),
    seedBaseUrl: kDshBaseUrl,
  );
}

Widget _banner({
  String host = 'Build box',
  domain.ConnectionPhase? phase = _reconnecting,
  VoidCallback? onReconnect,
}) {
  return l10nApp(
    home: Scaffold(
      body: HostUnreachableBanner(
        hostLabel: host,
        phase: phase,
        onReconnect: onReconnect,
      ),
    ),
  );
}

void main() {
  testWidgets('an unreachable host is named with a reconnect action', (
    tester,
  ) async {
    var reconnects = 0;
    await tester.pumpWidget(_banner(onReconnect: () => reconnects += 1));

    expect(find.text("Can't reach Build box"), findsOneWidget);
    await tester.tap(find.text('Reconnect'));
    await tester.pump();
    expect(reconnects, 1);
  });

  testWidgets('a reachable, connecting or unknown phase shows no banner', (
    tester,
  ) async {
    for (final domain.ConnectionPhase? phase in const <domain.ConnectionPhase?>[
      _connected,
      domain.ConnectionPhase.connecting,
      null,
    ]) {
      await tester.pumpWidget(_banner(phase: phase));
      await tester.pump();
      expect(find.textContaining("Can't reach"), findsNothing);
    }
  });

  testWidgets('dismiss hides the outage and a new loss re-arms it', (
    tester,
  ) async {
    await tester.pumpWidget(_banner());
    expect(find.text("Can't reach Build box"), findsOneWidget);

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    expect(find.text("Can't reach Build box"), findsNothing);

    // Still the same outage: stays hidden.
    await tester.pumpWidget(_banner());
    await tester.pump();
    expect(find.text("Can't reach Build box"), findsNothing);

    // A successful reconnect then a fresh loss is a new outage.
    await tester.pumpWidget(_banner(phase: _connected));
    await tester.pump();
    await tester.pumpWidget(_banner());
    await tester.pump();
    expect(find.text("Can't reach Build box"), findsOneWidget);
  });

  testWidgets('the chat route surfaces the active host and reconnects it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1280);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final socket = _CountingSocket();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendStoreProvider.overrideWith((ref) async => _testStore()),
          dshRpcClientProvider(Uri.parse(kDshBaseUrl))
              .overrideWithValue(_FakeRpc()),
          dshEventSocketProvider(Uri.parse(kDshBaseUrl))
              .overrideWithValue(socket),
          backendConnectionStateProvider('default').overrideWithValue(
            const AsyncData(domain.ConnectionState(phase: _reconnecting)),
          ),
        ],
        child: l10nApp(home: const ChatRoute()),
      ),
    );
    // The registry load and the roster pull need real dart:io turns.
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump();
      if (find.textContaining("Can't reach").evaluate().isNotEmpty) break;
    }
    expect(find.text("Can't reach 127.0.0.1:3080"), findsOneWidget);

    // The manual reconnect tears the DI member down and rebuilds it, which
    // dials a fresh generation immediately instead of waiting out the
    // manager's backoff.
    final before = socket.connectCount;
    await tester.tap(find.text('Reconnect'));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();
    expect(socket.connectCount, greaterThan(before));
  });
}
