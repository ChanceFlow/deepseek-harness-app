/// Access-mode chip — mobile port of the web PermissionSelect seat
/// (ui-conversation skeleton/PermissionSelect.tsx): a compact chip in
/// the composer's tools row showing the current permission preset,
/// opening the menu-surface sheet of switchable presets. Selecting one
/// submits the `/permission` host command; full access passes a risk
/// confirmation first, and a `custom` effective value renders the chip
/// read-only (nothing to switch to).
library;

import 'package:domain/model/permission_select.dart';
import 'package:flutter/material.dart';

import '../theme/deepsuite_extension.dart'
    show dsOf, kDsShadowLv3;
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
      .map((word) => word.isEmpty ? word : word[0].toUpperCase() + word.substring(1))
      .join(' ');
}

/// Web `optionLabel`: the full-access machine name carries the product
/// label `Full access`; every other row title-cases its published name.
String permissionOptionLabel(PermissionPresetOption option) {
  return option.value == _kFullAccess
      ? 'Full access'
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
    super.key,
    required this.value,
    required this.locked,
    required this.onAction,
  });

  final PermissionSelect value;

  /// Seat lock: a locked composer (no session / send in flight) offers
  /// no switching.
  final bool locked;

  /// Command dispatch — selection rides the existing send path.
  final void Function(ChatAction) onAction;

  String get _currentValue => value.currentValue;

  String get _label {
    final current = value.currentOption;
    return current == null
        ? permissionDisplayName(_currentValue)
        : permissionOptionLabel(current);
  }

  /// A `custom` effective value has no switch target (the host composed
  /// it from settings this surface cannot edit) — the chip stays
  /// read-only.
  bool get _readOnly => _currentValue == 'custom';

  void _submit(String preset) {
    onAction(SendPrompt('/permission $preset'));
  }

  Future<void> _open(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // Menu-surface sheet (ModelSelect vocabulary): menu fill, 12px
      // radius, lv3 elevation, 4px inner padding.
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: dsOf(sheetContext).menu,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: dsOf(sheetContext).borderInverted),
            boxShadow: kDsShadowLv3,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: _PermissionSheet(
              value: value,
              onPick: (preset) {
                Navigator.of(sheetContext).pop();
                _choose(sheetContext, preset);
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Web `choose`: re-picking the current value is a no-op; full access
  /// routes through the risk confirmation before anything is submitted.
  void _choose(BuildContext context, String preset) {
    if (preset == _currentValue) return;
    if (preset == _kFullAccess) {
      _confirmFullAccess(context, preset);
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
    final ds = dsOf(context);
    final theme = Theme.of(context);
    final enabled = !locked && !_readOnly;
    return Tooltip(
      message: value.currentOption?.description ?? 'Access mode: $_label',
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
                color: ds.bgLayer1,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    permissionGlyph(_currentValue),
                    size: 14,
                    color: ds.labelSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: ds.labelSecondary,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.keyboard_arrow_down,
                    size: 12,
                    color: ds.labelCaption,
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
    final ds = dsOf(context);
    final theme = Theme.of(context);
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
          child: Text('Access mode', style: theme.textTheme.titleSmall),
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
                            color: ds.labelSecondary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  permissionOptionLabel(option),
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
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(
                                          fontSize: 12,
                                          color: ds.labelTertiary,
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
    return AlertDialog(
      title: const Text('Enable Full access?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Full access reduces confirmation steps and lets the agent '
            'perform more actions directly, including sensitive '
            'operations, file changes, or external commands. Only use it '
            'when you trust the current task.',
          ),
          CheckboxListTile(
            value: _acknowledged,
            onChanged: (checked) =>
                setState(() => _acknowledged = checked ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text('I understand the risks and want to continue'),
          ),
        ],
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _acknowledged ? widget.onEnable : null,
          child: const Text('Enable Full access'),
        ),
      ],
    );
  }
}
