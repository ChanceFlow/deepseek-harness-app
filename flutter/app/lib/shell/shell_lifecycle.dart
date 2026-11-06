/// The shell's app-wide wiring: the keep-alive watch set, the reconnect and
/// resume sync, the notification permission ask, and the foreground toast.
///
/// These lived on the native root. They are not UI features — they must run
/// with nothing but the shell on screen — so they moved here when the native
/// screens left.
library;

import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../di/providers.dart';
import '../notifications/notification_events.dart';
import '../notifications/notification_permission_gate.dart';
import '../notifications/notification_toast.dart';
import '../theme/theme.dart';

/// Hosts the shell and the notification surface above it.
class ShellLifecycle extends ConsumerStatefulWidget {
  const ShellLifecycle({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<ShellLifecycle> createState() => _ShellLifecycleState();
}

class _ShellLifecycleState extends ConsumerState<ShellLifecycle> {
  AppNotificationEvent? _toastEvent;
  Timer? _toastTimer;
  StreamSubscription<AppNotificationEvent>? _eventSub;
  Stream<AppNotificationEvent>? _subscribedEvents;
  StreamSubscription<bool>? _workSub;
  bool _permissionAskInFlight = false;

  /// Two completions of one session produce equal events, so the banner is
  /// keyed on a counter: the second one must animate in, not update in place.
  int _toastNonce = 0;

  @override
  void initState() {
    super.initState();
    _workSub = ref
        .read(workInFlightChangesProvider)
        .listen((inFlight) => unawaited(_askForNotifications(inFlight)));
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    unawaited(_eventSub?.cancel());
    unawaited(_workSub?.cancel());
    super.dispose();
  }

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
      // An unavailable gate or a refused dialog is not worth an error in the
      // user's face; the permission simply stays unasked.
    } finally {
      _permissionAskInFlight = false;
    }
  }

  void _showToast(AppNotificationEvent event) {
    _toastTimer?.cancel();
    setState(() {
      _toastEvent = event;
      _toastNonce++;
    });
    // The shell has no per-session surface to jump to, and the manifest's
    // launch mode already brings the app forward on a tap.
    _toastTimer = Timer(kNotificationToastHold, _dismissToast);
  }

  void _dismissToast() {
    _toastTimer?.cancel();
    setState(() => _toastEvent = null);
  }

  @override
  Widget build(BuildContext context) {
    // Watched for the app's lifetime: the coordinator owns the keep-alive
    // foreground service that holds the sockets open while work is in flight.
    ref.watch(keepAliveCoordinatorProvider);
    // Immediate reconnect when the platform reports the network back.
    ref.watch(networkReconnectProvider);
    // Re-check connection health and re-sync rosters on foreground.
    ref.watch(appResumeSyncProvider);
    // System-notification copy follows the in-app language choice.
    ref.watch(notificationLocaleSyncProvider);
    // Clear posted rows on launch so the deterministic ids reconcile.
    ref.watch(postedRowsSweepProvider);
    ref.watch(allBackendConnectionsProvider);
    final events = ref.watch(foregroundNotificationEventsProvider);
    if (!identical(events, _subscribedEvents)) {
      _subscribedEvents = events;
      unawaited(_eventSub?.cancel());
      _eventSub = events.listen(_showToast);
    }

    return Stack(
      children: [
        widget.child,
        AnimatedSwitcher(
          duration: DshMotion.durationMedium,
          switchInCurve: DshMotion.curveEnter,
          switchOutCurve: DshMotion.curveExit,
          transitionBuilder: (child, animation) => SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -1),
              end: Offset.zero,
            ).animate(animation),
            child: FadeTransition(opacity: animation, child: child),
          ),
          child: _toastEvent != null
              ? Align(
                  key: ValueKey<int>(_toastNonce),
                  alignment: Alignment.topCenter,
                  child: NotificationToast(
                    event: _toastEvent!,
                    onTap: (event) => _dismissToast(),
                    onDismiss: _dismissToast,
                  ),
                )
              : const SizedBox.shrink(key: ValueKey('no-toast')),
        ),
      ],
    );
  }
}

/// How long a foreground toast stays before auto-dismissing.
const Duration kNotificationToastHold = Duration(seconds: 4);
