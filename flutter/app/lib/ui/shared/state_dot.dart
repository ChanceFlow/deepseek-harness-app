/// The client's one state dot — the web StateDot port: a translucent halo
/// under a solid core, both riding the state color. Session-tree rows,
/// the jobs list, and the subagent catalog all wear this one glyph; a
/// state color is always a themed color — the `ColorScheme` roles
/// `primary` / `error` or the `theme.dart` non-role colors `success` /
/// `warning` — never a call-site value. Hand-built chrome: Material 3 ships
/// no state-dot component (the standing reason recorded by
/// [the sidebar status-dot note](../../../../../.agents/notes/implemented/feature/2026-08-20-sidebar-archive-priority-pending.md)
/// and the componentization note this file consolidates under).
library;

import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// Web StateDot halo wash under the core.
const double kStateDotHaloAlpha = 0.1;

/// Web StateDot core diameter as a fraction of the dot's box.
const double kStateDotCoreRatio = 0.6;

/// The five states a dot can carry. `warning` — waiting on the user —
/// rides the web palette's warn token (`scheme.warning`, amber), kept
/// apart from `error`'s red: the reference web defines
/// `--dsw-alias-state-warn-primary` (design-platform.css:230/:322) and the
/// warning StateDot wears it (StateDot.module.css:37-39), so red stays the
/// exclusive color of failure. `disabled` — switched off by choice, not
/// unreachable — rides the neutral `onSurfaceVariant` role.
enum StateDotState { ongoing, done, warning, error, disabled }

/// Halo + solid core riding the state color: blue ongoing (running),
/// green done, amber warning, red error, grey disabled (off by choice).
class StateDot extends StatelessWidget {
  const StateDot({required this.state, super.key, this.size = 10});

  final StateDotState state;
  final double size;

  static Color _colorFor(ColorScheme scheme, StateDotState state) =>
      switch (state) {
        StateDotState.ongoing => scheme.primary,
        StateDotState.done => scheme.success,
        StateDotState.warning => scheme.warning,
        StateDotState.error => scheme.error,
        StateDotState.disabled => scheme.onSurfaceVariant,
      };

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(Theme.of(context).colorScheme, state);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: color.withValues(alpha: kStateDotHaloAlpha),
              shape: BoxShape.circle,
            ),
          ),
          Center(
            child: Container(
              width: size * kStateDotCoreRatio,
              height: size * kStateDotCoreRatio,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
        ],
      ),
    );
  }
}
