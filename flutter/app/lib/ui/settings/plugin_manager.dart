/// Plugin management for Settings: the host's bundle roster, per-row
/// switches, uninstall, the installation flow, and the version-exemption
/// ledger.
///
/// Port of the reference `ui-plugin-manager` page
/// (`reference/deepseek-harness/packages/client/ui-plugin-manager/src/client/
/// PluginManagerPage.tsx`). Every package operation runs on the host; this
/// surface only drives it. Two things the reference keeps and a phone must
/// keep with it: the entry point is gated on
/// `pluginInventory/list`'s `managementAvailable`, and installation progress
/// is *pushed* (`plugin-manager/install-state` / `install-log`) rather than
/// polled — `waitForInstall` is recovery for a lost unary reply.
library;

import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/plugin_management.dart';
import 'package:domain/repository/chat_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import '../../notifications/session_notice_center.dart';
import '../shared/state_dot.dart';
import '../state_stream.dart';
import '../theme/theme.dart';
import 'settings_backend_scope.dart';
import 'settings_chrome.dart';

/// Where one installation is, from the surface's point of view.
///
/// `unconfirmed` and `failed` are the two honest end states: a reply lost on
/// the wire leaves the attempt unknown until `waitForInstall` reconciles it.
enum PluginInstallStage {
  idle,
  checking,
  starting,
  running,
  cancelling,
  applying,
  unconfirmed,
  done,
  failed,
}

/// One installation attempt's state.
final class PluginInstallState {
  const PluginInstallState({
    this.stage = PluginInstallStage.idle,
    this.spec = '',
    this.registry,
    this.requestId,
    this.attempt = '',
    this.log = '',
    this.error,
    this.pendingBuilds = const <String>[],
    this.bundle,
    this.needsRestart = false,
  });

  final PluginInstallStage stage;
  final String spec;
  final String? registry;
  final String? requestId;

  /// The registry the current attempt asks, and its position, as a line.
  final String attempt;
  final String log;

  /// The refusal the host folded into its result.
  final PluginManagementError? error;

  /// Build scripts the host would not run; approving them is the human's
  /// explicit acceptance.
  final List<String> pendingBuilds;
  final String? bundle;
  final bool needsRestart;

  /// The attempt is in flight and the surface owns its progress panel.
  bool get isPending => switch (stage) {
    PluginInstallStage.checking ||
    PluginInstallStage.starting ||
    PluginInstallStage.running ||
    PluginInstallStage.cancelling ||
    PluginInstallStage.applying ||
    PluginInstallStage.unconfirmed => true,
    _ => false,
  };

  PluginInstallState copyWith({
    PluginInstallStage? stage,
    String? spec,
    String? registry,
    String? requestId,
    String? attempt,
    String? log,
    PluginManagementError? error,
    List<String>? pendingBuilds,
    String? bundle,
    bool? needsRestart,
    bool clearError = false,
  }) => PluginInstallState(
    stage: stage ?? this.stage,
    spec: spec ?? this.spec,
    registry: registry ?? this.registry,
    requestId: requestId ?? this.requestId,
    attempt: attempt ?? this.attempt,
    log: log ?? this.log,
    error: clearError ? null : (error ?? this.error),
    pendingBuilds: pendingBuilds ?? this.pendingBuilds,
    bundle: bundle ?? this.bundle,
    needsRestart: needsRestart ?? this.needsRestart,
  );
}

/// The page's state.
final class PluginManagerUiState {
  const PluginManagerUiState({
    this.isLoading = false,
    this.failed = false,
    this.managementAvailable = false,
    this.bundles = const <PluginBundle>[],
    this.plugins = const <PluginInfo>[],
    this.registries,
    this.exemptions,
    this.busyKeys = const <String>{},
    this.install = const PluginInstallState(),
    this.query = '',
  });

  final bool isLoading;

  /// The roster read failed; the page shows its retry notice.
  final bool failed;

  /// Whether the host composes a plugin manager at all. False makes the whole
  /// page read-only, exactly as the inventory reports it.
  final bool managementAvailable;

  final List<PluginBundle> bundles;
  final List<PluginInfo> plugins;
  final PluginRegistries? registries;
  final PluginVersionExemptions? exemptions;

  /// Package names, or `row:<entryId>`, with an operation in flight.
  final Set<String> busyKeys;

  final PluginInstallState install;
  final String query;

