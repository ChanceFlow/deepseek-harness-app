/// The strip is a translation, never a resize: every page keeps the viewport
/// size while the strip slides.
library;

import 'package:app/shell/shell_page_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const double _width = 300;
const double _height = 500;

Widget _strip(double position, {double verticalOffset = 0}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: _width,
        height: _height,
        child: ShellPageStrip(
          pages: [
            for (var i = 0; i < 3; i++)
              SizedBox(
                key: ValueKey<int>(i),
                child: ColoredBox(
                  color: const Color(0xFF000000),
                  child: Text('page $i'),
                ),
              ),
          ],
          position: position,
          pageWidth: _width,
          verticalOffset: verticalOffset,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('the window shows page 0 at position 0', (tester) async {
    await tester.pumpWidget(_strip(0));
    expect(tester.getTopLeft(find.byKey(const ValueKey<int>(0))).dx, 0);
    expect(tester.getTopLeft(find.byKey(const ValueKey<int>(1))).dx, _width);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey<int>(2))).dx,
      2 * _width,
    );
  });

  testWidgets('a fractional position slides the strip by exactly that share', (
    tester,
  ) async {
    await tester.pumpWidget(_strip(1.5));
    expect(
      tester.getTopLeft(find.byKey(const ValueKey<int>(0))).dx,
      -1.5 * _width,
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey<int>(1))).dx,
      -0.5 * _width,
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey<int>(2))).dx,
      0.5 * _width,
    );
  });

  testWidgets('sliding never changes a page size', (tester) async {
    await tester.pumpWidget(_strip(0));
    final before = tester.getSize(find.byKey(const ValueKey<int>(1)));

    await tester.pumpWidget(_strip(1));
    final after = tester.getSize(find.byKey(const ValueKey<int>(1)));

    expect(after, before);
    expect(after, const Size(_width, _height));
  });

  testWidgets('the drawer offset moves the whole strip down, not its size', (
    tester,
  ) async {
    await tester.pumpWidget(_strip(0, verticalOffset: 96));
    expect(tester.getTopLeft(find.byKey(const ValueKey<int>(0))).dy, 96);
    expect(
      tester.getSize(find.byKey(const ValueKey<int>(0))),
      const Size(_width, _height),
    );
  });
}
