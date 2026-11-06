/// The exposé's drawer: one bubble per host and the settings orb.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/backend.dart';
import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// One bubble's fixed footprint; the strip's step is this plus [kBubbleGap].
const double kBubbleWidth = 108;
const double kBubbleHeight = 64;
const double kBubbleGap = 8;
const double kBubbleStep = kBubbleWidth + kBubbleGap;
const double kSettingsOrbSize = 40;

/// One host in the drawer. Not a live thumbnail: the page is a platform view
/// and cannot be rendered twice, so the bubble carries identity and state.
class HostBubble extends StatelessWidget {
  const HostBubble({
    required this.host,
    required this.active,
    required this.live,
    required this.onTap,
    super.key,
  });

  final BackendConfig host;
  final bool active;

  /// Whether this host currently holds a live page (inside the pool budget).
  final bool live;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Semantics(
      button: true,
      selected: active,
      label:
          '${host.label}, ${host.baseUri.authority}, '
          '${live ? l10n.shellHostLive : l10n.shellHostSleeping}',
      child: GestureDetector(
        // The whole bubble is the target, not just its text runs.
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: kBubbleWidth,
          height: kBubbleHeight,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            color: scheme.bgLayer2,
            borderRadius: BorderRadius.circular(kRadiusMd),
            border: Border.all(
              width: active ? 2 : 0.5,
              color: active ? scheme.stateBusinessPrimary : scheme.borderL4,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: live
                          ? scheme.stateSuccessPrimary
                          : scheme.labelCaption,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      host.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DshType.xsStrong13.style(
                        color: scheme.labelPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                host.baseUri.authority,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DshType.xxxs11.style(color: scheme.labelTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The drawer's right-end button: the native settings page.
class SettingsOrb extends StatelessWidget {
  const SettingsOrb({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Tooltip(
      message: l10n.shellSettingsTooltip,
      child: Semantics(
        button: true,
        label: l10n.shellSettingsTooltip,
        child: InkResponse(
          radius: kSettingsOrbSize / 2,
          onTap: onTap,
          child: Container(
            width: kSettingsOrbSize,
            height: kSettingsOrbSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.bgLayer2,
              border: Border.all(width: 0.5, color: scheme.borderL4),
            ),
            child: Icon(Icons.tune, size: 20, color: scheme.labelPrimary),
          ),
        ),
      ),
    );
  }
}