  /// Installed bundles plus the optional ones a profile may add, with the
  /// builtin composition bundles filtered out the way the reference does.
  List<PluginBundle> get visibleBundles {
    final normalized = query.trim().toLowerCase();
    return bundles.where((bundle) {
      if (!bundle.installed && !bundle.optional && bundle.error == null) {
        return false;
      }
      if (normalized.isEmpty) return true;
      final title = bundle.title?.resolve('en') ?? '';
      return bundle.name.toLowerCase().contains(normalized) ||
          title.toLowerCase().contains(normalized) ||
          (bundle.description ?? '').toLowerCase().contains(normalized);
    }).toList()..sort((a, b) => a.name.compareTo(b.name));
  }
}

/// One controller per backend, disposed with the Settings surface.
class PluginManagerController {
  PluginManagerController(
    this._repository, {
    SessionNoticeSink? notices,
    // ignore: prefer_initializing_formals
  }) : _notices = notices {
    _installProgressSub = _repository.observePluginInstallProgress().listen(
      _onInstallProgress,
    );
    _installLogSub = _repository.observePluginInstallLog().listen(
      _onInstallLog,
    );
    // A manager operation from anywhere — this page, the CLI, HMR — moves the
    // composition, so the roster is re-read rather than assumed.
    _changeSub = _repository.observePluginChanges().listen((_) {
      unawaited(_refreshNow());
    });
    unawaited(_refreshNow());
  }

  final ChatRepository _repository;

  /// The notice seat; null in a bare controller (a test double), where a
  /// failed refresh only reaches the page's own notice.
  final SessionNoticeSink? _notices;
  final AppStateStream<PluginManagerUiState> _state =
      AppStateStream<PluginManagerUiState>(const PluginManagerUiState());

  StreamSubscription<PluginInstallProgress>? _installProgressSub;
  StreamSubscription<PluginInstallLogChunk>? _installLogSub;
  StreamSubscription<void>? _changeSub;

  bool _isLoading = false;
  bool _failed = false;
  bool _managementAvailable = false;
  List<PluginBundle> _bundles = const <PluginBundle>[];
  List<PluginInfo> _plugins = const <PluginInfo>[];
  PluginRegistries? _registries;
  PluginVersionExemptions? _exemptions;
  final Set<String> _busyKeys = <String>{};
  PluginInstallState _install = const PluginInstallState();
  String _query = '';

  PluginManagerUiState get state => _state.value;
  Stream<PluginManagerUiState> get uiState => _state.stream;

  /// The page's callback surface, bound to this controller.
  PluginManagerActions get actions => PluginManagerActions(
    refresh: refresh,
    search: search,
    setBundleEnabled: (String name, bool enabled) =>
        unawaited(setBundleEnabled(name, enabled)),
    setPluginEnabled: (String entryId, bool enabled) =>
        unawaited(setPluginEnabled(entryId, enabled)),
    uninstall: (String name) => unawaited(uninstall(name)),
    startInstall: (String spec, String? registry) =>
        unawaited(startInstall(spec, registry: registry)),
    cancelInstall: () => unawaited(cancelInstall()),
    approveBuildsAndRetry: () => unawaited(approveBuildsAndRetry()),
    enableInstalled: () => unawaited(enableInstalled()),
    dismissInstall: dismissInstall,
    loadExemptions: () => unawaited(loadExemptions()),
    revokeExemption: (String packageVersion, String runtimeVersion) =>
        unawaited(revokeExemption(packageVersion, runtimeVersion)),
  );

  Future<void> dispose() async {
    await _installProgressSub?.cancel();
    await _installLogSub?.cancel();
    await _changeSub?.cancel();
  }

