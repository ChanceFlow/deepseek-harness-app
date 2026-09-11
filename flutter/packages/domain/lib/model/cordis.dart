/// Dynamic Cordis plugin approval vocabulary.
///
/// A `cordis_run` tool call whose plugin ships a browser half blocks the
/// model host-side on a `cordis/request-run` round trip; a forwarded
/// `cordis/request-run` event is that request reaching the client and
/// [CordisRunResolution] is the answer that settles it
/// (`dynamicCordisRunner/resolveRequestRun`). Wire truth:
/// `reference/deepseek-harness/packages/extensions/cordis-host-runner/src/
/// types.ts`.
library;

/// How a Client activation request entered the host
/// (`DynamicCordisRunMode`).
enum CordisRunMode { run, update }

/// How a settled request left the pending state
/// (`RequestRunOutcome`).
enum CordisRequestOutcome { approved, completed, rejected, cancelled, failed }

/// Why an approved activation failed (`DynamicCordisRunResolution`'s
/// `reason`).
enum CordisRunFailureReason { rejected, hostHalfFailed, clientHalfFailed }

/// One pending model-driven Client activation forwarded to browser pages
/// (`DynamicCordisRunRequest`).
final class CordisRunRequest {
  const CordisRunRequest({
    required this.requestId,
    required this.sessionId,
    required this.pluginId,
    required this.packageId,
    required this.mode,
    required this.name,
    required this.purpose,
    required this.requiresApproval,
  });

  /// Correlation identity the answer echoes back.
  final String requestId;

  /// Session whose plugin and tool call own the request.
  final String sessionId;

  /// Stable plugin instance being acted on.
  final String pluginId;

  /// Package version the request will activate.
  final String packageId;

  final CordisRunMode mode;

  /// Package label.
  final String name;

  /// User-facing reason supplied at define time.
  final String purpose;

  /// Whether a page must wait for an explicit user decision before
  /// activation. When false the host has already started its own half and
  /// only needs a page to attach to the Client half.
  final bool requiresApproval;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CordisRunRequest &&
          other.requestId == requestId &&
          other.sessionId == sessionId &&
          other.pluginId == pluginId &&
          other.packageId == packageId &&
          other.mode == mode &&
          other.name == name &&
          other.purpose == purpose &&
          other.requiresApproval == requiresApproval);

  @override
  int get hashCode => Object.hash(
    requestId,
    sessionId,
    pluginId,
    packageId,
    mode,
    name,
    purpose,
    requiresApproval,
  );
}

/// One settled model-driven activation request broadcast to all pages
/// (`DynamicCordisRequestResolved`).
final class CordisRequestResolved {
  const CordisRequestResolved({required this.requestId, required this.outcome});

  final String requestId;
  final CordisRequestOutcome outcome;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CordisRequestResolved &&
          other.requestId == requestId &&
          other.outcome == outcome);

  @override
  int get hashCode => Object.hash(requestId, outcome);
}

/// The browser verdict the host accepts for one request
/// (`DynamicCordisRunResolution`).
///
/// An approval names the exact activation ([pluginRunId]) the answering
/// page created or attached to; the host rejects a resolution whose run id
/// does not match the active half. A native client has no runtime for a
/// Cordis browser half, so [CordisRunRejected] is the decision it can
/// honestly deliver — and it is the one that releases the blocked
/// `cordis_run` tool call.
sealed class CordisRunResolution {
  const CordisRunResolution();
}

/// Approve the request and report the exact Client activation.
final class CordisRunApproved extends CordisRunResolution {
  const CordisRunApproved({
    required this.pluginRunId,
    this.waitingFor = const <String>[],
  });

  /// Identity of the activation the answering page created or attached to.
  final String pluginRunId;

  /// Services the successfully created Client fiber still waits on.
  final List<String> waitingFor;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CordisRunApproved &&
          other.pluginRunId == pluginRunId &&
          _listEquals(other.waitingFor, waitingFor));

  @override
  int get hashCode => Object.hash(pluginRunId, Object.hashAll(waitingFor));
}

/// Refuse the request without executing either half.
final class CordisRunRejected extends CordisRunResolution {
  const CordisRunRejected();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is CordisRunRejected;

  @override
  int get hashCode => 0;
}

/// Report an activation that failed after approval.
final class CordisRunFailed extends CordisRunResolution {
  const CordisRunFailed({
    required this.reason,
    this.pluginRunId,
    this.startedHere = false,
    this.message,
    this.stack,
  });

  final CordisRunFailureReason reason;

  /// Activation that failed; null for a refusal before activation.
  final String? pluginRunId;

  /// Whether this page created the failed activation instead of
  /// attaching to it.
  final bool startedHere;

  final String? message;
  final String? stack;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CordisRunFailed &&
          other.reason == reason &&
          other.pluginRunId == pluginRunId &&
          other.startedHere == startedHere &&
          other.message == message &&
          other.stack == stack);

  @override
  int get hashCode =>
      Object.hash(reason, pluginRunId, startedHere, message, stack);
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
