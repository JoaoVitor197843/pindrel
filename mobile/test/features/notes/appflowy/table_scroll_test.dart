// Rows of a long table appear and go as the page scrolls; what is on screen must not jump while it does.

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/notes/data/blocks.dart';
import 'package:mobile/features/notes/data/notes_db.dart';
import 'package:mobile/features/notes/data/workspace.dart';
import 'package:mobile/features/notes/presentation/pages/editor_page.dart';

import 'editor_test_utils.dart';

/// The text of the cells that exist, light (plain text while the page moves) or real.
Finder shownCells() => find.descendant(of: find.byType(RowsTableView), matching: find.textContaining('linha', findRichText: true));

/// The cheap cells (plain `Text`), as opposed to the paragraphs of the editor.
Finder lightCells() => find.descendant(of: find.byType(RowsTableView), matching: find.byWidgetPredicate((w) => w is Text && (w.textSpan?.toPlainText() ?? '').startsWith('linha')));

String _plain(Widget w) => w is RichText ? w.text.toPlainText() : (w as Text).textSpan?.toPlainText() ?? (w).data ?? '';

void main() {
  // rows of mixed height: every 4th row has a text that wraps to several lines in a 160 px column
  Block tall() {
    final cols = [for (var c = 0; c < 3; c++) TableColumn(id: 'c$c', label: 'Col $c')];
    return Block('t', BlockType.table, cols: cols, rows: [
      for (var r = 0; r < 200; r++) {for (final c in cols) c.id: r % 4 == 0 ? 'linha $r com um texto bem mais comprido que precisa quebrar em várias linhas na coluna' : 'linha $r'},
    ]);
  }

  testWidgets('scrolling a long table up and down in small steps: what is on screen moves by the step, within a row', (tester) async {
    final db = NotesDb.inMemory();
    final ws = Workspace(db);
    final pid = ws.newPage('Teste').id;
    ws.page(pid)!.content = [tall()];
    tester.view.physicalSize = const Size(800, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      ws.dispose();
      db.dispose();
    });
    await tester.pumpWidget(MaterialApp(theme: AppTheme.dark, home: EditorPage(ws: ws, pageId: pid)));
    await tester.pumpAndSettle();

    final scroll = find.byType(Scrollable).evaluate().map((e) => (e as StatefulElement).state as ScrollableState).where((s) => s.widget.axis == Axis.vertical).first;
    // y of the first fully visible drawn cell whose text starts with "linha "
    double? anchorY(String text) {
      final f = find.descendant(of: find.byType(RowsTableView), matching: find.text(text, findRichText: true));
      return f.evaluate().isEmpty ? null : tester.getTopLeft(f.first).dy;
    }

    // go to the middle at once (rows above were never built), then walk up in 40 px steps
    scroll.position.jumpTo(scroll.position.maxScrollExtent / 2);
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    // a jump is too fast to read: the screen is not left blank, it shows skeleton rows (bars where the text will be)...
    expect(find.descendant(of: find.byType(RowsTableView), matching: find.byType(CustomPaint)).evaluate().length, greaterThan(5), reason: 'skeleton rows right after the jump');
    // ...and the text comes a moment after it stops
    var frames = 0;
    for (; frames < 60; frames++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (shownCells().evaluate().length > 8) break;
    }
    // ignore: avoid_print
    print('frames until the screen is covered after a jump to the middle: ${frames + 1}');
    expect(frames, lessThan(30), reason: 'the text is there within half a second of the jump');
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    var worst = 0.0, total = 0.0, transient = 0.0;
    final transients = <double>[];
    var anchor = 'linha ';
    double? last;
    for (var i = 0; i < 80; i++) {
      final before = scroll.position.pixels;
      // find a text that stays on screen across the step: the one under the middle of the screen
      final shown = <String>[
        for (final e in shownCells().evaluate())
          if (tester.getTopLeft(find.byWidget(e.widget)).dy > 60 && tester.getTopLeft(find.byWidget(e.widget)).dy < 560) _plain(e.widget),
      ];
      expect(shown, isNotEmpty, reason: 'step $i: the screen must never be left without rows');
      anchor = shown.first;
      final y0 = anchorY(anchor)!;
      scroll.position.jumpTo(before - 40);
      await tester.pump(const Duration(milliseconds: 50));
      final first = anchorY(anchor);
      if (first != null && i > 0) {
        final t = ((first - y0) - 40).abs();
        transient = t > transient ? t : transient;
        if (t > 5) transients.add(t);
      }
      for (var k = 0; k < 4; k++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final y1 = anchorY(anchor);
      if (y1 == null) continue;
      // the page was asked to go 40 px up, so the cell must move 40 px down, however the rows above got measured
      final jitter = (y1 - y0) - 40;
      if (jitter.abs() > 1) {
        // ignore: avoid_print
        print('step $i: jitter ${jitter.toStringAsFixed(1)} (anchor "$anchor" y $y0 -> $y1)');
      }
      worst = jitter.abs() > worst ? jitter.abs() : worst;
      total += jitter;
      last = y1;
    }
    // ignore: avoid_print
    print('scroll jitter after settling: worst ${worst.toStringAsFixed(1)} px, sum ${total.toStringAsFixed(1)} px; right after the step (one frame): up to ${transient.toStringAsFixed(1)} px; steps with a one-frame displacement: ${transients.length} of 79; last $last');
    expect(tester.takeException(), isNull);
    expect(worst, lessThan(2), reason: 'once the rows above are measured the page is moved back: nothing stays displaced');
    expect(total.abs(), lessThan(2));
  });

  testWidgets('rows that come in while the page moves are plain text, and become the real paragraphs when it stops, in the same place', (tester) async {
    final db = NotesDb.inMemory();
    final ws = Workspace(db);
    final pid = ws.newPage('Teste').id;
    ws.page(pid)!.content = [tall()];
    tester.view.physicalSize = const Size(800, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      ws.dispose();
      db.dispose();
    });
    await tester.pumpWidget(MaterialApp(theme: AppTheme.dark, home: EditorPage(ws: ws, pageId: pid)));
    await tester.pumpAndSettle();
    final scroll = find.byType(Scrollable).evaluate().map((e) => (e as StatefulElement).state as ScrollableState).where((s) => s.widget.axis == Axis.vertical).first;
    int real() => tableCells().evaluate().length;
    final atRest = real();
    expect(atRest, greaterThan(0));

    // to the middle, then let everything settle: real paragraphs everywhere in view
    scroll.position.jumpTo(scroll.position.maxScrollExtent / 2);
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final settled = real();
    expect(settled, greaterThan(atRest ~/ 2));

    // now a slow move (a quarter of a screen in one step is not a fast one): the rows that come in are plain text
    scroll.position.jumpTo(scroll.position.pixels - 600);
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(real(), lessThan(settled), reason: 'the rows that came in are plain text, not paragraphs of the editor');
    final light = lightCells();
    expect(light.evaluate(), isNotEmpty, reason: 'plain text cells exist while the page has just moved');
    final lightName = _plain(light.evaluate().first.widget);
    final probe = find.descendant(of: find.byType(RowsTableView), matching: find.text(lightName, findRichText: true));
    final plainAt = tester.getTopLeft(probe.first);

    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final realAt = tester.getTopLeft(find.descendant(of: find.byType(RowsTableView), matching: find.text(lightName, findRichText: true)).first);
    expect(lightCells().evaluate(), isEmpty, reason: 'a moment later no plain text is left, all real again');
    expect(realAt.dx, closeTo(plainAt.dx, 0.5));
    expect(realAt.dy, closeTo(plainAt.dy, 1), reason: 'the swap does not move the text');
  });

  group('the text of the rows that go by waits when the device cannot draw it in time', () {
    setUp(RowBudget.reset);
    tearDown(RowBudget.reset);

    test('frames over four fifths of the budget, for a while, turn it off; fast ones and a hitch or two never do', () {
      RowBudget.lightOnScreen = true;
      for (var i = 0; i < 200; i++) {
        RowBudget.record(6);
      }
      expect(RowBudget.textOk, true, reason: 'a frame of 6 ms at 60 Hz is well inside');
      RowBudget.record(40);
      RowBudget.record(40);
      expect(RowBudget.textOk, true, reason: 'a hitch is not a verdict');
      for (var i = 0; i < 60; i++) {
        RowBudget.record(15);
      }
      expect(RowBudget.textOk, false);
    });

    test('the same frame is late on a 120 Hz screen, and frames drawn with no text going by are not counted', () {
      RowBudget.lightOnScreen = false;
      for (var i = 0; i < 100; i++) {
        RowBudget.record(30);
      }
      expect(RowBudget.textOk, true);
      RowBudget.lightOnScreen = true;
      for (var i = 0; i < 100; i++) {
        RowBudget.record(8, 120);
      }
      expect(RowBudget.textOk, false, reason: '8 ms is most of the 8.3 ms of a 120 Hz frame');
    });

    testWidgets('with the text turned off a slow scroll draws skeleton rows, and the paragraphs come back when it stops', (tester) async {
      RowBudget.textOk = false;
      final db = NotesDb.inMemory();
      final ws = Workspace(db);
      final pid = ws.newPage('Teste').id;
      ws.page(pid)!.content = [tall()];
      tester.view.physicalSize = const Size(800, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        ws.dispose();
        db.dispose();
      });
      await tester.pumpWidget(MaterialApp(theme: AppTheme.dark, home: EditorPage(ws: ws, pageId: pid)));
      await tester.pumpAndSettle();
      final scroll = find.byType(Scrollable).evaluate().map((e) => (e as StatefulElement).state as ScrollableState).where((s) => s.widget.axis == Axis.vertical).first;
      scroll.position.jumpTo(300);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(lightCells().evaluate(), isEmpty, reason: 'no text drawn on the way');
      for (var i = 0; i < 120; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tableCells().evaluate(), isNotEmpty, reason: 'real again at rest');
      expect(lightCells().evaluate(), isEmpty);
    });
  });
}
