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
import '../../notifications/notification_toast.dart';
import '../../notifications/system_notifier.dart' show NotificationTarget;
import '../chat/chat_screen.dart';
import '../chat/chat_ui_state.dart' show SelectSession;
import '../settings/settings_screen.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // A cold start from a notification tap navigates after the first
      // frame once the registry is available.
      final launch = ref.read(systemNotifierProvider).takeLaunchTarget();
      if (launch != null) _navigateToTarget(launch);
    });
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final destination = ref.watch(appDestinationProvider);
    // Foreground events become the toast; a later event replaces the one
    // on screen. The merged provider is watched here so every backend's
    // notification center stays alive for the app's lifetime.
    ref.listen<AsyncValue<AppNotificationEvent>>(
      foregroundNotificationEventsProvider,
      (previous, next) {
        final event = next.value;
        if (event != null) _showToast(event);
      },
    );
    // System-notification taps (running-app taps and post-launch arrivals)
    // navigate to the tapped session.
    ref.listen<AsyncValue<NotificationTarget>>(
      systemNotificationTargetsProvider,
      (previous, next) {
        final target = next.value;
        if (target != null) _navigateToTarget(target);
      },
    );

    return Scaffold(
      // IndexedStack keeps every destination's state alive across tab
      // switches — the composer draft, scroll positions, and expansion
      // states survive leaving and returning to a tab (a switch here
      // would unmount the route and drop them).
      body: Stack(
        children: [
          IndexedStack(
            index: destination.index,
            children: const [ChatRoute(), WorkspaceRoute(), SettingsRoute()],
          ),
          // The toast rides a top overlay above every destination.
          if (_toastEvent case final event?)
            Align(
              alignment: Alignment.topCenter,
              child: NotificationToast(
                event: event,
                onTap: _navigateToEvent,
                onDismiss: _dismissToast,
              ),
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
    setState(() => _toastEvent = event);
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
    _navigateToTarget(
      NotificationTarget(
        backendId: event.backendId,
        sessionId: event.sessionId,
      ),
    );
  }

  /// Jumps to [target]'s session: switches the active backend when needed,
  /// selects the session on that backend's controller (which opens it), and
  /// lands on the chat destination. A target whose backend is gone or
  /// disabled is dropped: its session belongs to a released connection
  /// (reading the controller family would reconnect the host).
  void _navigateToTarget(NotificationTarget target) {
    final registry = ref.read(backendRegistryStateProvider).value;
    if (registry != null &&
        !registry.enabledBackends.any(
          (backend) => backend.id == target.backendId,
        )) {
      return;
    }
    final activeBackendId = ref.read(activeBackendIdProvider).value;
    if (activeBackendId != target.backendId) {
      unawaited(
        ref
            .read(backendRegistryProvider.future)
            .then(
              (registry) => registry.onAction(SelectBackend(target.backendId)),
            ),
      );
    }
    ref
        .read(chatControllerProvider(target.backendId))
        .onAction(SelectSession(target.sessionId));
    ref.read(appDestinationProvider.notifier).select(AppDestination.chat);
  }
}
