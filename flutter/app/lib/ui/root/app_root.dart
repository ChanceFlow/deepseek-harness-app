/// App root — three bottom destinations (Places): the conversation
/// work surface, the workspace browser, and host configuration.
/// Session-scoped tools (Models/Goals/Subagents) live in the chat
/// sidebar's tools region, mirroring the web's context embedding.
/// The selected destination is [appDestinationProvider] state — the
/// bottom bar and the chat sidebar's settings trigger switch it.
///
/// Also hosts the foreground notification toast: it listens to the merged
/// notification stream and surfaces each event as a tappable banner that
/// navigates to the producing session, and it navigates on system-
/// notification taps (running-app taps plus cold-start launches).
library;

import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import '../../notifications/notification_events.dart' show AppNotificationEvent;
import '../../notifications/notification_permission_gate.dart';
import '../../notifications/notification_toast.dart';
import '../../notifications/system_notifier.dart' show NotificationTarget;
import '../chat/chat_screen.dart';
import '../chat/chat_ui_state.dart' show SelectSession;
import '../settings/settings_screen.dart';
import '../theme/theme.dart';
import '../workspace/workspace_screen.dart';
import 'app_destination.dart';

/// How long a foreground toast stays before auto-dismissing.
const Duration kNotificationToastHold = Duration(seconds: 4);

class AppRoot extends ConsumerStatefulWidget {
  const AppRoot({super.key});

