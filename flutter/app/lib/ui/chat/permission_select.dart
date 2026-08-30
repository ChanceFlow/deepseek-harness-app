/// Access-mode chip — mobile port of the web PermissionSelect seat
/// (ui-conversation skeleton/PermissionSelect.tsx): a compact chip in
/// the composer's tools row showing the current permission preset,
/// opening the menu-surface sheet of switchable presets. Selecting one
/// submits the `/permission` host command; full access passes a risk
/// confirmation first, and a `custom` effective value renders the chip
/// read-only (nothing to switch to).
library;

import 'dart:async';

import 'package:app/l10n/app_localizations.dart';
import 'package:domain/model/permission_select.dart';
import 'package:flutter/material.dart';

import '../shared/menu_sheet.dart';
import 'chat_ui_state.dart';

/// The one preset the host gates behind acknowledgement.
const String _kFullAccess = 'danger-full-access';

/// Web `displayName`: kebab-case machine names render as title-case
/// labels (`workspace-write` → `Workspace Write`); non-kebab
/// host-configured names pass through.
String permissionDisplayName(String name) {
  if (!RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$').hasMatch(name)) return name;
  return name
      .split('-')
      .map(
        (word) =>
            word.isEmpty ? word : word[0].toUpperCase() + word.substring(1),
      )
      .join(' ');
}

/// Web `optionLabel`: the full-access machine name carries the product
/// label `Full access`; every other row title-cases its published name.
String permissionOptionLabel(
  PermissionPresetOption option,
  AppLocalizations l10n,
) {
  return option.value == _kFullAccess
      ? l10n.fullAccessOption
      : permissionDisplayName(option.name);
}

/// Shield glyph for a permission value (web design set 1556: check =
/// read-only, pencil = workspace write, exclamation = full access);
/// host-configured values outside the set get the plain shield.
IconData permissionGlyph(String value) => switch (value) {
  'read-only' => Icons.verified_user_outlined,
  'workspace-write' => Icons.security,
  _kFullAccess => Icons.gpp_maybe_outlined,
  _ => Icons.shield_outlined,
};

/// The composer's access chip. Hidden when [value] is null (key absence
/// = permission-less host) — the caller also hides it without a
/// session.
class PermissionSelectChip extends StatelessWidget {
  const PermissionSelectChip({
    required this.value,
    required this.locked,
    required this.onAction,
    super.key,
  });

  final PermissionSelect value;

  /// Seat lock: a locked composer (no session / send in flight) offers
  /// no switching.
  final bool locked;

  /// Command dispatch — selection rides the existing send path.
  final void Function(ChatAction) onAction;

  String get _currentValue => value.currentValue;

  String _label(AppLocalizations l10n) {
    final current = value.currentOption;
    return current == null
        ? permissionDisplayName(_currentValue)
        : permissionOptionLabel(current, l10n);
  }

  /// A `custom` effective value has no switch target (the host composed
  /// it from settings this surface cannot edit) — the chip stays
  /// read-only.
  bool get _readOnly => _currentValue == 'custom';

  void _submit(String preset) {
    onAction(SendPrompt('/permission $preset'));
  }

  Future<void> _open(BuildContext context) {
    return showMenuSheet<void>(
      context,
      maxHeight: 360,
      builder: (sheetContext) => _PermissionSheet(
        value: value,
        onPick: (preset) {
          Navigator.of(sheetContext).pop();
          _choose(sheetContext, preset);
        },
      ),
    );
  }

  /// Web `choose`: re-picking the current value is a no-op; full access
  /// routes through the risk confirmation before anything is submitted.
  void _choose(BuildContext context, String preset) {
    if (preset == _currentValue) return;
    if (preset == _kFullAccess) {
      unawaited(_confirmFullAccess(context, preset));
      return;
    }
    _submit(preset);
  }

  Future<void> _confirmFullAccess(BuildContext context, String preset) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => _FullAccessDialog(
        onEnable: () {
          Navigator.of(dialogContext).pop();
          _submit(preset);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final enabled = !locked && !_readOnly;
    return Tooltip(
      message:
          value.currentOption?.description ??
          l10n.accessModeTooltip(_label(l10n)),
      child: Opacity(
        // Web .trigger:disabled — the locked seat dims.
        opacity: enabled ? 1 : 0.6,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: enabled ? () => _open(context) : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    permissionGlyph(_currentValue),
                    size: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _label(l10n),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.keyboard_arrow_down,
                    size: 12,
                    color: scheme.outline,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The preset roster sheet: one row per switchable preset (name +
/// description), the current one marked.
class _PermissionSheet extends StatelessWidget {
  const _PermissionSheet({required this.value, required this.onPick});

  final PermissionSelect value;
  final void Function(String preset) onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    // Web drops `custom` from the menu — it is a derived state, not a
    // switch target.
    final options = value.options
        .where((option) => option.value != 'custom')
        .toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
          child: Text(l10n.accessModeLabel, style: theme.textTheme.titleSmall),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final option in options)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => onPick(option.value),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            permissionGlyph(option.value),
                            size: 16,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  permissionOptionLabel(option, l10n),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontSize: 13,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                if (option.description
                                    case final String description)
                                  Text(
                                    description,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontSize: 12,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (option.value == value.currentValue)
                            Icon(
                              Icons.check,
                              size: 16,
                              color: theme.colorScheme.onSurface,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Web RiskConfirmation: the acknowledgement checkbox gates the enable
/// button; cancel, escape, and barrier dismissal submit nothing.
class _FullAccessDialog extends StatefulWidget {
  const _FullAccessDialog({required this.onEnable});

  final VoidCallback onEnable;

  @override
  State<_FullAccessDialog> createState() => _FullAccessDialogState();
}

class _FullAccessDialogState extends State<_FullAccessDialog> {
  bool _acknowledged = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.enableFullAccessTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.fullAccessRisks),
          CheckboxListTile(
            value: _acknowledged,
            onChanged: (checked) =>
                setState(() => _acknowledged = checked ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.acknowledgeRisks),
          ),
        ],
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _acknowledged ? widget.onEnable : null,
          child: Text(l10n.enableFullAccess),
        ),
      ],
    );
  }
}
