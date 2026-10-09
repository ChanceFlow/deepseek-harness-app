/// The message footer carries no rating control: the like/dislike pair was
/// removed at the reader's request, and this guards the removal (the copy
/// action and the rest of the strip stay).
library;

import 'package:app/ui/chat/message_icon_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';

void main() {
  testWidgets('the footer renders no thumbs and keeps its other actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      l10nApp(
        home: const Scaffold(
          body: MessageIconActions(
            text: 'a reply',
            timeEpochMs: 0,
            clockAtStart: false,
            metrics: '12 tok/s',
          ),
        ),
      ),
    );
    await tester.pump();

    for (final IconData icon in <IconData>[
      Icons.thumb_up,
      Icons.thumb_up_alt,
      Icons.thumb_up_alt_outlined,
      Icons.thumb_up_outlined,
      Icons.thumb_down,
      Icons.thumb_down_alt,
      Icons.thumb_down_alt_outlined,
      Icons.thumb_down_outlined,
    ]) {
      expect(find.byIcon(icon), findsNothing, reason: '${icon.codePoint}');
    }
    // The strip itself is alive: its own actions and the run metrics render.
    expect(find.byType(MessageIconActions), findsOneWidget);
    expect(find.byType(IconButton), findsWidgets);
    expect(find.text('12 tok/s'), findsOneWidget);
  });
}
