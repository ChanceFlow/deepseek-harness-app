/// Provider/model administration vocabulary for the dsh `llm` Remote
/// namespace: the live adapter routes (`llm/listProviders`), the
/// configurable-provider directory (`llm/listConfigurableProviders`), and
/// one endpoint interrogation (`llm/discoverModels`).
///
/// Domain-neutral: the two lists join into [LlmProviderRow] here because
/// the join is a pure projection, not a rendering decision.
library;

/// One provider route the harness currently serves (`llm/listProviders`).
///
/// Reference: `reference/deepseek-harness/packages/llm/llm/src/types.ts`
/// `LlmProviderInfo`.
final class LlmProvider {
  const LlmProvider({required this.id, required this.name});

  /// Provider route key used by a model selection.
  final String id;

  /// Human-readable provider name for selectors and diagnostics.
  final String name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LlmProvider && other.id == id && other.name == name);

  @override
  int get hashCode => Object.hash(id, name);
}

/// One provider route an adapter plugin can activate through configuration,
/// whether or not the route is currently registered
/// (`llm/listConfigurableProviders`).
///
/// Reference: `types.ts` `LlmConfigurableProvider`.
final class LlmConfigurableProvider {
  const LlmConfigurableProvider({
    required this.provider,
    required this.displayName,
    required this.settingsNs,
    required this.settingsPath,
    this.declared,
    this.error,
  });

  /// Provider route key this entry activates when configured.
  final String provider;

  /// Human-readable provider name for configuration surfaces.
  final String displayName;

  /// User-settings namespace whose section configures this provider.
  final String settingsNs;

  /// Path from that namespace's section root to this provider's profile
  /// object; empty when the whole section is the profile.
  final List<String> settingsPath;

  /// Whether the owning adapter knows this route only because configuration
  /// declared it. Absent means the adapter draws no such distinction.
  final bool? declared;

  /// Configuration diagnostic for repair; unaffected models may remain
  /// serviceable.
  final String? error;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LlmConfigurableProvider &&
          other.provider == provider &&
          other.displayName == displayName &&
          other.settingsNs == settingsNs &&
          _listEquals(other.settingsPath, settingsPath) &&
          other.declared == declared &&
          other.error == error);

  @override
  int get hashCode => Object.hash(
    provider,
    displayName,
    settingsNs,
    Object.hashAll(settingsPath),
    declared,
    error,
  );
}

/// One provider row a configuration surface renders: a declared directory
/// entry joined with its live/dormant state, followed by live routes the
/// directory does not declare.
final class LlmProviderRow {
  const LlmProviderRow({
    required this.provider,
    required this.displayName,
    required this.settingsNs,
    required this.settingsPath,
    required this.active,
    this.declared,
    this.error,
  });

  /// Provider route key.
  final String provider;

  /// Human-readable name (the directory's display name, or the live route's
  /// own name when nothing declares it).
  final String displayName;

  /// Settings namespace that configures this route; empty for a live route
  /// the configurable directory does not declare.
  final String settingsNs;

  /// Path to this route's profile inside [settingsNs]; empty for a live
  /// route the directory does not declare.
  final List<String> settingsPath;

  /// Whether the adapter registry currently serves this route.
  final bool active;

  /// Whether the owning adapter knows this route only because configuration
  /// declared it.
  final bool? declared;

  /// Configuration diagnostic the directory reported.
  final String? error;

  /// Whether this row can be configured at all (a declared directory entry
  /// carries a settings address; an undeclared live route does not).
  bool get configurable => settingsNs.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LlmProviderRow &&
          other.provider == provider &&
          other.displayName == displayName &&
          other.settingsNs == settingsNs &&
          _listEquals(other.settingsPath, settingsPath) &&
          other.active == active &&
          other.declared == declared &&
          other.error == error);

  @override
  int get hashCode => Object.hash(
    provider,
    displayName,
    settingsNs,
    Object.hashAll(settingsPath),
    active,
    declared,
    error,
  );
}

/// One interrogation of a provider endpoint the configuration has not
/// stored yet (`llm/discoverModels` request).
///
/// The wire request also carries an optional one-shot `apiKey`. This client
/// never populates it: discovery names a configured route and the host
/// resolves that route's stored credential, so a secret literal never
/// rides a request this app builds.
///
/// Reference: `types.ts` `LlmModelDiscoveryRequest`.
final class LlmModelDiscoveryRequest {
  const LlmModelDiscoveryRequest({this.provider, this.baseURL, this.api});

