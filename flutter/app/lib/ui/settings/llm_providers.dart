/// Provider and model administration surface for Settings.
///
/// One self-contained section: it lists the host's provider directory
/// (live/dormant), adds and removes a provider profile through
/// `settings/mutate`, stores or clears an API key through the host
/// credential plane (`credentials/set` / `credentials/unset`), and asks a
/// configured provider for the models it advertises (`llm/discoverModels`).
///
/// The service key field is obscured and its value never enters this
/// controller's published state, the error log, or telemetry: it travels
/// from the text field straight into one repository call.
library;

import 'dart:async';
import 'dart:convert';

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/llm_provider.dart';
import 'package:domain/model/settings.dart';
import 'package:domain/repository/chat_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import '../state_stream.dart';
import '../theme/theme.dart';
import 'settings_backend_scope.dart';
import 'settings_chrome.dart';

/// The route-id grammar a hand-added provider must satisfy (the reference
/// Models page's `ROUTE_PATTERN`, lower-case kebab-case). A leading letter
/// also keeps the derived credential reference inside the host's
/// `[A-Za-z_][A-Za-z0-9_]*` grammar.
final RegExp kProviderRoutePattern = RegExp(r'^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$');

/// One provider row enriched with the settings and credential facts the
/// surface renders. Structure mirrors the reference Models page store
/// (`packages/client/ui-settings-models/src/client/store.ts` `ProviderRow`),
/// narrowed to the layers this client reads.
final class LlmProviderRowState {
  const LlmProviderRowState({
    required this.row,
    required this.configured,
    required this.removable,
    this.apiKeyEnv,
    this.profileBaseURL,
    this.profileApi,
    this.credential,
    this.derivedCredential,
  });

  /// The joined directory entry and its live/dormant state.
  final LlmProviderRow row;

  /// Whether any layer configures this provider (its profile resolves).
  final bool configured;

  /// Whether the user layer alone carries the profile, so removing the
  /// profile is a real action rather than a no-op.
  final bool removable;

  /// The credential reference the resolved profile names, when one does.
  final String? apiKeyEnv;

  /// The resolved profile's `baseURL`, when it declares one. Discovery of a
  /// hand-declared route needs it; a catalog route answers from the adapter
  /// registry instead.
  final String? profileBaseURL;

  /// The resolved profile's `api`, when it declares one.
  final String? profileApi;

  /// Credential state for [apiKeyEnv], once described.
  final CredentialStatus? credential;

  /// Credential state for the derived `<ROUTE>_API_KEY`, described only
  /// while the profile names no reference.
  final CredentialStatus? derivedCredential;

  /// The credential reference the key field addresses.
  String get keyRef => apiKeyEnv ?? providerKeyRef(row.provider);

  /// The key state the profile addresses, if the host described it.
  CredentialStatus? get keyStatus =>
      apiKeyEnv != null ? credential : derivedCredential;

  /// Whether a key is stored for [keyRef].
  bool get keyConfigured => keyStatus?.configured ?? false;

  /// Whether this connection may change [keyRef]; an undescribed reference is
  /// treated as writable so a failed enrichment never blocks the write the
  /// host itself would accept.
  bool get keyWritable => keyStatus?.writable ?? true;

  /// Whether the endpoint can be interrogated: a declared directory entry
  /// carries the settings namespace discovery is keyed by.
  bool get discoverable => row.configurable;
}

/// Page snapshot for the providers section.
final class LlmProvidersUiState {
  const LlmProvidersUiState({
    this.isLoading = false,
    this.busyProviders = const <String>{},
    this.discoveringProvider,
    this.errorMessage,
    this.credentialError,
    this.discoveryErrors = const <String, String>{},
    this.writable = false,
    this.rows = const <LlmProviderRowState>[],
    this.families = const <String>[],
    this.discovered = const <String, List<LlmDiscoveredModel>>{},
  });

  /// A whole-load read is in flight.
  final bool isLoading;

  /// Routes whose profile or key write is in flight.
  final Set<String> busyProviders;

  /// The route whose model discovery is in flight.
  final String? discoveringProvider;

  /// Whole-load failure text; row-level write failures stay in the sheet.
  final String? errorMessage;

  /// Credential enrichment failure; provider rows remain usable.
  final String? credentialError;

  /// Last model-discovery failure per provider route, shown inside that
  /// provider's sheet.
  final Map<String, String> discoveryErrors;

  /// Whether the settings provider accepts writes.
  final bool writable;

