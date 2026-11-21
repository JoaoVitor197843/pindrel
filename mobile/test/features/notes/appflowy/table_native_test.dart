// The table inside the page editor: the stored table as the package's table, drawn lazily by rows.

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/notes/appflowy/doc_codec.dart' show maxCellText;
import 'package:mobile/features/notes/data/blocks.dart';
import 'package:mobile/features/notes/data/notes_db.dart';
import 'package:mobile/features/notes/data/workspace.dart';
import 'package:mobile/features/notes/presentation/pages/editor_page.dart';

import 'editor_test_utils.dart';

late NotesDb db;
late Workspace ws;
late String pid;

Future<void> open(WidgetTester tester, List<Block> blocks, {Size size = const Size(1000, 1000)}) async {
  ws.page(pid)!.content = blocks;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  await tester.pumpWidget(MaterialApp(theme: AppTheme.dark, home: EditorPage(ws: ws, pageId: pid)));
  await tester.pumpAndSettle();
}

List<Block> body() => ws.page(pid)!.content!;

Block table({int cols = 3, int rows = 3, String id = 't'}) {
  final cs = [for (var c = 0; c < cols; c++) TableColumn(id: 'c$c', label: 'Col $c')];
  return Block(id, BlockType.table, cols: cs, rows: [for (var r = 0; r < rows; r++) {for (final c in cs) c.id: 'r$r${c.id}'}]);
}

/// The paragraph of the cell at [row] (0 = the labels) and [col] of the table at the root index [at].
Node cellAt(WidgetTester t, int row, int col, {int at = 0}) {
  final tableNode = editorOf(t).document.root.children.elementAt(at);
  return tableNode.children.firstWhere((c) => c.attributes['rowPosition'] == row && c.attributes['colPosition'] == col).children.first;
}

