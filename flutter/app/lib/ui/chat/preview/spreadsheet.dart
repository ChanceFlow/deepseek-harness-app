/// Spreadsheet previews — the parsed sheets of a complete file, and the
/// bounds a phone preview accepts.
///
/// The reference parses `xlsx`, `xls`, `csv` and `tsv` in the browser under
/// three limits and reports a stable set of failures
/// (`reference/deepseek-harness/packages/client/ui-sidebar-documentpreview/src/client/excel/parse.ts:18-40`,
/// `.../excel/delimited.ts:15-34`, `.../excel/locales.ts:2-11`): source bytes,
/// combined rectangular cell area, and a parser deadline. The two byte and
/// area limits are the same here; the deadline belongs to the reference's
/// Web Worker and has no counterpart on one isolate, so the caps are what
/// bound the work.
///
/// `xls` is not read here: the reference decodes BIFF itself
/// (`.../excel/xls.ts`), and no phone parser is ported yet, so that suffix
/// stays in the unviewable list rather than promising a body it has not got.
library;

import 'dart:convert';
import 'dart:typed_data';

/// Maximum source file bytes: the reference's `excel.maxBytes`
/// (`.../src/config.ts:37`).
const int kSpreadsheetMaxBytes = 16 * 1024 * 1024;

/// Maximum combined rectangular cell area across worksheets: the reference's
/// `excel.maxCells` (`.../src/config.ts:38`).
const int kSpreadsheetMaxCells = 250000;

/// Maximum columns one sheet may have. The reference allocates dense canvas
/// cells, so its area limit alone bounds a sheet; a widget grid builds one
/// widget per cell of the rows it shows, so a row wider than this would be
/// built whole. A sheet over it reports the size limit rather than silently
/// showing part of the data.
const int kSpreadsheetMaxColumns = 300;

/// One worksheet as display text.
class SpreadsheetSheet {
  const SpreadsheetSheet({
    required this.name,
    required this.rows,
    this.hasFormulas = false,
  });

  /// The worksheet's own name.
  final String name;

  /// Row-major display text; every row is as long as that row's fields.
  final List<List<String>> rows;

  /// Whether any cell carried a formula. The reference shows the warning
  /// without evaluating anything (`.../excel/excel.tsx:50,58-62`).
  final bool hasFormulas;
}

/// A parsed workbook, or the single sheet of a delimited file.
class SpreadsheetPreview {
  const SpreadsheetPreview({required this.sheets});

  final List<SpreadsheetSheet> sheets;
}

/// Why a spreadsheet could not be previewed, read off the reference's own
/// failure keys (`.../excel/locales.ts:5-6`).
enum SpreadsheetFailure {
  /// The format could not be opened: malformed, password protected, or not
  /// the format its suffix promised.
  invalid,

  /// The file, or the rectangle it would allocate, is over a limit.
  tooLarge,

  /// A delimited file that is neither UTF-8 nor BOM-marked UTF-16.
  encoding,
}

/// The failure a parse stopped for.
class SpreadsheetException implements Exception {
  const SpreadsheetException(this.failure);

  final SpreadsheetFailure failure;

  @override
  String toString() => 'SpreadsheetException(${failure.name})';
}

/// Parses one delimited file: UTF-8, or UTF-16 when a byte-order mark says so
/// (`.../excel/delimited.ts:15-19`), with literal field values and no type
/// inference (`:24-34`).
SpreadsheetPreview parseDelimited(
  Uint8List bytes, {
  required String delimiter,
  required String sheetName,
}) {
  if (bytes.length > kSpreadsheetMaxBytes) {
    throw const SpreadsheetException(SpreadsheetFailure.tooLarge);
  }
  return SpreadsheetPreview(
    sheets: <SpreadsheetSheet>[
      _parseFields(
        _decodeDelimited(bytes),
        delimiter: delimiter,
        name: sheetName,
      ),
    ],
  );
}

/// Decodes a delimited file's bytes, refusing an encoding the reference also
/// refuses.
String _decodeDelimited(Uint8List bytes) {
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _decodeUtf16(bytes.sublist(2), Endian.little);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _decodeUtf16(bytes.sublist(2), Endian.big);
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    throw const SpreadsheetException(SpreadsheetFailure.encoding);
  }
}

/// UTF-16 code units to text; a trailing odd byte is not a code unit and is
/// dropped.
String _decodeUtf16(Uint8List bytes, Endian endian) {
  final data = ByteData.sublistView(bytes);
  final units = Uint16List(bytes.length ~/ 2);
  for (var index = 0; index < units.length; index++) {
    units[index] = data.getUint16(index * 2, endian);
  }
  return String.fromCharCodes(units);
}

/// One delimited document into one sheet.
///
/// Quoting is RFC 4180: a quoted field may contain the delimiter, line breaks
/// and doubled quotes. The area and column limits are the reference's, applied
/// as the fields are read so an oversized document stops instead of
/// allocating its whole rectangle (`.../excel/delimited.ts:25-30`). The result
/// has at least one row and one column, which is the reference's own floor
/// (`.../excel/delimited.ts:41-42`).
SpreadsheetSheet _parseFields(
  String text, {
  required String delimiter,
  required String name,
}) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  var index = 0;
  var columns = 0;

  void endField() {
    row.add(field.toString());
    field.clear();
  }

  void endRow() {
    endField();
    if (row.length > columns) columns = row.length;
    rows.add(row);
    row = <String>[];
    if (columns > kSpreadsheetMaxColumns ||
        rows.length * columns > kSpreadsheetMaxCells) {
      throw const SpreadsheetException(SpreadsheetFailure.tooLarge);
    }
  }

  while (index < text.length) {
    final character = text[index];
    if (quoted) {
      if (character == '"') {
        if (index + 1 < text.length && text[index + 1] == '"') {
          field.write('"');
          index += 2;
          continue;
        }
        quoted = false;
        index += 1;
        continue;
      }
      field.write(character);
      index += 1;
      continue;
    }
    if (character == '"' && field.isEmpty) {
      quoted = true;
      index += 1;
      continue;
    }
    if (character == delimiter) {
      endField();
      index += 1;
      continue;
    }
    if (character == '\n' || character == '\r') {
      if (character == '\r' &&
          index + 1 < text.length &&
          text[index + 1] == '\n') {
        index += 1;
      }
      endRow();
      index += 1;
      continue;
    }
    field.write(character);
    index += 1;
  }
  // The field and row still open at the end; a document that ended with a
  // line break closed its last row already and gains no empty one.
  if (field.isNotEmpty || row.isNotEmpty) endRow();
  if (rows.isEmpty) rows.add(<String>['']);
  return SpreadsheetSheet(name: name, rows: rows);
}
