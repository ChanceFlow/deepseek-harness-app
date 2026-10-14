/// Delimited-format spreadsheet tests: the fields a file's bytes name, and the
/// bounds that stop a parse.
///
/// The contract is the reference's delimited reader
/// (`reference/deepseek-harness/packages/client/ui-sidebar-documentpreview/src/client/excel/delimited.ts:15-44`):
/// UTF-8 or BOM-marked UTF-16, RFC 4180 quoting, literal values, and the byte
/// and area limits from `.../src/config.ts:36-40`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:app/ui/chat/preview/spreadsheet.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

SpreadsheetSheet _parse(String text, {String delimiter = ','}) =>
    parseDelimited(
      _bytes(text),
      delimiter: delimiter,
      sheetName: 'CSV',
    ).sheets.single;

void main() {
  test('fields, rows and quoting are read literally', () {
    final sheet = _parse('a,b\n"x,y",2\n"say ""hi""",\n');

    expect(sheet.rows, <List<String>>[
      <String>['a', 'b'],
      <String>['x,y', '2'],
      <String>['say "hi"', ''],
    ]);
  });

  test('a quoted field may carry a line break', () {
    final sheet = _parse('a,"one\ntwo"\n');

    expect(sheet.rows, <List<String>>[
      <String>['a', 'one\ntwo'],
    ]);
  });

  test('CRLF and a trailing line break add no empty row', () {
    final sheet = _parse('a,b\r\nc,d\r\n');

    expect(sheet.rows, <List<String>>[
      <String>['a', 'b'],
      <String>['c', 'd'],
    ]);
  });

  test('an empty file is one empty cell, which is the reference floor', () {
    expect(_parse('').rows, <List<String>>[
      <String>[''],
    ]);
  });

  test('a tab-separated file splits on the delimiter it was read with', () {
    final sheet = _parse('a\tb\n1\t2\n', delimiter: '\t');

    expect(sheet.rows, <List<String>>[
      <String>['a', 'b'],
      <String>['1', '2'],
    ]);
  });

  test('a UTF-16LE BOM decides the encoding', () {
    final bytes = Uint8List.fromList(<int>[
      0xFF,
      0xFE,
      ...'a,b\n'.codeUnits.expand((unit) => <int>[unit & 0xFF, unit >> 8]),
    ]);

    final sheet = parseDelimited(
      bytes,
      delimiter: ',',
      sheetName: 'CSV',
    ).sheets.single;
    expect(sheet.rows, <List<String>>[
      <String>['a', 'b'],
    ]);
  });

  test(
    'bytes that are neither UTF-8 nor BOM-marked UTF-16 report encoding',
    () {
      expect(
        () => parseDelimited(
          Uint8List.fromList(<int>[0x61, 0xFF, 0xFE, 0x61]),
          delimiter: ',',
          sheetName: 'CSV',
        ),
        throwsA(
          isA<SpreadsheetException>().having(
            (error) => error.failure,
            'failure',
            SpreadsheetFailure.encoding,
          ),
        ),
      );
    },
  );

  test('a rectangle over the cell limit reports the size limit', () {
    final wide = '${List<String>.filled(60, 'x').join(',')}\n' * 5000;

    expect(
      () => _parse(wide),
      throwsA(
        isA<SpreadsheetException>().having(
          (error) => error.failure,
          'failure',
          SpreadsheetFailure.tooLarge,
        ),
      ),
    );
  });

  test('a row wider than the column limit reports the size limit', () {
    final row = List<String>.filled(kSpreadsheetMaxColumns + 1, 'x').join(',');

    expect(() => _parse('$row\n'), throwsA(isA<SpreadsheetException>()));
  });
}
