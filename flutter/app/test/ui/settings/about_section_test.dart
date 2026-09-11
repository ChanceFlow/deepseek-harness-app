/// About section tests: the build's version, the docs link, and the feedback
/// link.
library;

import 'package:app/config.dart';
import 'package:app/ui/settings/about_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../l10n_app.dart';

Future<void> _pump(WidgetTester tester, {Locale? locale}) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    l10nApp(
      locale: locale,
      home: const Scaffold(
        body: SingleChildScrollView(child: SettingsAboutSection()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the real build version, docs, and feedback rows', (
    WidgetTester tester,
  ) async {
    await _pump(tester);

    expect(find.text('About'), findsOneWidget);
    expect(find.text('App version'), findsOneWidget);
    // The build-time constants are the only version source.
    expect(
      find.text('$kDshAppVersion (build $kDshBuildNumber)'),
      findsOneWidget,
    );
    expect(find.text('Documentation'), findsOneWidget);
    expect(find.text('Report a bug or send feedback'), findsOneWidget);
  });

  testWidgets('both link rows are tappable and carry the external-link icon', (
    WidgetTester tester,
  ) async {
    await _pump(tester);

    expect(find.byIcon(Icons.open_in_new), findsNWidgets(2));

    final ListTile docs = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'Documentation'),
    );
    final ListTile feedback = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'Report a bug or send feedback'),
    );
    expect(docs.onTap, isNotNull);
    expect(feedback.onTap, isNotNull);
  });

  testWidgets('has no telemetry toggle', (WidgetTester tester) async {
    await _pump(tester);

    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.byType(Switch), findsNothing);
  });

  testWidgets('localizes the section in Chinese', (WidgetTester tester) async {
    await _pump(tester, locale: const Locale('zh'));

    expect(find.text('关于'), findsOneWidget);
    expect(find.text('应用版本'), findsOneWidget);
    expect(find.text('文档'), findsOneWidget);
    expect(find.text('报告问题或发送反馈'), findsOneWidget);
  });

  test('the repository links hang off the build-provided source repo', () {
    expect(kAboutRepositoryUrl, contains(kDshSourceRepo));
    expect(kAboutRepositoryUrl, startsWith('https://'));
  });
}
