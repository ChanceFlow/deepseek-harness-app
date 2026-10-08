/// DshTheme construction tests — native Material 3 scheme from a blue
/// seed, stock M3 component roles, and the optional OLED appearance.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/ui/theme/theme.dart';

/// WCAG relative-luminance contrast, measured from the two roles the widget
/// under test actually wears.
double _contrast(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  final double hi = la > lb ? la : lb;
  final double lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('light scheme derives from the blue seed', () {
    final theme = DshTheme.light();
    final scheme = theme.colorScheme;
    expect(scheme.brightness, Brightness.light);
    expect(scheme.surface, isNotNull);
    expect(scheme.onSurface, isNotNull);
    expect(scheme.primary, isNotNull);
    expect(scheme.onPrimary, isNotNull);
    expect(theme.scaffoldBackgroundColor, scheme.surface);
  });

  test('dark scheme derives from the blue seed', () {
    final theme = DshTheme.dark();
    final scheme = theme.colorScheme;
    expect(scheme.brightness, Brightness.dark);
    expect(scheme.surface, isNotNull);
    expect(scheme.onSurface, isNotNull);
    expect(scheme.primary, isNotNull);
    expect(scheme.onPrimary, isNotNull);
    expect(theme.scaffoldBackgroundColor, scheme.surface);
  });

  test('light and dark primary differ in polarity', () {
    final light = DshTheme.light().colorScheme;
    final dark = DshTheme.dark().colorScheme;
    expect(light.primary, isNot(equals(dark.primary)));
    expect(light.surface, isNot(equals(dark.surface)));
  });

  test('the OLED appearance is the dark scheme on a pure-black page', () {
    final theme = DshTheme.oled();
    final scheme = theme.colorScheme;
    expect(scheme.brightness, Brightness.dark);
    expect(scheme.surface.computeLuminance(), 0.0);
    expect(scheme.surface.a, 1.0);
    expect(theme.scaffoldBackgroundColor, scheme.surface);
    // The ink roles stay the dark scheme's, so nothing else re-tunes.
    expect(scheme.onSurface, DshTheme.dark().colorScheme.onSurface);
    expect(scheme.primary, DshTheme.dark().colorScheme.primary);
    expect(scheme.error, DshTheme.dark().colorScheme.error);
  });

  test('the OLED container family is a near-black ladder above the page', () {
    final scheme = DshTheme.oled().colorScheme;
    final ladder = <Color>[
      scheme.surfaceContainerLow,
      scheme.surfaceContainer,
      scheme.surfaceContainerHigh,
      scheme.surfaceContainerHighest,
    ];
    for (final step in ladder) {
      expect(
        step.computeLuminance(),
        greaterThan(0.0),
        reason: 'every container steps off the pure-black page',
      );
    }
    for (var i = 1; i < ladder.length; i++) {
      expect(
        ladder[i].computeLuminance(),
        greaterThan(ladder[i - 1].computeLuminance()),
        reason: 'the ladder rises monotonically',
      );
    }
  });

  test('the OLED two-tone step keeps the dark scheme separation', () {
    final oled = DshTheme.oled().colorScheme;
    final dark = DshTheme.dark().colorScheme;
    // Content vs chrome: the transcript on `surface`, the frames on
    // `surfaceContainer`. Pure black costs tonal elevation shadows, not this
    // step.
    expect(
      _contrast(oled.surfaceContainer, oled.surface),
      greaterThanOrEqualTo(_contrast(dark.surfaceContainer, dark.surface)),
    );
    // The hairline the app already draws reads at least as strongly.
    expect(
      _contrast(oled.outlineVariant, oled.surface),
      greaterThan(_contrast(dark.outlineVariant, dark.surface)),
    );
  });

  test('every OLED ink role clears 4.5:1 on the pure-black surface', () {
    final scheme = DshTheme.oled().colorScheme;
    final inks = <String, Color>{
      'onSurface': scheme.onSurface,
      'onSurfaceVariant': scheme.onSurfaceVariant,
      'primary': scheme.primary,
      'error': scheme.error,
      'success': scheme.success,
      'warning': scheme.warning,
      'syntaxKeyword': scheme.syntaxKeyword,
      'syntaxString': scheme.syntaxString,
      'syntaxNumber': scheme.syntaxNumber,
    };
    for (final entry in inks.entries) {
      expect(
        _contrast(entry.value, scheme.surface),
        greaterThanOrEqualTo(4.5),
        reason: '${entry.key} is ink on the OLED page',
      );
    }
  });

  test('OLED syntax tokens clear 4.5:1 on the code surface', () {
    final scheme = DshTheme.oled().colorScheme;
    // A fence sits on `surfaceContainerHigh`, not on the page.
    for (final token in <Color>[
      scheme.syntaxKeyword,
      scheme.syntaxString,
      scheme.syntaxNumber,
    ]) {
      expect(
        _contrast(token, scheme.surfaceContainerHigh),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  test('stock M3 component roles are present on every theme', () {
    for (final theme in [DshTheme.light(), DshTheme.dark(), DshTheme.oled()]) {
      final scheme = theme.colorScheme;
      expect(scheme.surfaceContainerLow, isNotNull);
      expect(scheme.surfaceContainerHigh, isNotNull);
      expect(scheme.surfaceContainerHighest, isNotNull);
      expect(scheme.onSurfaceVariant, isNotNull);
      expect(scheme.outline, isNotNull);
      expect(scheme.outlineVariant, isNotNull);
      expect(scheme.primaryContainer, isNotNull);
      expect(scheme.secondaryContainer, isNotNull);
      expect(scheme.errorContainer, isNotNull);
    }
  });

  test('success is a scheme role and tracks brightness', () {
    final light = DshTheme.light().colorScheme;
    final dark = DshTheme.dark().colorScheme;
    expect(light.success, isNot(equals(dark.success)));
    // The dark value is the lighter green: legible on a dark surface.
    expect(
      dark.success.computeLuminance(),
      greaterThan(light.success.computeLuminance()),
    );
  });

  test('warning is a scheme role and tracks brightness', () {
    final light = DshTheme.light().colorScheme;
    final dark = DshTheme.dark().colorScheme;
    expect(light.warning, isNot(equals(dark.warning)));
    // The dark value is the brighter amber: legible on a dark surface.
    expect(
      dark.warning.computeLuminance(),
      greaterThan(light.warning.computeLuminance()),
    );
  });

  test('the deep-diving roles mix the pin palette in both brightnesses', () {
    final light = DshTheme.light().colorScheme;
    final dark = DshTheme.dark().colorScheme;

    // The reference's own `color-mix` results, from its static palette steps
    // (design-platform.css:11-62): light mixes deepseek-500 into blue-950,
    // dark mixes deepseek-450 into neutral-bluish-400 and blue-300 into
    // deepseek-400.
    expect(light.labelDeepDiving.toARGB32(), 0xFF345EBA);
    expect(light.labelDeepDivingShimmer.toARGB32(), 0xFF243D80);
    expect(dark.labelDeepDiving.toARGB32(), 0xFF7D9ADF);
    expect(dark.labelDeepDivingShimmer.toARGB32(), 0xFF8ABCFE);

    // Two brightnesses, two values, and neither is an accent or the old
    // turn-status glint.
    expect(light.labelDeepDiving, isNot(equals(dark.labelDeepDiving)));
    expect(
      light.labelDeepDivingShimmer,
      isNot(equals(dark.labelDeepDivingShimmer)),
    );
    for (final scheme in <ColorScheme>[light, dark]) {
      expect(scheme.labelDeepDiving, isNot(equals(scheme.primary)));
      expect(scheme.labelDeepDivingShimmer, isNot(equals(scheme.onSurface)));
    }
  });

  test('the content type scale is the reference\'s 14/24 and 13/20', () {
    for (final theme in <ThemeData>[
      DshTheme.light(),
      DshTheme.dark(),
      DshTheme.oled(),
    ]) {
      final text = theme.textTheme;
      // `--dsh-content-font-size` 14px on the 24px body line
      // (gradient-shadow-text.css:89-92), secondary 13px on 20px
      // (`--dsw-font-xs-13`, :230-235).
      expect(text.bodyMedium?.fontSize, 14);
      expect(text.bodyMedium?.height, 24 / 14);
      expect(text.bodySmall?.fontSize, 13);
      expect(text.bodySmall?.height, 20 / 13);
    }
  });

  test('the strong weight is the reference\'s 500, not an invented 600', () {
    // The Figma 510 renders as 500 (design-platform.css:1-3); the sheets pin
    // every `-strong-` step at 500 (gradient-shadow-text.css:225, :239).
    final text = DshTheme.light().textTheme;
    expect(text.labelLarge?.fontWeight, FontWeight.w500);
    expect(text.titleMedium?.fontWeight, FontWeight.w500);
    expect(text.titleLarge?.fontWeight, FontWeight.w500);
  });

  test('the user bubble wears the reference fill in both brightnesses', () {
    // `--dsw-specific-bubble` (design-platform.css:268 light, :386 dark):
    // deepseek-50 rgb(237, 243, 254) and neutral-bluish-850 rgb(44, 44, 46).
    expect(DshTheme.light().colorScheme.bubble.toARGB32(), 0xFFEDF3FE);
    expect(DshTheme.dark().colorScheme.bubble.toARGB32(), 0xFF2C2C2E);
    // The OLED appearance moves the surface family only.
    expect(
      DshTheme.oled().colorScheme.bubble,
      DshTheme.dark().colorScheme.bubble,
    );
  });

  test('the transcript rhythm is the reference\'s 6/12/16', () {
    // `--dsh-chat-flow-gap` (ChatView.module.css:70-95).
    expect(kChatFlowGapStep, 6);
    expect(kChatFlowGap, 12);
    expect(kChatFlowGapAfterTurnHeader, 16);
    expect(kEdgeFade, 24);
    expect(kReasoningSummaryFade, 48);
    expect(kShapeBubble, 20);
  });

  test('the code stack is the reference\'s, closed by Android\'s mono', () {
    // base.css:10.
    expect(kCodeFontFamily, 'SF Mono');
    expect(
      kCodeFontFamilyFallback,
      containsAllInOrder(<String>[
        'JetBrains Mono',
        'Fira Code',
        'Consolas',
        'Liberation Mono',
        'Menlo',
        'Courier',
        'PingFang SC',
        'Microsoft YaHei',
      ]),
    );
    // No reference face ships with the app, so the platform's own mono alias
    // closes the list — the recorded Android limit.
    expect(kCodeFontFamilyFallback.last, 'monospace');
  });

  test('no deepsuite theme extension is attached', () {
    expect(DshTheme.light().extensions, isEmpty);
    expect(DshTheme.dark().extensions, isEmpty);
    // The OLED appearance overrides scheme roles; it adds no extension.
    expect(DshTheme.oled().extensions, isEmpty);
  });

  test('composer small FAB keeps a compact footprint', () {
    for (final theme in [DshTheme.light(), DshTheme.dark(), DshTheme.oled()]) {
      expect(
        theme.floatingActionButtonTheme.smallSizeConstraints,
        const BoxConstraints.tightFor(width: 40, height: 40),
      );
    }
  });

  test('Material widgets resolve against the themed roles', () {
    final builder = MaterialApp(
      theme: DshTheme.light(),
      darkTheme: DshTheme.dark(),
      home: Builder(
        builder: (context) => ColoredBox(
          color: Theme.of(context).colorScheme.primary,
          child: const SizedBox.shrink(),
        ),
      ),
    );
    expect(builder, isA<MaterialApp>());
  });
}
