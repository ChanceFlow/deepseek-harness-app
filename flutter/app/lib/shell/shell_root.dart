/// The WebView shell: host pages on one horizontal strip, an exposé drawer,
/// and the settings orb.
///
/// Each enabled backend host renders the dsh web client in its own WebView.
/// The pages are laid side by side at exactly the viewport width; switching
/// translates the strip and never resizes a page, so a host never reflows.
/// A three-finger swipe down (or the grabber) pushes the strip down by the
/// drawer height; the drawer holds one bubble per host and the settings orb.
/// Notifications keep running on the Dart side, independent of the page.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/backend.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../di/providers.dart';
import '../theme/theme.dart';
import 'host_bubbles.dart';
import 'host_pool.dart';
import 'host_web_view.dart';
import 'shell_gestures.dart';
import 'shell_page_strip.dart';
import 'shell_settings.dart';

/// Builds one host's page. Production passes [HostWebView]; tests pass a
/// stand-in so the shell can be driven without a platform view.
typedef HostViewBuilder = Widget Function(
  BuildContext context,
  BackendConfig backend,
);

/// Builds the real page for a host.
typedef HostBuilder = Widget Function(BackendConfig backend);

/// The drawer's content height; the strip drops by exactly this much.
const double kExposeDrawerHeight = 96;

/// The shell root: page strip, exposé drawer, settings.
class ShellRoot extends ConsumerStatefulWidget {
  const ShellRoot({this.hostViewBuilder, super.key});

  /// Null renders the real [HostWebView].
  final HostViewBuilder? hostViewBuilder;

  @override
  ConsumerState<ShellRoot> createState() => _ShellRootState();
}

