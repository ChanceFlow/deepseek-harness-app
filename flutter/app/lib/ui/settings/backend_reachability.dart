/// Host-sheet reachability check: the "Test connection" affordance, its
/// bounded in-progress state, and the classified outcome.
///
/// The probe runs only when the user taps the button — never from a build
/// method. Saving is a separate action that the probe never gates: a host
/// can legitimately be offline while it is configured, so a failed check
/// states that saving is unaffected instead of blocking it.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/dsh_reachability.dart';
import '../../di/providers.dart';
import '../theme/theme.dart';

/// The localized sentence for one probe outcome.
///
/// One outcome, one sentence: the classes are never collapsed for display.
/// [DshProbeResult.ambiguity] adds its caveat on top when the signal could
/// not prove the class.
String describeDshProbeResult(AppLocalizations l10n, DshProbeResult result) {
  return switch (result.outcome) {
    DshProbeOutcome.reachable => l10n.backendProbeReachable,
    DshProbeOutcome.unreachable => l10n.backendProbeUnreachable,
    DshProbeOutcome.certificateNotTrusted =>
      l10n.backendProbeCertificateNotTrusted,
    DshProbeOutcome.authenticationRequired =>
      l10n.backendProbeAuthenticationRequired,
    DshProbeOutcome.notDshSurface => l10n.backendProbeNotDshSurface,
    DshProbeOutcome.unexpectedResponse =>
      result.httpStatus == null
          ? l10n.backendProbeUnenvelopedResponse
          : l10n.backendProbeUnexpectedStatus(result.httpStatus!),
    DshProbeOutcome.unknown => l10n.backendProbeUnknown,
  };
}

/// The edit sheet's reachability row: a "Test connection" button that runs
/// [DshReachabilityProbe.probe] against the typed base URL, then the
/// localized classification.
class BackendReachabilityCheck extends ConsumerStatefulWidget {
  const BackendReachabilityCheck({
    required this.baseUri,
    required this.trustHostCertificate,
    super.key,
  });

  /// The parsed base URL currently in the sheet's URL field; null while the
  /// text is not a valid `http(s)` URL (the button stays disabled).
  final Uri? baseUri;

  /// The sheet's current certificate-trust toggle, passed to the probe so a
  /// test reflects the opt-in before it is saved.
  final bool trustHostCertificate;

  @override
  ConsumerState<BackendReachabilityCheck> createState() =>
      _BackendReachabilityCheckState();
}

class _BackendReachabilityCheckState
    extends ConsumerState<BackendReachabilityCheck> {
  bool _running = false;
  DshProbeResult? _result;

  /// Distinguishes in-flight probes so a slow earlier one cannot overwrite
  /// the result of a later tap.
  int _generation = 0;

  @override
  void didUpdateWidget(BackendReachabilityCheck oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A changed address or trust setting invalidates both the shown
    // classification and any in-flight probe for the old one: bumping the
    // generation makes the old completion a no-op. A rebuild is already
    // scheduled, so the fields are assigned directly.
    if (oldWidget.baseUri != widget.baseUri ||
        oldWidget.trustHostCertificate != widget.trustHostCertificate) {
      _generation++;
      _running = false;
      _result = null;
    }
  }

  Future<void> _probe() async {
    final Uri? uri = widget.baseUri;
    if (uri == null || _running) return;
    final int generation = ++_generation;
    setState(() {
      _running = true;
      _result = null;
    });
    final DshProbeResult result = await ref
        .read(dshReachabilityProbeProvider)
        .probe(uri, trustHostCertificate: widget.trustHostCertificate);
    if (!mounted || generation != _generation) return;
    setState(() {
      _running = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final DshProbeResult? result = _result;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: widget.baseUri == null || _running ? null : _probe,
            icon: const Icon(Icons.network_check, size: 18),
            label: Text(l10n.backendTestConnection),
          ),
        ),
        if (_running) ...<Widget>[
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.backendProbeRunning,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ] else if (result != null) ...<Widget>[
          const SizedBox(height: 8),
          _ProbeOutcomeLine(result: result),
        ],
      ],
    );
  }
}

class _ProbeOutcomeLine extends StatelessWidget {
  const _ProbeOutcomeLine({required this.result});

  final DshProbeResult result;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final bool reachable = result.reachable;
    final Color tone = reachable ? scheme.success : scheme.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                reachable ? Icons.check_circle_outline : Icons.error_outline,
                size: 16,
                color: tone,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                describeDshProbeResult(l10n, result),
                style: theme.textTheme.bodySmall?.copyWith(color: tone),
              ),
            ),
          ],
        ),
        if (result.ambiguity ==
            DshProbeAmbiguity.tlsHandshakeUnspecified) ...<Widget>[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Text(
              l10n.backendProbeAmbiguousTls,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
        if (!reachable) ...<Widget>[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Text(
              l10n.backendProbeSaveNotBlocked,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