  /// Every configurable provider joined with its configured/credential state.
  final List<LlmProviderRowState> rows;

  /// Declared settings namespaces that can host a hand-added route.
  final List<String> families;

  /// Discovered models by provider route, newest result per route.
  final Map<String, List<LlmDiscoveredModel>> discovered;

  /// The row for [provider], or null once it left the directory.
  LlmProviderRowState? rowFor(String provider) {
    for (final LlmProviderRowState candidate in rows) {
      if (candidate.row.provider == provider) return candidate;
    }
    return null;
  }
}

sealed class LlmProvidersAction {
  const LlmProvidersAction();
}

final class RefreshLlmProviders extends LlmProvidersAction {
  const RefreshLlmProviders();
}

final class DismissLlmProvidersError extends LlmProvidersAction {
  const DismissLlmProvidersError();
}

/// Store or replace one provider's API key, recording the profile's
/// `apiKeyEnv` when it names none.
final class SaveLlmProviderKey extends LlmProvidersAction {
  const SaveLlmProviderKey({required this.provider, required this.value});

  final String provider;
  final String value;
}

/// Remove one provider's stored credential; the profile is left in place.
final class ClearLlmProviderKey extends LlmProvidersAction {
  const ClearLlmProviderKey(this.provider);

  final String provider;
}

/// Create a provider profile in one declared settings family.
final class AddLlmProvider extends LlmProvidersAction {
  const AddLlmProvider({
    required this.provider,
    required this.settingsNs,
    this.displayName,
    this.baseURL,
    this.api,
    this.modelIds = const <String>[],
    this.apiKey,
  });

  final String provider;
  final String settingsNs;
  final String? displayName;
  final String? baseURL;
  final String? api;
  final List<String> modelIds;

  /// The typed key stored after the profile lands; null stores none, leaving
  /// the route on its provider-native auth path.
  final String? apiKey;
}

/// Remove one provider's stored profile from the user settings layer.
final class RemoveLlmProvider extends LlmProvidersAction {
  const RemoveLlmProvider(this.provider);

  final String provider;
}

/// Ask a configured provider's endpoint which models it advertises.
final class DiscoverLlmProviderModels extends LlmProvidersAction {
  const DiscoverLlmProviderModels(this.provider);

  final String provider;
}

/// Provider-directory controller (UDF), one per backend.
class LlmProvidersController {
  LlmProvidersController(this._repository) {
    _refresh();
  }

  final ChatRepository _repository;
  final AppStateStream<LlmProvidersUiState> _state =
      AppStateStream<LlmProvidersUiState>(const LlmProvidersUiState());

  List<LlmProviderRowState> _rows = const <LlmProviderRowState>[];
  List<String> _families = const <String>[];
  Map<String, List<LlmDiscoveredModel>> _discovered =
      const <String, List<LlmDiscoveredModel>>{};

  /// Raw directory entries, kept for the family/path derivation an add needs.
  List<LlmConfigurableProvider> _directory = const <LlmConfigurableProvider>[];

  /// Settings revisions per namespace, for the CAS guard on writes.
  Map<String, int> _revisions = const <String, int>{};
  final Set<String> _busy = <String>{};
  String? _discovering;
  bool _isLoading = false;
  bool _writable = false;
  String? _errorMessage;
  String? _credentialError;
  Map<String, String> _discoveryErrors = const <String, String>{};

  LlmProvidersUiState get state => _state.value;
  Stream<LlmProvidersUiState> get uiState => _state.stream;

  void dispose() {}

  void onAction(LlmProvidersAction action) {
    switch (action) {
      case RefreshLlmProviders():
        _refresh();
      case DismissLlmProvidersError():
        _errorMessage = null;
        _discoveryErrors = const <String, String>{};
        _publish();
      case SaveLlmProviderKey():
        _saveKey(action.provider, action.value);
      case ClearLlmProviderKey():
        _clearKey(action.provider);
      case AddLlmProvider():
        _add(action);
      case RemoveLlmProvider():
        _remove(action.provider);
      case DiscoverLlmProviderModels():
        _discover(action.provider);
    }
  }

  void _publish() {
    _state.value = LlmProvidersUiState(
      isLoading: _isLoading,
      busyProviders: Set<String>.unmodifiable(_busy),
      discoveringProvider: _discovering,
      errorMessage: _errorMessage,
      credentialError: _credentialError,
      discoveryErrors: _discoveryErrors,
      writable: _writable,
      rows: _rows,
      families: _families,
      discovered: _discovered,
    );
  }

  void _refresh() {
    unawaited(_refreshNow());
  }

