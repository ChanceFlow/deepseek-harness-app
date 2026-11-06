/// The WebView shell — the phone's one surface once the native screens are
/// gone.
///
/// Each enabled backend host renders the dsh web client in its own WebView, so
/// the UI is always the host's own. The shell supplies only the three things a
/// browser cannot: the host switcher, the WebView pool, and the bridge to our
/// notification pipeline. Notifications keep running on the Dart side
/// (`lib/notifications/` over `ChatRepository.observeSessions()`), independent
/// of which page is on screen.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/backend.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../di/providers.dart';
import '../theme/theme.dart';
import 'host_pool.dart';
import 'host_web_view.dart';

/// Builds one host's page. Production passes [HostWebView]; tests pass a
/// stand-in so the shell can be driven without a platform view.
typedef HostViewBuilder = Widget Function(
  BuildContext context,
  BackendConfig backend,
);

/// Builds the real page for a host.
typedef HostBuilder = Widget Function(BackendConfig backend);

/// The shell root: chrome bar, host WebViews, switches.
class ShellRoot extends ConsumerStatefulWidget {
  const ShellRoot({this.hostViewBuilder, super.key});

  /// Null renders the real [HostWebView].
  final HostViewBuilder? hostViewBuilder;

  @override
  ConsumerState<ShellRoot> createState() => _ShellRootState();
}

class _ShellRootState extends ConsumerState<ShellRoot> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  /// The host the user last switched to; null follows the registry's choice.
  String? _selectedId;

  /// Which hosts hold a live WebView. Beyond the policy's budget the
  /// least-recently-used page is released and reloads on return.
  final HostPool _pool = HostPool();

  /// The live page per host id, and the URL each page loaded (a URL edit
  /// rebuilds the page).
  final Map<String, Widget> _pages = <String, Widget>{};
  final Map<String, Uri> _pageUrls = <String, Uri>{};

  /// Creates and releases pages so only the pool's live hosts carry a
  /// WebView. Called from `build`; idempotent and state-free.
  void _syncPages(
    List<BackendConfig> hosts,
    String? activeId,
    HostBuilder build,
  ) {
    final known = _pool.hostIds.toSet();
    _pool.setHosts([for (final host in hosts) host.id]);
    // A host loads the first time it is configured (the point of keeping
    // several alive is instant switching); the active one is newest.
    for (final host in hosts) {
      if (!known.contains(host.id)) _pool.touch(host.id);
    }
    if (activeId != null) _pool.touch(activeId);
    final live = _pool.liveIds.toSet();
    for (final host in hosts) {
      final loaded = _pageUrls[host.id];
      if (live.contains(host.id) &&
          (!_pages.containsKey(host.id) || loaded != host.baseUri)) {
        _pages[host.id] = build(host);
        _pageUrls[host.id] = host.baseUri;
      }
    }
    _pages.removeWhere((id, _) {
      if (live.contains(id)) return false;
      _pageUrls.remove(id);
      return true;
    });
  }

  BackendConfig? _activeOf(
    List<BackendConfig> hosts,
    String? registryActiveId,
  ) {
    final wanted = _selectedId ?? registryActiveId;
    return hosts.where((host) => host.id == wanted).firstOrNull ??
        hosts.firstOrNull;
  }

  Future<void> _select(BackendConfig host) async {
    setState(() => _selectedId = host.id);
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
    await ref
        .read(backendRegistryProvider.future)
        .then((registry) => registry.onAction(SelectBackend(host.id)))
        .catchError((Object _) {
          // No registry behind this shell (a bare test): switching stays
          // local. The production tree always resolves one.
        });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final registry = ref.watch(backendRegistryStateProvider).value;
    final hosts = registry?.enabledBackends ?? const <BackendConfig>[];
    final active = _activeOf(hosts, registry?.activeId);
    final builder = widget.hostViewBuilder;
    final activeId = active?.id;
    _syncPages(hosts, activeId, (BackendConfig host) {
      if (builder != null) return builder(context, host);
      return HostWebView(
        key: ValueKey<String>('host-page:${host.id}'),
        backend: host,
      );
    });

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: scheme.aliases.bgBase,
      drawer: _HostDrawer(
        hosts: hosts,
        activeId: active?.id,
        onSelect: _select,
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _ShellBar(
              host: active,
              onOpenSwitcher: () => _scaffoldKey.currentState?.openDrawer(),
            ),
            Expanded(
              child: hosts.isEmpty
                  ? _EmptyShell(
                      message: l10n.noHostsTitle,
                      action: l10n.addBackend,
                      onAction: () => _scaffoldKey.currentState?.openDrawer(),
                    )
                  : IndexedStack(
                      index: hosts.indexWhere((host) => host.id == activeId),
                      children: [
                        for (final host in hosts)
                          _pages[host.id] ?? const _SleepingHostPage(),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The 40 px chrome: the active host, its reachability dot, and the switcher.
class _ShellBar extends ConsumerWidget {
  const _ShellBar({required this.host, required this.onOpenSwitcher});

  final BackendConfig? host;
  final VoidCallback onOpenSwitcher;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final host = this.host;
    final connection = host == null
        ? null
        : ref.watch(backendConnectionStateProvider(host.id)).value;
    final live = connection == null || connection.isConnected;
    return Container(
      height: 44,
      padding: const EdgeInsets.only(left: 4, right: 8),
      decoration: BoxDecoration(
        color: scheme.aliases.specificSidebarFill,
        border: Border(bottom: BorderSide(width: 0.5, color: scheme.borderL2)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.menu),
            tooltip: l10n.manageHosts,
            onPressed: onOpenSwitcher,
          ),
          const SizedBox(width: 2),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: live ? scheme.stateSuccessPrimary : scheme.labelCaption,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              host?.label ?? l10n.noHostsTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DshType.sStrong14.style(color: scheme.labelPrimary),
            ),
          ),
          Text(
            host?.baseUri.authority ?? '',
            style: DshType.xxs12.style(color: scheme.labelTertiary),
          ),
        ],
      ),
    );
  }
}

