// The magnifier and Ctrl +, Ctrl -, Ctrl 0: how large the text of the pages is.

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/notes/data/blocks.dart';
import 'package:mobile/features/notes/data/note_page.dart';
import 'package:mobile/features/notes/data/notes_db.dart';
import 'package:mobile/features/notes/data/workspace.dart';
import 'package:mobile/features/notes/presentation/pages/editor_page.dart';

import 'appflowy/editor_test_utils.dart';

late NotesDb db;
late Workspace ws;
late String pid;

Future<void> open(WidgetTester tester, List<Block> blocks, {Size size = const Size(1200, 900), double systemScale = 1}) async {
  ws.page(pid)!.content = blocks;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = systemScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  await tester.pumpWidget(MaterialApp(theme: AppTheme.dark, home: EditorPage(ws: ws, pageId: pid)));
  await tester.pumpAndSettle();
}

Future<void> ctrl(WidgetTester t, LogicalKeyboardKey key, {bool shift = false}) async {
  await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await t.sendKeyEvent(key);
  if (shift) await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await t.pumpAndSettle();
}

/// The height of the first paragraph of the page's body: grows with the text.
double bodyHeight(WidgetTester t, String text) => t.getSize(find.textContaining(text, findRichText: true).first).height;

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

  group('the setting', () {
    test('goes in steps of a tenth, inside the range, and never to NaN', () {
      expect(Settings.cleanScale(1.04), 1.0);
      expect(Settings.cleanScale(1.06), 1.1);
      expect(Settings.cleanScale(0), minTextScale);
      expect(Settings.cleanScale(99), maxTextScale);
      expect(Settings.cleanScale(double.nan), 1.0);
      expect(Settings.cleanScale(double.infinity), maxTextScale);
      expect(Settings.cleanScale(-3), minTextScale);
    });

    test('is kept in the database, and a damaged value reads as the normal size', () {
      ws.setTextScale(1.3);
      expect(db.settings().textScale, 1.3);
      final again = Workspace(db);
      expect(again.settings.textScale, 1.3, reason: 'a workspace opened later reads it');
      again.dispose();
      db.saveSettings(const Settings());
      expect(db.settings().textScale, 1.0);
    });

    test('a step each way lands on the same sizes, and the same size is not written twice', () {
      var calls = 0;
      ws.addListener(() => calls++);
      for (var i = 0; i < 5; i++) {
        ws.setTextScale(ws.settings.textScale + textScaleStep);
      }
      expect(ws.settings.textScale, 1.5);
      for (var i = 0; i < 5; i++) {
        ws.setTextScale(ws.settings.textScale - textScaleStep);
      }
      expect(ws.settings.textScale, 1.0);
      expect(calls, 10);
      ws.setTextScale(1.0);
      expect(calls, 10, reason: 'nothing changed, nobody is told');
    });

    test('the other settings are not touched by it', () {
      ws.saveSettings(const Settings(useTrash: false, retention: 14));
      ws.setTextScale(1.5);
      expect(ws.settings.useTrash, false);
      expect(ws.settings.retention, 14);
    });
  });

  group('the magnifier button and its panel', () {
    testWidgets('a button with a magnifier is in the header, on a desktop and on a phone', (tester) async {
      await open(tester, [Block('a', BlockType.paragraph, text: 'um texto')]);
      expect(find.byTooltip('Tamanho do texto (Ctrl + e Ctrl −)'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await open(tester, [Block('a', BlockType.paragraph, text: 'um texto')], size: const Size(390, 800));
      expect(find.byTooltip('Tamanho do texto'), findsOneWidget);
      expect(find.byIcon(Icons.format_size), findsOneWidget);
    });

    testWidgets('the panel makes the text larger and smaller by a step, and back to normal', (tester) async {
      await open(tester, [Block('a', BlockType.paragraph, text: 'um texto')]);
      final normal = bodyHeight(tester, 'um texto');
      await tester.tap(find.byIcon(Icons.format_size));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('text-size-panel')), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      await tester.tap(find.byTooltip('Aumentar o texto'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('text-size-value')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('text-size-value'))).data, '110%');
      expect(ws.settings.textScale, 1.1);
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byTooltip('Aumentar o texto'));
        await tester.pump();
      }
      expect(ws.settings.textScale, 1.5);
      expect(bodyHeight(tester, 'um texto'), greaterThan(normal * 1.3), reason: 'the text of the page really is larger');
      await tester.tap(find.byTooltip('Diminuir o texto'));
      await tester.pumpAndSettle();
      expect(ws.settings.textScale, 1.4);
      await tester.tap(find.text('Tamanho normal'));
      await tester.pumpAndSettle();
      expect(ws.settings.textScale, 1.0);
      expect(bodyHeight(tester, 'um texto'), closeTo(normal, 0.5));
    });

    testWidgets('the slider moves it too, and the buttons stop at the ends', (tester) async {
      await open(tester, [Block('a', BlockType.paragraph, text: 'um texto')]);
      await tester.tap(find.byIcon(Icons.format_size));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Slider), const Offset(2000, 0));
      await tester.pumpAndSettle();
      expect(ws.settings.textScale, maxTextScale);
      await tester.tap(find.byTooltip('Aumentar o texto'));
      await tester.pumpAndSettle();
      expect(ws.settings.textScale, maxTextScale, reason: 'the button at the end does nothing');
      await tester.drag(find.byType(Slider), const Offset(-4000, 0));
      await tester.pumpAndSettle();
      expect(ws.settings.textScale, minTextScale);
      await tester.tap(find.byTooltip('Diminuir o texto'));
      await tester.pumpAndSettle();
      expect(ws.settings.textScale, minTextScale);
    });

    testWidgets('tapping outside closes the panel and the size stays', (tester) async {
      await open(tester, [Block('a', BlockType.paragraph, text: 'um texto')]);
      await tester.tap(find.byIcon(Icons.format_size));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Aumentar o texto'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(40, 700));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('text-size-panel')), findsNothing);
      expect(ws.settings.textScale, 1.1);
    });

    testWidgets('on a phone the panel fits the screen at the largest system text', (tester) async {
      await open(tester, [Block('a', BlockType.paragraph, text: 'um texto')], size: const Size(320, 640), systemScale: 2);
      await tester.tap(find.byIcon(Icons.format_size));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final r = tester.getRect(find.byKey(const Key('text-size-panel')));
      expect(r.left, greaterThanOrEqualTo(0));
      expect(r.right, lessThanOrEqualTo(320));
    });
  });

  group('the keyboard', () {
    testWidgets('Ctrl = and Ctrl + make it larger, Ctrl - smaller, Ctrl 0 back, with the caret in the text', (tester) async {
      await open(tester, [Block('a', BlockType.paragraph, text: 'um texto')]);
      await caretAt(tester, 0, 2);
      await ctrl(tester, LogicalKeyboardKey.equal);
      expect(ws.settings.textScale, 1.1);
      await ctrl(tester, LogicalKeyboardKey.equal, shift: true);
      expect(ws.settings.textScale, 1.2);
      await ctrl(tester, LogicalKeyboardKey.numpadAdd);
      expect(ws.settings.textScale, 1.3);
      await ctrl(tester, LogicalKeyboardKey.minus);
      await ctrl(tester, LogicalKeyboardKey.numpadSubtract);
      expect(ws.settings.textScale, 1.1);
      await ctrl(tester, LogicalKeyboardKey.digit0);
      expect(ws.settings.textScale, 1.0);
      expect(find.textContaining('Texto em 100%'), findsOneWidget, reason: 'it says where it is');
      expect(editorOf(tester).selection, isNotNull, reason: 'the caret stays where it was');
    });

    testWidgets('and without the editor having the focus, and with the Cmd key of a Mac', (tester) async {
      await open(tester, [Block('a', BlockType.paragraph, text: 'um texto')]);
      await ctrl(tester, LogicalKeyboardKey.equal);
      expect(ws.settings.textScale, 1.1);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.minus);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(ws.settings.textScale, 1.0);
    });

    testWidgets('a plain = or - typed in the text writes the character and changes no size', (tester) async {
      await open(tester, [Block('a', BlockType.paragraph, text: 'um texto')]);
      await caretAt(tester, 0, 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.minus);
      await tester.sendKeyEvent(LogicalKeyboardKey.equal);
      await tester.pumpAndSettle();
      expect(ws.settings.textScale, 1.0);
    });

    testWidgets('held down, it stops at the largest and at the smallest', (tester) async {
      await open(tester, [Block('a', BlockType.paragraph, text: 'um texto')]);
      for (var i = 0; i < 30; i++) {
        await ctrl(tester, LogicalKeyboardKey.equal);
      }
      expect(ws.settings.textScale, maxTextScale);
      for (var i = 0; i < 40; i++) {
        await ctrl(tester, LogicalKeyboardKey.minus);
      }
      expect(ws.settings.textScale, minTextScale);
      expect(tester.takeException(), isNull);
    });

    testWidgets('works with the caret in a table cell, and the table keeps its shape', (tester) async {
      final cols = [for (var c = 0; c < 3; c++) TableColumn(id: 'c$c', label: 'Col $c')];
      await open(tester, [Block('t', BlockType.table, cols: cols, rows: [for (var r = 0; r < 6; r++) {for (final c in cols) c.id: 'célula $r ${c.id} com um texto que pode quebrar'}])]);
      final before = tester.getSize(find.descendant(of: find.byType(RowsTableView), matching: find.textContaining('célula 0 c0', findRichText: true)).first).height;
      final es = editorOf(tester);
      es.selection = Selection.collapsed(Position(path: [0, 4, 0], offset: 2));
      await tester.pumpAndSettle();
      await ctrl(tester, LogicalKeyboardKey.equal);
      await ctrl(tester, LogicalKeyboardKey.equal);
      await ctrl(tester, LogicalKeyboardKey.equal);
      expect(ws.settings.textScale, 1.3);
      expect(tester.takeException(), isNull);
      final after = tester.getSize(find.descendant(of: find.byType(RowsTableView), matching: find.textContaining('célula 0 c0', findRichText: true)).first).height;
      expect(after, greaterThan(before), reason: 'the cells grow with the text (and wrap more)');
      // the rows that are built still follow one another, none left at the old height
      final tops = <double>[];
      for (var r = 0; r < 6; r++) {
        final f = find.descendant(of: find.byType(RowsTableView), matching: find.textContaining('célula $r c0', findRichText: true));
        if (f.evaluate().isNotEmpty) tops.add(tester.getTopLeft(f.first).dy);
      }
      expect(tops.length, greaterThan(2));
      for (var i = 1; i < tops.length; i++) {
        expect(tops[i], greaterThan(tops[i - 1] + 20));
      }
    });
  });

  group('what scales', () {
    testWidgets('the paragraphs, a quote, a code block and a callout; the system text size is kept on top', (tester) async {
      await open(tester, [
        Block('p', BlockType.paragraph, text: 'paragrafo'),
        Block('q', BlockType.quote, text: 'citacao'),
        Block('k', BlockType.code, lang: 'go', text: 'fmt.Println()'),
        Block('c', BlockType.callout, text: 'destaque'),
      ]);
      double h(String s) => tester.getSize(find.textContaining(s, findRichText: true).first).height;
      final normal = {for (final s in ['paragrafo', 'citacao', 'destaque']) s: h(s)};
      ws.setTextScale(1.5);
      await tester.pumpAndSettle();
      for (final s in normal.keys) {
        expect(h(s), greaterThan(normal[s]! * 1.3), reason: s);
      }
      // a phone with its text already larger
      ws.setTextScale(1.0);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await open(tester, [Block('p', BlockType.paragraph, text: 'paragrafo')], systemScale: 1.5);
      final system = h('paragrafo');
      ws.setTextScale(1.5);
      await tester.pumpAndSettle();
      expect(h('paragrafo'), greaterThan(system * 1.3), reason: 'the two add up');
    });

    testWidgets('it is the same after the page is closed and opened again', (tester) async {
      await open(tester, [Block('a', BlockType.paragraph, text: 'um texto')]);
      ws.setTextScale(1.4);
      await tester.pumpAndSettle();
      final big = bodyHeight(tester, 'um texto');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MaterialApp(theme: AppTheme.dark, home: EditorPage(ws: ws, pageId: pid)));
      await tester.pumpAndSettle();
      expect(bodyHeight(tester, 'um texto'), closeTo(big, 0.5));
    });
  });
}