  /// Filters the roster by package name, title, or one-liner.
  void search(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized == _query) return;
    _query = normalized;
    _publish();
  }

  void refresh() => unawaited(_refreshNow());

  Future<void> _refreshNow() async {
    _isLoading = true;
    _publish();
    try {
      final inventory = await _repository.listPluginInventory();
      _managementAvailable = inventory.managementAvailable;
      if (!_managementAvailable) {
        _bundles = const <PluginBundle>[];
        _plugins = const <PluginInfo>[];
        _failed = false;
        return;
      }
      final results = await Future.wait(<Future<Object?>>[
        _repository.listPluginBundles(),
        _repository.listPlugins(),
      ]);
      _bundles = results[0]! as List<PluginBundle>;
      _plugins = results[1]! as List<PluginInfo>;
      _registries = await _repository.pluginRegistries();
      _failed = false;
    } catch (error, stackTrace) {
      _failed = true;
      // The page shows its own retry notice, but that notice unmounts with
      // the page; the app-wide seat is what keeps a failed refresh visible
      // after the user navigates away (reference PluginRefreshToast).
      _notices?.pluginRefreshFailed();
      ErrorLogCollector.instance.captureError(
        error,
        stackTrace: stackTrace,
        context: const <String, Object?>{
          'controller': 'PluginManagerController',
          'action': 'refresh',
        },
      );
    } finally {
      _isLoading = false;
      _publish();
    }
  }

  Future<void> loadExemptions() async {
    try {
      final exemptions = await _repository.listPluginVersionExemptions();
      _exemptions = exemptions;
      _publish();
    } catch (error, stackTrace) {
      ErrorLogCollector.instance.captureError(
        error,
        stackTrace: stackTrace,
        context: const <String, Object?>{
          'controller': 'PluginManagerController',
          'action': 'loadExemptions',
        },
      );
    }
  }

  /// Enables or disables one installed bundle.
  Future<void> setBundleEnabled(String name, bool enabled) =>
      _runChange(name, () => _repository.setPluginBundleEnabled(name, enabled));

  /// Enables or disables one plugin row inside a bundle.
  Future<void> setPluginEnabled(String entryId, bool enabled) => _runChange(
    'row:$entryId',
    () => _repository.setPluginEnabled(entryId, enabled),
  );

  /// Uninstalls one bundle. The surface confirms this one: it is the only
  /// destructive manager operation.
  Future<void> uninstall(String name) =>
      _runChange(name, () => _repository.removePluginBundle(name));

  Future<void> _runChange(
    String busyKey,
    Future<PluginChangeResult> Function() operation,
  ) async {
    _busyKeys.add(busyKey);
    _publish();
    try {
      final result = await operation();
      _lastChange = result;
    } catch (error, stackTrace) {
      _lastChange = null;
      ErrorLogCollector.instance.captureError(
        error,
        stackTrace: stackTrace,
        context: <String, Object?>{
          'controller': 'PluginManagerController',
          'action': 'change',
          'target': busyKey,
        },
      );
    } finally {
      _busyKeys.remove(busyKey);
      await _refreshNow();
    }
  }

  /// The last operation's outcome, for the page's toast.
  PluginChangeResult? _lastChange;
  PluginChangeResult? takeLastChange() {
    final change = _lastChange;
    _lastChange = null;
    return change;
  }

  void _onInstallProgress(PluginInstallProgress progress) {
    if (_install.requestId != progress.requestId) return;
    final attempt = progress.registry == null
        ? ''
        : progress.attemptTotal == null
        ? progress.registry!
        : '${progress.registry} (${progress.attemptIndex}/${progress.attemptTotal})';
    _install = _install.copyWith(
      stage: switch (progress.phase) {
        PluginInstallPhase.installing => PluginInstallStage.running,
        PluginInstallPhase.cancelling => PluginInstallStage.cancelling,
        PluginInstallPhase.applying => PluginInstallStage.applying,
      },
      attempt: attempt,
    );
    _publish();
  }

  void _onInstallLog(PluginInstallLogChunk chunk) {
    if (chunk.requestId != null && chunk.requestId != _install.requestId) {
      return;
    }
    // Keep the tail only: a package run is minutes of output and the panel is
    // a phone's worth of it.
    final combined = '${_install.log}${chunk.text}';
    _install = _install.copyWith(
      log: combined.length > 8192
          ? combined.substring(combined.length - 8192)
          : combined,
    );
    _publish();
  }

  /// Inspects one spec, then installs it with a client-minted request id so
  /// the host pushes progress and log events for this attempt.
  Future<void> startInstall(String spec, {String? registry}) async {
    final trimmed = spec.trim();
    if (trimmed.isEmpty) return;
    _install = PluginInstallState(
      stage: PluginInstallStage.checking,
      spec: trimmed,
      registry: registry,
    );
    _publish();
    PluginSpecInspection inspection;
    try {
      inspection = await _repository.inspectPluginSpec(
        trimmed,
        registry: registry,
      );
    } catch (error, stackTrace) {
      ErrorLogCollector.instance.captureError(
        error,
        stackTrace: stackTrace,
        context: const <String, Object?>{
          'controller': 'PluginManagerController',
          'action': 'inspect',
        },
      );
      _install = _install.copyWith(stage: PluginInstallStage.failed);
      _publish();
      return;
    }
    if (inspection is PluginSpecRefused) {
      _install = _install.copyWith(
        stage: PluginInstallStage.failed,
        error: PluginManagementError(
          code: PluginManagementErrorCode.invalidSpec,
          diagnostic: inspection.registries.isEmpty
              ? inspection.reason
              : '${inspection.reason} (${inspection.registries.join(', ')})',
        ),
      );
      _publish();
      return;
    }
    _install = _install.copyWith(stage: PluginInstallStage.starting);
    _publish();
    await _installBundle(approvedBuilds: const <String>[]);
  }

  Future<void> _installBundle({required List<String> approvedBuilds}) async {
    // The request id is minted here because the host only pushes
    // `install-state`/`install-log` for an attempt that names one.
    final requestId =
        _install.requestId ?? 'req-${DateTime.now().microsecondsSinceEpoch}';
    _install = _install.copyWith(requestId: requestId);
    _publish();
    try {
      final result = await _repository.installPluginBundle(
        _install.spec,
        requestId: requestId,
        registry: _install.registry,
        approvedBuilds: approvedBuilds,
      );
      _settleInstall(result);
    } catch (error, stackTrace) {
      // A lost unary reply is not a lost installation: reconcile it before
      // telling the user anything.
      ErrorLogCollector.instance.captureError(
        error,
        stackTrace: stackTrace,
        context: const <String, Object?>{
          'controller': 'PluginManagerController',
          'action': 'installBundle',
        },
      );
      await _reconcileInstall(requestId);
    }
  }

  Future<void> _reconcileInstall(String requestId) async {
    try {
      final result = await _repository.waitForPluginInstall(requestId);
      if (result == null) {
        _install = _install.copyWith(stage: PluginInstallStage.unconfirmed);
      } else {
        _settleInstall(result);
      }
    } catch (error, stackTrace) {
      ErrorLogCollector.instance.captureError(
        error,
        stackTrace: stackTrace,
        context: const <String, Object?>{
          'controller': 'PluginManagerController',
          'action': 'waitForInstall',
        },
      );
      _install = _install.copyWith(stage: PluginInstallStage.unconfirmed);
    }
    _publish();
  }

  void _settleInstall(PluginChangeResult result) {
    switch (result.application) {
      case PluginChangeApplication.failed:
        _install = _install.copyWith(
          stage: PluginInstallStage.failed,
          error: result.error,
          pendingBuilds: result.pendingBuilds,
        );
      case PluginChangeApplication.cancelled:
        _install = _install.copyWith(
          stage: PluginInstallStage.starting,
          requestId: '',
          log: '',
        );
      case PluginChangeApplication.applied:
      case PluginChangeApplication.restartRequired:
      case PluginChangeApplication.overridden:
        _install = _install.copyWith(
          stage: PluginInstallStage.done,
          bundle: result.bundle,
          needsRestart: result.needsRestart,
          pendingBuilds: const <String>[],
        );
    }
    _publish();
  }

  /// Retries a build-blocked install with the scripts the host refused.
  Future<void> approveBuildsAndRetry() async {
    final pending = _install.pendingBuilds;
    if (pending.isEmpty) return;
    _install = _install.copyWith(
      stage: PluginInstallStage.starting,
      pendingBuilds: const <String>[],
      clearError: true,
    );
    _publish();
    await _installBundle(approvedBuilds: pending);
  }

  /// Cancels an in-flight installation.
  Future<void> cancelInstall() async {
    final requestId = _install.requestId;
    if (requestId == null || requestId.isEmpty) return;
    _install = _install.copyWith(stage: PluginInstallStage.cancelling);
    _publish();
    try {
      final status = await _repository.cancelPluginInstall(requestId);
      // `too-late` means the host is already applying; the progress stream
      // stays authoritative and the phase must not regress.
      if (status == PluginInstallCancellation.cancelled) {
        _install = PluginInstallState(spec: _install.spec);
      }
    } catch (error, stackTrace) {
      ErrorLogCollector.instance.captureError(
        error,
        stackTrace: stackTrace,
        context: const <String, Object?>{
          'controller': 'PluginManagerController',
          'action': 'cancelInstall',
        },
      );
    }
    _publish();
  }

  /// Activates a bundle an install left disabled, exactly as the reference's
  /// done screen does.
  Future<void> enableInstalled() async {
    final bundle = _install.bundle;
    if (bundle == null) return;
    await setBundleEnabled(bundle, true);
    _install = const PluginInstallState();
    _publish();
  }

  /// Dismisses the installation panel without touching the host.
  void dismissInstall() {
    _install = const PluginInstallState();
    _publish();
  }

  /// Revokes one version exemption; granting one needs the exact current
  /// runtime version and an explicit risk acceptance, which only a
  /// version-refusal flow carries.
  Future<void> revokeExemption(String packageVersion, String runtimeVersion) =>
      _runExemption(
        packageVersion: packageVersion,
        runtimeVersion: runtimeVersion,
        enabled: false,
      );

  Future<void> _runExemption({
    required String packageVersion,
    required String runtimeVersion,
    required bool enabled,
    bool acceptRisk = false,
  }) async {
    try {
      await _repository.setPluginVersionExemption(
        packageVersion: packageVersion,
        runtimeVersion: runtimeVersion,
        enabled: enabled,
        acceptRisk: acceptRisk,
      );
      await loadExemptions();
    } catch (error, stackTrace) {
      ErrorLogCollector.instance.captureError(
        error,
        stackTrace: stackTrace,
        context: <String, Object?>{
          'controller': 'PluginManagerController',
          'action': 'setVersionExemption',
          'packageVersion': packageVersion,
        },
      );
    }
  }

  void _publish() {
    _state.value = PluginManagerUiState(
      isLoading: _isLoading,
      failed: _failed,
      managementAvailable: _managementAvailable,
      bundles: _bundles,
      plugins: _plugins,
      registries: _registries,
      exemptions: _exemptions,
      busyKeys: Set<String>.unmodifiable(_busyKeys),
      install: _install,
      query: _query,
    );
  }
}

