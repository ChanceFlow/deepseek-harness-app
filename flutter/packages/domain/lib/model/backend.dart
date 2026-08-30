/// Backend vocabulary — one configured dsh host this client talks to.
///
/// Backend configs live on the device (they decide WHICH host to talk to,
/// so no host can own them); `baseUri` is the host's web base URL
/// (`http://host:port`), with RPC and event paths derived exactly as the
/// single-backend build did.
library;

final class BackendConfig {
  const BackendConfig({
    required this.id,
    required this.label,
    required this.baseUri,
    this.enabled = true,
  });

  /// Stable identity (device-local; the seed backend keeps `default`).
  final String id;

  /// Human label shown in switchers and group headers.
  final String label;

  /// Base URL (`http://host:port`).
  final Uri baseUri;

  /// Whether the client keeps a live connection to this host. A disabled
  /// backend stays configured (Settings still lists and edits it) but
  /// owns no connection, controller, sidebar slice, or switcher entry;
  /// the active backend is always enabled.
  final bool enabled;

  BackendConfig copyWith({String? label, Uri? baseUri, bool? enabled}) =>
      BackendConfig(
        id: id,
        label: label ?? this.label,
        baseUri: baseUri ?? this.baseUri,
        enabled: enabled ?? this.enabled,
      );

  @override
  bool operator ==(Object other) =>
      other is BackendConfig &&
      other.id == id &&
      other.label == label &&
      other.baseUri == baseUri &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(id, label, baseUri, enabled);
}

/// The registry's published state: the configured backends, which one the
/// chat surface currently presents, and the last mutation's failure
/// (guarded mutations fail loud — the message rides the state so every
/// registry surface can render it).
final class BackendRegistryState {
  const BackendRegistryState({
    this.backends = const <BackendConfig>[],
    this.activeId,
    this.errorMessage,
  });

  final List<BackendConfig> backends;
  final String? activeId;

  /// Why the last registry mutation was refused or failed to persist;
  /// null after any successful mutation.
  final String? errorMessage;

  /// The active backend's config; null before the store loads, when all
  /// backends are disabled, or when the id dangles (the controller's load
  /// falls back to the first enabled entry).
  BackendConfig? get active =>
      backends.where((backend) => backend.id == activeId).firstOrNull;

  /// The connected slice of [backends]: every surface that talks to hosts
  /// (keep-alive, sidebar slices, switchers, notification centers) reads
  /// this list; Settings' host-management sheet reads [backends] whole so
  /// a disabled backend stays reachable for re-enabling.
  List<BackendConfig> get enabledBackends =>
      backends.where((backend) => backend.enabled).toList(growable: false);

  /// A successful mutation clears the error: the state it leaves behind
  /// describes the current list, not the refusal before it.
  BackendRegistryState withBackends(List<BackendConfig> backends) =>
      BackendRegistryState(backends: backends, activeId: activeId);

  BackendRegistryState withActiveId(String? activeId) =>
      BackendRegistryState(backends: backends, activeId: activeId);

  BackendRegistryState withError(String? errorMessage) => BackendRegistryState(
    backends: backends,
    activeId: activeId,
    errorMessage: errorMessage,
  );
}
