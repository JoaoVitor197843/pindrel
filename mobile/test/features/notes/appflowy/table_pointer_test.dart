// The table with the mouse and the finger: what a person does first. Written after the first version could not select
// text with the mouse and needed two taps to move between cells.

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/notes/data/blocks.dart';
import 'package:mobile/features/notes/data/notes_db.dart';
import 'package:mobile/features/notes/data/workspace.dart';
import 'package:mobile/features/notes/presentation/pages/editor_page.dart';

import 'editor_test_utils.dart';

late NotesDb db;
late Workspace ws;
late String pid;

Block table({int cols = 3, int rows = 3, int w = 160}) {
  final cs = [for (var c = 0; c < cols; c++) TableColumn(id: 'c$c', label: 'Col $c', w: w)];
  return Block('t', BlockType.table, cols: cs, rows: [for (var r = 0; r < rows; r++) {for (final c in cs) c.id: 'cel $r ${c.id}'}]);
}

List<Block> body() => ws.page(pid)!.content!;

Future<void> open(WidgetTester tester, List<Block> blocks, {Size size = const Size(1300, 800)}) async {
  ws.page(pid)!.content = blocks;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  await tester.pumpWidget(MaterialApp(theme: AppTheme.dark, home: EditorPage(ws: ws, pageId: pid)));
  await tester.pumpAndSettle();
}

Finder text(String s) => find.descendant(of: find.byType(RowsTableView), matching: find.textContaining(s, findRichText: true));

