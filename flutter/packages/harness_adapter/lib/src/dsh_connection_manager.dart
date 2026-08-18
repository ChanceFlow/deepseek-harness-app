/// Connection generation manager: owns both downlink streams plus the
/// `host.describe` handshake, publishing CONNECTED only when all three
/// readiness facts hold.
library;

import 'dart:async';

import 'package:domain/model/connection_state.dart';
import 'package:network/dsh_exceptions.dart';
import 'package:network/dsh_rpc_client.dart';
import 'package:network/dsh_event_socket.dart';
import 'package:network/rpc_envelope.dart';

import 'state_stream.dart';
import 'wire_json.dart';

const String _eventsMuxPath = '/api/events.mux';
const String _eventsHostPath = '/api/events.host';
const String _hostDescribe = 'host.describe';
const Duration _streamOpenTimeout = Duration(milliseconds: 3000);

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
    value = value > maxMillis ~/ 2 ? maxMillis : (value * 2 > maxMillis ? maxMillis : value * 2);
  }
  return value;
}

class DshConnectionManager {
  DshConnectionManager(
    this._rpcClient,
    this._eventSocket,
    this._backoffDelay,
  );

  final DshRpcClient _rpcClient;
  final DshEventSocket _eventSocket;
  final DshBackoffDelay _backoffDelay;

  final StateStream<ConnectionState> _state =
      StateStream<ConnectionState>(const ConnectionState());
  final StateStream<HostDescription?> _hostDescription =
      StateStream<HostDescription?>(null);
  final StreamController<ServerRequest> _muxFrames =
      StreamController<ServerRequest>.broadcast();
  final StreamController<ServerRequest> _hostFrames =
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
  Stream<ServerRequest> get hostFrames => _hostFrames.stream;

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
    unawaited(_hostFrames.close());
    unawaited(_state.close());
    unawaited(_hostDescription.close());
  }

  /// The loop owns generations: each generation opens both downlinks and
  /// requires a successful `host.describe` plus both WebSocket onOpen
  /// events before publishing CONNECTED. Any stream loss counts as
  /// generation loss.
  Future<void> _connectLoop() async {
    var attempt = 0;
    while (!_stopped) {
      final connected = await _runGeneration();
      if (_stopped) break;
      _hostDescription.value = null;
      _state.value = ConnectionState(
        phase: ConnectionPhase.reconnecting,
        hostDescription: _state.value.hostDescription,
        generation: _state.value.generation,
      );
      // A generation that reached CONNECTED was healthy until stream loss;
      // its loss starts a fresh backoff sequence.
      if (connected) attempt = 0;
      await Future<void>.delayed(Duration(milliseconds: _backoffDelay(attempt)));
      attempt += 1;
    }
  }

  Future<bool> _runGeneration() async {
    var connected = false;
    final generationId = ++_generation;

    final muxOpened = Completer<void>();
    final hostOpened = Completer<void>();
    final failure = Completer<Object?>();
    final generationSubs = <StreamSubscription<ServerRequest>>[];

    _pump(
      _eventsMuxPath,
      muxOpened,
      failure,
      _muxFrames,
      generationSubs,
    );
    if (_stopped) return false;
    _pump(
      _eventsHostPath,
      hostOpened,
      failure,
      _hostFrames,
      generationSubs,
    );

    try {
      final result =
          await _rpcClient.call(_hostDescribe, _hostDescribe, <String, Object?>{});
      if (!result.ok) {
        throw DshBusinessException(
          code: result.error?.code ?? 'internal',
          message: result.error?.message ?? 'host.describe failed',
        );
      }
      final value = result.value;
      if (value == null) {
        throw DshBusinessException(
            code: 'bad-response', message: 'host.describe missing value');
      }
      final description = HostDescription(
        version: wireString(value, 'version') ?? '',
        cwd: wireString(value, 'cwd') ?? '',
        provider: wireString(value, 'provider'),
        model: wireString(value, 'model'),
        attachedSessions: wireLong(value, 'attachedSessions'),
        canOpenPath: wireBool(value, 'canOpenPath'),
      );

      await Future.wait(<Future<void>>[
        muxOpened.future.timeout(_streamOpenTimeout),
        hostOpened.future.timeout(_streamOpenTimeout),
      ]);

      _hostDescription.value = description;
      _state.value = ConnectionState(
        phase: ConnectionPhase.connected,
        hostDescription: description,
        generation: generationId,
      );
      connected = true;

      if (!failure.isCompleted) await failure.future;
    } catch (_) {
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

  /// Subscribes one downlink stream in the background; any error or clean
  /// close completes [failure], which the generation handshake awaits.
  void _pump(
    String path,
    Completer<void> opened,
    Completer<Object?> failure,
    StreamController<ServerRequest> sink,
    List<StreamSubscription<ServerRequest>> generationSubs,
  ) {
    final stream = _eventSocket.connect(path, onOpen: () {
      if (!opened.isCompleted) opened.complete();
    });
    final sub = stream.listen(
      sink.add,
      onError: (Object error) {
        if (!failure.isCompleted) failure.complete(error);
      },
      onDone: () {
        if (!failure.isCompleted) failure.complete(null);
      },
      cancelOnError: true,
    );
    generationSubs.add(sub);
    _activeSubs.add(sub);
  }
}
