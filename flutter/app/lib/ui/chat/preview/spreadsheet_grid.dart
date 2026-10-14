/// The spreadsheet body: a read-only grid per worksheet.
///
/// The reference draws its grid on a canvas through a spreadsheet component
/// (`reference/deepseek-harness/packages/client/ui-sidebar-documentpreview/src/client/excel/excel.tsx:63-65`:
/// read-only, no toolbar, sheet tabs, copy-only context menu). The phone's
/// counterpart is the framework's own scrolling: a frozen column-letter header
/// over one lazily built row per source row, and the worksheet tabs a workbook
/// with more than one sheet needs. There is no cell selection, formatting
/// evaluation or merged-cell geometry, which the reference's canvas component
/// has.
library;

import 'package:flutter/material.dart';

import 'spreadsheet.dart';

/// One parsed workbook or delimited file.
class SpreadsheetGrid extends StatelessWidget {
  const SpreadsheetGrid({required this.preview, super.key});

  final SpreadsheetPreview preview;

  @override
  Widget build(BuildContext context) {
    final sheets = preview.sheets;
    if (sheets.length == 1) return _SheetGrid(sheet: sheets.first);
    return DefaultTabController(
      length: sheets.length,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabs: [for (final sheet in sheets) Tab(text: sheet.name)],
          ),
          Expanded(
            child: TabBarView(
              children: [for (final sheet in sheets) _SheetGrid(sheet: sheet)],
            ),
          ),
        ],
      ),
    );
  }
}

/// One worksheet's rows under a column-letter header.
class _SheetGrid extends StatelessWidget {
  const _SheetGrid({required this.sheet});

  final SpreadsheetSheet sheet;

  /// A cell's width and height, and the row-number gutter's width. The
  /// reference's grid starts from its component's own 73px cell; a phone
  /// reads shorter values, so the cells are narrower and the rows shorter.
  static const double _cellWidth = 104;
  static const double _cellHeight = 32;
  static const double _gutterWidth = 44;

  @override
  Widget build(BuildContext context) {
    final rows = sheet.rows;
    final columns = rows.fold<int>(
      1,
      (widest, row) => row.length > widest ? row.length : widest,
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: _gutterWidth + columns * _cellWidth,
        child: Column(
          children: [
            _HeaderRow(columns: columns),
            Expanded(
              child: ListView.builder(
                itemExtent: _cellHeight,
                itemCount: rows.length,
                itemBuilder: (context, index) => _GridRow(
                  number: index + 1,
                  cells: rows[index],
                  columns: columns,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The frozen header: the gutter's corner and one column letter per column.
class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.columns});

  final int columns;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      height: _SheetGrid._cellHeight,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          const _GutterCell(),
          for (var column = 0; column < columns; column++)
            SizedBox(
              width: _SheetGrid._cellWidth,
              child: Center(
                child: Text(
                  columnName(column),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One source row: its number, then its cells padded to the sheet's width.
class _GridRow extends StatelessWidget {
  const _GridRow({
    required this.number,
    required this.cells,
    required this.columns,
  });

  final int number;
  final List<String> cells;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          _GutterCell(number: number),
          for (var column = 0; column < columns; column++)
            Container(
              width: _SheetGrid._cellWidth,
              height: _SheetGrid._cellHeight,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: scheme.outlineVariant)),
              ),
              child: Text(
                column < cells.length ? cells[column] : '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The row-number gutter: one cell, with a number when the caller has one.
class _GutterCell extends StatelessWidget {
  const _GutterCell({this.number});

  final int? number;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: _SheetGrid._gutterWidth,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        border: Border(right: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Text(
        number == null ? '' : '$number',
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// A zero-based column's spreadsheet name: `A`…`Z`, then `AA`….
String columnName(int index) {
  var remaining = index + 1;
  final letters = <String>[];
  while (remaining > 0) {
    remaining -= 1;
    letters.add(String.fromCharCode(0x41 + remaining % 26));
    remaining ~/= 26;
  }
  return letters.reversed.join();
}
