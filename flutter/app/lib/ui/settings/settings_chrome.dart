/// Shared chrome and navigation vocabulary for the Settings surfaces.
///
/// The Settings root is an index of one-line rows; every row leads to a
/// pushed page, a sheet, or a host dialog. Those surfaces draw the same
/// heading, grouped card, hairline divider, sheet shell, and row shape, and
/// that vocabulary lives here once instead of in each section file.
library;

import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'settings_ui_state.dart';

/// The live settings state one surface reads: the last published value, the
/// sink that carries its intents, and — when the surface is
/// controller-backed — the stream that replaces [state] as writes land.
///
/// Sub-pages are pushed onto the root navigator, so a pushed page is not a
/// descendant of the Settings tab and cannot watch its provider; carrying
/// the channel is how it stays live. A caller holding only a fixed state (a
/// widget test that pumps a snapshot) leaves [stream] null and the value
/// stands.
final class SettingsChannel {
  const SettingsChannel({
    required this.state,
    required this.onAction,
    this.stream,
  });

  final SettingsUiState state;
  final void Function(SettingsAction) onAction;
  final Stream<SettingsUiState>? stream;
}

/// Re-renders [builder] from [channel]: the stream's latest value when the
/// surface is controller-backed, the carried value otherwise.
class SettingsLive extends StatelessWidget {
  const SettingsLive({required this.channel, required this.builder, super.key});

  final SettingsChannel channel;
  final Widget Function(
    BuildContext context,
    SettingsUiState state,
    void Function(SettingsAction) onAction,
  )
  builder;

  @override
  Widget build(BuildContext context) {
    final Stream<SettingsUiState>? stream = channel.stream;
    if (stream == null) {
      return builder(context, channel.state, channel.onAction);
    }
    return StreamBuilder<SettingsUiState>(
      stream: stream,
      initialData: channel.state,
      builder: (
        BuildContext context,
        AsyncSnapshot<SettingsUiState> snapshot,
      ) => builder(context, snapshot.data ?? channel.state, channel.onAction),
    );
  }
}

/// Unified section heading with optional subtitle.
///
/// [showTitle] is false on a pushed page whose app bar already names the
/// section: the intro paragraph leads the page instead of repeating the
/// title under it.
class SettingsSectionHeading extends StatelessWidget {
  const SettingsSectionHeading({
    required this.title,
    this.intro,
    this.showTitle = true,
    super.key,
  });

