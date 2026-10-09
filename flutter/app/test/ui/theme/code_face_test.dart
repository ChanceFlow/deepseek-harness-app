/// The code face resolves on the Android path — and to a mono.
///
/// The pin's code stack names faces no Android device ships (`base.css:10`), and
/// an unresolvable `fontFamily` is not walked into `fontFamilyFallback`: the run
/// falls to the platform default, which is how inline code stopped reading as
/// code. The Android primary is therefore the one mono name the platform
/// resolves, and these tests pin both halves of that: the name, and the fixed
/// advance that makes it a mono rather than the proportional default.
library;

import 'dart:io';

import 'package:app/ui/theme/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The advance of [text] in [family], measured by the engine that paints the app.
double _advance(String text, String family) {
  final TextPainter painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(fontFamily: family, fontSize: 14),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final double width = painter.width;
  painter.dispose();
  return width;
}

void main() {
  testWidgets('the Android code face resolves to a mono, not the body face', (
    tester,
  ) async {
    final String? root = Platform.environment['FLUTTER_ROOT'];
    if (root == null) {
      markTestSkipped('FLUTTER_ROOT is unset — run through flutter test');
      return;
    }
    // What a device has: Roboto for text, and a mono family the platform
    // resolves by the name `monospace`.
    Future<void> load(String family, String path) async {
      final File file = File(path);
      if (!file.existsSync()) return;
      final FontLoader loader = FontLoader(family)
        ..addFont(file.readAsBytes().then((b) => ByteData.view(b.buffer)));
      await loader.load();
    }

    // The loads are real file I/O, so they need the tester's own async zone:
    // inside `testWidgets` the default zone is fake-async and `FontLoader.load`
    // would never complete.
    await tester.runAsync(() async {
      await load(
        kUiFontFamily,
        '$root/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      );
      await load(
        'monospace',
        '$root/bin/cache/dart-sdk/bin/resources/devtools/assets/fonts/'
            'Roboto_Mono/RobotoMono-Regular.ttf',
      );
      // And under a name the pin's stack would reach only through its fallback
      // list, which is what the next assertion measures.
      await load(
        'Roboto Mono',
        '$root/bin/cache/dart-sdk/bin/resources/devtools/assets/fonts/'
            'Roboto_Mono/RobotoMono-Regular.ttf',
      );
    });
    // The measurement is the Android one: the target platform decides the
    // default face the engine falls back to when a name does not resolve. The
    // override is cleared inside the body, because the binding asserts every
    // foundation debug variable is unset before a teardown could run.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      // The primary must be the name the platform resolves. `SF Mono` here would
      // leave the run on the platform default, because the fallback list is only
      // consulted for glyphs the resolved family lacks.
      expect(kCodeFontFamily, 'monospace');

      // The mono above is what makes the measurement mean something: without it
      // the name would resolve to the test default, which is fixed-width for a
      // reason that has nothing to do with the device.
      expect(
        _advance('mmmm', kCodeFontFamily),
        isNot(_advance('mmmm', 'no-such-family-in-this-test')),
        reason: 'the measurement needs a real mono under the resolved name',
      );

      // The mechanism, measured rather than assumed: with the old primary the
      // engine does **not** walk into `fontFamilyFallback`, so a run that names an
      // unresolvable family and lists a real mono behind it is not that mono —
      // it is whatever the platform falls back to. `'Roboto Mono'` is registered
      // above, so the only reason the run misses it is the fallback rule.
      const TextStyle unresolved = TextStyle(
        fontFamily: 'SF Mono',
        fontFamilyFallback: <String>['Roboto Mono', 'monospace'],
        fontSize: 14,
      );
      const TextStyle resolved = TextStyle(
        fontFamily: 'monospace',
        fontFamilyFallback: <String>['Roboto Mono'],
        fontSize: 14,
      );
      double advanceOf(TextStyle style) {
        final TextPainter painter = TextPainter(
          text: TextSpan(text: 'mmmm', style: style),
          textDirection: TextDirection.ltr,
        )..layout();
        final double width = painter.width;
        painter.dispose();
        return width;
      }

      expect(
        advanceOf(unresolved),
        isNot(advanceOf(resolved)),
        reason:
            'an unresolvable primary must not have reached the fallback mono',
      );

      // A mono has one advance for every glyph; the body face does not.
      final double narrow = _advance('iiii', kCodeFontFamily);
      final double wide = _advance('mmmm', kCodeFontFamily);
      expect(
        narrow,
        wide,
        reason: 'a code run must be fixed-width, not the proportional default',
      );
      expect(
        wide,
        isNot(_advance('mmmm', kUiFontFamily)),
        reason: 'the code face must not be the body face',
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
