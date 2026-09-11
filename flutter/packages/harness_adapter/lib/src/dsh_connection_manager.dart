/// Connection generation manager: owns the required mux downlink and the
/// `$events` readiness handshake, publishing CONNECTED once the gateway's
/// `ready` frame and the mux open hold.
library;

import 'dart:async';
import 'dart:convert';

import 'package:domain/model/connection_state.dart';
import 'package:network/dsh_event_socket.dart';
import 'package:network/rpc_envelope.dart';

import 'adapter_diagnostics.dart';
import 'rpc_map.dart';
import 'state_stream.dart';
import 'wire_json.dart';

const String _remoteMuxPath = '/api/remote.mux';

/// The logical stream id this client opens for the Gateway's forwarded Remote
/// Events (`$events`). Its registration answer is the generation handshake.
const String _remoteEventsStreamId = 'remote-events';

const Duration _streamOpenTimeout = Duration(milliseconds: 3000);

/// Deadline for the generation's `$events` registration answer. The gateway
/// answers the `$events` open with a `ready` frame carrying the host facts;
/// a host that accepts the socket but never registers the stream must fail
/// the generation instead of stalling the reconnect loop's readiness gate
/// forever. The generation already recovers through its own backoff.
const Duration _readyFrameTimeout = Duration(seconds: 30);

/// Retry-time policy seam. The product uses randomized exponential backoff;
/// tests inject a deterministic schedule so generation transitions are
/// exact-time assertions.
typedef DshBackoffDelay = int Function(int attempt);

/// Randomized exponential backoff: base 500 ms doubling to a 10 s cap,
/// jittered in the upper half like the Kotlin implementation.
int exponentialDshBackoffDelay(
  int attempt, {
  int baseMillis = 500,
  int maxMillis = 10000,
  int Function(int max)? random,
}) {
  final cap = _exponentialCap(
    attempt > 20 ? 20 : attempt,
    baseMillis,
    maxMillis,
  );
  final half = cap ~/ 2;
  final next = (random ?? _defaultRandom)(half + 1);
  return half + next;
}

int _defaultRandom(int maxExclusive) {
  // Deterministic-enough jitter for production; tests inject their own.
  final tick = DateTime.now().microsecondsSinceEpoch;
  return tick % maxExclusive;
}

int _exponentialCap(int times, int baseMillis, int maxMillis) {
  var value = baseMillis < 1 ? 1 : baseMillis;
  if (value > maxMillis) value = maxMillis;
  for (var i = 0; i < times; i++) {
    value = value > maxMillis ~/ 2
        ? maxMillis
        : (value * 2 > maxMillis ? maxMillis : value * 2);
  }
  return value;
}

class DshConnectionManager {
  DshConnectionManager(
    this._eventSocket,
    this._backoffDelay, {
    this.onDiagnostic,
  });

  final DshEventSocket _eventSocket;
  final DshBackoffDelay _backoffDelay;
  final AdapterDiagnosticListener? onDiagnostic;

  final StateStream<ConnectionState> _state = StateStream<ConnectionState>(
    const ConnectionState(),
  );
  final StateStream<HostDescription?> _hostDescription =
      StateStream<HostDescription?>(null);
  final StreamController<ServerRequest> _muxFrames =
      StreamController<ServerRequest>.broadcast();

  int _generation = 0;
  bool _started = false;
  bool _stopped = false;
  final List<StreamSubscription<void>> _activeSubs =
      <StreamSubscription<void>>[];

  /// Current connection state; `.value` for synchronous reads (tests) and
  /// `.stream` for collectors, mirroring Kotlin's StateFlow surface.
  StateStream<ConnectionState> get state => _state;
  StateStream<HostDescription?> get hostDescription => _hostDescription;
  Stream<ServerRequest> get muxFrames => _muxFrames.stream;

  /// Sends a raw JSON message to the mux WebSocket if connected.
  void sendMuxMessage(String message) {
    final socket = _eventSocket;
    if (socket is DshWritableEventSocket) {
      try {
        socket.send(_remoteMuxPath, message);
      } catch (e, st) {
        onDiagnostic?.call(
          AdapterDiagnostic(
            level: AdapterDiagnosticLevel.warning,
            context: 'connection_manager:sendMuxMessage',
            message: 'Failed to send mux message: $e',
            error: e,
            stackTrace: st,
          ),
        );
      }
    }
  }

