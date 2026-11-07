/// The horizontal strip every host page lives on.
///
/// The pages are laid out side by side at exactly the viewport width and the
/// strip is translated, never resized: switching from A to C slides the strip
/// past B, and the host's WebView keeps its size and layout the whole time.
///
/// The translation is a compositor transform, not a layout offset: the row is
/// laid out once and every frame only updates the matrix, so moving a page
/// never re-lays-out the platform view.
library;

import 'package:flutter/material.dart';

/// Offsets [pages] by a fractional page index.
class ShellPageStrip extends StatelessWidget {
  const ShellPageStrip({
    required this.pages,
    required this.position,
    required this.pageWidth,
    required this.verticalOffset,
    super.key,
  });

  /// One slot per host, in registry order.
  final List<Widget> pages;

  /// Fractional index; 0.5 means the strip is halfway from page 0 to page 1.
  final double position;

  final double pageWidth;

  /// How far the whole strip is pushed down (the exposé drawer's height).
  final double verticalOffset;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final stripWidth = pageWidth * pages.length;
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: stripWidth,
            maxWidth: stripWidth,
            minHeight: height,
            maxHeight: height,
            child: Transform.translate(
              offset: Offset(-position * pageWidth, verticalOffset),
              child: Row(
                children: [
                  for (final page in pages)
                    SizedBox(width: pageWidth, height: height, child: page),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
