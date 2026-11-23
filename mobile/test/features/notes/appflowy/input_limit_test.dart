// What is typed or pasted is held to the same limits the page is stored with, so the screen shows what is kept.

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/notes/appflowy/doc_codec.dart' show maxCellText, maxLabelText;
import 'package:mobile/features/notes/data/blocks.dart';
import 'package:mobile/features/notes/data/notes_db.dart';
import 'package:mobile/features/notes/data/workspace.dart';
import 'package:mobile/features/notes/presentation/pages/editor_page.dart';

import 'editor_test_utils.dart';

late NotesDb db;
late Workspace ws;
late String pid;

// words, so that the text wraps (one unbroken word of thousands of letters overflows the stack of the test runner)
String words(int n) => List.filled((n / 3).ceil(), 'ab ').join().substring(0, n);

Future<void> open(WidgetTester tester, List<Block> blocks) async {
  ws.page(pid)!.content = blocks;
  tester.view.physicalSize = const Size(1000, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  await tester.pumpWidget(MaterialApp(theme: AppTheme.dark, home: EditorPage(ws: ws, pageId: pid)));
  await tester.pumpAndSettle();
}

List<Block> body() => ws.page(pid)!.content!;

Block table() {
  final cs = [for (var c = 0; c < 2; c++) TableColumn(id: 'c$c', label: 'Col $c')];
  return Block('t', BlockType.table, cols: cs, rows: [for (var r = 0; r < 2; r++) {for (final c in cs) c.id: 'x'}]);
}

Node cellAt(WidgetTester t, int row, int col) {
  final tableNode = editorOf(t).document.root.children.first;
  return tableNode.children.firstWhere((c) => c.attributes['rowPosition'] == row && c.attributes['colPosition'] == col).children.first;
}

Future<void> paste(WidgetTester t, Node node, String text) async {
  final es = editorOf(t);
  es.selection = Selection.collapsed(Position(path: node.path, offset: node.delta!.length));
  await es.apply(es.transaction..insertText(node, node.delta!.length, text));
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

  testWidgetsLongText('a paste over the limit of a cell is cut on the screen, not only when it is stored', (tester) async {
    await open(tester, [table()]);
    await paste(tester, cellAt(tester, 1, 1), words(3000));
    expect(cellAt(tester, 1, 1).delta!.length, maxCellText);
    expect(body().single.rows![0]['c1']!.length, maxCellText);
  });

  testWidgets('a column label is held to its own, smaller limit', (tester) async {
    await open(tester, [table()]);
    await paste(tester, cellAt(tester, 0, 0), words(500));
    expect(cellAt(tester, 0, 0).delta!.length, maxLabelText);
    expect(body().single.cols![0].label.length, maxLabelText);
  });

  testWidgetsLongText('a text block is held to the block limit', (tester) async {
    await open(tester, [Block('p', BlockType.paragraph, text: 'oi')]);
    await paste(tester, editorOf(tester).document.root.children.first, words(maxText + 500));
    expect(editorOf(tester).document.root.children.first.delta!.length, maxText);
    expect(body().first.text!.length, maxText);
  });

  testWidgetsLongText('under the limit nothing is cut and the caret is not moved', (tester) async {
    await open(tester, [table()]);
    final cell = cellAt(tester, 1, 0);
    await paste(tester, cell, words(1500));
    expect(cell.delta!.length, 1501);
    expect(editorOf(tester).selection!.start.offset, 1501);
  });

  testWidgetsLongText('the markers count: bold text near the limit is cut so that the stored form fits', (tester) async {
    await open(tester, [table()]);
    final es = editorOf(tester);
    final cell = cellAt(tester, 1, 0);
    await paste(tester, cell, words(1990));
    await es.apply(es.transaction..formatText(cell, 0, 1990, {'bold': true}));
    await es.apply(es.transaction..insertText(cell, cell.delta!.length, words(100)));
    await tester.pumpAndSettle();
    expect(body().single.rows![0]['c0']!.length, lessThanOrEqualTo(maxCellText));
    // what is on the screen is what was stored: nothing was cut a second time by the storing
    expect(body().single.rows![0]['c0']!.replaceAll('**', '').length, cell.delta!.length);
  });
}
