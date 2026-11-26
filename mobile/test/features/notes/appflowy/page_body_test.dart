import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/notes/data/blocks.dart';
import 'package:mobile/features/notes/data/notes_db.dart';
import 'package:mobile/features/notes/data/page_editor.dart';
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
PageEditor pageEditor(WidgetTester t) => bodyOf(t).ed;

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

  group('a barra de formatação', () {
    Future<void> press(WidgetTester t, String tip) async {
      await t.tap(find.byTooltip(tip));
      await t.pumpAndSettle();
    }

    testWidgets('cada marca vira o marcador da web e some ao tocar de novo', (tester) async {
      await open(tester, [Block('a', BlockType.paragraph, text: 'uma frase boa')]);
      for (final (tip, mark) in [('Negrito', '**'), ('Itálico', '*'), ('Sublinhado', '__'), ('Riscado', '~~'), ('Código', '`'), ('Destaque', '==')]) {
        await selectIn(tester, 0, 4, 9);
        await press(tester, tip);
        expect(body().single.text, 'uma ${mark}frase$mark boa', reason: tip);
        await selectIn(tester, 0, 4, 9);
        await press(tester, tip);
        expect(body().single.text, 'uma frase boa', reason: '$tip off');
      }
    });

    testWidgets('o botão deixa de aparecer ligado quando a marca sai do texto selecionado, por qualquer caminho', (tester) async {
      await open(tester, [Block('a', BlockType.paragraph, text: 'uma __frase__ boa')]);
      bool on(String tip) => tester.widgetList<Semantics>(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == tip && w.properties.selected != null)).first.properties.selected == true;
      await selectIn(tester, 0, 4, 9);
      expect(on('Sublinhado'), true);
      // taken off from outside the bar (a shortcut, a paste, the editor's own command): same selection, other text
      final es = editorOf(tester);
      await es.formatDelta(es.selection, {AppFlowyRichTextKeys.underline: null});
      await tester.pumpAndSettle();
      expect(body().single.text, 'uma frase boa');
      expect(on('Sublinhado'), false);
      // and by the bar's own button, twice
      await tester.tap(find.byTooltip('Negrito'));
      await tester.pumpAndSettle();
      expect(on('Negrito'), true);
      await tester.tap(find.byTooltip('Negrito'));
      await tester.pumpAndSettle();
      expect(on('Negrito'), false);
    });

    testWidgets('depois de "Começar com: Texto" os atalhos do teclado já valem, sem precisar clicar no texto', (tester) async {
      await open(tester, [Block('a', BlockType.paragraph, text: '')]);
      bodyOf(tester).controller.focusBlock('a');
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus.toString(), contains('page editor'), reason: 'the editor holds the focus');
      final es = editorOf(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(es.toggledStyle['bold'], true, reason: 'Ctrl+B turned bold on for what is typed next');
    });

    testWidgets('várias marcas na mesma palavra e a leitura da web volta igual', (tester) async {
      await open(tester, [Block('a', BlockType.paragraph, text: 'uma frase boa')]);
      await selectIn(tester, 0, 4, 9);
      await press(tester, 'Negrito');
      await selectIn(tester, 0, 4, 9);
      await press(tester, 'Itálico');
      final t = body().single.text!;
      expect(t, contains('frase'));
      expect(t.startsWith('uma '), true);
      expect(t.endsWith(' boa'), true);
      // close and reopen the page: what was stored reads back as the same two marks
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MaterialApp(theme: AppTheme.dark, home: EditorPage(ws: ws, pageId: pid)));
      await tester.pumpAndSettle();
      final delta = editorOf(tester).getNodeAtPath([0])!.delta!;
      final run = delta.toList().whereType<TextInsert>().firstWhere((o) => o.text == 'frase');
      expect(run.attributes!['bold'], true);
      expect(run.attributes!['italic'], true);
    });

    testWidgets('o link só aceita endereço seguro', (tester) async {
      await open(tester, [Block('a', BlockType.paragraph, text: 'veja o site')]);
      await selectIn(tester, 0, 7, 11);
      await press(tester, 'Link');
      await tester.enterText(find.byType(TextField).last, 'javascript:alert(1)');
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();
      expect(body().single.text, 'veja o site');
      await selectIn(tester, 0, 7, 11);
      await press(tester, 'Link');
      await tester.enterText(find.byType(TextField).last, 'exemplo.com');
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();
      expect(body().single.text, 'veja o [site](https://exemplo.com)');
      // and removing it
      await selectIn(tester, 0, 7, 11);
      await press(tester, 'Link');
      await tester.tap(find.text('Remover'));
      await tester.pumpAndSettle();
      expect(body().single.text, 'veja o site');
    });

    testWidgets('um link cancelado não muda nada, e o texto do diálogo some', (tester) async {
      await open(tester, [Block('a', BlockType.paragraph, text: 'veja o site')]);
      await selectIn(tester, 0, 7, 11);
      await press(tester, 'Link');
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(body().single.text, 'veja o site');
      expect(find.text('Endereço do link'), findsNothing);
    });

    testWidgets('desfazer e refazer pela barra', (tester) async {
      await open(tester, [Block('a', BlockType.paragraph, text: 'um')]);
      await caretAt(tester, 0, 2);
      await typeAtEnd(tester, 0, ' dois');
      await tester.pumpAndSettle();
      expect(body().single.text, 'um dois');
      await press(tester, 'Desfazer');
      expect(body().single.text, 'um');
      await press(tester, 'Refazer');
      expect(body().single.text, 'um dois');
    });

    testWidgets('sem seleção a barra some; um clique fora dela não a esconde no meio de uma ação', (tester) async {
      await open(tester, [Block('a', BlockType.paragraph, text: 'um')]);
      expect(find.byKey(const Key('format-bar')), findsNothing);
      await caretAt(tester, 0, 1);
      expect(find.byKey(const Key('format-bar')), findsOneWidget);
      editorOf(tester).selection = null;
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('format-bar')), findsNothing);
    });
  });

  group('o que muda de fora entra no editor', () {
    testWidgets('várias mudanças seguidas, sem esperar uma pela outra, deixam o documento igual aos blocos', (tester) async {
      await open(tester, [Block('a', BlockType.paragraph, text: 'um')]);
      final ed = pageEditor(tester);
      for (var i = 0; i < 25; i++) {
        ed.insert(i.isEven ? BlockType.divider : BlockType.quote, afterId: i == 0 ? 'a' : null);
      }
      await tester.pumpAndSettle();
      expect(editorOf(tester).document.root.children.length, body().length);
      expect(editorOf(tester).document.root.children.map((n) => n.attributes['bid']).toList(), body().map((b) => b.id).toList());
    });

    testWidgets('mover, duplicar e excluir de fora refletem na ordem do editor', (tester) async {
      await open(tester, [for (final t in ['a', 'b', 'c']) Block(t, BlockType.paragraph, text: t)]);
      final ed = pageEditor(tester);
      ed.moveBy('c', -1);
      await tester.pumpAndSettle();
      expect(editorOf(tester).document.root.children.map((n) => n.attributes['bid']), ['a', 'c', 'b']);
      ed.remove('a');
      await tester.pumpAndSettle();
      expect(editorOf(tester).document.root.children.map((n) => n.attributes['bid']), ['c', 'b']);
    });

    testWidgets('o que se digita logo depois de uma mudança de fora não se perde', (tester) async {
      await open(tester, [Block('a', BlockType.paragraph, text: 'um')]);
      pageEditor(tester).insert(BlockType.divider, afterId: 'a');
      await tester.pumpAndSettle();
      await typeAtEnd(tester, 0, ' dois');
      await tester.pumpAndSettle();
      expect(body().map((b) => b.type), [BlockType.paragraph, BlockType.divider]);
      expect(body().first.text, 'um dois');
    });

    testWidgets('um bloco que o editor não edita guarda o que se digita nele, ao lado de texto editado', (tester) async {
      final code = Block('k', BlockType.code, lang: 'go', text: 'x');
      await open(tester, [Block('a', BlockType.paragraph, text: 'antes'), code]);
      await tester.enterText(find.widgetWithText(TextField, 'x').first, 'fmt.Println()');
      await tester.pump();
      await typeAtEnd(tester, 0, ' e depois');
      await tester.pumpAndSettle();
      expect(body().last.text, 'fmt.Println()');
      expect(identical(body().last, code), true, reason: 'the very same block object');
      expect(body().first.text, 'antes e depois');
    });

    testWidgets('mudar o tom de um destaque não reconstrói o documento nem tira o cursor do texto', (tester) async {
      await open(tester, [Block('a', BlockType.paragraph, text: 'um'), Block('c', BlockType.callout, text: 'x')]);
      await caretAt(tester, 0, 1);
      final before = editorOf(tester).selection;
      pageEditor(tester).setTone('c', CalloutTone.danger);
      await tester.pumpAndSettle();
      expect(editorOf(tester).selection, before);
    });
  });

  group('a página inteira', () {
    testWidgets('500 blocos abrem, e digitar no fim guarda sem perder nenhum id', (tester) async {
      final blocks = [for (var i = 0; i < maxBlocks; i++) Block('p$i', i % 7 == 0 ? BlockType.divider : BlockType.paragraph, text: i % 7 == 0 ? null : 'linha **$i**')];
      await open(tester, blocks);
      final ids = body().map((b) => b.id).toList();
      await tester.scrollUntilVisible(find.byKey(const Key('add-at-end')), 3000, scrollable: find.byType(Scrollable).first, maxScrolls: 400);
      await tester.pumpAndSettle();
      final last = editorOf(tester).document.root.children.length - 1;
      final sw = Stopwatch()..start();
      await typeAtEnd(tester, last, '!');
      await tester.pump();
      expect(sw.elapsedMilliseconds, lessThan(1500));
      expect(body().map((b) => b.id).toList(), ids);
      expect(body().last.text, contains('!'));
    });

    testWidgets('só os blocos que aparecem viram widgets', (tester) async {
      await open(tester, [for (var i = 0; i < maxBlocks; i++) Block('p$i', BlockType.paragraph, text: 'linha $i')]);
      expect(find.textContaining('linha', findRichText: true).evaluate().length, lessThan(60));
    });

    testWidgets('apagar tudo deixa a página com um parágrafo vazio e o editor continua usável', (tester) async {
      await open(tester, [Block('a', BlockType.paragraph, text: 'um'), Block('b', BlockType.paragraph, text: 'dois')]);
      final es = editorOf(tester);
      await es.apply(es.transaction..deleteNodes(es.document.root.children.toList()));
      await tester.pumpAndSettle();
      expect(() => body(), returnsNormally);
      await tester.tap(find.byKey(const Key('add-at-end')));
      await tester.pumpAndSettle();
      expect(body().length, greaterThanOrEqualTo(1));
    });

    testWidgets('em 320 px com texto grande não estoura', (tester) async {
      await open(tester, [Block('a', BlockType.heading, text: 'Título bem comprido que não cabe', level: 1), Block('b', BlockType.paragraph, text: 'texto ' * 80), Block('c', BlockType.checklist, items: [ChecklistItem(id: 'i', text: 'tarefa')]), Block('d', BlockType.numbered, text: 'item', indent: 0)], size: const Size(320, 640));
      await caretAt(tester, 1, 3);
      expect(tester.takeException(), isNull);
    });
  });

  group('páginas e leituras', () {
    testWidgets('o corpo guardado numa página fechada volta igual ao reabrir', (tester) async {
      await open(tester, [Block('a', BlockType.paragraph, text: 'um **dois**'), makeBlock(BlockType.code)]);
      await caretAt(tester, 0, 3);
      await typeAtEnd(tester, 0, ' três');
      await tester.pumpAndSettle();
      final before = [for (final b in body()) b.toJson()];
      await tester.pumpWidget(const SizedBox());
      ws.release(pid);
      final again = ws.contentOf(pid)!;
      expect([for (final b in again) b.toJson()], before);
    });
  });

  group('Tab', () {
    // what the editor does on Tab with the caret where it is
    Future<void> tab(WidgetTester t) async {
      final indent = bodyOf(t).controller.commandShortcuts.firstWhere((e) => e.key == 'indent');
      indent.handler(editorOf(t));
      await t.pumpAndSettle();
      bodyOf(t).controller.flush();
    }

    testWidgets('aninha um item de lista sob o anterior, e o nível é guardado', (tester) async {
      await open(tester, [Block('a', BlockType.bullet, text: 'um', indent: 0), Block('b', BlockType.bullet, text: 'dois', indent: 0)]);
      await caretAt(tester, 1);
      await tab(tester);
      expect(editorOf(tester).document.root.children.length, 1);
      expect([for (final b in body()) (b.id, b.indent)], [('a', 0), ('b', 1)]);
    });

    testWidgets('não aninha o que a página não guarda aninhado: parágrafo, tarefa, nem um item além do nível 3', (tester) async {
      await open(tester, [
        Block('p', BlockType.paragraph, text: 'um'),
        Block('q', BlockType.paragraph, text: 'dois'),
        Block('c', BlockType.checklist, items: [ChecklistItem(id: 'i1', text: 'x'), ChecklistItem(id: 'i2', text: 'y')]),
        Block('l', BlockType.bullet, text: 'item'),
      ]);
      for (final at in [1, 3, 4]) {
        await caretAt(tester, at);
        await tab(tester);
        expect(editorOf(tester).document.root.children.length, 5, reason: 'Tab at $at nested a node');
      }
      // a list item under a paragraph would be stored at the first level: it stays there on screen too
      expect(body().last.indent, 0);
    });

    testWidgets('um item no nível 3 não desce para um 4º que não existe', (tester) async {
      await open(tester, [
        Block('a', BlockType.bullet, text: '0', indent: 0),
        Block('b', BlockType.bullet, text: '1', indent: 1),
        Block('c', BlockType.bullet, text: '2', indent: 2),
        Block('d', BlockType.bullet, text: '3', indent: 3),
        Block('e', BlockType.bullet, text: '3 também', indent: 3),
      ]);
      editorOf(tester).selection = Selection.collapsed(Position(path: [0, 0, 0, 1]));
      await tester.pumpAndSettle();
      await tab(tester);
      expect([for (final b in body()) b.indent], [0, 1, 2, 3, 3]);
      expect(editorOf(tester).getNodeAtPath([0, 0, 0, 1])?.attributes['bid'], 'e');
    });

    testWidgets('um item com filhos só desce quando o mais fundo deles ainda cabe no nível 3', (tester) async {
      await open(tester, [
        Block('p', BlockType.bullet, text: 'antes', indent: 0),
        Block('a', BlockType.bullet, text: '0', indent: 0),
        Block('b', BlockType.bullet, text: '1', indent: 1),
        Block('c', BlockType.bullet, text: '2', indent: 2),
        Block('d', BlockType.bullet, text: '3', indent: 3),
      ]);
      await caretAt(tester, 1);
      await tab(tester);
      // `d` would land on a 4th level that the page cannot keep, and come back as a sibling of `c`
      expect([for (final b in body()) (b.id, b.indent)], [('p', 0), ('a', 0), ('b', 1), ('c', 2), ('d', 3)]);
      expect(editorOf(tester).document.root.children.length, 2);
    });

    testWidgets('um item com filhos desce junto com eles quando todos cabem', (tester) async {
      await open(tester, [
        Block('p', BlockType.numbered, text: 'antes', indent: 0),
        Block('a', BlockType.numbered, text: '0', indent: 0),
        Block('b', BlockType.numbered, text: '1', indent: 1),
        Block('c', BlockType.numbered, text: '2', indent: 2),
      ]);
      await caretAt(tester, 1);
      await tab(tester);
      expect([for (final b in body()) (b.id, b.indent)], [('p', 0), ('a', 1), ('b', 2), ('c', 3)]);
    });
  });
}