  @override
  ConsumerState<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends ConsumerState<AppRoot> {
  AppNotificationEvent? _toastEvent;
  Timer? _toastTimer;
  StreamSubscription<NotificationTarget>? _targetSub;
  StreamSubscription<bool>? _workSub;

  /// The foreground channel subscription and the stream it is attached to.
  /// The merged provider rebuilds when the backend registry changes, so the
  /// listener follows the new stream instead of holding a dead one.
  StreamSubscription<AppNotificationEvent>? _eventSub;
  Stream<AppNotificationEvent>? _subscribedEvents;

  bool _permissionAskInFlight = false;

  /// Counts toast arrivals. Two completions of the same session produce
  /// equal [AppNotificationEvent]s, so keying the banner on the event alone
  /// would render the second one in place — no entry animation, and to the
  /// user no sign that anything arrived.
  int _toastNonce = 0;

  @override
  void initState() {
    super.initState();
    // Taps on posted notifications are events, so they ride the stream
    // directly instead of a provider state that would dedupe a repeat tap
    // on the same session (its ongoing row and its completion notice
    // share one payload). The cold-start case stays a one-shot pull below:
    // the process was not alive to observe that tap.
    _targetSub = ref
        .read(systemNotificationTargetsProvider)
        .listen(_navigateToTarget);
    // The notification permission is asked for once, the first time agent
    // work is actually in flight: the ask lands while the user can see why
    // notifications matter, instead of on a first launch with nothing on
    // screen. Android stops showing its own dialog after a couple of
    // declines, so the rationale comes first.
    _workSub = ref
        .read(workInFlightChangesProvider)
        .listen((inFlight) => unawaited(_askForNotifications(inFlight)));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // A cold start from a notification tap navigates after the first
      // frame once the registry is available.
      final launch = ref.read(systemNotifierProvider).takeLaunchTarget();
      if (launch != null) unawaited(_navigateToTarget(launch));
    });
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    unawaited(_targetSub?.cancel());
    unawaited(_workSub?.cancel());
    unawaited(_eventSub?.cancel());
    super.dispose();
  }

  /// Explains why notifications are wanted, then spends the one system ask.
  ///
  /// Only the first in-flight transition reaches the prompt, and only if this
  /// device has not already seen the explanation
  /// ([NotificationPermissionGate]): re-asking after a decline would burn
  /// Android's remaining dialog for nothing.
  Future<void> _askForNotifications(bool inFlight) async {
    if (!inFlight || _permissionAskInFlight) return;
    _permissionAskInFlight = true;
    try {
      final notifier = ref.read(systemNotifierProvider);
      if (!notifier.permissionGranted) return;
      final gate = await ref.read(notificationPermissionGateProvider.future);
      if (!mounted || gate.prompted) return;
      await gate.markPrompted();
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      if (l10n == null) return;
      final allow = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.notificationPermissionTitle),
          content: Text(l10n.notificationPermissionBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.notificationPermissionLater),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.notificationPermissionAllow),
            ),
          ],
        ),
      );
      if (allow != true) return;
      await notifier.ensurePermissionRequested();
    } catch (_) {
      // An unavailable one-shot gate or a refused dialog is never worth an
      // error in the user's face; the permission simply stays unasked.
    } finally {
      _permissionAskInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final destination = ref.watch(appDestinationProvider);
    // Watched for the app's lifetime: the coordinator owns the keep-alive
    // foreground service that holds the connection open while agent work is
    // in flight, and it needs the enabled-backend watch set to stay live.
    ref.watch(keepAliveCoordinatorProvider);
    // Also watched for the app's lifetime: it turns the platform's
    // network-availability hints into an immediate reconnect for every
    // enabled backend instead of waiting out the loss backoff.
    ref.watch(networkReconnectProvider);
    // Keeps system-notification copy in step with the in-app language
    // choice; notification copy is composed outside the widget tree.
    ref.watch(notificationLocaleSyncProvider);
    // Foreground events become the toast; a later event replaces the one on
    // screen. Watching the stream here keeps every backend's notification
    // center alive for the app's lifetime, and re-attaches the listener
    // whenever that provider hands over a new stream. Subscribing directly
    // (rather than through a state provider) is what lets a repeated event —
    // two completions of one session are equal events — reach the banner at
    // all.
    final events = ref.watch(foregroundNotificationEventsProvider);
    if (!identical(events, _subscribedEvents)) {
      _subscribedEvents = events;
      unawaited(_eventSub?.cancel());
      _eventSub = events.listen(_showToast);
    }
    // System-notification taps (running-app taps and post-launch arrivals)
    // navigate via the stream subscription armed in initState.

    return Scaffold(
      // AnimatedIndexedStack keeps every destination's state alive across tab
      // switches with smooth cross-fading, preventing jarring layout hard-cuts.
      body: Stack(
        children: [
          AnimatedIndexedStack(
            index: destination.index,
            children: const [ChatRoute(), WorkspaceRoute(), SettingsRoute()],
          ),
          // The toast rides a top overlay with smooth slide-and-fade entry/exit.
          AnimatedSwitcher(
            duration: DshMotion.durationMedium,
            switchInCurve: DshMotion.curveEnter,
            switchOutCurve: DshMotion.curveExit,
            transitionBuilder: (child, animation) {
              return SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -1.0),
                  end: Offset.zero,
                ).animate(animation),
                child: FadeTransition(opacity: animation, child: child),
              );
            },
            child: _toastEvent != null
                ? Align(
                    key: ValueKey<int>(_toastNonce),
                    alignment: Alignment.topCenter,
                    child: NotificationToast(
                      event: _toastEvent!,
                      onTap: _navigateToEvent,
                      onDismiss: _dismissToast,
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('no-toast')),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: destination.index,
        onDestinationSelected: (index) => ref
            .read(appDestinationProvider.notifier)
            .select(AppDestination.values[index]),
        destinations: [
          for (final destination in AppDestination.values)
            NavigationDestination(
              icon: Icon(destination.icon),
              label: destination.label(AppLocalizations.of(context)!),
            ),
        ],
      ),
    );
  }

  void _showToast(AppNotificationEvent event) {
    _toastTimer?.cancel();
    setState(() {
      _toastEvent = event;
      _toastNonce++;
    });
    _toastTimer = Timer(kNotificationToastHold, _dismissToast);
  }

  void _dismissToast() {
    _toastTimer?.cancel();
    _toastTimer = null;
    if (_toastEvent == null) return;
    setState(() => _toastEvent = null);
  }

  void _navigateToEvent(AppNotificationEvent event) {
    _dismissToast();
    unawaited(
      _navigateToTarget(
        NotificationTarget(
          backendId: event.backendId,
          sessionId: event.sessionId,
        ),
      ),
    );
  }

  /// Jumps to [target]'s session: switches the active backend when needed,
  /// selects the session on that backend's controller (which opens it) and
  /// asks the transcript to land on the newest content, then lands on the
  /// chat destination.
  ///
  /// The registry is awaited rather than read as a snapshot: a target whose
  /// backend was removed must be dropped, and deciding from a not-yet-loaded
  /// registry falls through to the controller family — which reconnects the
  /// released host this guard exists to avoid. Awaiting also puts the
  /// backend switch (a synchronous state write) before the selection, which
  /// the previous fire-and-forget ordering did not guarantee.
  Future<void> _navigateToTarget(NotificationTarget target) async {
    final BackendRegistryController registry;
    try {
      registry = await ref.read(backendRegistryProvider.future);
    } catch (_) {
      // A destination that cannot be resolved is dropped; a notification
      // tap never raises an error of its own.
      return;
    }
    if (!mounted) return;
    if (!registry.state.enabledBackends.any(
      (backend) => backend.id == target.backendId,
    )) {
      return;
    }
    if (ref.read(activeBackendIdProvider).value != target.backendId) {
      registry.onAction(SelectBackend(target.backendId));
      if (!mounted) return;
    }
    ref
        .read(chatControllerProvider(target.backendId))
        .onAction(SelectSession(target.sessionId, landAtLatest: true));
    ref.read(appDestinationProvider.notifier).select(AppDestination.chat);
  }
}

/// An [IndexedStack] that smoothly fades in on destination changes while
/// keeping all destinations mounted and their states intact.
class AnimatedIndexedStack extends StatefulWidget {
  const AnimatedIndexedStack({
    required this.index,
    required this.children,
    this.duration = DshMotion.durationShort,
    this.curve = DshMotion.curveEnter,
    super.key,
  });

  final int index;
  final List<Widget> children;
  final Duration duration;
  final Curve curve;

  @override
  State<AnimatedIndexedStack> createState() => _AnimatedIndexedStackState();
}

class _AnimatedIndexedStackState extends State<AnimatedIndexedStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..value = 1.0;

  late final Animation<double> _animation = CurvedAnimation(
    parent: _controller,
    curve: widget.curve,
  );

  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.index;
  }

  @override
  void didUpdateWidget(AnimatedIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != _currentIndex) {
      _currentIndex = widget.index;
      if (DshMotion.isReducedMotion(context)) {
        _controller.value = 1.0;
      } else {
        _controller.forward(from: 0.0);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: IndexedStack(index: _currentIndex, children: widget.children),
    );
  }
}
