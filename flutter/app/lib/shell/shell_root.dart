/// The WebView shell: host pages on one horizontal strip, an exposé drawer,
/// and the settings orb.
///
/// Each enabled backend host renders the dsh web client in its own WebView.
/// The pages are laid side by side at exactly the viewport width; switching
/// translates the strip and never resizes a page, so a host never reflows.
/// The top grabber pushes the strip down by the drawer height; the drawer
/// holds one bubble per host and the settings orb. The page keeps every
/// touch: the shell claims no gesture, because a WebView owns panning and a
/// background listener that mis-classifies three fingers is worse than a
/// handle the user can always find.
///
/// Motion is transform-only: the strip, the drawer and the bubbles are laid
/// out once and moved with `Transform.translate`, and only the layers that
/// move rebuild, never the shell around them.
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
import 'shell_page_strip.dart';
import 'shell_settings.dart';
import 'webview_renderer.dart';

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

/// How long the first renderer-death rebuild waits before replacing the
/// pages; each consecutive death doubles it.
const Duration kRendererDeathBackoff = Duration(milliseconds: 600);

/// The longest a renderer-death rebuild waits; a page that repeatedly kills
/// its renderer then rebuilds no more often than this, not on every report.
const Duration kRendererDeathMaxBackoff = Duration(milliseconds: 5000);

/// How long one renderer death absorbs further reports after its rebuild.
/// Android reports the death once per WebView attached to the dead renderer,
/// and the settle window keeps that burst to one page rebuild.
const Duration kRendererDeathCoalesce = Duration(milliseconds: 1500);

/// Consecutive renderer deaths further apart than this start a fresh backoff
/// streak, so an occasional death never accumulates the long delays.
const Duration kRendererDeathReset = Duration(seconds: 60);

/// The shell root: page strip, exposé drawer, settings.
class ShellRoot extends ConsumerStatefulWidget {
  const ShellRoot({this.hostViewBuilder, this.rendererWatch, super.key});

  /// Null renders the real [HostWebView].
  final HostViewBuilder? hostViewBuilder;

  /// The renderer-death source; null creates a [PlatformRendererWatch].
  ///
  /// Tests inject a watch that emits [RendererGone] values directly, so the
  /// recovery path runs without a platform channel. The shell reads the watch
  /// in [initState], keeps it for its lifetime, and disposes it with the
  /// shell.
  final RendererWatch? rendererWatch;

  @override
  ConsumerState<ShellRoot> createState() => _ShellRootState();
}

