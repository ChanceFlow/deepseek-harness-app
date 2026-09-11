/// Connection lifecycle vocabulary published by the adapter.
library;

enum ConnectionPhase { disconnected, connecting, connected, reconnecting }

/// Host-level facts one connection generation publishes.
///
/// The facts come from the `$events` stream's opening `ready` frame
/// (`reference/deepseek-harness/packages/api/gateway/src/stream-protocol.ts`
/// `RemoteEventReadyFrame` -> `RemoteEventHostInfo`). The 0.1.1
/// `host/describe` payload has no 0.1.5 source: `cwd`, `provider`, and
/// `model` are per-session facts (`session/list` rows,
/// `session/modelCatalog`), and `attachedSessions` / `canOpenPath` are
/// published nowhere. Those members are deleted rather than defaulted — a
/// fact without a source is absent from this type.
final class HostDescription {
  const HostDescription({required this.home, this.version});

  /// Host account home directory from the generation's `ready` frame; the
  /// host publishes it to abbreviate displayed filesystem paths.
  final String home;

  /// Host product version. No pinned route publishes one, so this is null on
  /// every generation — never a fabricated default. The field remains only
  /// while `flutter/app/lib/ui/settings/settings_screen.dart` reads it.
  final String? version;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HostDescription &&
          other.home == home &&
          other.version == version);

  @override
  int get hashCode => Object.hash(home, version);
}

final class ConnectionState {
  const ConnectionState({
    this.phase = ConnectionPhase.disconnected,
    this.hostDescription,
    this.generation = 0,
  });

  final ConnectionPhase phase;
  final HostDescription? hostDescription;
  final int generation;

  bool get isConnected => phase == ConnectionPhase.connected;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ConnectionState &&
          other.phase == phase &&
          other.hostDescription == hostDescription &&
          other.generation == generation);

  @override
  int get hashCode => Object.hash(phase, hostDescription, generation);
}