/// One controller per backend, disposed with the Settings surface.
final pluginManagerControllerProvider = Provider.family
    .autoDispose<PluginManagerController, String>((ref, backendId) {
      final controller = PluginManagerController(
        ref.watch(chatRepositoryProvider(backendId)),
        notices: ref.watch(sessionNoticeSinkProvider(backendId)),
      );
      ref.onDispose(() => unawaited(controller.dispose()));
      return controller;
    });

/// The manager operations the page may invoke.
///
/// The page is presentation only — it renders one [PluginManagerUiState] and
/// calls back — so its states are testable without a repository double, and
/// the controller stays the only owner of the wire.
final class PluginManagerActions {
  const PluginManagerActions({
    required this.refresh,
    required this.search,
    required this.setBundleEnabled,
    required this.setPluginEnabled,
    required this.uninstall,
    required this.startInstall,
    required this.cancelInstall,
    required this.approveBuildsAndRetry,
    required this.enableInstalled,
    required this.dismissInstall,
    required this.loadExemptions,
    required this.revokeExemption,
  });

  final void Function() refresh;
  final void Function(String query) search;
  final void Function(String name, bool enabled) setBundleEnabled;
  final void Function(String entryId, bool enabled) setPluginEnabled;
  final void Function(String name) uninstall;
  final void Function(String spec, String? registry) startInstall;
  final void Function() cancelInstall;
  final void Function() approveBuildsAndRetry;
  final void Function() enableInstalled;
  final void Function() dismissInstall;
  final void Function() loadExemptions;
  final void Function(String packageVersion, String runtimeVersion)
  revokeExemption;
}