  /// Reload the whole snapshot: the provider directory and settings
  /// describe, then one batched credential describe over every referenced
  /// key. A failed directory or settings read keeps the last good rows and
  /// surfaces an error; credential enrichment degrades to no badge.
  Future<void> _refreshNow() async {
    _isLoading = true;
    _publish();
    try {
      final SettingsSnapshot settings = await _repository.describeSettings();
      final List<LlmProvider> providers = await _repository.listLlmProviders();
      final List<LlmConfigurableProvider> directory = await _repository
          .listConfigurableProviders();
      final Map<String, SettingsNamespace> namespaces =
          <String, SettingsNamespace>{
            for (final SettingsNamespace namespace in settings.namespaces)
              namespace.ns: namespace,
          };
      _directory = directory;
      _families = providerFamilies(directory);
      _revisions = <String, int>{
        for (final SettingsNamespace namespace in settings.namespaces)
          namespace.ns: namespace.revision,
      };
      _writable = settings.writable;
      final List<LlmProviderRowState> rows = joinProviderDirectory(
        providers,
        directory,
      ).map((LlmProviderRow row) => _enrich(row, namespaces)).toList();
      _rows = rows;
      _errorMessage = null;
      _credentialError = null;
      _publish();
      await _loadCredentials(rows);
    } catch (error, stackTrace) {
      _errorMessage = error.toString();
      _publish();
      ErrorLogCollector.instance.captureError(
        error,
        stackTrace: stackTrace,
        context: const <String, Object?>{
          'controller': 'LlmProvidersController',
          'action': 'refresh',
        },
      );
    } finally {
      _isLoading = false;
      _publish();
    }
  }

  Future<void> _loadCredentials(List<LlmProviderRowState> rows) async {
    final List<String> refs = <String>{
      for (final LlmProviderRowState row in rows) row.keyRef,
    }.toList();
    if (refs.isEmpty) {
      _credentialError = null;
      _rows = rows;
      return;
    }
    try {
      final List<CredentialStatus> statuses = await _repository
          .describeCredentials(refs);
      final Map<String, CredentialStatus> byRef = <String, CredentialStatus>{
        for (final CredentialStatus status in statuses) status.ref: status,
      };
      _rows = rows
          .map(
            (LlmProviderRowState row) => _withCredential(
              row,
              byRef[row.apiKeyEnv],
              byRef[providerKeyRef(row.row.provider)],
            ),
          )
          .toList();
      _credentialError = null;
    } catch (error, stackTrace) {
      // Credential state is an enrichment: a failure degrades the badge
      // instead of blanking the directory.
      _credentialError = error.toString();
      ErrorLogCollector.instance.captureError(
        error,
        stackTrace: stackTrace,
        context: const <String, Object?>{
          'controller': 'LlmProvidersController',
          'action': 'describeCredentials',
        },
      );
    }
  }

  LlmProviderRowState _enrich(
    LlmProviderRow row,
    Map<String, SettingsNamespace> namespaces,
  ) {
    final SettingsNamespace? namespace = namespaces[row.settingsNs];
    if (namespace == null) {
      return LlmProviderRowState(row: row, configured: false, removable: false);
    }
    final Object? profile = row.settingsPath.isEmpty
        ? namespace.value
        : _jsonAtPath(namespace.value, row.settingsPath);
    final bool configured = row.settingsPath.isEmpty || profile != null;
    final bool removable =
        row.settingsPath.isNotEmpty &&
        _jsonAtPath(namespace.user, row.settingsPath) != null;
    return LlmProviderRowState(
      row: row,
      configured: configured,
      removable: removable,
      apiKeyEnv: _stringMember(profile, 'apiKeyEnv'),
      profileBaseURL: _stringMember(profile, 'baseURL'),
      profileApi: _stringMember(profile, 'api'),
    );
  }

  LlmProviderRowState _withCredential(
    LlmProviderRowState row,
    CredentialStatus? named,
    CredentialStatus? derived,
  ) => LlmProviderRowState(
    row: row.row,
    configured: row.configured,
    removable: row.removable,
    apiKeyEnv: row.apiKeyEnv,
    profileBaseURL: row.profileBaseURL,
    profileApi: row.profileApi,
    credential: named,
    derivedCredential: row.apiKeyEnv == null ? derived : null,
  );

