/// Connection lifecycle vocabulary published by the adapter.
library;

enum ConnectionPhase { disconnected, connecting, connected, reconnecting }

final class HostDescription {
  const HostDescription({
    required this.version,
    required this.cwd,
    this.provider,
    this.model,
    this.attachedSessions = 0,
    this.canOpenPath = false,
  });

  final String version;
  final String cwd;
  final String? provider;
  final String? model;
  final int attachedSessions;
  final bool canOpenPath;

  @override
  bool operator ==(Object other) =>
      other is HostDescription &&
      other.version == version &&
      other.cwd == cwd &&
      other.provider == provider &&
      other.model == model &&
      other.attachedSessions == attachedSessions &&
      other.canOpenPath == canOpenPath;

  @override
  int get hashCode =>
      Object.hash(version, cwd, provider, model, attachedSessions, canOpenPath);
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
      other is ConnectionState &&
      other.phase == phase &&
      other.hostDescription == hostDescription &&
      other.generation == generation;

  @override
  int get hashCode => Object.hash(phase, hostDescription, generation);
}