String sel(WidgetTester t) {
  final s = editorOf(t).selection;
  return s == null ? 'null' : '${s.start.path}:${s.start.offset}..${s.end.path}:${s.end.offset}';
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

  for (final (name, platform, kind) in [('mouse on Linux', TargetPlatform.linux, PointerDeviceKind.mouse), ('finger on Android', TargetPlatform.android, PointerDeviceKind.touch)]) {
    group(name, () {
      Future<void> click(WidgetTester t, Finder f, {double dx = 0}) async {
        final g = await t.startGesture(t.getCenter(f.first) + Offset(dx, 0), kind: kind);
        await t.pump(const Duration(milliseconds: 60));
        await g.up();
        await t.pump(const Duration(milliseconds: 400));
        await t.pumpAndSettle();
      }

      testWidgets('ONE click on another cell puts the caret in it, every time', variant: TargetPlatformVariant.only(platform), (tester) async {
        await open(tester, [table()]);
        await click(tester, text('cel 0 c0'));
        expect(editorOf(tester).selection!.start.path, cellParagraphPath(tester, 1, 0));
        for (final (row, col) in [(1, 1), (2, 2), (0, 2), (2, 0), (1, 1)]) {
          await click(tester, text('cel $row c$col'));
          expect(editorOf(tester).selection!.start.path, cellParagraphPath(tester, row + 1, col), reason: 'cell $row/$col');
        }
      });

      testWidgets('the caret goes where the click is, not to the end of the text', variant: TargetPlatformVariant.only(platform), (tester) async {
        await open(tester, [table()]);
        final f = text('cel 1 c1');
        final box = tester.getRect(f.first);
        final g = await tester.startGesture(Offset(box.left + 3, box.center.dy), kind: kind);
        await g.up();
        await tester.pumpAndSettle(const Duration(milliseconds: 400));
        expect(editorOf(tester).selection!.start.offset, lessThan(2));
      });

      testWidgets('typing after the click goes into that cell, and is stored', variant: TargetPlatformVariant.only(platform), (tester) async {
        await open(tester, [table()]);
        await click(tester, text('cel 1 c2'));
        final es = editorOf(tester);
        await typeInto(tester, es.getNodeAtPath(es.selection!.start.path)!, 'oi ');
        await tester.pumpAndSettle();
        expect(body().single.rows![1]['c2'], startsWith('oi '));
      });
    });
  }

  group('mouse', () {
    Future<void> drag(WidgetTester t, Offset from, Offset to) async {
      final g = await t.startGesture(from, kind: PointerDeviceKind.mouse);
      await g.moveBy(const Offset(6, 0));
      for (var i = 1; i <= 8; i++) {
        await g.moveTo(from + (to - from) * (i / 8));
        await t.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await t.pumpAndSettle();
    }

    testWidgets('dragging over the text of a cell selects it', variant: TargetPlatformVariant.only(TargetPlatform.linux), (tester) async {
      await open(tester, [table()]);
      final box = tester.getRect(text('cel 1 c0').first);
      await drag(tester, Offset(box.left + 2, box.center.dy), Offset(box.left + 40, box.center.dy));
      final s = editorOf(tester).selection!;
      expect(s.isCollapsed, false);
      expect(s.start.path, s.end.path);
      expect(s.normalized.start.offset, 0);
    });

    testWidgets('dragging from a cell to another selects across them', variant: TargetPlatformVariant.only(TargetPlatform.linux), (tester) async {
      await open(tester, [table()]);
      final a = tester.getRect(text('cel 0 c0').first), b = tester.getRect(text('cel 2 c2').first);
      await drag(tester, Offset(a.left + 4, a.center.dy), Offset(b.left + 40, b.center.dy));
      final s = editorOf(tester).selection!.normalized;
      expect(s.start.path, isNot(s.end.path));
      expect(s.start.path, cellParagraphPath(tester, 1, 0));
      expect(s.end.path, cellParagraphPath(tester, 3, 2));
    });

    testWidgets('a double click selects a word of the cell', variant: TargetPlatformVariant.only(TargetPlatform.linux), (tester) async {
      await open(tester, [Block('t', BlockType.table, cols: [TableColumn(id: 'a', label: 'A', w: 300)], rows: [{'a': 'um dois três'}])]);
      final f = text('um dois');
      final at = tester.getCenter(f.first);
      await tester.tapAt(at, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(at, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      final s = editorOf(tester).selection!;
      expect(s.isCollapsed, false);
      expect(s.normalized.end.offset - s.normalized.start.offset, lessThan('um dois três'.length));
    });

    testWidgets('the header edge is dragged to resize a column, in one edit', variant: TargetPlatformVariant.only(TargetPlatform.linux), (tester) async {
      await open(tester, [table()]);
      final head = tester.getRect(text('Col 0').first);
      final x = head.left - 8 + 160 - 3; // the 8 px strip at the right edge of the column
      final g = await tester.startGesture(Offset(x, head.center.dy), kind: PointerDeviceKind.mouse);
      await g.moveBy(const Offset(10, 0));
      await g.moveBy(const Offset(50, 0));
      await g.up();
      await tester.pumpAndSettle();
      expect(body().single.cols!.first.w, closeTo(220, 12));
      expect(body().single.cols![1].w, 160);
    });
  });

  contextMenuTests();

  group('how it looks', () {
    testWidgets('the cells start where the text of the page starts, the handles hang on the left', (tester) async {
      await open(tester, [Block('p', BlockType.paragraph, text: 'texto da página'), table()]);
      final para = tester.getTopLeft(find.textContaining('texto da página', findRichText: true).first).dx;
      final firstCellText = tester.getTopLeft(text('cel 0 c0').first).dx;
      // the cell's own 8 px padding, like the web's inputs
      expect(firstCellText - para, closeTo(8, 1));
      final handle = tester.getTopLeft(find.byTooltip('Linha 1')).dx;
      expect(handle, lessThan(para), reason: 'the row handles are in the gutter, left of the text');
    });

    testWidgets('the table is as wide as the page column and starts at its left edge, not centered', (tester) async {
      await open(tester, [table(cols: 2, w: 100)]);
      final cell = tester.getTopLeft(text('cel 0 c0').first).dx;
      final grip = tester.getTopLeft(find.byTooltip('Linha 1')).dx;
      expect(cell - grip, closeTo(32, 1), reason: 'a narrow table is not pushed to the middle: 24 px handle at the right of the 28 px gutter, then the cell padding');
    });

    testWidgets('on a phone nothing sticks out of the screen and the handles stay reachable', (tester) async {
      await open(tester, [table(cols: 5)], size: const Size(390, 800));
      expect(tester.takeException(), isNull);
      expect(tester.getTopLeft(find.byTooltip('Linha 1')).dx, greaterThanOrEqualTo(0));
      expect(tester.getSize(find.ancestor(of: find.byType(RowsTableView), matching: find.byType(SingleChildScrollView)).first).width, lessThanOrEqualTo(390), reason: 'wide tables scroll sideways inside the column');
    });
  });

  group('the handles', () {
    testWidgets('a row goes up and down, taking its text and keeping the others', (tester) async {
      await open(tester, [table()]);
      await tester.tap(find.byTooltip('Linha 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mover linha para cima'));
      await tester.pumpAndSettle();
      expect(body().single.rows!.map((r) => r['c0']), ['cel 1 c0', 'cel 0 c0', 'cel 2 c0']);
      await tester.tap(find.byTooltip('Linha 1'));
      await tester.pumpAndSettle();
      expect(find.text('Mover linha para cima'), findsNothing, reason: 'first body row');
    });

    testWidgets('a column moves with its name, width and id', (tester) async {
      final b = table();
      b.cols![0].w = 100;
      await open(tester, [b]);
      await tester.tap(find.byTooltip('Coluna 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mover coluna para a direita'));
      await tester.pumpAndSettle();
      final cols = body().single.cols!;
      expect(cols.map((c) => c.label), ['Col 1', 'Col 0', 'Col 2']);
      expect(cols.map((c) => c.id), ['c1', 'c0', 'c2'], reason: 'the id travels with the column');
      expect(cols.map((c) => c.w), [160, 100, 160]);
      expect(body().single.rows!.first['c0'], 'cel 0 c0', reason: 'the cells keep their column id');
    });

    testWidgets('a plain tap on a handle opens its menu once, and a tap outside closes it', (tester) async {
      await open(tester, [table()]);
      await tester.tap(find.byTooltip('Coluna 2'));
      await tester.pumpAndSettle();
      final item = find.descendant(of: find.byType(PopupMenuItem<int>), matching: find.text('Excluir coluna'));
      expect(item, findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(item, findsNothing);
    });
  });
}

/// The path of the paragraph of the cell at [row] (0 is the header) and [col] of the only table of the page.
List<int> cellParagraphPath(WidgetTester t, int row, int col) {
  // the first block of these pages is the table; cells are stored column by column, the header being row 0
  final table = editorOf(t).document.root.children.firstWhere((n) => n.type == 'table');
  final cell = table.children.firstWhere((c) => c.attributes['rowPosition'] == row && c.attributes['colPosition'] == col);
  return cell.children.first.path;
}

void contextMenuTests() {
  group('right click', () {
    Future<void> rightClick(WidgetTester t, Finder f, {double dx = 0}) async {
      final g = await t.startGesture(t.getCenter(f.first) + Offset(dx, 0), kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await t.pump(const Duration(milliseconds: 50));
      await g.up();
      await t.pumpAndSettle();
    }

    testWidgets('on the text of a cell opens a menu with the text and the table actions', variant: TargetPlatformVariant.only(TargetPlatform.linux), (tester) async {
      await open(tester, [table()]);
      await rightClick(tester, text('cel 1 c1'));
      expect(find.byKey(const Key('page-context-menu')), findsOneWidget);
      for (final label in ['Colar', 'Selecionar tudo', 'Inserir linha acima', 'Inserir linha abaixo', 'Excluir linha', 'Inserir coluna à esquerda', 'Inserir coluna à direita', 'Excluir coluna']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('"Excluir linha" there removes the row the click was in, and the menu closes', variant: TargetPlatformVariant.only(TargetPlatform.linux), (tester) async {
      await open(tester, [table()]);
      await rightClick(tester, text('cel 1 c1'));
      await tester.tap(find.text('Excluir linha'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('page-context-menu')), findsNothing);
      expect(body().single.rows!.map((r) => r['c0']), ['cel 0 c0', 'cel 2 c0']);
    });

    testWidgets('"Inserir coluna à direita" there puts a column right of the one clicked', variant: TargetPlatformVariant.only(TargetPlatform.linux), (tester) async {
      await open(tester, [table()]);
      await rightClick(tester, text('cel 0 c0'));
      await tester.tap(find.text('Inserir coluna à direita'));
      await tester.pumpAndSettle();
      final cols = body().single.cols!;
      expect(cols.length, 4);
      expect(cols.first.id, 'c0');
      expect(cols[1].id, isNot(anyOf('c0', 'c1', 'c2')));
      expect(cols[2].id, 'c1');
    });

    testWidgets('on a paragraph outside the table the menu has only the text actions', variant: TargetPlatformVariant.only(TargetPlatform.linux), (tester) async {
      await open(tester, [Block('p', BlockType.paragraph, text: 'um texto'), table()]);
      await rightClick(tester, find.textContaining('um texto', findRichText: true));
      expect(find.byKey(const Key('page-context-menu')), findsOneWidget);
      expect(find.text('Colar'), findsOneWidget);
      expect(find.text('Excluir linha'), findsNothing);
    });

    testWidgets('a tap anywhere else closes it', variant: TargetPlatformVariant.only(TargetPlatform.linux), (tester) async {
      await open(tester, [table()]);
      await rightClick(tester, text('cel 1 c1'));
      await tester.tapAt(const Offset(5, 700));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('page-context-menu')), findsNothing);
    });
  });
}
