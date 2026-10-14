/// Workbook tests: one real archive read into sheets, and the states a
/// workbook that cannot be read earns.
///
/// The fixture is written by the same OOXML reader's writer, so the bytes are
/// a real package rather than a hand-built model, and the assertions are about
/// this preview's own mapping: display text per cell, and the formula flag.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:app/ui/chat/preview/spreadsheet.dart';
import 'package:app/ui/chat/preview/workbook.dart';
import 'package:excel/excel.dart' as xls;
import 'package:flutter_test/flutter_test.dart';

/// A one-sheet workbook whose `A1` is text, `B1` a number and `C1` a formula.
Uint8List _workbook() {
  final book = xls.Excel.createExcel();
  final sheet = book['Sheet1'];
  sheet.cell(xls.CellIndex.indexByString('A1')).value = xls.TextCellValue('hi');
  sheet.cell(xls.CellIndex.indexByString('B1')).value = const xls.IntCellValue(
    2,
  );
  sheet.cell(xls.CellIndex.indexByString('C1')).value =
      const xls.FormulaCellValue('SUM(B1:B2)');
  return Uint8List.fromList(book.encode()!);
}

void main() {
  test('a workbook reads into sheets with display text and a formula flag', () {
    final preview = parseWorkbook(_workbook());

    expect(preview.sheets.length, 1);
    final sheet = preview.sheets.single;
    expect(sheet.rows.first.take(3), <String>['hi', '2', 'SUM(B1:B2)']);
    expect(sheet.hasFormulas, isTrue);
  });

  test('bytes that are not an archive report an invalid workbook', () {
    expect(
      () => parseWorkbook(Uint8List.fromList(utf8.encode('not a zip'))),
      throwsA(
        isA<SpreadsheetException>().having(
          (error) => error.failure,
          'failure',
          SpreadsheetFailure.invalid,
        ),
      ),
    );
  });

  test('a workbook over the byte limit reports the size limit', () {
    expect(
      () => parseWorkbook(Uint8List(kSpreadsheetMaxBytes + 1)),
      throwsA(
        isA<SpreadsheetException>().having(
          (error) => error.failure,
          'failure',
          SpreadsheetFailure.tooLarge,
        ),
      ),
    );
  });
}