  void start() {
    if (_started) return;
    _started = true;
    // Deferred like the Kotlin coroutine launch: the first state transition
    // happens on the next event-loop turn, not synchronously in start().
    scheduleMicrotask(() {
      if (_stopped) return;
      if (_state.value.phase != ConnectionPhase.disconnected) return;
      _state.value = ConnectionState(
        phase: ConnectionPhase.connecting,
        hostDescription: _state.value.hostDescription,
        generation: _state.value.generation,
      );
      unawaited(_connectLoop());
    });
  }

  /// Stops the retry loop and closes every current generation/stream.
  void stop() {
    _stopped = true;
    for (final sub in _activeSubs) {
      unawaited(sub.cancel());
    }
    _activeSubs.clear();
    unawaited(_muxFrames.close());
    unawaited(_state.close());
    unawaited(_hostDescription.close());
  }

  /// The loop owns generations: each generation dials the required mux
  /// downlink and requires the mux WebSocket onOpen plus the gateway's
  /// `$events` `ready` frame before publishing CONNECTED. Any loss on the
  /// required stream counts as generation loss.
  Future<void> _connectLoop() async {
    var attempt = 0;
    while (!_stopped) {
      final connected = await _runGeneration();
      if (_stopped) break;
      _hostDescription.value = null;
      _state.value = ConnectionState(
        phase: ConnectionPhase.reconnecting,
        hostDescription: null,
        generation: _state.value.generation,
      );
      // A generation that reached CONNECTED was healthy until stream loss;
      // its loss starts a fresh backoff sequence.
      if (connected) attempt = 0;
      final delay = _backoffDelay(attempt);
      onDiagnostic?.call(
        AdapterDiagnostic(
          level: AdapterDiagnosticLevel.warning,
          context: 'connection_manager',
          message:
              'Generation lost, reconnecting (attempt: $attempt, delay: ${delay}ms)',
        ),
      );
      await Future<void>.delayed(Duration(milliseconds: delay));
      attempt += 1;
    }
  }

  Future<bool> _runGeneration() async {
    var connected = false;
    final generationId = ++_generation;

    final muxOpened = Completer<void>();
    final readyFrame = Completer<HostDescription>();
    final failure = Completer<Object?>();
    final generationSubs = <StreamSubscription<ServerRequest>>[];

    _pump(
      _remoteMuxPath,
      muxOpened,
      readyFrame,
      failure,
      _muxFrames,
      generationSubs,
    );
    if (_stopped) return false;

    try {
      await muxOpened.future.timeout(_streamOpenTimeout);
      final description = await _awaitReady(
        readyFrame.future,
        failure.future,
      ).timeout(_readyFrameTimeout);

      _hostDescription.value = description;
      _state.value = ConnectionState(
        phase: ConnectionPhase.connected,
        hostDescription: description,
        generation: generationId,
      );
      connected = true;

      if (!failure.isCompleted) await failure.future;
    } catch (e, st) {
      onDiagnostic?.call(
        AdapterDiagnostic(
          level: AdapterDiagnosticLevel.warning,
          context: 'connection_manager',
          message: 'Generation handshake failed: $e',
          error: e,
          stackTrace: st,
        ),
      );
      if (_stopped) return connected;
      // Generation failed before readiness; the retry loop owns it.
    } finally {
      // Cancels this generation's downlinks (Kotlin: generationJob.cancel()
      // in the finally block). Idempotent with the failure-driven cancel.
      for (final sub in generationSubs) {
        unawaited(sub.cancel());
      }
      _activeSubs.removeWhere(generationSubs.contains);
    }
    return connected;
  }

  /// Readiness, or the required stream's loss, whichever settles first: a mux
  /// downlink that closes before the `$events` registration is a failed
  /// generation, not a 30-second stall.
  Future<HostDescription> _awaitReady(
    Future<HostDescription> ready,
    Future<Object?> failure,
  ) {
    return Future.any(<Future<HostDescription>>[
      ready,
      failure.then<HostDescription>((Object? error) {
        throw error ?? StateError('mux downlink closed before readiness');
      }),
    ]);
  }