Future<void> caretInCell(WidgetTester t, int row, int col, {int offset = 0, int at = 0}) async {
  editorOf(t).selection = Selection.collapsed(Position(path: cellAt(t, row, col, at: at).path, offset: offset));
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    db = NotesDb.inMemory();
    ws = Workspace(db);
    pid = ws.newPage('Teste').id;
  });
  tearDown(() {
    ws.dispose();
    db.dispose();
  });

  group('the two ways of the sync', () {
    testWidgets('a cell edited in the editor is stored; the very same block keeps its id', (tester) async {
      await open(tester, [table()]);
      await caretInCell(tester, 1, 1);
      await typeInto(tester, cellAt(tester, 1, 1), 'novo ');
      await tester.pumpAndSettle();
      expect(body().single.id, 't');
      expect(body().single.rows![0]['c1'], 'novo r0c1');
    });

    testWidgets('marks typed in a cell are stored with the web markers', (tester) async {
      await open(tester, [table()]);
      final es = editorOf(tester);
      final node = cellAt(tester, 1, 0);
      await caretInCell(tester, 1, 0, offset: 0);
      await es.apply(es.transaction..formatText(node, 0, 2, {'bold': true}));
      await tester.pumpAndSettle();
      expect(body().single.rows![0]['c0'], '**r0**c0');
    });

    testWidgets('a change from outside the editor (a row added by the page editor) shows in the cells', (tester) async {
      await open(tester, [table(rows: 2)]);
      final before = tableCells().evaluate().length;
      final ed = bodyOf(tester).ed;
      ed.addRow('t');
      await tester.pumpAndSettle();
      expect(tableCells().evaluate().length, before + 3);
      ed.setCell('t', 0, 'c1', 'de fora');
      await tester.pumpAndSettle();
      expect(find.textContaining('de fora', findRichText: true), findsOneWidget);
    });

    testWidgets('undo takes back a cell edit and the stored table follows', (tester) async {
      await open(tester, [table()]);
      await caretInCell(tester, 2, 2);
      await typeInto(tester, cellAt(tester, 2, 2), 'zzz');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(body().single.rows![1]['c2'], 'zzzr1c2');
      undoCommand.execute(editorOf(tester));
      await tester.pumpAndSettle();
      expect(body().single.rows![1]['c2'], 'r1c2');
    });

    testWidgets('a cell with a line break and a very long text is kept, cut at the limit', (tester) async {
      await open(tester, [table()]);
      await caretInCell(tester, 1, 0);
      await typeInto(tester, cellAt(tester, 1, 0), 'a\nb');
      await typeInto(tester, cellAt(tester, 1, 1), 'x' * 5000);
      await tester.pumpAndSettle();
      expect(body().single.rows![0]['c0'], startsWith('a\nb'));
      expect(body().single.rows![0]['c1']!.length, maxCellText);
    });
  });

  group('keys inside a cell', () {
    testWidgets('Tab goes to the next cell, Shift+Tab back, the next row after the last column', (tester) async {
      await open(tester, [table()]);
      final es = editorOf(tester);
      await caretInCell(tester, 1, 0);
      tabInTableCell.execute(es);
      await tester.pumpAndSettle();
      expect(es.selection!.start.path, cellAt(tester, 1, 1).path);
      tabInTableCell.execute(es);
      tabInTableCell.execute(es);
      await tester.pumpAndSettle();
      expect(es.selection!.start.path, cellAt(tester, 2, 0).path, reason: 'wraps to the next row');
      shiftTabInTableCell.execute(es);
      await tester.pumpAndSettle();
      expect(es.selection!.start.path, cellAt(tester, 1, 2).path);
    });

    testWidgets('arrows leave a cell only at its edge; up and down keep the offset', (tester) async {
      await open(tester, [table()]);
      final es = editorOf(tester);
      await caretInCell(tester, 1, 1, offset: 2);
      downInTableCell.execute(es);
      await tester.pumpAndSettle();
      expect(es.selection!.start.path, cellAt(tester, 2, 1).path);
      expect(es.selection!.start.offset, 2);
      upInTableCell.execute(es);
      await tester.pumpAndSettle();
      expect(es.selection!.start.path, cellAt(tester, 1, 1).path);
      leftInTableCell.execute(es);
      await tester.pumpAndSettle();
      expect(es.selection!.start.path, cellAt(tester, 1, 1).path, reason: 'not at the start yet');
      await caretInCell(tester, 1, 1, offset: 0);
      leftInTableCell.execute(es);
      await tester.pumpAndSettle();
      expect(es.selection!.start.path, cellAt(tester, 1, 0).path);
    });

    testWidgets('Enter in the last row opens a paragraph after the table; Backspace at the start of a cell stops there', (tester) async {
      await open(tester, [table(rows: 1)]);
      final es = editorOf(tester);
      await caretInCell(tester, 1, 0);
      final before = cellAt(tester, 1, 0).delta!.toPlainText();
      backspaceCommand.execute(es);
      await tester.pumpAndSettle();
      expect(cellAt(tester, 1, 0).delta!.toPlainText(), before);
      expect(body().single.type, BlockType.table);
      enterInTableCell.execute(es);
      await tester.pumpAndSettle();
      expect(body().map((b) => b.type), [BlockType.table, BlockType.paragraph]);
    });

    testWidgets('typing "# ", "- ", "> ", "1. ", "[] " or "---" in a cell does not turn it into another block', (tester) async {
      await open(tester, [table()]);
      final es = editorOf(tester);
      for (final seed in ['#', '-', '>', '1.', '[]', '*']) {
        await caretInCell(tester, 1, 0);
        final node = cellAt(tester, 1, 0);
        es.apply(es.transaction..deleteText(node, 0, node.delta!.length));
        await typeInto(tester, node, seed);
        es.selection = Selection.collapsed(Position(path: node.path, offset: seed.length));
        await tester.pump();
        await pressChar(tester, ' ');
        expect(es.getNodeAtPath(node.path)!.type, 'paragraph', reason: seed);
        expect(es.getNodeAtPath(node.path)!.parent!.type, 'table/cell', reason: seed);
      }
      expect(body().single.type, BlockType.table);
      expect(body().length, 1);
    });

    testWidgets('"/" in an empty cell does not open the insert menu', (tester) async {
      await open(tester, [table()]);
      final es = editorOf(tester);
      final node = cellAt(tester, 1, 0);
      await caretInCell(tester, 1, 0);
      es.apply(es.transaction..deleteText(node, 0, node.delta!.length));
      await tester.pump();
      await pressChar(tester, '/');
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Inserir bloco'), findsNothing);
    });

    testWidgets('inline marks still work in a cell: **x** becomes bold', (tester) async {
      await open(tester, [table()]);
      final es = editorOf(tester);
      final node = cellAt(tester, 1, 0);
      await caretInCell(tester, 1, 0);
      es.apply(es.transaction..deleteText(node, 0, node.delta!.length));
      await typeInto(tester, node, '**x*');
      es.selection = Selection.collapsed(Position(path: node.path, offset: 4));
      await tester.pump();
      await pressChar(tester, '*');
      await tester.pumpAndSettle();
      expect(body().single.rows![0]['c0'], '**x**');
    });
  });

  group('the bar under the table', () {
    testWidgets('the row and column menus: the header row cannot be removed or have a row put above it', (tester) async {
      await open(tester, [table()]);
      await caretInCell(tester, 0, 1);
      await tester.tap(find.byTooltip('Cabeçalho'));
      await tester.pumpAndSettle();
      expect(find.text('Inserir linha abaixo'), findsOneWidget);
      expect(find.text('Inserir linha acima'), findsNothing);
      expect(find.text('Duplicar linha'), findsNothing);
      expect(find.descendant(of: find.byType(PopupMenuItem<int>), matching: find.text('Excluir linha')), findsNothing);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
    });

    testWidgets('a column menu: widen and narrow are one edit each and undo brings the width back', (tester) async {
      await open(tester, [table()]);
      await caretInCell(tester, 1, 0);
      await tester.tap(find.byTooltip('Coluna 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alargar coluna'));
      await tester.pumpAndSettle();
      expect(body().single.cols!.first.w, 200);
      await tester.tap(find.byTooltip('Coluna 1'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 1; i++) {
        await tester.tap(find.text('Estreitar coluna'));
        await tester.pumpAndSettle();
      }
      expect(body().single.cols!.first.w, 160);
      await tester.pump(const Duration(milliseconds: 300));
      undoCommand.execute(editorOf(tester));
      await tester.pumpAndSettle();
      expect(body().single.cols!.first.w, 200);
    });

    testWidgets('a column cannot be narrower than the model allows nor wider than it allows', (tester) async {
      await open(tester, [table()]);
      await caretInCell(tester, 1, 0);
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byTooltip('Coluna 1'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Estreitar coluna'));
        await tester.pumpAndSettle();
      }
      expect(body().single.cols!.first.w, greaterThanOrEqualTo(minColWidth));
      for (var i = 0; i < 20; i++) {
        await tester.tap(find.byTooltip('Coluna 1'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Alargar coluna'));
        await tester.pumpAndSettle();
      }
      expect(body().single.cols!.first.w, lessThanOrEqualTo(maxColWidth));
    });

    testWidgets('the limits hide "+ coluna" at 12 columns and "+ linha" at 200 rows', (tester) async {
      await open(tester, [table(cols: 12, rows: 2)]);
      await caretInCell(tester, 1, 0);
      expect(find.byTooltip('Adicionar coluna'), findsNothing);
      expect(find.text('+ linha'), findsOneWidget);
      ws.page(pid)!.content = [table(cols: 2, rows: 200)];
      bodyOf(tester).ed.notifyListeners();
      await tester.pumpAndSettle();
      await caretInCell(tester, 1, 0);
      expect(find.text('+ linha'), findsNothing);
      expect(find.byTooltip('Adicionar coluna'), findsOneWidget);
    });

    testWidgets('the last column and the last body row cannot be removed', (tester) async {
      await open(tester, [table(cols: 1, rows: 1)]);
      await caretInCell(tester, 1, 0);
      await tester.tap(find.byTooltip('Coluna 1'));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(PopupMenuItem<int>), matching: find.text('Excluir coluna')), findsNothing);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Linha 1'));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(PopupMenuItem<int>), matching: find.text('Excluir linha')), findsNothing);
    });

    testWidgets('the bar\'s block menu acts on the whole table when the caret is in a cell', (tester) async {
      await open(tester, [Block('a', BlockType.paragraph, text: 'antes'), table()]);
      await caretInCell(tester, 1, 1, at: 1);
      await tester.tap(find.byTooltip('Opções do bloco'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Duplicar'));
      await tester.pumpAndSettle();
      expect(body().map((b) => b.type), [BlockType.paragraph, BlockType.table, BlockType.table]);
      expect(body()[1].id, isNot(body()[2].id));
    });

    testWidgets('clearing a row empties its cells and keeps the table', (tester) async {
      await open(tester, [table()]);
      await caretInCell(tester, 2, 1);
      await tester.tap(find.byTooltip('Linha 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Limpar linha'));
      await tester.pumpAndSettle();
      expect(body().single.rows![1].values.every((v) => v.isEmpty), true);
      expect(editorOf(tester).document.root.children.first.children.every((c) => c.children.length == 1), true, reason: 'one paragraph per cell');
      expect(body().single.rows![0]['c0'], 'r0c0');
    });
  });

  group('careless use and load', () {
    testWidgets('five tables of 12 x 100 open, scroll end to end and keep only the near rows', (tester) async {
      await open(tester, [for (var i = 0; i < 5; i++) table(cols: 12, rows: 100, id: 't$i')], size: const Size(800, 700));
      expect(tableCells().evaluate().length, lessThan(12 * 80), reason: 'a table has 1212 cells, nothing like all of them is built');
      final scroll = find.byType(Scrollable).evaluate().map((e) => (e as StatefulElement).state as ScrollableState).where((s) => s.widget.axis == Axis.vertical).first;
      for (var i = 0; i < 40; i++) {
        scroll.position.jumpTo(scroll.position.maxScrollExtent * i / 39);
        await tester.pump();
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
      expect(tableCells().evaluate().length, lessThan(12 * 100));
      expect(body().length, 5);
    });

    testWidgets('taps all over the cells, fast and out of order, never lose or change a cell', (tester) async {
      await open(tester, [table()]);
      final before = [for (final r in body().single.rows!) Map.of(r)];
      final cells = tableCells();
      for (var i = 0; i < 40; i++) {
        final n = cells.evaluate().length;
        await tester.tap(cells.at((i * 7) % n), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(body().single.rows, before);
    });

    testWidgets('the selection leaving the page (null) with a menu open does not lose the bar or break', (tester) async {
      await open(tester, [table()]);
      await caretInCell(tester, 1, 0);
      await tester.tap(find.byTooltip('Linha 1'));
      await tester.pumpAndSettle();
      editorOf(tester).selection = null;
      await tester.pumpAndSettle();
      expect(find.text('Inserir linha abaixo'), findsOneWidget, reason: 'the menu stays while it is open');
      await tester.tap(find.text('Inserir linha abaixo'));
      await tester.pumpAndSettle();
      expect(body().single.rows!.length, 4);
      expect(tester.takeException(), isNull);
    });

    testWidgets('320 px and a huge text scale do not overflow', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await open(tester, [table()], size: const Size(320, 640));
      await caretInCell(tester, 1, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a page with a table, a deleted table and a table moved around keeps the other blocks', (tester) async {
      await open(tester, [Block('a', BlockType.paragraph, text: 'um'), table(), Block('b', BlockType.paragraph, text: 'dois')]);
      final ed = bodyOf(tester).ed;
      ed.moveBy('t', 1);
      await tester.pumpAndSettle();
      expect(body().map((b) => b.id), ['a', 'b', 't']);
      ed.remove('t');
      await tester.pumpAndSettle();
      expect(body().map((b) => b.id), ['a', 'b']);
    });
  });
}
