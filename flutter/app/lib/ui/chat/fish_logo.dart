/// DeepSeek fish logo — exact port of the web FishLogo (figma I39:24057).
///
/// The reference SVG path uses only absolute M/C/Z commands; the tiny
/// parser below covers that subset, so the glyph is pixel-faithful
/// (native 23.16×17.04 viewBox) rather than an approximation.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

const String _fishPathData =
    'M22.9168 1.43018C22.6713 1.31018 22.5658 1.53918 22.4223 1.65519 '
    'C22.3733 1.69269 22.3318 1.74169 22.2903 1.78669C21.9317 2.1697 '
    '21.5127 2.42121 20.9657 2.39121C20.1657 2.34621 19.4827 2.59771 '
    '18.8787 3.20973C18.7502 2.45521 18.3236 2.0047 17.6746 1.71569 '
    'C17.3351 1.56568 16.9916 1.41518 16.7536 1.08867C16.5876 0.856163 '
    '16.5421 0.597155 16.4591 0.341647C16.4061 0.187643 16.3536 0.0301382 '
    '16.1761 0.00363739C15.9836 -0.0263635 15.9081 0.135141 15.8326 0.270145 '
    'C15.5306 0.822162 15.4136 1.43018 15.4251 2.0462C15.4516 3.43174 '
    '16.0366 4.53527 17.1991 5.3203C17.3311 5.4103 17.3651 5.5003 17.3236 '
    '5.63181C17.2441 5.90231 17.1501 6.16482 17.0671 6.43533C17.0141 '
    '6.60784 16.9351 6.64584 16.7501 6.57033C16.1121 6.30383 15.5611 '
    '5.90931 15.074 5.4328C14.2475 4.63328 13.5 3.75075 12.568 3.05973 '
    'C12.349 2.89822 12.13 2.74822 11.9034 2.60522C10.9524 1.68169 12.028 '
    '0.923165 12.277 0.833162C12.5375 0.739159 12.3675 0.41615 11.5259 '
    '0.42015C10.6844 0.42365 9.91439 0.705658 8.93286 1.08117C8.78935 '
    '1.13767 8.63835 1.17867 8.48384 1.21267C7.59332 1.04367 6.66829 '
    '1.00617 5.70226 1.11517C3.88321 1.31768 2.43016 2.1777 1.36213 '
    '3.64575C0.0790928 5.4103 -0.222916 7.41536 0.146595 9.50642 '
    'C0.535106 11.7105 1.66014 13.535 3.38869 14.9616C5.18125 16.4406 '
    '7.24581 17.1657 9.60138 17.0266C11.0319 16.9441 12.6245 16.7526 '
    '14.421 15.2321C14.874 15.4576 15.3496 15.5476 16.1381 15.6151 '
    'C16.7456 15.6716 17.3306 15.5856 17.7836 15.4916C18.4931 15.3416 '
    '18.4441 14.6841 18.1876 14.5636C16.1081 13.595 16.5646 13.9891 '
    '16.1496 13.67C17.2061 12.42 18.8202 10.1979 19.3182 7.17235 '
    'C19.3672 6.83834 19.4297 6.36783 19.4222 6.09732C19.4182 5.93231 '
    '19.4562 5.86831 19.6447 5.84931C20.1657 5.78931 20.6712 5.64681 '
    '21.1357 5.3913C22.4833 4.65528 23.0268 3.44624 23.1548 1.9972 '
    'C23.1738 1.77569 23.1508 1.54668 22.9168 1.43018Z '
    'M11.1749 14.4736C9.15936 12.889 8.18184 12.3675 7.77832 12.39 '
    'C7.40081 12.4125 7.46881 12.8445 7.55182 13.126C7.63882 13.404 '
    '7.75182 13.5955 7.91033 13.8396C8.01983 14.0011 8.09533 14.2411 '
    '7.80083 14.4216C7.15181 14.8231 6.02327 14.2866 5.97027 14.2601 '
    'C4.65673 13.4865 3.5587 12.4655 2.78467 11.069C2.03715 9.72493 '
    '1.60314 8.28289 1.53164 6.74384C1.51264 6.37233 1.62214 6.24082 '
    '1.99215 6.17332C2.47916 6.08332 2.98118 6.06432 3.46769 6.13582 '
    'C5.52476 6.43633 7.27581 7.35586 8.74385 8.8129C9.58188 9.64243 '
    '10.2159 10.634 10.8689 11.6025C11.5634 12.631 12.3105 13.611 13.262 '
    '14.4146C13.598 14.6961 13.866 14.9101 14.1225 15.0681C13.349 15.1546 '
    '12.058 15.1731 11.1749 14.4746L11.1749 14.4736Z '
    'M12.141 8.25988C12.141 8.09488 12.273 7.96338 12.439 7.96338 '
    'C12.4765 7.96338 12.5105 7.97088 12.541 7.98188C12.5825 7.99688 '
    '12.6205 8.01938 12.6505 8.05338C12.7035 8.10588 12.7335 8.18088 '
    '12.7335 8.25988C12.7335 8.42489 12.6015 8.55639 12.4355 8.55639 '
    'C12.2695 8.55639 12.141 8.42489 12.141 8.25988Z '
    'M15.1415 9.79893C14.949 9.87793 14.7565 9.94544 14.5715 9.95294 '
    'C14.284 9.96794 13.971 9.85143 13.801 9.70893C13.537 9.48742 13.348 '
    '9.36342 13.2695 8.97691C13.2355 8.8119 13.2545 8.55639 13.2845 '
    '8.40989C13.3525 8.09438 13.2775 7.89187 13.0545 7.70787C12.8735 '
    '7.55786 12.6435 7.51636 12.39 7.51636C12.295 7.51636 12.209 7.47486 '
    '12.1445 7.44136C12.039 7.38886 11.9519 7.25735 12.035 7.09585 '
    'C12.061 7.04335 12.19 6.91584 12.22 6.89334C12.5635 6.69784 12.9595 '
    '6.76195 13.3265 6.90834C13.6655 7.04735 13.9225 7.30236 14.2925 '
    '7.66287C14.6695 8.09838 14.7375 8.21838 14.9525 8.54539C15.1225 '
    '8.8009 15.2775 9.06341 15.3831 9.36392C15.4475 9.55142 15.3645 '
    '9.70493 15.1415 9.79893Z';

