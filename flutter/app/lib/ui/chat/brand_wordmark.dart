/// DeepSeek Harness brand wordmark — native composition.
///
/// The web BrandWordmark (figma 356:14644) is one SVG: whale +
/// "deepseek-official" letterforms + a knocked-out HARNESS badge plate.
/// The whale is the exact [FishLogo] path; the letterforms are rendered
/// as a styled text run and the badge as a filled plate with inverted
/// text (deviation from the traced letterforms, recorded in ROADMAP §8).
library;

import 'package:flutter/material.dart';

import 'fish_logo.dart';

class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key, this.height = 24, this.color});

  /// Cap height in logical px; the row keeps optical centering.
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ink = color ?? Theme.of(context).colorScheme.onSurface;
    final inverted = Theme.of(context).colorScheme.surface;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        FishLogo(size: height, color: ink),
        const SizedBox(width: 8),
        Text(
          'DeepSeek',
          style: TextStyle(
            color: ink,
            fontSize: height * 0.66,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.2,
            height: 1.0,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: height * 0.18,
            vertical: height * 0.08,
          ),
          decoration: BoxDecoration(
            color: ink,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Text(
            'HARNESS',
            style: TextStyle(
              color: inverted,
              fontSize: height * 0.36,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.0,
              height: 1.0,
            ),
          ),
        ),
      ],
    );
  }
}
