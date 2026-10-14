/// The markdown-to-plain-text projection over the parser's own vocabulary:
/// what a card's summary shows must be the text the transcript renders, with
/// every mark the renderer paints stripped away.
library;

import 'package:app/ui/chat/markdown/plain_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a rule projects to nothing', () {
    expect(extractMarkdownPlainText('above\n\n---\n\nbelow'), 'above\n\nbelow');
  });

  test('a container holding only a rule keeps the text around it', () {
    expect(extractMarkdownPlainText('- ***\n- text'), 'text');
    expect(extractMarkdownPlainText('> ---\n\nafter'), 'after');
  });
}