  /// Store one key, then record the profile's `apiKeyEnv` when it names
  /// none — the same two-step order the reference provider editor uses
  /// (`ProviderEditor.tsx` `applyOnce`).
  void _saveKey(String provider, String value) {
    if (value.trim().isEmpty) return;
    unawaited(() async {
      _busy.add(provider);
      _publish();
      try {
        final LlmProviderRowState? row = state.rowFor(provider);
        if (row == null) return;
        final String secret = value.trim();
        final String ref = row.keyRef;
        await _repository.setCredential(ref, secret);
        if (row.apiKeyEnv == null && row.row.configurable) {
          await _repository.mutateSetting(row.row.settingsNs, <SettingPathOp>[
            SettingPathOp(
              op: 'set',
              path: <String>[...row.row.settingsPath, 'apiKeyEnv'],
              jsonValue: jsonEncode(ref),
            ),
          ], expectedRevision: _revisions[row.row.settingsNs]);
        }
        await _refreshNow();
      } catch (error, stackTrace) {
        _recordWriteFailure('saveKey', error, stackTrace);
      } finally {
        _busy.remove(provider);
        _publish();
      }
    }());
  }

  void _clearKey(String provider) {
    unawaited(() async {
      _busy.add(provider);
      _publish();
      try {
        final LlmProviderRowState? row = state.rowFor(provider);
        if (row == null) return;
        await _repository.unsetCredential(row.keyRef);
        await _refreshNow();
      } catch (error, stackTrace) {
        _recordWriteFailure('clearKey', error, stackTrace);
      } finally {
        _busy.remove(provider);
        _publish();
      }
    }());
  }

  /// Create a provider profile and, when one was typed, store its key.
  ///
  /// The profile write lands first: a key stored for a route whose profile
  /// never materialized would be a credential nothing resolves.
  void _add(AddLlmProvider action) {
    final String route = action.provider.trim();
    if (route.isEmpty) return;
    final List<String>? path = providerPathFor(
      _directory,
      action.settingsNs,
      route,
    );
    if (path == null) {
      _errorMessage = 'no configurable provider family declares $route';
      _publish();
      return;
    }
    unawaited(() async {
      _busy.add(route);
      _publish();
      try {
        final String ref = providerKeyRef(route);
        final Map<String, Object?> profile = <String, Object?>{
          if (_nonEmpty(action.displayName) case final String name)
            'displayName': name,
          if (_nonEmpty(action.baseURL) case final String baseURL)
            'baseURL': baseURL,
          if (_nonEmpty(action.api) case final String api) 'api': api,
          if (action.modelIds.isNotEmpty)
            'models': <Object?>[
              for (final String id in action.modelIds)
                <String, Object?>{'id': id},
            ],
          if (_nonEmpty(action.apiKey) != null) 'apiKeyEnv': ref,
        };
        await _repository.mutateSetting(action.settingsNs, <SettingPathOp>[
          SettingPathOp(op: 'set', path: path, jsonValue: jsonEncode(profile)),
        ], expectedRevision: _revisions[action.settingsNs]);
        if (_nonEmpty(action.apiKey) case final String key) {
          await _repository.setCredential(ref, key);
        }
        await _refreshNow();
      } catch (error, stackTrace) {
        _recordWriteFailure('addProvider', error, stackTrace);
      } finally {
        _busy.remove(route);
        _publish();
      }
    }());
  }

  void _remove(String provider) {
    unawaited(() async {
      _busy.add(provider);
      _publish();
      try {
        final LlmProviderRowState? row = state.rowFor(provider);
        if (row == null || !row.removable) return;
        await _repository.mutateSetting(row.row.settingsNs, <SettingPathOp>[
          SettingPathOp(op: 'unset', path: row.row.settingsPath),
        ], expectedRevision: _revisions[row.row.settingsNs]);
        await _refreshNow();
      } catch (error, stackTrace) {
        _recordWriteFailure('removeProvider', error, stackTrace);
      } finally {
        _busy.remove(provider);
        _publish();
      }
    }());
  }

