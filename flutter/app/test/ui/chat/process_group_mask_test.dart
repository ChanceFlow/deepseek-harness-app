/// `ProcessGroupBody`'s fade gate: does the mask ever paint an *active* fade
/// against a body that has nothing behind it?
///
/// The body's box shrink-wraps to its content while that content is shorter
/// than the cap, so the mask's rect **is** the content extent in that state.
/// The two alphas that keep that safe — `_canScrollUp` / `_canScrollDown` — are
/// read from the scroll controller in a listener and in a post-frame callback
/// registered by the body's own `build`. A body whose *child* changes length
/// without a scroll notification and without a rebuild therefore keeps the gate
/// it last read.
///
/// This test drives that sequence and samples the painted pixels: overflow the
/// body and scroll it (gate true, correct fade), shrink the child back under
/// the cap with no scroll (gate must go false), then sample the edge. A faded
/// edge on a body with `maxScrollExtent == 0` is the defect — the fade has
/// nothing to fade and it cuts the last line of text.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:app/ui/chat/process_disclosure.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// A solid block, so a masked pixel is unambiguous: alpha 255 where the mask is
/// opaque, less where the fade ramps. The draw is the boundary's own, so an
/// active fade shows as alpha — nothing sits behind the boundary to blend in.
class _Block extends StatelessWidget {
  const _Block({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: height,
    child: const ColoredBox(color: Color(0xFF000000)),
  );
}

/// A row that resizes itself, the way a pin tool row discloses in place: its
/// own `setState` changes its height, so the group body's content grows and
/// shrinks **without the body rebuilding** and without any scroll event.
class _SelfResizingRow extends StatefulWidget {
  const _SelfResizingRow({super.key});

  @override
  State<_SelfResizingRow> createState() => _SelfResizingRowState();
}

class _SelfResizingRowState extends State<_SelfResizingRow> {
  bool _open = true;

  /// Flip the row's own height, the way a tool row discloses in place.
  void toggle() => setState(() => _open = !_open);

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      SizedBox(
        height: 40,
        child: TextButton(
          onPressed: () => setState(() => _open = !_open),
          child: const Text('toggle'),
        ),
      ),
      _Block(height: _open ? 660 : 20),
    ],
  );
}