/// The Settings mount point: the host's bundle roster, its row switches, the
/// installation flow, and the version-exemption ledger.
class SettingsPluginManagerPage extends ConsumerStatefulWidget {
  const SettingsPluginManagerPage({super.key});

  @override
  ConsumerState<SettingsPluginManagerPage> createState() =>
      _SettingsPluginManagerPageState();
}

class _SettingsPluginManagerPageState
    extends ConsumerState<SettingsPluginManagerPage> {
  @override
  Widget build(BuildContext context) {
    final backendId = ref.watch(settingsBackendScopeProvider);
    if (backendId.isEmpty) {
      return const SettingsPageScaffold(title: '', children: <Widget>[]);
    }
    final controller = ref.watch(pluginManagerControllerProvider(backendId));
    return StreamBuilder<PluginManagerUiState>(
      stream: controller.uiState,
      initialData: controller.state,
      builder: (context, snapshot) {
        final state = snapshot.data ?? const PluginManagerUiState();
        return PluginManagerBody(
          state: state,
          states: controller.uiState,
          actions: controller.actions,
        );
      },
    );
  }
}

/// The manager page: one state in, callbacks out.
class PluginManagerBody extends StatelessWidget {
  const PluginManagerBody({
    required this.state,
    required this.states,
    required this.actions,
    super.key,
  });

