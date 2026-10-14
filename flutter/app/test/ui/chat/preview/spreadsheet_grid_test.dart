/// Spreadsheet grid tests: what one parsed sheet shows.
library;

import 'package:app/ui/chat/preview/spreadsheet.dart';
import 'package:app/ui/chat/preview/spreadsheet_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../l10n_app.dart';

void main() {
  test('a zero-based column is named the spreadsheet way', () {
    expect(columnName(0), 'A');
    expect(columnName(25), 'Z');
    expect(columnName(26), 'AA');
    expect(columnName(27), 'AB');
    expect(columnName(51), 'AZ');
    expect(columnName(52), 'BA');
    expect(columnName(701), 'ZZ');
    expect(columnName(702), 'AAA');
  });

  testWidgets('a sheet shows its header letters, row numbers and cells', (
    tester,
  ) async {
    const preview = SpreadsheetPreview(
      sheets: <SpreadsheetSheet>[
        SpreadsheetSheet(
          name: 'CSV',
          rows: <List<String>>[
            <String>['name', 'count'],
            <String>['alpha', 'two'],
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      l10nApp(
        home: const Scaffold(body: SpreadsheetGrid(preview: preview)),
      ),
    );
    await tester.pumpAndSettle();

    // The column letters and the row numbers of the frozen gutter.
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    // The cells themselves.
    expect(find.text('name'), findsOneWidget);
    expect(find.text('count'), findsOneWidget);
    expect(find.text('alpha'), findsOneWidget);
  });

  testWidgets('a workbook with two sheets shows one tab per sheet', (
    tester,
  ) async {
    const preview = SpreadsheetPreview(
      sheets: <SpreadsheetSheet>[
        SpreadsheetSheet(
          name: 'First',
          rows: <List<String>>[
            <String>['a'],
          ],
        ),
        SpreadsheetSheet(
          name: 'Second',
          rows: <List<String>>[
            <String>['b'],
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      l10nApp(
        home: const Scaffold(body: SpreadsheetGrid(preview: preview)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Tab), findsNWidgets(2));
    expect(find.text('First'), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);
    expect(find.text('a'), findsOneWidget);

    await tester.tap(find.text('Second'));
    await tester.pumpAndSettle();
    expect(find.text('b'), findsOneWidget);
  });
}