/// The host switcher: one row per host, with the add and edit seats.
class _HostDrawer extends ConsumerWidget {
  const _HostDrawer({
    required this.hosts,
    required this.activeId,
    required this.onSelect,
  });

  final List<BackendConfig> hosts;
  final String? activeId;
  final void Function(BackendConfig host) onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Drawer(
      width: 280,
      backgroundColor: scheme.aliases.specificSidebarFill,
      // The pin's drawer meets the scrim with square edges.
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.manageHosts,
                      style: DshType.l20.style(color: scheme.labelPrimary),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: l10n.addBackend,
                    onPressed: () => _showAddHost(context, ref),
                  ),
                ],
              ),
            ),
            for (final host in hosts)
              _HostRow(
                host: host,
                active: host.id == activeId,
                onTap: () => onSelect(host),
              ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                l10n.hostsCarryTheirOwnUi,
                style: DshType.xxs12.style(color: scheme.labelTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddHost(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final label = TextEditingController();
    final url = TextEditingController();
    final added = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.addBackend),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: label,
              decoration: InputDecoration(
                labelText: l10n.backendLabel,
                hintText: l10n.backendLabelHint,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: url,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: l10n.backendBaseUrlLabel,
                hintText: l10n.backendBaseUrlHint,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.add),
          ),
        ],
      ),
    );
    if (added ?? false) {
      await ref
          .read(backendRegistryProvider.future)
          .then(
            (registry) => registry.onAction(
              AddBackend(label.text.trim(), url.text.trim()),
            ),
          )
          .catchError((Object _) {});
    }
    label.dispose();
    url.dispose();
  }
}

class _HostRow extends StatelessWidget {
  const _HostRow({
    required this.host,
    required this.active,
    required this.onTap,
  });

  final BackendConfig host;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: InkWell(
        borderRadius: BorderRadius.circular(kRadiusMd),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: active ? scheme.interactiveBgHover : null,
            borderRadius: BorderRadius.circular(kRadiusMd),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      host.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DshType.s14.style(color: scheme.labelPrimary),
                    ),
                    Text(
                      host.baseUri.authority,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DshType.xxs12.style(color: scheme.labelTertiary),
                    ),
                  ],
                ),
              ),
              if (active)
                Icon(Icons.check, size: 16, color: scheme.stateBusinessPrimary),
            ],
          ),
        ),
      ),
    );
  }
}

/// A host whose page was released by the pool budget: it is never the visible
/// child (the active host is always live), so it only holds the slot.
class _SleepingHostPage extends StatelessWidget {
  const _SleepingHostPage();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _EmptyShell extends StatelessWidget {
  const _EmptyShell({
    required this.message,
    required this.action,
    required this.onAction,
  });

  final String message;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: DshType.s14.style(color: scheme.labelSecondary)),
          const SizedBox(height: 12),
          FilledButton(onPressed: onAction, child: Text(action)),
        ],
      ),
    );
  }
}