  /// Route the draft is editing; a route whose adapter already knows its
  /// models answers from that knowledge instead of asking the endpoint.
  final String? provider;

  /// Endpoint to interrogate, when the draft is not a known route.
  final String? baseURL;

  /// Wire protocol the endpoint speaks, when the draft names one.
  final String? api;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LlmModelDiscoveryRequest &&
          other.provider == provider &&
          other.baseURL == baseURL &&
          other.api == api);

  @override
  int get hashCode => Object.hash(provider, baseURL, api);
}

/// One model an endpoint reports about itself (`llm/discoverModels`).
///
/// Reference: `types.ts` `LlmDiscoveredModel`. Every field but the id is
/// optional because most provider listings disclose an id and nothing else.
final class LlmDiscoveredModel {
  const LlmDiscoveredModel({
    required this.id,
    this.name,
    this.contextWindow,
    this.maxTokens,
  });

  /// Model id the endpoint accepts.
  final String id;

  /// Human-readable name when the endpoint supplies one.
  final String? name;

  /// Maximum combined request and response context, when disclosed.
  final int? contextWindow;

  /// Maximum output tokens, when disclosed.
  final int? maxTokens;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LlmDiscoveredModel &&
          other.id == id &&
          other.name == name &&
          other.contextWindow == contextWindow &&
          other.maxTokens == maxTokens);

  @override
  int get hashCode => Object.hash(id, name, contextWindow, maxTokens);
}

/// Join the declared configurable-provider directory with the currently
/// registered routes.
///
/// Mirrors the reference Models page join
/// (`packages/client/ui-settings-models/src/client/store.ts`
/// `joinProviderDirectory`): declared rows first, in declaration order,
/// then live routes no declaration covers.
List<LlmProviderRow> joinProviderDirectory(
  List<LlmProvider> registered,
  List<LlmConfigurableProvider> directory,
) {
  final Set<String> active = registered.map((p) => p.id).toSet();
  final Set<String> declared = directory.map((e) => e.provider).toSet();
  final List<LlmProviderRow> rows = <LlmProviderRow>[
    for (final LlmConfigurableProvider entry in directory)
      LlmProviderRow(
        provider: entry.provider,
        displayName: entry.displayName,
        settingsNs: entry.settingsNs,
        settingsPath: entry.settingsPath,
        active: active.contains(entry.provider),
        declared: entry.declared,
        error: entry.error,
      ),
  ];
  for (final LlmProvider provider in registered) {
    if (declared.contains(provider.id)) continue;
    rows.add(
      LlmProviderRow(
        provider: provider.id,
        displayName: provider.name,
        settingsNs: '',
        settingsPath: const <String>[],
        active: true,
      ),
    );
  }
  return rows;
}

/// The credential reference this client derives for a provider route when
/// the resolved profile names none (reference `store.ts` `deriveKeyRef`).
String providerKeyRef(String provider) =>
    '${provider.toUpperCase().replaceAll(RegExp('[^A-Z0-9]+'), '_')}_API_KEY';

/// The declared directory families that can host a hand-added route: a
/// family whose entries address a profile by path (an empty path means the
/// whole section is one profile, which cannot hold a second route).
///
/// The returned namespace keys are in first-declaration order.
List<String> providerFamilies(List<LlmConfigurableProvider> directory) {
  final List<String> families = <String>[];
  for (final LlmConfigurableProvider entry in directory) {
    if (entry.settingsPath.isEmpty) continue;
    if (!families.contains(entry.settingsNs)) families.add(entry.settingsNs);
  }
  return families;
}

/// The settings path a hand-added route gets inside a declared family: the
/// family's own profile path with its final segment replaced by [route].
///
/// Returns null when [settingsNs] hosts no path-addressed entry.
List<String>? providerPathFor(
  List<LlmConfigurableProvider> directory,
  String settingsNs,
  String route,
) {
  for (final LlmConfigurableProvider entry in directory) {
    if (entry.settingsNs != settingsNs) continue;
    if (entry.settingsPath.isEmpty) continue;
    return <String>[
      ...entry.settingsPath.take(entry.settingsPath.length - 1),
      route,
    ];
  }
  return null;
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