void main() {
  testWidgets('a shrunken group body paints no fade', (tester) async {
    final height = ValueNotifier<double>(120);
    addTearDown(height.dispose);
    final boundaryKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: <Widget>[
              const SizedBox(height: 40),
              RepaintBoundary(
                key: boundaryKey,
                child: ProcessGroupBody(
                  child: ValueListenableBuilder<double>(
                    valueListenable: height,
                    builder: (context, value, _) => _Block(height: value),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    /// The RGBA 4px above the body's bottom edge: inside the 24px ramp when the
    /// bottom fade is active.
    Future<List<int>> bottomPixel() async {
      final box = tester.renderObject<RenderBox>(find.byType(ProcessGroupBody));
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      late Uint8List rgba;
      late int width;
      await tester.runAsync(() async {
        final ui.Image image = await boundary.toImage(pixelRatio: 2);
        width = image.width;
        final ByteData? data = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        image.dispose();
        rgba = data!.buffer.asUint8List();
      });
      final x = (box.size.width).round();
      final y = ((box.size.height - 4) * 2).round();
      final index = (y * width + x) * 4;
      return <int>[
        rgba[index],
        rgba[index + 1],
        rgba[index + 2],
        rgba[index + 3],
      ];
    }

    ScrollPosition bodyPosition() => tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byType(ProcessGroupBody),
            matching: find.byType(Scrollable),
          ),
        )
        .position;

    String describe(String label) {
      final box = tester.renderObject<RenderBox>(find.byType(ProcessGroupBody));
      final position = bodyPosition();
      return '$label: box=${box.size.height.toStringAsFixed(0)} '
          'viewport=${position.viewportDimension.toStringAsFixed(0)} '
          'max=${position.maxScrollExtent.toStringAsFixed(0)} '
          'pixels=${position.pixels.toStringAsFixed(0)}';
    }

    // 1. Short body: it fits, so there is nothing behind either edge and the
    //    gate is false. No fade is correct.
    height.value = 120;
    await tester.pump();
    await tester.pump();
    final shortAtRest = await bottomPixel();
    final shortMax = bodyPosition().maxScrollExtent;
    // ignore: avoid_print
    print('${describe('short at rest')} bottomAlpha=${shortAtRest[3]}');

    // 2. The child grows past the cap — the shape a send has while a group is
    //    open. The body now needs its bottom fade, and the gate must read it.
    height.value = 700;
    await tester.pump();
    await tester.pump();
    final grown = await bottomPixel();
    final grownMax = bodyPosition().maxScrollExtent;
    // ignore: avoid_print
    print('${describe('grown past the cap')} bottomAlpha=${grown[3]}');

    // 3. A reader scroll inside the body: the controller notifies, the gate is
    //    read, and the fade appears.
    await tester.drag(
      find.descendant(
        of: find.byType(ProcessGroupBody),
        matching: find.byType(Scrollable),
      ),
      const Offset(0, -40),
    );
    await tester.pump();
    final scrolling = await bottomPixel();
    // ignore: avoid_print
    print('${describe('scrolled inside')} bottomAlpha=${scrolling[3]}');

    // 4. The child shrinks back under the cap with no scroll notification, which
    //    is what a settled transcript does when a group loses rows. The gate
    //    must go false.
    height.value = 120;
    await tester.pump();
    final shrunken = await bottomPixel();
    final shrunkenMax = bodyPosition().maxScrollExtent;
    // ignore: avoid_print
    print('${describe('shrunken frame 0')} bottomAlpha=${shrunken[3]}');

    await tester.pump();
    final afterOne = await bottomPixel();
    // ignore: avoid_print
    print('${describe('shrunken frame 1')} bottomAlpha=${afterOne[3]}');

    await tester.pump(const Duration(milliseconds: 200));
    final settled = await bottomPixel();
    // ignore: avoid_print
    print('${describe('settled')} bottomAlpha=${settled[3]}');

    // Nothing behind the edge on the short frames, content behind it on the
    // long ones: the alpha must follow that, and only that.
    expect(shortMax, 0, reason: 'the short body fits');
    expect(shortAtRest[3], 255, reason: 'a body that fits paints no fade');
    // The mirror sign: a body that has never overflowed grows past the cap and
    // must paint the fade rather than a bare hard clip.
    expect(grownMax, greaterThan(0), reason: 'the grown body overflows');
    expect(
      grown[3],
      lessThan(255),
      reason: 'an overflowing body must fade its bottom edge',
    );
    expect(scrolling[3], lessThan(255), reason: 'and keeps it while scrolling');
    expect(shrunkenMax, 0, reason: 'nothing behind it');
    expect(
      shrunken[3],
      255,
      reason: 'the shrink frame must not paint an active fade',
    );
    expect(settled[3], 255, reason: 'nor once it settles');
  });

  // The app-shaped path: nothing here rebuilds `ProcessGroupBody` — the row
  // inside it changes its own height, exactly as a pin tool row discloses in
  // place. The body's content length changes, no scroll notification fires, and
  // the remembered gate keeps painting.
  testWidgets('a row that resizes itself does not strand the gate', (
    tester,
  ) async {
    final boundaryKey = GlobalKey();
    final rowKey = GlobalKey<_SelfResizingRowState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: <Widget>[
              const SizedBox(height: 40),
              RepaintBoundary(
                key: boundaryKey,
                child: ProcessGroupBody(child: _SelfResizingRow(key: rowKey)),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    Future<int> bottomAlpha() async {
      final box = tester.renderObject<RenderBox>(find.byType(ProcessGroupBody));
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      late Uint8List rgba;
      late int width;
      await tester.runAsync(() async {
        final ui.Image image = await boundary.toImage(pixelRatio: 2);
        width = image.width;
        final ByteData? data = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        image.dispose();
        rgba = data!.buffer.asUint8List();
      });
      final x = box.size.width.round();
      final y = ((box.size.height - 2) * 2).round();
      return rgba[(y * width + x) * 4 + 3];
    }

    ScrollPosition bodyPosition() => tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byType(ProcessGroupBody),
            matching: find.byType(Scrollable),
          ),
        )
        .position;

    // The open row makes the body overflow, and a scroll inside it reads the
    // gate true — the correct fade.
    await tester.drag(
      find.descendant(
        of: find.byType(ProcessGroupBody),
        matching: find.byType(Scrollable),
      ),
      const Offset(0, -60),
    );
    await tester.pump();
    expect(bodyPosition().maxScrollExtent, greaterThan(0));
    expect(await bottomAlpha(), lessThan(255), reason: 'overflowing body');

    // Collapse the row from the inside. The body now fits, so nothing is behind
    // either edge and no fade may paint.
    rowKey.currentState!.toggle();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(bodyPosition().maxScrollExtent, 0, reason: 'the body fits now');
    expect(
      await bottomAlpha(),
      255,
      reason: 'a body that fits must not paint a fade',
    );
  });
}
