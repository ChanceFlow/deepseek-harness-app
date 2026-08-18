import 'package:flutter_test/flutter_test.dart';

import 'package:app/main.dart';

void main() {
  testWidgets('app shell renders its placeholder', (WidgetTester tester) async {
    await tester.pumpWidget(const DshApp());

    expect(find.text('Flutter rewrite in progress'), findsOneWidget);
  });
}