  /// Ask one configured provider's endpoint which models it advertises.
  ///
  /// The draft names the route and, for a hand-declared route, the profile's
  /// own endpoint and protocol: the host resolves the stored credential, so
  /// no secret literal rides this request.
  void _discover(String provider) {
    unawaited(() async {
      final LlmProviderRowState? row = state.rowFor(provider);
      if (row == null || !row.discoverable) return;
      _discovering = provider;
      _discoveryErrors = <String, String>{
        for (final MapEntry<String, String> entry in _discoveryErrors.entries)
          if (entry.key != provider) entry.key: entry.value,
      };
      _publish();
      try {
        final List<LlmDiscoveredModel> models = await _repository
            .discoverModels(
              row.row.settingsNs,
              LlmModelDiscoveryRequest(
                provider: row.row.provider,
                baseURL: row.profileBaseURL,
                api: row.profileApi,
              ),
            );
        _discovered = <String, List<LlmDiscoveredModel>>{
          ..._discovered,
          provider: models,
        };
      } catch (error, stackTrace) {
        _discoveryErrors = <String, String>{
          ..._discoveryErrors,
          provider: error.toString(),
        };
        ErrorLogCollector.instance.captureError(
          error,
          stackTrace: stackTrace,
          context: const <String, Object?>{
            'controller': 'LlmProvidersController',
            'action': 'discoverModels',
          },
        );
      } finally {
        _discovering = null;
        _publish();
      }
    }());
  }

  void _recordWriteFailure(String action, Object error, StackTrace stackTrace) {
    _errorMessage = error.toString();
    ErrorLogCollector.instance.captureError(
      error,
      stackTrace: stackTrace,
      context: <String, Object?>{
        'controller': 'LlmProvidersController',
        'action': action,
      },
    );
  }
}

/// The Settings mount point: provider directory, key plane, and discovery.
///
/// Self-contained: it watches its own controller for the scoped backend, so
/// a host mounts it as one child of the Settings list.
class SettingsLlmProvidersSection extends ConsumerWidget {
  const SettingsLlmProvidersSection({this.showTitle = true, super.key});

  /// False on the Providers page, whose app bar already names it.
  final bool showTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String backendId = ref.watch(settingsBackendScopeProvider);
    if (backendId.isEmpty) return const SizedBox.shrink();
    final LlmProvidersController controller = ref.watch(
      llmProvidersControllerProvider(backendId),
    );
    return StreamBuilder<LlmProvidersUiState>(
      stream: controller.uiState,
      initialData: controller.state,
      builder:
          (BuildContext context, AsyncSnapshot<LlmProvidersUiState> snapshot) {
            final LlmProvidersUiState state = snapshot.data ?? controller.state;
            return _ProvidersCard(
              state: state,
              controller: controller,
              showTitle: showTitle,
            );
          },
    );
  }
}

class _ProvidersCard extends StatelessWidget {
  const _ProvidersCard({
    required this.state,
    required this.controller,
    required this.showTitle,
  });

  final LlmProvidersUiState state;
  final LlmProvidersController controller;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SettingsSectionHeading(
          title: l10n.settingsSectionProviders,
          intro: l10n.providersIntro,
          showTitle: showTitle,
        ),
        SettingsSectionCard(
          children: <Widget>[
            if (!state.writable && !state.isLoading)
              _CardNotice(l10n.providersReadOnlyNotice),
            if (state.errorMessage case final String error) ...<Widget>[
              _CardNotice(l10n.providersLoadFailed(error), color: scheme.error),
              const SettingsCardDivider(),
            ],
            if (state.isLoading && state.rows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                ),
              ),
            if (!state.isLoading && state.rows.isEmpty)
              _CardNotice(l10n.providersEmpty),
            for (int i = 0; i < state.rows.length; i++) ...<Widget>[
              if (i > 0) const SettingsCardDivider(),
              _ProviderTile(
                row: state.rows[i],
                onTap: () => _openProviderSheet(
                  context,
                  controller,
                  state.rows[i].row.provider,
                ),
              ),
            ],
            if (state.credentialError case final String error) ...<Widget>[
              const SettingsCardDivider(),
              _CardNotice(l10n.providerCredentialUnavailable(error)),
            ],
            const SettingsCardDivider(),
            ListTile(
              leading: Icon(Icons.add, color: scheme.primary),
              title: Text(l10n.addProvider),
              enabled: state.writable && state.families.isNotEmpty,
              onTap: state.writable && state.families.isNotEmpty
                  ? () => _openAddProviderSheet(context, controller)
                  : null,
            ),
            const SettingsCardDivider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Text(
                l10n.providerFooter,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ProviderTile extends StatelessWidget {
  const _ProviderTile({required this.row, required this.onTap});

  final LlmProviderRowState row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final List<String> meta = <String>[
      l10n.providerRouteLine(row.row.provider),
      row.row.active ? l10n.providerStateLive : l10n.providerStateDormant,
      if (row.row.declared ?? false) l10n.providerDeclared,
      if (row.row.configurable)
        row.keyConfigured ? l10n.apiKeyConfigured : l10n.apiKeyMissing,
    ];
    return ListTile(
      title: Text(row.row.displayName),
      subtitle: Text(
        row.row.error == null
            ? meta.join(' · ')
            : l10n.providerNeedsRepair(row.row.error!),
        style: theme.textTheme.bodySmall?.copyWith(
          color: row.row.error == null ? scheme.onSurfaceVariant : scheme.error,
        ),
      ),
      trailing: Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
      onTap: onTap,
    );
  }
}

Future<void> _openProviderSheet(
  BuildContext context,
  LlmProvidersController controller,
  String provider,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) =>
        _ProviderSheet(controller: controller, provider: provider),
  );
}

