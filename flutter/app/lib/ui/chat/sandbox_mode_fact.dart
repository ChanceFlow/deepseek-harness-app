/// Sandbox-mode wording — the labels and tooltip line for a session's
/// decoded `sandbox/mode` fact.
///
/// A session's effective sandbox mode is a durable log-only fact
/// (`reference/deepseek-harness/packages/sandbox/sandbox-policy/src/
/// session-mode.ts`), folded by the adapter into `SandboxModeFact` and
/// published through `observeSandboxMode`. The reference web client has no
/// surface for it: the permission preset chip happens to name the same string,
/// because a preset composes a sandbox mode plus an approval policy.
///
/// The mobile seat is the access chip's tooltip (`PermissionSelectChip
/// .tooltipDetail`) rather than a chip of its own. The effective mode can
/// differ from the preset's own composition once the host switches it, so the
/// fact needs stating; a second chip does not fit the action row's left group
/// on a 320dp dock, and a seat that appears only once the fact arrives would
/// read as "the mode just changed".
///
/// Honesty rule: a null [fact] means no `sandbox/mode` event has folded and the
/// deployment default applies. That default is a host-side composition this
/// client cannot read, so the line says the fact is unreported — it never
/// names a mode and never goes blank.
library;

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/sandbox.dart';
import 'package:flutter/material.dart';

/// The tooltip line stating the session's confinement fact.
String sandboxModeDetail(SandboxModeFact? fact, AppLocalizations l10n) {
  final mode = fact?.mode;
  return mode == null
      ? l10n.sandboxModeUnknownTooltip
      : l10n.sandboxModeTooltip(sandboxModeLabel(mode, l10n));
}

/// Confinement glyph per mode; null (unreported) is the plain shield.
IconData sandboxModeGlyph(SandboxMode? mode) => switch (mode) {
  SandboxMode.readOnly => Icons.lock_outline,
  SandboxMode.workspaceWrite => Icons.folder_outlined,
  SandboxMode.dangerFullAccess => Icons.gpp_maybe_outlined,
  null => Icons.shield_outlined,
};

/// Localized mode name. The wire literal is the kebab-case machine name; the
/// label is the same capitalization the access chip uses.
String sandboxModeLabel(SandboxMode mode, AppLocalizations l10n) =>
    switch (mode) {
      SandboxMode.readOnly => l10n.sandboxModeReadOnly,
      SandboxMode.workspaceWrite => l10n.sandboxModeWorkspaceWrite,
      SandboxMode.dangerFullAccess => l10n.sandboxModeDangerFullAccess,
    };
