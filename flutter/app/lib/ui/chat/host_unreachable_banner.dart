/// Host-unreachable banner — the one place the chat surface reports that its
/// host is unreachable.
///
/// The workspace and settings tabs carry a per-host connection dot; the chat
/// tab owns the conversation, so a dropped host has to be visible where the
/// blocked work is. The banner names the host, offers the manual reconnect,
/// and can be dismissed for the current outage (a fresh outage or a host
/// switch re-arms it).
///
/// The reconnect callback is supplied by the route that owns the DI seam;
/// this widget only knows a host label and a [ConnectionPhase], keeping the
/// adapter's connection manager out of the UI layer.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/connection_state.dart';
import 'package:flutter/material.dart';

class HostUnreachableBanner extends StatefulWidget {
  const HostUnreachableBanner({
    required this.hostLabel,
    required this.phase,
    super.key,
    this.onReconnect,
  });

  /// Human label for the host that cannot be reached.
  final String hostLabel;

  /// Live connection phase; null (state not yet published) renders nothing.
  final ConnectionPhase? phase;

  /// Manual reconnect; null renders the notice without the action.
  final VoidCallback? onReconnect;

  @override
  State<HostUnreachableBanner> createState() => _HostUnreachableBannerState();
}

class _HostUnreachableBannerState extends State<HostUnreachableBanner> {
  bool _dismissed = false;

  @override
  void didUpdateWidget(covariant HostUnreachableBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A host switch is a different outage; a reconnect that succeeds clears
    // the dismissal so the next failure is reported again.
    if (oldWidget.hostLabel != widget.hostLabel ||
        (widget.phase == ConnectionPhase.connected &&
            oldWidget.phase != ConnectionPhase.connected)) {
      _dismissed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final phase = widget.phase;
    // Connecting is the startup path, not a failure; only a lost or absent
    // generation is worth a banner.
    if (_dismissed ||
        (phase != ConnectionPhase.disconnected &&
            phase != ConnectionPhase.reconnecting)) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Material(
      color: scheme.errorContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
          child: Row(
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 18,
                color: scheme.onErrorContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.connectionHostUnreachable(widget.hostLabel),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onErrorContainer,
                  ),
                ),
              ),
              if (widget.onReconnect case final reconnect?)
                TextButton(
                  onPressed: reconnect,
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.onErrorContainer,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(l10n.reconnect),
                ),
              IconButton(
                tooltip: l10n.dismiss,
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _dismissed = true),
                icon: Icon(
                  Icons.close,
                  size: 18,
                  color: scheme.onErrorContainer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
