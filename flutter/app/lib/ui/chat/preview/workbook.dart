/// XLSX workbooks into the phone's spreadsheet preview.
library;

import 'dart:typed_data';

import 'package:excel/excel.dart' as workbook;

import 'spreadsheet.dart';

/// Parses one `.xlsx` workbook through the maintained pure-Dart reader.
///
/// The reference decodes the OOXML archive itself and drops the parts it does
/// not draw (`reference/deepseek-harness/packages/client/ui-sidebar-documentpreview/src/client/excel/xlsx.ts:26-31`,
/// `.../excel/xlsx-archive.ts:32-64`). This build hands the archive to
/// `package:excel` and shows the cells it yields: charts, images, shapes and
/// conditional formatting are not detected, so the reference's
/// unsupported-feature notice has no source here, and a formula cell shows its
/// formula instead of a result this reader never computed — the reference
/// warns about those missing results (`.../excel/locales.ts:6`).
///
/// A workbook with no visible worksheet, a malformed archive and a
/// password-protected file all reach the reader as an exception; the reference
/// reports one state for them (`.../excel/xlsx.ts:35`,
/// `.../excel/locales.ts:5`).
SpreadsheetPreview parseWorkbook(Uint8List bytes) {
  if (bytes.length > kSpreadsheetMaxBytes) {
    throw const SpreadsheetException(SpreadsheetFailure.tooLarge);
  }
  final workbook.Excel book;
  try {
    book = workbook.Excel.decodeBytes(bytes);
  } catch (_) {
    throw const SpreadsheetException(SpreadsheetFailure.invalid);
  }
  final sheets = <SpreadsheetSheet>[];
  var area = 0;
  for (final entry in book.tables.entries) {
    final columns = entry.value.maxColumns;
    final rows = entry.value.rows;
    if (columns > kSpreadsheetMaxColumns) {
      throw const SpreadsheetException(SpreadsheetFailure.tooLarge);
    }
    area += rows.length * columns;
    if (area > kSpreadsheetMaxCells) {
      throw const SpreadsheetException(SpreadsheetFailure.tooLarge);
    }
    var hasFormulas = false;
    final display = <List<String>>[];
    for (final row in rows) {
      final cells = <String>[];
      for (final cell in row) {
        final value = cell?.value;
        if (value is workbook.FormulaCellValue) hasFormulas = true;
        cells.add(_displayText(value));
      }
      display.add(cells);
    }
    sheets.add(
      SpreadsheetSheet(
        name: entry.key,
        rows: display.isEmpty
            ? <List<String>>[
                <String>[''],
              ]
            : display,
        hasFormulas: hasFormulas,
      ),
    );
  }
  if (sheets.isEmpty) {
    throw const SpreadsheetException(SpreadsheetFailure.invalid);
  }
  return SpreadsheetPreview(sheets: sheets);
}

/// One cell's display text. Every scalar the reader yields has a text form;
/// richer spans keep the reader's own rendering.
String _displayText(workbook.CellValue? value) => switch (value) {
  null => '',
  final workbook.TextCellValue text => text.value.toString(),
  final workbook.FormulaCellValue formula => formula.formula,
  _ => value.toString(),
};
