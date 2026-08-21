/// DshTheme construction tests — native Material 3 scheme from a blue
/// seed, stock M3 component roles.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/ui/theme/theme.dart';

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

  test('stock M3 component roles are present on both themes', () {
    for (final theme in [DshTheme.light(), DshTheme.dark()]) {
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

  test('no deepsuite theme extension is attached', () {
    expect(DshTheme.light().extensions, isEmpty);
    expect(DshTheme.dark().extensions, isEmpty);
  });

  test('composer small FAB keeps a compact footprint', () {
    for (final theme in [DshTheme.light(), DshTheme.dark()]) {
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