class _ShellRootState extends ConsumerState<ShellRoot>
    with TickerProviderStateMixin {
  /// The host the user last switched to; null follows the registry's choice.
  String? _selectedId;

  /// Which hosts hold a live WebView. Beyond the policy's budget the
  /// least-recently-used page is released and reloads on return.
  final HostPool _pool = HostPool();

  /// The live page per host id, and the URL each page loaded.
  final Map<String, Widget> _pages = <String, Widget>{};
  final Map<String, Uri> _pageUrls = <String, Uri>{};

  /// Whether the drawer is showing, and its 0..1 progress.
  bool _exposed = false;
  late final AnimationController _expose = AnimationController(
    vsync: this,
    duration: DshMotion.durationMedium,
  )..addListener(() => setState(() {}));

  /// Fractional strip position: 0 is the first host, 1.5 is halfway between
  /// the second and third.
  double _page = 0;

  /// The last registry-active host the strip aligned itself to; a change
  /// outside a sweep re-seats the strip, a sweep wins over it.
  String? _lastActiveId;

  /// The sweep animation between two whole pages.
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: _sweepDuration(1),
  )..addListener(_onSweepTick);
  double _sweepBegin = 0;
  double _sweepEnd = 0;

  /// Drag state for the bubble row.
  double _dragStartPage = 0;
  double _dragDistance = 0;

  @override
  void dispose() {
    _expose.dispose();
    _sweep.dispose();
    super.dispose();
  }

  Duration _sweepDuration(int pages) =>
      Duration(milliseconds: (240 + 60 * (pages - 1)).clamp(240, 600));

  void _onSweepTick() {
    final t = Curves.easeInOutCubic.transform(_sweep.value);
    setState(() => _page = lerpDouble(_sweepBegin, _sweepEnd, t)!);
  }

  double get _exposeT => Curves.easeOutCubic.transform(_expose.value);

  /// Reduced motion turns the drawer into a cut, not an animation.
  bool get _reduceMotion => DshMotion.isReducedMotion(context);

  void _openExpose() {
    if (_exposed) return;
    _expose.duration = _reduceMotion ? Duration.zero : DshMotion.durationMedium;
    setState(() => _exposed = true);
    unawaited(_expose.forward());
  }

  void _closeExpose() {
    if (!_exposed) return;
    _expose.duration = _reduceMotion ? Duration.zero : DshMotion.durationMedium;
    setState(() => _exposed = false);
    unawaited(_expose.reverse());
  }

  /// Sweeps the strip to [index]; collapses afterwards when [collapse].
  void _sweepTo(int index, {required bool collapse}) {
    final from = _page;
    if ((from - index).abs() < 0.001) {
      if (collapse) _closeExpose();
      return;
    }
    final distance = (index - from).abs();
    _sweep.duration = _reduceMotion
        ? Duration.zero
        : _sweepDuration(distance.ceil());
    _sweepBegin = from;
    _sweepEnd = index.toDouble();
    unawaited(
      _sweep.forward(from: 0).whenComplete(() {
        if (collapse) _closeExpose();
      }),
    );
  }

  /// The whole page the strip currently rests on (or is nearest to).
  int _nearestPage(int hostCount) =>
      _page.round().clamp(0, hostCount == 0 ? 0 : hostCount - 1);

  void _select(BackendConfig host) {
    if (_selectedId == host.id) return;
    setState(() => _selectedId = host.id);
    unawaited(
      ref
          .read(backendRegistryProvider.future)
          .then((registry) => registry.onAction(SelectBackend(host.id)))
          .catchError((Object _) {
            // No registry behind this shell (a bare test): switching stays
            // local.
          }),
    );
  }

  /// Creates and releases pages so only the pool's live hosts carry a
  /// WebView. Called from `build`; idempotent and state-free.
  void _syncPages(
    List<BackendConfig> hosts,
    String? activeId,
    HostBuilder build,
  ) {
    final known = _pool.hostIds.toSet();
    _pool.setHosts([for (final host in hosts) host.id]);
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final registry = ref.watch(backendRegistryStateProvider).value;
    final hosts = registry?.enabledBackends ?? const <BackendConfig>[];
    final active =
        hosts
            .where((host) => host.id == (_selectedId ?? registry?.activeId))
            .firstOrNull ??
        hosts.firstOrNull;
    final builder = widget.hostViewBuilder;
    _syncPages(hosts, active?.id, (BackendConfig host) {
      if (builder != null) return builder(context, host);
      return HostWebView(
        key: ValueKey<String>('host-page:${host.id}'),
        backend: host,
      );
    });

    // The strip follows the registry's active host until the user sweeps;
    // adding or removing hosts keeps the position in range.
    if (hosts.isNotEmpty) {
      _page = _page.clamp(0, hosts.length - 1).toDouble();
    }
    if (_lastActiveId != active?.id) {
      _lastActiveId = active?.id;
      final index = hosts.indexWhere((host) => host.id == active?.id);
      if (index >= 0 && !_sweep.isAnimating) _page = index.toDouble();
    }

    final t = _exposeT;
    final drawerHeight = kExposeDrawerHeight * t;

    return PopScope(
      canPop: !_exposed,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _closeExpose();
      },
      child: Scaffold(
        backgroundColor: scheme.aliases.bgBase,
        body: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return Stack(
                fit: StackFit.expand,
                children: [
                  ThreeFingerSwipeDetector(
                    onSwipeDown: _openExpose,
                    onSwipeUp: _closeExpose,
                    child: Stack(
                      children: [
                        if (hosts.isNotEmpty)
                          Positioned.fill(
                            child: IgnorePointer(
                              ignoring: _exposed,
                              child: ShellPageStrip(
                                pages: [
                                  for (final host in hosts)
                                    _pages[host.id] ??
                                        const _SleepingHostPage(),
                                ],
                                position: _page,
                                pageWidth: width,
                                verticalOffset: drawerHeight,
                              ),
                            ),
                          ),
                        if (_exposed)
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onTap: _closeExpose,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (hosts.isEmpty)
                    Positioned.fill(
                      child: _EmptyShell(
                        message: l10n.noHostsTitle,
                        action: l10n.addBackend,
                        onAction: _openSettings,
                      ),
                    ),
                  if (t >= 0.999)
                    const SizedBox.shrink()
                  else if (hosts.isNotEmpty)
                    Positioned(
                      top: 6,
                      left: width / 2 - 16,
                      child: _Grabber(
                        label: l10n.shellExposeHint,
                        onTap: _openExpose,
                      ),
                    ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: kExposeDrawerHeight,
                    child: ClipRect(
                      child: Transform.translate(
                        offset: Offset(0, -(1 - t) * kExposeDrawerHeight),
                        child: SizedBox(
                          width: width,
                          height: kExposeDrawerHeight,
                          child: _ExposeDrawer(
                            hosts: hosts,
                            liveIds: _pool.liveIds.toSet(),
                            page: _page,
                            onBubbleDragStart: () {
                              _dragStartPage = _page;
                              _dragDistance = 0;
                            },
                            onBubbleDragUpdate: (dx) {
                              _dragDistance += dx;
                              setState(() {
                                _page =
                                    (_dragStartPage -
                                            _dragDistance / kBubbleStep)
                                        .clamp(0, math.max(0, hosts.length - 1))
                                        .toDouble();
                              });
                            },
                            onBubbleDragEnd: () {
                              final target = _nearestPage(hosts.length);
                              _sweepTo(target, collapse: false);
                              _select(hosts[target]);
                            },
                            onBubbleTap: (index) {
                              _sweepTo(index, collapse: true);
                              _select(hosts[index]);
                            },
                            onSettings: _openSettings,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _openSettings() {
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => const ShellSettingsScreen()),
      ),
    );
  }
}

/// The page slot for a host whose WebView the pool released.
class _SleepingHostPage extends StatelessWidget {
  const _SleepingHostPage();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// The 32×4 handle that opens the drawer without the gesture.
class _Grabber extends StatelessWidget {
  const _Grabber({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        key: const ValueKey<String>('shell-grabber'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Container(
            width: 32,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.labelCaption,
              borderRadius: BorderRadius.circular(kShapePill),
            ),
          ),
        ),
      ),
    );
  }
}

/// The drawer's content: the bubble strip and the settings orb.
class _ExposeDrawer extends StatelessWidget {
  const _ExposeDrawer({
    required this.hosts,
    required this.liveIds,
    required this.page,
    required this.onBubbleDragStart,
    required this.onBubbleDragUpdate,
    required this.onBubbleDragEnd,
    required this.onBubbleTap,
    required this.onSettings,
  });

  final List<BackendConfig> hosts;
  final Set<String> liveIds;
  final double page;
  final VoidCallback onBubbleDragStart;
  final void Function(double dx) onBubbleDragUpdate;
  final VoidCallback onBubbleDragEnd;
  final void Function(int index) onBubbleTap;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Semantics(
      container: true,
      label: l10n.shellDockLabel,
      child: Container(
        decoration: BoxDecoration(
          color: scheme.aliases.bgBase,
          border: Border(
            bottom: BorderSide(width: 0.5, color: scheme.borderL2),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: ClipRect(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: (_) => onBubbleDragStart(),
                    onHorizontalDragUpdate: (details) =>
                        onBubbleDragUpdate(details.delta.dx),
                    onHorizontalDragEnd: (_) => onBubbleDragEnd(),
                    child: LayoutBuilder(
                      builder: (context, bubbleConstraints) => Stack(
                        children: [
                          Positioned(
                            left:
                                (bubbleConstraints.maxWidth - kBubbleWidth) /
                                    2 -
                                page * kBubbleStep,
                            top: 0,
                            height: kBubbleHeight,
                            child: Row(
                              children: [
                                for (var i = 0; i < hosts.length; i++)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      right: kBubbleGap,
                                    ),
                                    child: HostBubble(
                                      key: ValueKey<String>(
                                        'host-bubble:${hosts[i].id}',
                                      ),
                                      host: hosts[i],
                                      active: i == page.round(),
                                      live: liveIds.contains(hosts[i].id),
                                      onTap: () => onBubbleTap(i),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SettingsOrb(onTap: onSettings),
              const SizedBox(width: 2),
            ],
          ),
        ),
      ),
    );
  }
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
