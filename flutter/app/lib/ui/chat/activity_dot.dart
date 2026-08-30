/// The timeline's in-flight leading glyph: a neutral dot in the same
/// 14px state slot the settled check and cross wear, so a row's leading
/// edge holds its geometry across the whole run. Motion is not this
/// widget's job — the shared [SweepHighlight] glare over the row carries
/// the in-flight signal (the web ToolRow's contract: "running keeps the
/// icon, the row sweep carries the signal").
library;

import 'package:flutter/material.dart';

class ActivityDot extends StatelessWidget {
  const ActivityDot({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 14,
      height: 14,
      child: Center(
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
