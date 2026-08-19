/// deepsuite token invariants — provenance is scripts/gen_deepsuite_tokens.py.
library;

import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';

import 'package:app/ui/theme/deepsuite_tokens.dart';

void main() {
  test('sampled static palette values match the reference CSS', () {
    // design-platform.css L1..: --dsw-static-deepseek-500: rgb(65, 118, 230)
    expect(DeepSuiteStatic.deepseek500, const Color(0xff4176e6));
    expect(DeepSuiteStatic.neutralBluish00, const Color(0xffffffff));
    expect(DeepSuiteStatic.neutralBluish950, const Color(0xff151517));
    expect(DeepSuiteStatic.neutralBluish1000, const Color(0xff0f1115));
    expect(DeepSuiteStatic.red600, const Color(0xffec1313));
    expect(DeepSuiteStatic.green500, const Color(0xff22c55e));
  });

  test('light aliases resolve like the light theme block', () {
    expect(DeepSuiteLight.aliasBgBase, DeepSuiteStatic.neutralBluish00);
    // The web brand is an ink style: near-black on light, near-white on
    // dark; the DeepSeek blue lives in the separate *NewColor accent.
    expect(DeepSuiteLight.aliasBrandPrimary,
        DeepSuiteStatic.neutralBluish1000);
    expect(
      DeepSuiteLight.aliasBrandPrimaryNewColorprimaryNewColor,
      DeepSuiteStatic.deepseek500,
    );
    // Masks keep their alpha (light mask-1 = rgba(0,0,0,0.24)).
    expect(DeepSuiteLight.aliasBgMask1, const Color(0x3d000000));
  });

  test('dark aliases resolve like the dark theme block', () {
    expect(DeepSuiteDark.aliasBgBase, DeepSuiteStatic.neutralBluish950);
    expect(DeepSuiteDark.aliasBgLayer1, DeepSuiteStatic.neutralBluish875);
    expect(DeepSuiteDark.aliasBgLayer2, DeepSuiteStatic.neutralBluish850);
    expect(DeepSuiteDark.aliasBrandPrimary,
        DeepSuiteStatic.neutralBluish50);
  });

  test('light and dark expose the same alias key set', () {
    expect(
      DeepSuiteLight.byName.keys.toSet(),
      equals(DeepSuiteDark.byName.keys.toSet()),
    );
    expect(DeepSuiteLight.byName.length, greaterThan(80));
  });

  test('sidebar tokens exist and differ between themes', () {
    // --dsw-specific-sidebar-fill: light neutral-bluish-50 vs dark 950-875 band.
    expect(
      DeepSuiteLight.byName['--dsw-specific-sidebar-fill'],
      isNot(equals(DeepSuiteDark.byName['--dsw-specific-sidebar-fill'])),
    );
    expect(
      DeepSuiteLight.byName.containsKey(
          '--dsw-specific-sidebar-nav-item-active'),
      isTrue,
    );
  });

  test('motion durations follow base.css', () {
    expect(kDsDurationFast, const Duration(milliseconds: 100));
    expect(kDsDuration, const Duration(milliseconds: 200));
    expect(kDsDurationSlow, const Duration(milliseconds: 300));
  });

  test('code font resolves to the platform monospace stack', () {
    expect(kFontFamilyMonospace, 'monospace');
  });
}
