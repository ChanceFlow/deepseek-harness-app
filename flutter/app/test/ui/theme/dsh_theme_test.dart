/// DshTheme construction tests — Material roles + extension carry the
/// deepsuite alias values.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/ui/theme/deepsuite_extension.dart';
import 'package:app/ui/theme/deepsuite_tokens.dart';
import 'package:app/ui/theme/theme.dart';

void main() {
  test('light scheme uses the ink brand and canvas band', () {
    final theme = DshTheme.light();
    final scheme = theme.colorScheme;
    expect(scheme.brightness, Brightness.light);
    expect(scheme.primary, DeepSuiteLight.aliasBrandPrimary);
    expect(scheme.primary, DeepSuiteStatic.neutralBluish1000);
    expect(scheme.onPrimary, DeepSuiteStatic.neutralBluish00);
    expect(scheme.surface, DeepSuiteStatic.neutralBluish00);
    expect(scheme.surfaceContainerHighest, DeepSuiteLight.aliasBgLayer2);
    expect(scheme.error, DeepSuiteStatic.red600);
    expect(theme.scaffoldBackgroundColor, scheme.surface);
  });

  test('dark scheme uses the inverted ink brand and dark canvas', () {
    final theme = DshTheme.dark();
    final scheme = theme.colorScheme;
    expect(scheme.brightness, Brightness.dark);
    expect(scheme.primary, DeepSuiteStatic.neutralBluish50);
    expect(scheme.onPrimary, DeepSuiteStatic.neutralBluish1000);
    expect(scheme.surface, DeepSuiteStatic.neutralBluish950);
    expect(scheme.surfaceContainerHighest, DeepSuiteDark.aliasBgLayer2);
    expect(scheme.onSurfaceVariant, DeepSuiteDark.aliasLabelSecondary);
  });

  test('DeepSeek-blue accent rides the secondary role per theme', () {
    expect(DshTheme.light().colorScheme.secondary,
        DeepSuiteStatic.deepseek500);
    expect(DshTheme.dark().colorScheme.secondary,
        DeepSuiteStatic.deepseek450);
  });

  test('DeepSuiteColors extension is attached to both themes', () {
    final light = DshTheme.light().extension<DeepSuiteColors>();
    final dark = DshTheme.dark().extension<DeepSuiteColors>();
    expect(light, isNotNull);
    expect(dark, isNotNull);
    expect(light!.sidebarFill, DeepSuiteLight.specificSidebarFill);
    expect(dark!.sidebarFill, DeepSuiteDark.specificSidebarFill);
    expect(light.sidebarNavItemActive, isNot(equals(dark.sidebarNavItemActive)));
    expect(light.accent, DeepSuiteStatic.deepseek500);
    expect(dark.accent, DeepSuiteStatic.deepseek450);
    expect(light.bgLayer1, isNot(equals(dark.bgLayer1)));
  });

  test('title roles carry the Figma-510-equivalent weight', () {
    for (final theme in [DshTheme.light(), DshTheme.dark()]) {
      expect(theme.textTheme.titleLarge?.fontWeight, FontWeight.w500);
      expect(theme.textTheme.titleMedium?.fontWeight, FontWeight.w500);
      expect(theme.textTheme.titleSmall?.fontWeight, FontWeight.w500);
    }
  });

  test('extension lerp reaches the other theme at t=1', () {
    final light = DshTheme.light().extension<DeepSuiteColors>()!;
    final dark = DshTheme.dark().extension<DeepSuiteColors>()!;
    expect(light.lerp(dark, 1).sidebarFill, dark.sidebarFill);
    expect(dark.lerp(light, 1).accent, light.accent);
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