Future<void> _openAddProviderSheet(
  BuildContext context,
  LlmProvidersController controller,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) =>
        _AddProviderSheet(controller: controller),
  );
}

class _ProviderSheet extends StatefulWidget {
  const _ProviderSheet({required this.controller, required this.provider});

  final LlmProvidersController controller;
  final String provider;

  @override
  State<_ProviderSheet> createState() => _ProviderSheetState();
}

class _ProviderSheetState extends State<_ProviderSheet> {
  final TextEditingController _key = TextEditingController();

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<LlmProvidersUiState>(
      stream: widget.controller.uiState,
      initialData: widget.controller.state,
      builder:
          (BuildContext context, AsyncSnapshot<LlmProvidersUiState> snapshot) {
            final LlmProvidersUiState state =
                snapshot.data ?? widget.controller.state;
            final LlmProviderRowState? row = state.rowFor(widget.provider);
            if (row == null) {
              return const SizedBox(height: 0);
            }
            return _ProviderSheetBody(
              state: state,
              row: row,
              keyController: _key,
              onAction: widget.controller.onAction,
            );
          },
    );
  }
}

class _ProviderSheetBody extends StatelessWidget {
  const _ProviderSheetBody({
    required this.state,
    required this.row,
    required this.keyController,
    required this.onAction,
  });

  final LlmProvidersUiState state;
  final LlmProviderRowState row;
  final TextEditingController keyController;
  final void Function(LlmProvidersAction) onAction;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool busy = state.busyProviders.contains(row.row.provider);
    final bool writable = state.writable && row.keyWritable;
    final List<LlmDiscoveredModel>? discovered =
        state.discovered[row.row.provider];
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      row.row.displayName,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  _StateBadge(
                    label: row.row.active
                        ? l10n.providerStateLive
                        : l10n.providerStateDormant,
                    active: row.row.active,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${l10n.providerRouteLine(row.row.provider)} · '
                '${l10n.providerKeyRefLine(row.keyRef)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              _FieldLabel(l10n.secretValueLabel),
              const SizedBox(height: 6),
              TextField(
                controller: keyController,
                obscureText: true,
                enabled: writable,
                autocorrect: false,
                enableSuggestions: false,
                decoration: _fieldDecoration(
                  context,
                  hint: l10n.secretValueHint,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                row.keyConfigured ? l10n.apiKeyConfigured : l10n.apiKeyMissing,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: row.keyConfigured ? scheme.success : scheme.error,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.providerKeyHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  if (row.keyConfigured && writable)
                    TextButton(
                      onPressed: busy
                          ? null
                          : () =>
                                onAction(ClearLlmProviderKey(row.row.provider)),
                      style: TextButton.styleFrom(
                        foregroundColor: scheme.error,
                      ),
                      child: Text(l10n.unset),
                    ),
                  const Spacer(),
                  if (busy)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  FilledButton(
                    onPressed: writable && !busy
                        ? () {
                            onAction(
                              SaveLlmProviderKey(
                                provider: row.row.provider,
                                value: keyController.text,
                              ),
                            );
                            keyController.clear();
                          }
                        : null,
                    child: Text(l10n.save),
                  ),
                ],
              ),
              if (!writable) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  state.writable
                      ? l10n.credentialReadOnlyHint
                      : l10n.providersReadOnlyNotice,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (row.discoverable) ...<Widget>[
                const Divider(height: 24),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        l10n.discoveredModelsTitle,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    OutlinedButton(
                      onPressed: state.discoveringProvider == null && !busy
                          ? () => onAction(
                              DiscoverLlmProviderModels(row.row.provider),
                            )
                          : null,
                      child: state.discoveringProvider == row.row.provider
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(l10n.discoverModels),
                    ),
                  ],
                ),
                if (state.discoveryErrors[row.row.provider]
                    case final String error) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    l10n.discoverModelsFailed(error),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                    ),
                  ),
                ],
                if (discovered != null) ...<Widget>[
                  const SizedBox(height: 4),
                  if (discovered.isEmpty)
                    Text(
                      l10n.discoverModelsEmpty,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    )
                  else
                    for (final LlmDiscoveredModel model in discovered)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(model.name ?? model.id),
                        subtitle: _modelLimits(context, model),
                      ),
                ],
              ],
              if (row.row.configurable) ...<Widget>[
                const Divider(height: 24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: row.removable && state.writable && !busy
                        ? () => _confirmRemove(context, row)
                        : null,
                    style: TextButton.styleFrom(foregroundColor: scheme.error),
                    child: Text(l10n.providerRemoveAction),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.close),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _modelLimits(BuildContext context, LlmDiscoveredModel model) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final List<String> parts = <String>[
      if (model.contextWindow case final int window)
        l10n.modelContextWindowLine(window),
      if (model.maxTokens case final int max) l10n.modelMaxTokensLine(max),
    ];
    if (parts.isEmpty) return null;
    return Text(parts.join(' · '));
  }

  Future<void> _confirmRemove(
    BuildContext context,
    LlmProviderRowState row,
  ) async {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(l10n.providerRemoveConfirm(row.row.displayName)),
        content: Text(l10n.providerRemoveBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: scheme.error),
            child: Text(l10n.remove),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      onAction(RemoveLlmProvider(row.row.provider));
    }
  }
}

