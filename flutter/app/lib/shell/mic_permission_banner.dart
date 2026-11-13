/// The recovery affordance for a permanently denied microphone.
///
/// The host page keeps its own prompt copy, and the shell cannot inject a
/// dialog into it. When Android will no longer show the runtime-permission
/// dialog, this banner is the one way back: it names the host that asked and
/// opens the app's settings, where the permission can be re-allowed. It stays
/// until the user dismisses it or a later ask is granted.
library;

import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/theme.dart';
import 'mic_permission_recovery.dart';
import 'webview_permissions.dart';

/// A top-anchored banner over the shell while a page is blocked from the
/// microphone; nothing when no page is blocked.
class MicPermissionBanner extends ConsumerWidget {
  const MicPermissionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocked = ref.watch(micPermissionRecoveryProvider);
    if (blocked == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Material(
          elevation: 6,
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(kShapeMenuSheet),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.mic_off_outlined, color: scheme.error),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            l10n.micPermissionBlockedTitle,
                            style: DshType.sStrong14.style(
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            l10n.micPermissionBlockedBody(blocked.hostLabel),
                            style: DshType.xs13.style(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => ref
                          .read(micPermissionRecoveryProvider.notifier)
                          .clear(),
                      child: Text(l10n.micPermissionDismiss),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () =>
                          unawaited(WebViewPermissions.openAppSettings()),
                      child: Text(l10n.micPermissionOpenSettings),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