  final PluginManagerUiState state;

  /// The live state stream; the exemptions sub-page follows it.
  final Stream<PluginManagerUiState> states;

  final PluginManagerActions actions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bundles = state.visibleBundles;
    return SettingsPageScaffold(
      title: l10n.settingsNavPluginManager,
      children: <Widget>[
        SettingsSectionHeading(
          title: l10n.settingsNavPluginManager,
          intro: l10n.pluginManagerIntro,
          showTitle: false,
        ),
        Row(
          children: <Widget>[
            IconButton(
              tooltip: l10n.refresh,
              icon: const Icon(Icons.refresh),
              onPressed: state.isLoading ? null : actions.refresh,
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: state.managementAvailable
                  ? () => unawaited(
                      showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) =>
                            _InstallSheet(actions: actions, state: state),
                      ),
                    )
                  : null,
              icon: const Icon(Icons.add),
              label: Text(l10n.pluginManagerAdd),
            ),
          ],
        ),
        if (state.install.stage != PluginInstallStage.idle) ...<Widget>[
          const SizedBox(height: 8),
          _InstallCard(actions: actions, install: state.install),
        ],
        if (!state.isLoading && !state.managementAvailable) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            l10n.pluginManagerUnavailable,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ] else if (state.failed && bundles.isEmpty) ...<Widget>[
          const SizedBox(height: 8),
          SettingsNavRow(
            title: l10n.retry,
            leading: const Icon(Icons.refresh),
            onTap: actions.refresh,
          ),
        ] else ...<Widget>[
          const SizedBox(height: 8),
          TextField(
            decoration: InputDecoration(
              hintText: l10n.pluginManagerSearchHint,
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: actions.search,
          ),
          const SizedBox(height: 8),
          if (bundles.isEmpty && !state.isLoading)
            Text(
              l10n.pluginManagerEmpty,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          for (final bundle in bundles)
            _BundleCard(
              bundle: bundle,
              busy: state.busyKeys.contains(bundle.name),
              rowsBusy: state.busyKeys,
              plugins: state.plugins,
              onSetEnabled: (bool enabled) =>
                  actions.setBundleEnabled(bundle.name, enabled),
              onSetRowEnabled: actions.setPluginEnabled,
              onUninstall: () => unawaited(_confirmUninstall(context, bundle)),
            ),
        ],
        const SizedBox(height: 16),
        SettingsNavRow(
          title: l10n.pluginExemptionsTitle,
          leading: const Icon(Icons.verified_user_outlined),
          onTap: () {
            actions.loadExemptions();
            unawaited(
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => _ExemptionsPage(
                    states: states,
                    initial: state,
                    actions: actions,
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Future<void> _confirmUninstall(
    BuildContext context,
    PluginBundle bundle,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.pluginManagerUninstallTitle(bundle.name)),
        content: Text(l10n.pluginManagerUninstallBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.pluginManagerUninstall),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      actions.uninstall(bundle.name);
    }
  }
}

/// One bundle row: its identity, its switch, and — when it is on — the plugin
/// entries it composes.
class _BundleCard extends StatelessWidget {
  const _BundleCard({
    required this.bundle,
    required this.busy,
    required this.rowsBusy,
    required this.plugins,
    required this.onSetEnabled,
    required this.onSetRowEnabled,
    required this.onUninstall,
  });

  final PluginBundle bundle;
  final bool busy;
  final Set<String> rowsBusy;
  final List<PluginInfo> plugins;
  final void Function(bool enabled) onSetEnabled;
  final void Function(String entryId, bool enabled) onSetRowEnabled;
  final VoidCallback onUninstall;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final readOnly = bundle.readOnlyReason;
    final title = bundle.title?.resolve(locale) ?? bundle.name;
    final description =
        bundle.description ?? bundle.metaDescription?.resolve(locale);
    // A locked row explains itself; the reference's tooltips become a line.
    final locked = switch (readOnly) {
      PluginReadOnlyReason.managementRequired =>
        l10n.pluginManagerReadOnlyManagement,
      PluginReadOnlyReason.unaddressable => l10n.pluginManagerReadOnlyAddress,
      null => null,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kShapeCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: theme.textTheme.bodyMedium),
                    Text(
                      bundle.version == null
                          ? bundle.name
                          : '${bundle.name} · ${bundle.version}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    Wrap(
                      spacing: 6,
                      children: <Widget>[
                        if (bundle.isExperimental)
                          _Tag(
                            label: l10n.pluginManagerBetaTag,
                            color: scheme.secondaryContainer,
                            onColor: scheme.onSecondaryContainer,
                          ),
                        if (bundle.error != null)
                          _Tag(
                            label: l10n.pluginManagerProblemTag,
                            color: scheme.errorContainer,
                            onColor: scheme.onErrorContainer,
                          ),
                      ],
                    ),
                    if (description != null && description.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          description,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    if (bundle.error?.diagnostic case final diagnostic?)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          diagnostic,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.error,
                          ),
                        ),
                      ),
                    if (locked != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          locked,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (bundle.installed && bundle.removable)
                PopupMenuButton<String>(
                  tooltip: l10n.pluginManagerUninstall,
                  enabled: !busy,
                  onSelected: (_) => onUninstall(),
                  itemBuilder: (context) => <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(
                      value: 'uninstall',
                      child: Text(l10n.pluginManagerUninstall),
                    ),
                  ],
                ),
              Switch(
                value: bundle.enabled,
                onChanged: busy || readOnly != null ? null : onSetEnabled,
              ),
            ],
          ),
          if (bundle.rows.isNotEmpty && bundle.enabled)
            ExpansionTile(
              shape: const Border(),
              collapsedShape: const Border(),
              tilePadding: EdgeInsets.zero,
              title: Text(
                l10n.pluginManagerRowsTitle(bundle.rows.length),
                style: theme.textTheme.labelMedium,
              ),
              children: <Widget>[
                for (final row in bundle.rows)
                  _RowTile(
                    row: row,
                    plugin: plugins
                        .where((plugin) => plugin.entryId == row.entryId)
                        .firstOrNull,
                    busy:
                        row.entryId != null &&
                        rowsBusy.contains('row:${row.entryId}'),
                    bundleReadOnly: readOnly != null,
                    onSetEnabled: onSetRowEnabled,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _RowTile extends StatelessWidget {
  const _RowTile({
    required this.row,
    required this.plugin,
    required this.busy,
    required this.bundleReadOnly,
    required this.onSetEnabled,
  });

  final PluginBundleRow row;
  final PluginInfo? plugin;
  final bool busy;
  final bool bundleReadOnly;
  final void Function(String entryId, bool enabled) onSetEnabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final entryId = row.entryId;
    final enabled = plugin?.enabled ?? false;
    // A row is switchable only when the host addressed it and neither the
    // bundle nor the row is locked by the profile.
    final switchable =
        entryId != null && !bundleReadOnly && plugin?.readOnlyReason == null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: StateDot(state: StateDotState.disabled, size: 8),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  row.title?.resolve(locale) ?? row.moduleName,
                  style: theme.textTheme.bodySmall,
                ),
                if (row.description case final description?)
                  Text(
                    description.resolve(locale),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                if (row.metaError case final error?)
                  Text(
                    error,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
          Switch(
            value: enabled,
            onChanged: busy || !switchable
                ? null
                : (bool next) => onSetEnabled(entryId, next),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color, required this.onColor});

  final String label;
  final Color color;
  final Color onColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(kShapeChip),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: onColor),
      ),
    );
  }
}