class _AddProviderSheet extends StatefulWidget {
  const _AddProviderSheet({required this.controller});

  final LlmProvidersController controller;

  @override
  State<_AddProviderSheet> createState() => _AddProviderSheetState();
}

class _AddProviderSheetState extends State<_AddProviderSheet> {
  final TextEditingController _route = TextEditingController();
  final TextEditingController _displayName = TextEditingController();
  final TextEditingController _baseURL = TextEditingController();
  final TextEditingController _api = TextEditingController();
  final TextEditingController _models = TextEditingController();
  final TextEditingController _key = TextEditingController();

  /// The chosen declared settings family; null uses the first one, which is
  /// the only one every deployment with a path-addressed directory carries.
  String? _family;

  @override
  void dispose() {
    _route.dispose();
    _displayName.dispose();
    _baseURL.dispose();
    _api.dispose();
    _models.dispose();
    _key.dispose();
    super.dispose();
  }

  String? _selectedFamily(LlmProvidersUiState state) {
    if (state.families.isEmpty) return null;
    final String? chosen = _family;
    if (chosen != null && state.families.contains(chosen)) return chosen;
    return state.families.first;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return StreamBuilder<LlmProvidersUiState>(
      stream: widget.controller.uiState,
      initialData: widget.controller.state,
      builder:
          (BuildContext context, AsyncSnapshot<LlmProvidersUiState> snapshot) {
            final LlmProvidersUiState state =
                snapshot.data ?? widget.controller.state;
            final String? family = _selectedFamily(state);
            final String targetFamily = family ?? '';
            return SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: SingleChildScrollView(
                  child: ListenableBuilder(
                    listenable: Listenable.merge(<Listenable>[
                      _route,
                      _baseURL,
                    ]),
                    builder: (BuildContext context, Widget? _) {
                      final String route = _route.text.trim();
                      final String baseURL = _baseURL.text.trim();
                      final bool taken = state.rows.any(
                        (LlmProviderRowState row) =>
                            row.row.provider == route && route.isNotEmpty,
                      );
                      final bool routeInvalid =
                          route.isNotEmpty &&
                          !kProviderRoutePattern.hasMatch(route);
                      final bool baseURLInvalid =
                          baseURL.isNotEmpty && !_isHttpUrl(baseURL);
                      final bool ready =
                          route.isNotEmpty &&
                          !routeInvalid &&
                          !taken &&
                          !baseURLInvalid &&
                          state.writable &&
                          targetFamily.isNotEmpty;
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            l10n.addProvider,
                            style: theme.textTheme.titleMedium,
                          ),
                          if (state.families.length > 1) ...<Widget>[
                            const SizedBox(height: 12),
                            _FieldLabel(l10n.addProviderFamilyLabel),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<String>(
                              initialValue: family,
                              decoration: _fieldDecoration(context),
                              items: <DropdownMenuItem<String>>[
                                for (final String ns in state.families)
                                  DropdownMenuItem<String>(
                                    value: ns,
                                    child: Text(ns),
                                  ),
                              ],
                              onChanged: (String? next) =>
                                  setState(() => _family = next),
                            ),
                          ],
                          const SizedBox(height: 12),
                          _FieldLabel(l10n.addProviderRouteLabel),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _route,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: _fieldDecoration(
                              context,
                              hint: l10n.addProviderRouteHint,
                            ),
                          ),
                          if (routeInvalid || taken) ...<Widget>[
                            const SizedBox(height: 4),
                            Text(
                              routeInvalid
                                  ? l10n.addProviderRouteInvalid
                                  : l10n.addProviderRouteTaken,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.error,
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          _FieldLabel(l10n.addProviderDisplayNameLabel),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _displayName,
                            decoration: _fieldDecoration(context),
                          ),
                          const SizedBox(height: 12),
                          _FieldLabel(l10n.addProviderBaseUrlLabel),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _baseURL,
                            autocorrect: false,
                            enableSuggestions: false,
                            keyboardType: TextInputType.url,
                            decoration: _fieldDecoration(context),
                          ),
                          if (baseURLInvalid) ...<Widget>[
                            const SizedBox(height: 4),
                            Text(
                              l10n.addProviderBaseUrlInvalid,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.error,
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          _FieldLabel(l10n.addProviderProtocolLabel),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _api,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: _fieldDecoration(context),
                          ),
                          const SizedBox(height: 12),
                          _FieldLabel(l10n.addProviderModelsLabel),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _models,
                            minLines: 2,
                            maxLines: 4,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: _fieldDecoration(context),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l10n.addProviderModelsHint,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _FieldLabel(l10n.secretValueLabel),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _key,
                            obscureText: true,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: _fieldDecoration(
                              context,
                              hint: l10n.secretValueHint,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l10n.providerKeyHint,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          if (state.errorMessage
                              case final String error) ...<Widget>[
                            const SizedBox(height: 8),
                            Text(
                              l10n.providersLoadFailed(error),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.error,
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          Row(
                            children: <Widget>[
                              const Spacer(),
                              OutlinedButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: Text(l10n.cancel),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed: ready
                                    ? () {
                                        widget.controller.onAction(
                                          AddLlmProvider(
                                            provider: route,
                                            settingsNs: targetFamily,
                                            displayName: _nonEmpty(
                                              _displayName.text,
                                            ),
                                            baseURL: _nonEmpty(_baseURL.text),
                                            api: _nonEmpty(_api.text),
                                            modelIds: _modelIds(_models.text),
                                            apiKey: _nonEmpty(_key.text),
                                          ),
                                        );
                                        Navigator.of(context).pop();
                                      }
                                    : null,
                                child: Text(l10n.add),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            );
          },
    );
  }
}

/// Splits a one-per-line model-id field into trimmed, non-empty ids.
List<String> _modelIds(String raw) => raw
    .split('\n')
    .map((String line) => line.trim())
    .where((String line) => line.isNotEmpty)
    .toList();

String? _nonEmpty(String? value) {
  final String trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

bool _isHttpUrl(String value) =>
    value.startsWith('http://') || value.startsWith('https://');

/// Reads one member of a decoded JSON object, or null.
Object? _jsonAtPath(Object? root, List<String> path) {
  Object? cursor = root;
  for (final String segment in path) {
    if (cursor is! Map) return null;
    if (!cursor.containsKey(segment)) return null;
    cursor = cursor[segment];
  }
  return cursor;
}

String? _stringMember(Object? json, String key) {
  if (json is! Map) return null;
  final Object? value = json[key];
  return value is String && value.isNotEmpty ? value : null;
}

class _CardNotice extends StatelessWidget {
  const _CardNotice(this.message, {this.color});

  final String message;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Text(
        message,
        style: theme.textTheme.bodySmall?.copyWith(
          color: color ?? theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Color foreground = active ? scheme.success : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(kShapeChip),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: foreground),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Text(
      label,
      style: Theme.of(context).textTheme.labelMedium
          ?.copyWith(color: scheme.onSurfaceVariant),
    );
  }
}

InputDecoration _fieldDecoration(BuildContext context, {String? hint}) {
  final ThemeData theme = Theme.of(context);
  final ColorScheme scheme = theme.colorScheme;
  final OutlineInputBorder border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(kShapeChip),
    borderSide: BorderSide(color: scheme.outlineVariant),
  );
  return InputDecoration(
    hintText: hint,
    hintStyle: theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    ),
    filled: true,
    fillColor: scheme.surfaceContainerLow,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
    enabledBorder: border,
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(kShapeChip),
      borderSide: BorderSide(color: scheme.primary),
    ),
  );
}