  final String title;
  final String? intro;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String? lead = intro;
    if (!showTitle && lead == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (showTitle)
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (lead != null) ...<Widget>[
            if (showTitle) const SizedBox(height: 2),
            Text(
              lead,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Standard grouped container card for setting items.
///
/// A [Material] rather than a decorated box, so a row's ink splash paints on
/// the card instead of being hidden behind a colored layer.
class SettingsSectionCard extends StatelessWidget {
  const SettingsSectionCard({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kShapeCard),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

/// Thin hairline divider between items inside a section card.
class SettingsCardDivider extends StatelessWidget {
  const SettingsCardDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

/// One index row: a title, an optional leading glyph, one trailing fact, and
/// the chevron that promises the surface behind it.
///
/// The row is one line tall on purpose — the Settings root is an index, and
/// every word of explanation belongs on the page the row opens.
class SettingsNavRow extends StatelessWidget {
  const SettingsNavRow({
    required this.title,
    required this.onTap,
    this.leading,
    this.value,
    this.trailing,
    this.enabled = true,
    super.key,
  });

  final String title;
  final VoidCallback onTap;

  /// Glyph naming the row's family; the row supplies its size and tone.
  final Widget? leading;

  /// The current setting, shown right-aligned. [trailing] wins over it.
  final String? value;

  /// A richer trailing fact (a count badge); replaces [value].
  final Widget? trailing;

  /// False renders the row inert: the surface behind it has nothing to act
  /// on. The chevron stays, so the branch is still discoverable.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Widget? glyph = leading;
    final Widget? mark = trailing;
    final String? fact = value;
    // One node, not two: the ink host publishes the tap action and the
    // merged label together, so a screen reader announces one named button
    // rather than an unlabelled one wrapping a text node.
    return MergeSemantics(
      child: Semantics(
        button: true,
        enabled: enabled,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: <Widget>[
                  if (glyph != null) ...<Widget>[
                    IconTheme.merge(
                      data: IconThemeData(
                        size: 20,
                        color: scheme.onSurfaceVariant,
                      ),
                      child: glyph,
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: enabled
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (mark != null)
                    mark
                  else if (fact != null)
                    Flexible(
                      child: Text(
                        fact,
                        textAlign: TextAlign.end,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: scheme.onSurfaceVariant,
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

/// One pushed Settings sub-page: the app-bar title and a scrollable body.
class SettingsPageScaffold extends StatelessWidget {
  const SettingsPageScaffold({
    required this.title,
    required this.children,
    super.key,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: children,
        ),
      ),
    );
  }
}

/// Round icon button riding the app bar and the host sheet.
class SettingsCircleAction extends StatelessWidget {
  const SettingsCircleAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.iconSize = 18,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: iconSize, color: scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

/// The tone one trailing badge carries.
enum SettingsBadgeTone { neutral, primary, error }

/// A short trailing fact in a pill: a count, a stored/unset state, a live
/// host standing. The label always states the fact in words, so the tone is
/// emphasis rather than the only signal.
class SettingsBadge extends StatelessWidget {
  const SettingsBadge({
    required this.label,
    this.tone = SettingsBadgeTone.neutral,
    super.key,
  });

  final String label;
  final SettingsBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final (Color? background, Color foreground) = switch (tone) {
      SettingsBadgeTone.neutral => (null, scheme.onSurfaceVariant),
      SettingsBadgeTone.primary => (
        scheme.primaryContainer,
        scheme.onSurfaceVariant,
      ),
      SettingsBadgeTone.error => (scheme.errorContainer, scheme.error),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(kShapePill),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: foreground),
      ),
    );
  }
}

/// An 8dp dot carrying one fact's tone.
class SettingsStatusDot extends StatelessWidget {
  const SettingsStatusDot({required this.color, super.key});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// Tone one fact row's value takes.
enum SettingsFactTone { positive, warning, neutral }

/// One read-only host fact: a title, what it means, and the host's answer.
class SettingsFactRow extends StatelessWidget {
  const SettingsFactRow({
    required this.title,
    required this.description,
    required this.value,
    required this.tone,
    super.key,
  });

  final String title;
  final String description;
  final String value;
  final SettingsFactTone tone;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final (Color dotColor, Color textColor) = switch (tone) {
      SettingsFactTone.positive => (scheme.success, scheme.onSurfaceVariant),
      SettingsFactTone.warning => (scheme.error, scheme.onErrorContainer),
      SettingsFactTone.neutral => (scheme.outline, scheme.onSurfaceVariant),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SettingsStatusDot(color: dotColor),
          const SizedBox(width: 6),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(color: textColor),
          ),
        ],
      ),
    );
  }
}

/// The capsule selector one mutually-exclusive local mode rides.
class SettingsModeButton extends StatelessWidget {
  const SettingsModeButton({
    required this.label,
    required this.selected,
    this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final ThemeData theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(kShapeDock),
        hoverColor: scheme.surfaceContainerHigh,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? scheme.primaryContainer : null,
              borderRadius: BorderRadius.circular(kShapeDock),
              border: selected
                  ? null
                  : Border.all(color: scheme.outlineVariant),
            ),
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A form field's caption.
class SettingsFieldLabel extends StatelessWidget {
  const SettingsFieldLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Text(
      label,
      style: Theme.of(context).textTheme.labelMedium
          ?.copyWith(color: scheme.onSurfaceVariant),
    );
  }
}

/// The input decoration every Settings text field wears.
InputDecoration settingsInputDecoration(BuildContext context, {String? hint}) {
  final ThemeData theme = Theme.of(context);
  final ColorScheme scheme = theme.colorScheme;
  final OutlineInputBorder border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(kShapeChip),
    borderSide: BorderSide(color: scheme.outlineVariant),
  );
  return InputDecoration(
    hintText: hint,
    hintStyle: theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    ),
    filled: true,
    fillColor: scheme.surfaceContainerLow,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
    enabledBorder: border,
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(kShapeChip),
      borderSide: BorderSide(color: scheme.primary),
    ),
  );
}

/// The filled capsule: one per surface, on its primary action.
ButtonStyle settingsFilledCapsule(BuildContext context) {
  return FilledButton.styleFrom(
    minimumSize: const Size(64, 36),
    padding: const EdgeInsets.symmetric(horizontal: 14),
    shape: const StadiumBorder(),
    textStyle: Theme.of(context).textTheme.bodyMedium,
  );
}

/// The outlined capsule: a secondary action beside the filled one.
ButtonStyle settingsOutlineCapsule(BuildContext context) {
  final ColorScheme scheme = Theme.of(context).colorScheme;
  return OutlinedButton.styleFrom(
    minimumSize: const Size(64, 36),
    padding: const EdgeInsets.symmetric(horizontal: 14),
    shape: const StadiumBorder(),
    foregroundColor: scheme.onSurfaceVariant,
    side: BorderSide(color: scheme.outlineVariant),
    textStyle: Theme.of(context).textTheme.bodyMedium,
  );
}

/// The destructive capsule: removal, stated in the error role.
ButtonStyle settingsDangerCapsule(BuildContext context) {
  return TextButton.styleFrom(
    minimumSize: const Size(64, 36),
    padding: const EdgeInsets.symmetric(horizontal: 14),
    shape: const StadiumBorder(),
    foregroundColor: Theme.of(context).colorScheme.error,
    textStyle: Theme.of(context).textTheme.bodyMedium,
  );
}

/// Floats [builder]'s result on the modal sheet shell every Settings sheet
/// uses: the sheet radius, the chrome tone, and the elevation shadow.
///
/// The shell is a [Material] rather than a decorated box, so a `ListTile`
/// inside it paints its ink and background where the framework expects —
/// [showSettingsChoiceSheet]'s radio rows are exactly that case.
///
/// [isScrollControlled] is for a sheet holding a text field; the builder's
/// own content decides how tall it grows.
Future<T?> showSettingsSheet<T>(
  BuildContext context, {
  required Widget Function(BuildContext sheetContext) builder,
  bool isScrollControlled = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    builder: (BuildContext sheetContext) {
      final double insets = MediaQuery.of(sheetContext).viewInsets.bottom;
      final ColorScheme scheme = Theme.of(sheetContext).colorScheme;
      return Padding(
        padding: EdgeInsets.fromLTRB(8, 0, 8, 8 + insets),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(kShapeSheet),
            boxShadow: kM3ShadowElevation3,
          ),
          child: Material(
            color: scheme.surfaceContainer,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(kShapeSheet),
              side: BorderSide(color: scheme.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SafeArea(top: false, child: builder(sheetContext)),
            ),
          ),
        ),
      );
    },
  );
}

/// One option a choice sheet offers.
final class SettingsChoice<T> {
  const SettingsChoice({
    required this.value,
    required this.label,
    this.description,
    this.enabled = true,
  });

  final T value;
  final String label;
  final String? description;

  /// False renders the option disabled: the host or the device cannot accept
  /// it, and hiding it would leave the choice unexplained.
  final bool enabled;
}

/// Show [choices] as radio rows over [current], resolving to the picked value
/// or null when the sheet is dismissed. The caller owns the write.
Future<T?> showSettingsChoiceSheet<T>(
  BuildContext context, {
  required String title,
  required List<SettingsChoice<T>> choices,
  required T? current,
  String? description,
}) {
  return showSettingsSheet<T>(
    context,
    builder: (BuildContext sheetContext) {
      final ThemeData theme = Theme.of(sheetContext);
      final ColorScheme scheme = theme.colorScheme;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: theme.textTheme.titleMedium),
          if (description != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 4),
          // The group owns the value and the change routing; the tiles carry
          // only their own option.
          RadioGroup<T>(
            groupValue: current,
            onChanged: (T? value) {
              if (value == null) return;
              Navigator.of(sheetContext).pop(value);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final SettingsChoice<T> choice in choices)
                  RadioListTile<T>(
                    contentPadding: EdgeInsets.zero,
                    value: choice.value,
                    enabled: choice.enabled,
                    title: Text(choice.label),
                    subtitle: choice.description == null
                        ? null
                        : Text(
                            choice.description!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                  ),
              ],
            ),
          ),
        ],
      );
    },
  );
}