/// The installation panel: pushed progress, the package log, a cancel, the
/// refusal with its build approval, and the done screen's enable step.
class _InstallCard extends StatelessWidget {
  const _InstallCard({required this.actions, required this.install});

  final PluginManagerActions actions;
  final PluginInstallState install;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final stageLabel = switch (install.stage) {
      PluginInstallStage.idle => '',
      PluginInstallStage.checking => l10n.pluginInstallChecking,
      PluginInstallStage.starting => l10n.pluginInstallStarting,
      PluginInstallStage.running => l10n.pluginInstallRunning,
      PluginInstallStage.cancelling => l10n.pluginInstallCancelling,
      PluginInstallStage.applying => l10n.pluginInstallApplying,
      PluginInstallStage.unconfirmed => l10n.pluginInstallUnconfirmed,
      PluginInstallStage.done => l10n.pluginInstallDone,
      PluginInstallStage.failed => l10n.pluginInstallFailed,
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kShapeCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(install.spec, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text(
            install.attempt.isEmpty
                ? stageLabel
                : '$stageLabel · ${install.attempt}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (install.isPending) ...<Widget>[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
          if (install.error?.diagnostic case final diagnostic?) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              diagnostic,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ],
          if (install.log.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: SingleChildScrollView(
                child: Text(
                  install.log,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              if (install.isPending &&
                  install.stage != PluginInstallStage.checking)
                TextButton(
                  onPressed: install.stage == PluginInstallStage.cancelling
                      ? null
                      : actions.cancelInstall,
                  child: Text(l10n.cancel),
                ),
              if (install.pendingBuilds.isNotEmpty)
                FilledButton.tonal(
                  onPressed: actions.approveBuildsAndRetry,
                  child: Text(l10n.pluginInstallApproveBuilds),
                ),
              if (install.stage == PluginInstallStage.done &&
                  install.bundle != null)
                FilledButton(
                  onPressed: actions.enableInstalled,
                  child: Text(l10n.pluginInstallEnableNow),
                ),
              if (install.stage == PluginInstallStage.done &&
                  install.needsRestart)
                Text(
                  l10n.pluginInstallRestartRequired,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.warning,
                  ),
                ),
              if (install.stage == PluginInstallStage.failed ||
                  install.stage == PluginInstallStage.unconfirmed ||
                  install.stage == PluginInstallStage.done)
                TextButton(
                  onPressed: actions.dismissInstall,
                  child: Text(l10n.close),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The spec field, the registry picker, and the install button.
class _InstallSheet extends StatefulWidget {
  const _InstallSheet({required this.actions, required this.state});

  final PluginManagerActions actions;
  final PluginManagerUiState state;

  @override
  State<_InstallSheet> createState() => _InstallSheetState();
}

class _InstallSheetState extends State<_InstallSheet> {
  late final TextEditingController _spec = TextEditingController();
  String? _registry;

  @override
  void initState() {
    super.initState();
    // The host's resolution leads; the probe only refines it.
    _registry = widget.state.registries?.resolved;
  }

  @override
  void dispose() {
    _spec.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final offered = widget.state.registries?.offered ?? const <String>[];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l10n.pluginManagerAdd, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            TextField(
              controller: _spec,
              autofocus: true,
              decoration: InputDecoration(
                hintText: l10n.pluginInstallSpecHint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (offered.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                l10n.pluginInstallRegistry,
                style: theme.textTheme.labelMedium,
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: <Widget>[
                  for (final registry in offered)
                    ChoiceChip(
                      label: Text(registry, overflow: TextOverflow.ellipsis),
                      selected: _registry == registry,
                      onSelected: (_) => setState(() => _registry = registry),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.cancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    final spec = _spec.text;
                    if (spec.trim().isEmpty) return;
                    Navigator.of(context).pop();
                    widget.actions.startInstall(spec, _registry);
                  },
                  child: Text(l10n.pluginInstallAction),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The saved version exemptions: what the running version has been told to
/// accept. Granting one needs an exact runtime version plus an explicit risk
/// acceptance, so this surface lists and revokes; a grant rides the refusal a
/// version mismatch produces.
class _ExemptionsPage extends StatelessWidget {
  const _ExemptionsPage({
    required this.states,
    required this.initial,
    required this.actions,
  });

  final Stream<PluginManagerUiState> states;
  final PluginManagerUiState initial;
  final PluginManagerActions actions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return StreamBuilder<PluginManagerUiState>(
      stream: states,
      initialData: initial,
      builder: (context, snapshot) {
        final state = snapshot.data ?? initial;
        final exemptions =
            state.exemptions?.exemptions ?? const <String, List<String>>{};
        return SettingsPageScaffold(
          title: l10n.pluginExemptionsTitle,
          children: <Widget>[
            SettingsSectionHeading(
              title: l10n.pluginExemptionsTitle,
              intro: l10n.pluginExemptionsIntro,
              showTitle: false,
            ),
            if (exemptions.isEmpty)
              Text(
                l10n.pluginExemptionsEmpty,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              )
            else
              for (final entry in exemptions.entries)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(entry.key),
                  subtitle: Text(entry.value.join(', ')),
                  trailing: TextButton(
                    onPressed: entry.value.isEmpty
                        ? null
                        : () => actions.revokeExemption(
                            entry.key,
                            entry.value.first,
                          ),
                    child: Text(l10n.pluginExemptionsRevoke),
                  ),
                ),
            if (state.exemptions?.warnings.isNotEmpty ?? false)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  state.exemptions!.warnings.join('\n'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.warning,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
