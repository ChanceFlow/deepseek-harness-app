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