/// Minimal absolute-subset SVG path parser (M, C, L, Z).
ui.Path parseSvgPath(String d) {
  final path = ui.Path();
  final tokens = d
      .replaceAllMapped(RegExp(r'([A-Za-z])'), (m) => ' ${m[1]} ')
      .split(RegExp(r'\s+'));
  var command = '';
  final args = <double>[];
  double? toNum(String s) => double.tryParse(s);

  void apply() {
    if (command.isEmpty || args.length < 2 && command != 'Z') return;
    switch (command) {
      case 'M':
        path.moveTo(args[0], args[1]);
      case 'C':
        if (args.length >= 6) {
          path.cubicTo(args[0], args[1], args[2], args[3], args[4], args[5]);
        }
      case 'L':
        if (args.length >= 2) path.lineTo(args[0], args[1]);
      case 'Z':
        path.close();
    }
    args.clear();
  }

  for (final token in tokens) {
    if (token.isEmpty) continue;
    final code = token[0];
    if (code == 'M' || code == 'C' || code == 'L' || code == 'Z') {
      apply();
      command = code;
      final rest = token.substring(1);
      if (rest.isNotEmpty) {
        final value = toNum(rest);
        if (value != null) args.add(value);
      }
    } else {
      final value = toNum(token);
      if (value != null) args.add(value);
      // C carries six args per segment; flush continuously.
      if (command == 'C' && args.length == 6) {
        apply();
      } else if (command == 'M' && args.length == 2) {
        apply();
      } else if (command == 'L' && args.length == 2) {
        apply();
      }
    }
  }
  apply();
  return path;
}

/// The fish glyph painter; color rides [color] like the web currentColor.
class FishLogo extends StatelessWidget {
  const FishLogo({super.key, this.size = 24, this.color});

  /// Width in logical px; height keeps the 23.16:17.04 ratio.
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final width = size;
    final height = size * 17.04 / 23.16;
    return CustomPaint(
      size: Size(width, height),
      painter: _FishPainter(
        color ??
            DefaultTextStyle.of(context).style.color ??
            Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}

class _FishPainter extends CustomPainter {
  const _FishPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 23.16;
    final path = parseSvgPath(_fishPathData);
    final paint = Paint()..color = color;
    canvas.save();
    canvas.scale(scale, scale);
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FishPainter oldDelegate) => oldDelegate.color != color;
}