  /// Subscribes the required mux downlink in the background. On open it
  /// registers the logical streams; any error or clean close completes
  /// [failure], which the generation handshake awaits.
  void _pump(
    String path,
    Completer<void> opened,
    Completer<HostDescription> ready,
    Completer<Object?> failure,
    StreamController<ServerRequest> sink,
    List<StreamSubscription<ServerRequest>> generationSubs,
  ) {
    final stream = _eventSocket.connect(
      path,
      onOpen: () {
        final socket = _eventSocket;
        if (path == _remoteMuxPath && socket is DshWritableEventSocket) {
          socket.send(
            path,
            jsonEncode(<String, Object?>{
              'type': 'open',
              'streamId': 'workspace-follow',
              'endpoint': 'workspace/follow',
              'payload': <String, Object?>{'args': <String, Object?>{}},
            }),
          );
          socket.send(
            path,
            jsonEncode(<String, Object?>{
              'type': 'open',
              'streamId': 'session-control',
              'endpoint': 'session/control',
              'payload': <String, Object?>{'args': <String, Object?>{}},
            }),
          );
          // Forwarded Remote Events (`$events`): the 0.1.2 delivery path for
          // an interactive decision. The host pushes an Agent-scoped
          // waterfall and the client answers with one `$events/result`
          // call; a 0.1.2 host never sends the 0.1.1 `question/requested` /
          // `approval/requested` mux frames, so a question nobody opens this
          // stream for has no card at all.
          socket.send(
            path,
            jsonEncode(<String, Object?>{
              'type': 'open',
              'streamId': _remoteEventsStreamId,
              'endpoint': r'$events',
              'payload': <String, Object?>{'args': <String, Object?>{}},
            }),
          );
        }
        if (!opened.isCompleted) opened.complete();
      },
    );
    final sub = stream.listen(
      (frame) {
        _observeReadyFrame(frame, ready);
        sink.add(frame);
      },
      onError: (Object error, [StackTrace? st]) {
        onDiagnostic?.call(
          AdapterDiagnostic(
            level: AdapterDiagnosticLevel.warning,
            context: 'connection_manager:stream:$path',
            message: 'Downlink stream error on $path: $error',
            error: error,
            stackTrace: st,
          ),
        );
        if (!failure.isCompleted) failure.complete(error);
      },
      onDone: () {
        onDiagnostic?.call(
          AdapterDiagnostic(
            level: AdapterDiagnosticLevel.debug,
            context: 'connection_manager:stream:$path',
            message: 'Downlink stream closed on $path',
          ),
        );
        if (!failure.isCompleted) failure.complete(null);
      },
      cancelOnError: true,
    );
    generationSubs.add(sub);
    _activeSubs.add(sub);
  }

  /// Completes [ready] from the `$events` registration answer.
  ///
  /// The gateway answers the `$events` open with an item whose value is
  /// `{type: 'ready', clientId, host: {home}}`
  /// (`reference/deepseek-harness/packages/api/gateway/src/stream-protocol.ts`
  /// `RemoteEventReadyFrame`), and this is the pinned contract's only
  /// generation-readiness handshake: `host/describe` is not registered at
  /// 0.1.5. A frame that announces itself ready without its required
  /// `host.home` fails the generation loudly instead of substituting a
  /// default.
  void _observeReadyFrame(
    ServerRequest frame,
    Completer<HostDescription> ready,
  ) {
    if (ready.isCompleted) return;
    if (frame.rpcId != _remoteEventsStreamId) return;
    if (wireString(frame.payload, 'type') != 'ready') return;
    final JsonMap? host = asJsonObject(frame.payload['host']);
    if (host == null) {
      ready.completeError(
        const FormatException(
          'remote-events ready frame is missing required "host"',
        ),
      );
      return;
    }
    try {
      ready.complete(HostDescription(home: wireRequiredString(host, 'home')));
    } catch (error, stackTrace) {
      // The required-field decoder throws with the field name; a stream
      // listener must not let that escape into the zone, so it fails the
      // generation through the readiness completer instead.
      ready.completeError(error, stackTrace);
    }
  }
}