class _ShellRootState extends ConsumerState<ShellRoot>
    with TickerProviderStateMixin {
  /// The host the user last switched to; null follows the registry's choice.
  ///
  /// A selection made outside this shell (a notification tap selects its host
  /// in the registry) wins: [build] drops [_selectedId] whenever the
  /// registry's active host has moved away from the one this local switch
  /// started from.
  String? _selectedId;

  /// The registry's active host at the moment [_selectedId] was set.
  String? _selectionBaseActive;

  /// Which hosts hold a live WebView. Beyond the policy's budget the
  /// least-recently-used page is released and reloads on return.
  final HostPool _pool = HostPool();

  /// The live page per host id, and the URL each page loaded.
  final Map<String, Widget> _pages = <String, Widget>{};
  final Map<String, Uri> _pageUrls = <String, Uri>{};

  /// Whether the drawer is showing.
  bool _exposed = false;

  /// Drives the drawer's 0..1 progress.
  late final AnimationController _expose = AnimationController(
    vsync: this,
    duration: DshMotion.durationMedium,
  );

  /// The page the strip rests on when no sweep is running; 0 is the first
  /// host. Written by a settled interaction, never by a frame callback.
  double _page = 0;

  /// The last registry-active host the strip aligned itself to; a change
  /// outside a sweep re-seats the strip, a sweep wins over it.
  String? _lastActiveId;

  /// The sweep animation between two whole pages.
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: _sweepDuration(1),
  );
  double _sweepBegin = 0;
  double _sweepEnd = 0;

  /// Drag state for the bubble row.
  double _dragStartPage = 0;
  double _dragDistance = 0;

  /// The renderer-death source and its subscription; both live as long as the
  /// shell.
  RendererWatch? _watch;
  StreamSubscription<RendererGone>? _rendererReports;

  /// True from a death report until the rebuild's settle window closes; every
  /// report arriving in between belongs to the same renderer death and is
  /// dropped.
  bool _rendererDeathPending = false;

  /// Fires the coalesced rebuild once the death's backoff has elapsed.
  Timer? _rendererDeathBackoffTimer;

  /// Ends the coalescing window after the rebuild.
  Timer? _rendererDeathSettleTimer;

  /// Consecutive renderer deaths, each within [kRendererDeathReset] of the
  /// previous one. The count picks the backoff, so a page that kills its
  /// renderer every time reloads less and less often.
  int _consecutiveRendererDeaths = 0;

  /// When the last death report arrived; a quiet gap over
  /// [kRendererDeathReset] starts a new streak.
  DateTime? _lastRendererDeathAt;

  /// Increments on every renderer-death rebuild. It is part of each
  /// [HostWebView]'s key, so a rebuild replaces the page's State and the dead
  /// WebView with a fresh one instead of updating the dead controller.
  int _pageEpoch = 0;

  @override
  void initState() {
    super.initState();
    final watch = widget.rendererWatch ?? PlatformRendererWatch();
    _watch = watch;
    _rendererReports = watch.events.listen(_onRendererDeath);
  }

  @override
  void dispose() {
    _rendererDeathBackoffTimer?.cancel();
    _rendererDeathSettleTimer?.cancel();
    unawaited(_rendererReports?.cancel());
    _watch?.dispose();
    _expose.dispose();
    _sweep.dispose();
    super.dispose();
  }

  /// Handles one renderer-death report.
  ///
  /// Every report replaces the same pages: `didCrash` and `priority` describe
  /// the platform's death, and recovery does not branch on them. The first
  /// report of a death starts the backoff and marks the death pending; the
  /// rest of the burst is dropped. The rebuild runs once the backoff elapses
  /// and the settle timer then clears the pending flag, so the next death
  /// starts a new cycle.
  void _onRendererDeath(RendererGone report) {
    if (!mounted || _rendererDeathPending) return;
    final now = DateTime.now();
    final last = _lastRendererDeathAt;
    if (last == null || now.difference(last) > kRendererDeathReset) {
      _consecutiveRendererDeaths = 0;
    }
    _lastRendererDeathAt = now;
    _consecutiveRendererDeaths += 1;
    _rendererDeathPending = true;
    _recordRendererDeath(report);
    _rendererDeathBackoffTimer = Timer(
      _rendererDeathDelay(),
      _rebuildDeadPages,
    );
  }

  /// Leaves the diagnostic trail for one renderer death.
  ///
  /// Only the report that flips [_rendererDeathPending] reaches here; the
  /// coalesced duplicates that follow the same death leave no entry. A dead
  /// renderer is a warning about the page, not an app error, so the entry is
  /// [ErrorLogLevel.warning], never fatal.
  void _recordRendererDeath(RendererGone report) {
    final collector = ErrorLogCollector.instance;
    collector.addBreadcrumb(
      'renderer gone: didCrash=${report.didCrash} '
      'priority=${report.priority} livePages=${_pool.liveIds.length}',
      level: 'warn',
    );
    collector.captureError(
      'WebView renderer gone: didCrash=${report.didCrash} '
      'priority=${report.priority}',
      level: ErrorLogLevel.warning,
      type: 'webview-renderer-gone',
      context: <String, Object?>{
        'didCrash': report.didCrash,
        'priority': report.priority,
        'livePages': _pool.liveIds.length,
        'consecutiveDeaths': _consecutiveRendererDeaths,
        'epoch': _pageEpoch,
      },
    );
  }

  /// 600 ms for the first death, doubled for each consecutive one, capped at
  /// [kRendererDeathMaxBackoff].
  Duration _rendererDeathDelay() {
    final exponent = math.min(_consecutiveRendererDeaths - 1, 10);
    final milliseconds = math.min(
      kRendererDeathBackoff.inMilliseconds * (1 << exponent),
      kRendererDeathMaxBackoff.inMilliseconds,
    );
    return Duration(milliseconds: milliseconds);
  }

  /// Drops every live page so `_syncPages` builds them again: a page whose
  /// renderer died must not keep its dead WebView. The bumped epoch is part of
  /// each [HostWebView]'s key, so the replacement page gets a fresh State.
  void _rebuildDeadPages() {
    _rendererDeathBackoffTimer = null;
    if (!mounted) return;
    setState(() {
      _pageEpoch += 1;
      _pages.clear();
      _pageUrls.clear();
    });
    _rendererDeathSettleTimer = Timer(kRendererDeathCoalesce, () {
      _rendererDeathSettleTimer = null;
      _rendererDeathPending = false;
    });
  }

  Duration _sweepDuration(int pages) =>
      Duration(milliseconds: (240 + 60 * (pages - 1)).clamp(240, 600));

  double get _exposeT => Curves.easeOutCubic.transform(_expose.value);

  /// The page the strip shows this frame: the sweep's interpolated value
  /// while it runs, the settled page otherwise. Derived, never assigned, so
  /// a frame costs no `setState`.
  double get _displayedPage {
    if (_sweep.isAnimating) {
      final t = Curves.easeInOutCubic.transform(_sweep.value);
      return lerpDouble(_sweepBegin, _sweepEnd, t)!;
    }
    return _page;
  }

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
    final from = _displayedPage;
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
        setState(() => _page = _sweepEnd);
        if (collapse) _closeExpose();
      }),
    );
  }

  /// The whole page the strip currently rests on (or is nearest to).
  int _nearestPage(int hostCount) =>
      _displayedPage.round().clamp(0, hostCount == 0 ? 0 : hostCount - 1);

  void _select(BackendConfig host) {
    if (_selectedId == host.id) return;
    setState(() {
      _selectionBaseActive = ref
          .read(backendRegistryStateProvider)
          .value
          ?.activeId;
      _selectedId = host.id;
    });
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
    if (_selectedId != null && registry?.activeId != _selectionBaseActive) {
      _selectedId = null;
    }
    final active =
        hosts
            .where((host) => host.id == (_selectedId ?? registry?.activeId))
            .firstOrNull ??
        hosts.firstOrNull;
    final builder = widget.hostViewBuilder;
    _syncPages(hosts, active?.id, (BackendConfig host) {
      if (builder != null) return builder(context, host);
      // The key carries the loaded URL and the renderer-death epoch: a host
      // whose URL changed, or whose renderer died, must build a new State, not
      // update a controller pointing at the old page.
      return HostWebView(
        key: ValueKey<String>(
          'host-page:${host.id}:$_pageEpoch:${host.baseUri}',
        ),
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

    final pages = [
      for (final host in hosts) _pages[host.id] ?? const _SleepingHostPage(),
    ];
    final liveIds = _pool.liveIds.toSet();

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
                  if (hosts.isNotEmpty)
                    Positioned.fill(
                      child: IgnorePointer(
                        ignoring: _exposed,
                        child: AnimatedBuilder(
                          animation: Listenable.merge([_expose, _sweep]),
                          builder: (context, _) => ShellPageStrip(
                            pages: pages,
                            position: _displayedPage,
                            pageWidth: width,
                            verticalOffset: kExposeDrawerHeight * _exposeT,
                          ),
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
                  if (hosts.isEmpty)
                    Positioned.fill(
                      child: _EmptyShell(
                        message: l10n.noHostsTitle,
                        action: l10n.addBackend,
                        onAction: _openSettings,
                      ),
                    ),
                  if (!_exposed && hosts.isNotEmpty)
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
                    child: AnimatedBuilder(
                      animation: Listenable.merge([_expose, _sweep]),
                      builder: (context, _) => ClipRect(
                        child: Transform.translate(
                          offset: Offset(
                            0,
                            -(1 - _exposeT) * kExposeDrawerHeight,
                          ),
                          child: SizedBox(
                            width: width,
                            height: kExposeDrawerHeight,
                            child: _ExposeDrawer(
                              hosts: hosts,
                              liveIds: liveIds,
                              page: _displayedPage,
                              onBubbleDragStart: () {
                                _dragStartPage = _displayedPage;
                                _dragDistance = 0;
                              },
                              onBubbleDragUpdate: (dx) {
                                _dragDistance += dx;
                                setState(() {
                                  _page =
                                      (_dragStartPage -
                                              _dragDistance / kBubbleStep)
                                          .clamp(
                                            0,
                                            math.max(0, hosts.length - 1),
                                          )
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

/// The 32×4 handle that opens the drawer; the page keeps every gesture.
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
                      builder: (context, bubbleConstraints) => Align(
                        alignment: Alignment.topLeft,
                        child: Transform.translate(
                          offset: Offset(
                            (bubbleConstraints.maxWidth - kBubbleWidth) / 2 -
                                page * kBubbleStep,
                            0,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
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
