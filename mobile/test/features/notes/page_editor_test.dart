import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/notes/data/blocks.dart';
import 'package:mobile/features/notes/data/links.dart';
import 'package:mobile/features/notes/data/note_page.dart';
import 'package:mobile/features/notes/data/notes_db.dart';
import 'package:mobile/features/notes/data/page_editor.dart';
import 'package:mobile/features/notes/data/workspace.dart';

void main() {
  late NotesDb db;
  late Workspace ws;
  late PageEditor ed;
  var clock = 1000000;

  setUp(() {
    db = NotesDb.inMemory();
    ws = Workspace(db, clock: () => clock += 10);
    ed = PageEditor(ws, ws.newPage('Página').id, saveDelay: const Duration(milliseconds: 5));
  });
  tearDown(() {
    ed.dispose();
    db.dispose();
  });

  Block para(String text) {
    final b = ed.insert(BlockType.paragraph)!;
    ed.setText(b.id, text);
    return b;
  }

  group('links e emoji', () {
    test('safeUrl aceita só http, https e mailto', () {
      expect(safeUrl('https://a.com/x'), 'https://a.com/x');
      expect(safeUrl('exemplo.com'), 'https://exemplo.com');
      expect(safeUrl('a@b.com'), 'mailto:a@b.com');
      expect(safeUrl('javascript:alert(1)'), isNull);
      expect(safeUrl('data:text/html,x'), isNull);
      expect(safeUrl('file:///etc/passwd'), isNull);
      expect(safeUrl('http://'), isNull);
      expect(safeUrl('a b.com'), isNull);
      expect(safeUrl('<script>'), isNull);
      expect(safeUrl(''), isNull);
      expect(safeUrl('https://a.com/${'x' * 3000}'), isNull);
      expect(safeUrl('https://a.com/(x)'), 'https://a.com/%28x%29');
    });
    test('isEmoji', () {
      for (final e in ['💡', '✅', '🇧🇷', '👨‍👩‍👧', '⚠️', '1️⃣']) {
        expect(isEmoji(e), true, reason: e);
      }
      for (final e in ['', 'a', 'ab', '💡💡', '<b>', '1', '💡x']) {
        expect(isEmoji(e), false, reason: e);
      }
    });
  });

  group('inserir, remover e mover', () {
    test('insere depois de um bloco ou no fim', () {
      final a = para('a');
      final c = para('c');
      final b = ed.insert(BlockType.quote, afterId: a.id)!;
      expect(ed.blocks.map((x) => x.id), [a.id, b.id, c.id]);
      expect(ed.insert(BlockType.divider, afterId: 'nada'), isNotNull);
      expect(ed.blocks.last.type, BlockType.divider);
    });
    test('respeita o limite de blocos', () {
      for (var i = 0; i < maxBlocks; i++) {
        expect(ed.insert(BlockType.divider), isNotNull);
      }
      expect(ed.insert(BlockType.paragraph), isNull);
      expect(ed.duplicateBlock(ed.blocks.first.id), isNull);
    });
    test('remove, move e moveBy', () {
      final a = para('a'), b = para('b'), c = para('c');
      ed.moveBy(a.id, 1);
      expect(ed.blocks.map((x) => x.text), ['b', 'a', 'c']);
      ed.moveBy(a.id, -1);
      ed.moveBy(a.id, -1);
      expect(ed.blocks.first.text, 'a');
      ed.moveBy(c.id, 1);
      expect(ed.blocks.last.text, 'c');
      ed.move(0, 3);
      expect(ed.blocks.map((x) => x.text), ['b', 'c', 'a']);
      ed.remove(b.id);
      ed.remove('nada');
      expect(ed.blocks.map((x) => x.text), ['c', 'a']);
    });
    test('mudar o que está na página atualiza o cartão e grava', () {
      para('olá mundo');
      expect(ws.page(ed.id)!.excerpt, 'olá mundo');
      expect(ws.page(ed.id)!.blocks, 1);
    });
    test('o aviso de "salvando" aparece e some', () async {
      para('x');
      expect(ed.saving, true);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(ed.saving, false);
    });
  });

  group('texto', () {
    test('setText corta no limite e ignora o que não tem texto', () {
      final a = para('');
      ed.setText(a.id, 'x' * (maxText + 50));
      expect(a.text!.length, maxText);
      final d = ed.insert(BlockType.divider)!;
      ed.setText(d.id, 'nada');
      expect(d.text, isNull);
      ed.setText('nada', 'x');
    });
    test('título sem quebras de linha e no limite', () {
      ed.setTitle('a\n\n  b\t c');
      expect(ws.page(ed.id)!.title, 'a b c');
      ed.setTitle('y' * 500);
      expect(ws.page(ed.id)!.title.length, maxTitle);
    });
    test('split corta no cursor, mesmo fora do texto', () {
      final a = para('olá mundo');
      final made = ed.split(a.id, 3)!;
      expect((a.text, made.text), ('olá', ' mundo'));
      expect(ed.split(a.id, -5)!.text, 'olá');
      expect(a.text, '');
      final b = para('fim');
      expect(ed.split(b.id, 999)!.text, '');
      expect(ed.split('nada', 1), isNull);
      final d = ed.insert(BlockType.divider)!;
      expect(ed.split(d.id, 0), isNull);
    });
    test('Enter numa lista cria outro item do mesmo nível', () {
      final a = ed.insert(BlockType.bullet)!..text = 'um';
      ed.indent(a.id, 1);
      final made = ed.split(a.id, 2)!;
      expect((made.type, made.indent), (BlockType.bullet, 1));
    });
    test('turnInto mantém o texto e recusa o que não é texto', () {
      final a = para('olá');
      expect(ed.turnInto(a.id, BlockType.heading, level: 1), true);
      var b = ed.blocks.first;
      expect((b.type, b.level, b.text), (BlockType.heading, 1, 'olá'));
      expect(ed.turnInto(a.id, BlockType.heading, level: 1), false);
      expect(ed.turnInto(a.id, BlockType.heading, level: 2), true);
      expect(ed.blocks.first.level, isNull);
      expect(ed.turnInto(a.id, BlockType.heading, level: 2, toggle: true), true);
      ed.setBody(a.id, 'corpo');
      expect(ed.turnInto(a.id, BlockType.heading, level: 3, toggle: true), true);
      expect(ed.blocks.first.body, 'corpo');
      expect(ed.turnInto(a.id, BlockType.bullet), true);
      expect(ed.blocks.first.indent, 0);
      expect(ed.turnInto(a.id, BlockType.divider), false);
      final sec = ed.insert(BlockType.secure)!;
      expect(ed.turnInto(sec.id, BlockType.paragraph), false);
      final sp = ed.insert(BlockType.spoiler)!;
      expect(ed.turnInto(sp.id, BlockType.quote), false);
      expect(ed.turnInto('nada', BlockType.quote), false);
    });
    test('toggle vira título com toggle sem perder o texto', () {
      final t = ed.insert(BlockType.toggle)!..text = 'T';
      expect(ed.turnInto(t.id, BlockType.paragraph), true);
      expect(ed.blocks.first.text, 'T');
    });
    test('listas: indent, leaveList e limites', () {
      final a = ed.insert(BlockType.numbered)!;
      expect(ed.indent(a.id, -1), false);
      for (var i = 0; i < maxIndent; i++) {
        expect(ed.indent(a.id, 1), true);
      }
      expect(ed.indent(a.id, 1), false);
      expect(ed.leaveList(a.id), true);
      expect(ed.blocks.first.indent, maxIndent - 1);
      while (ed.blocks.first.type == BlockType.numbered) {
        ed.leaveList(a.id);
      }
      expect(ed.blocks.first.type, BlockType.paragraph);
      expect(ed.leaveList(a.id), false);
      expect(ed.indent(a.id, 1), false);
    });
    test('setBody só em toggle', () {
      final t = ed.insert(BlockType.toggle)!;
      ed.setBody(t.id, 'x' * (maxText + 1));
      expect(t.body!.length, maxText);
      final p = para('a');
      ed.setBody(p.id, 'nada');
      expect(p.body, isNull);
    });
    test('callout: tom', () {
      final c = ed.insert(BlockType.callout)!;
      ed.setTone(c.id, CalloutTone.danger);
      expect(c.tone, CalloutTone.danger);
      ed.setTone(c.id, CalloutTone.info);
      expect(c.tone, isNull);
      ed.setTone(para('x').id, CalloutTone.danger);
    });
    test('código: linguagem', () {
      final c = ed.insert(BlockType.code)!;
      ed.setLang(c.id, 'rust');
      expect(c.lang, 'rust');
    });
  });

  group('duplicar bloco', () {
    test('copia com ids novos, inclusive nos itens da lista', () {
      final c = ed.insert(BlockType.checklist)!;
      ed.setItemText(c.id, c.items!.first.id, 'tarefa');
      final copy = ed.duplicateBlock(c.id)!;
      expect(copy.id, isNot(c.id));
      expect(copy.items!.first.id, isNot(c.items!.first.id));
      expect(copy.items!.first.text, 'tarefa');
      copy.items!.first.text = 'outra';
      expect(c.items!.first.text, 'tarefa');
      expect(ed.blocks[1], same(copy));
    });
    test('imagem da sessão não duplica; a do servidor sim', () {
      final i = ed.insert(BlockType.image)!;
      ed.setImage(i.id, 'a.png', 'blob:1');
      expect(ed.duplicateBlock(i.id), isNull);
      i.fileId = 'f1';
      expect(ed.duplicateBlock(i.id), isNotNull);
    });
  });

  group('checklist', () {
    test('marca, escreve, adiciona e remove', () {
      final c = ed.insert(BlockType.checklist)!;
      final first = c.items!.first.id;
      ed.toggleItem(c.id, first);
      expect(ed.progress, (done: 1, total: 1));
      final second = ed.addItem(c.id)!;
      final between = ed.addItem(c.id, first)!;
      expect(c.items!.map((i) => i.id), [first, between, second]);
      expect(ed.addItem(c.id, 'nada'), isNotNull);
      ed.removeItem(c.id, between);
      expect(c.items!.length, 3);
      ed.toggleItem(c.id, 'nada');
      ed.setItemText(c.id, 'nada', 'x');
    });
    test('o limite de itens', () {
      final c = ed.insert(BlockType.checklist)!;
      for (var i = 0; i < maxItems + 20; i++) {
        ed.addItem(c.id);
      }
      expect(c.items!.length, maxItems);
      expect(ed.addItem(c.id), isNull);
    });
    test('tirar o último item tira o bloco', () {
      final c = ed.insert(BlockType.checklist)!;
      ed.removeItem(c.id, c.items!.first.id);
      expect(ed.blocks, isEmpty);
    });
  });

  group('tabela', () {
    late Block t;
    setUp(() => t = ed.insert(BlockType.table)!);
    test('células, colunas e linhas', () {
      final col = t.cols!.first.id;
      ed.setCell(t.id, 0, col, 'x');
      expect(t.rows![0][col], 'x');
      ed.setCell(t.id, 99, col, 'x');
      ed.setCell(t.id, -1, col, 'x');
      ed.setCell(t.id, 0, 'nada', 'x');
      ed.setLabel(t.id, col, 'y' * 200);
      expect(t.cols!.first.label.length, 80);
      final added = ed.addCol(t.id)!;
      expect(t.rows!.every((r) => r.containsKey(added)), true);
      ed.addRow(t.id);
      expect(t.rows!.length, 4);
      ed.removeCol(t.id, added);
      expect(t.rows!.any((r) => r.containsKey(added)), false);
      ed.removeRow(t.id, 0);
      expect(t.rows!.length, 3);
    });
    test('sempre sobra uma coluna e uma linha', () {
      for (final c in [...t.cols!]) {
        ed.removeCol(t.id, c.id);
      }
      expect(t.cols!.length, 1);
      for (var i = 0; i < 10; i++) {
        ed.removeRow(t.id, 0);
      }
      expect(t.rows!.length, 1);
      ed.removeRow(t.id, 5);
    });
    test('limites de colunas e linhas', () {
      for (var i = 0; i < 30; i++) {
        ed.addCol(t.id);
      }
      expect(t.cols!.length, maxCols);
      expect(ed.addCol(t.id), isNull);
      for (var i = 0; i < maxRows + 10; i++) {
        ed.addRow(t.id);
      }
      expect(t.rows!.length, maxRows);
    });
    test('largura e ordem', () {
      final col = t.cols!.first.id;
      ed.resizeCol(t.id, col, 5);
      expect(t.cols!.first.w, minColWidth);
      ed.resizeCol(t.id, col, 99999);
      expect(t.cols!.first.w, maxColWidth);
      ed.resizeCol(t.id, col, double.nan);
      expect(t.cols!.first.w, maxColWidth);
      final ids = t.cols!.map((c) => c.id).toList();
      ed.moveCol(t.id, 0, 3);
      expect(t.cols!.map((c) => c.id), [ids[1], ids[2], ids[0]]);
      final r0 = t.rows![0];
      ed.moveRow(t.id, 0, 3);
      expect(t.rows!.last, same(r0));
    });
  });

  group('endereços e links entre páginas', () {
    test('setUrl: cartão aceita mailto, mídia só http(s)', () {
      final b = ed.insert(BlockType.bookmark)!;
      expect(ed.setUrl(b.id, 'a@b.com', '  Meu   e-mail '), true);
      expect((b.url, b.title), ('mailto:a@b.com', 'Meu e-mail'));
      final v = ed.insert(BlockType.video)!;
      expect(ed.setUrl(v.id, 'a@b.com'), false);
      expect(ed.setUrl(v.id, 'javascript:alert(1)'), false);
      expect(v.url, '');
      expect(ed.setUrl(v.id, 'https://x.com/a.mp4', 'y' * 500), true);
      expect(v.title!.length, 200);
      expect(ed.setUrl(para('x').id, 'https://a.com'), false);
    });
    test('pagelink: nunca a si mesma, à lixeira ou ao cofre', () {
      final other = ws.newPage('Outra');
      final trashed = ws.newPage('Lixo');
      ws.trash(trashed.id);
      final vault = ws.newPage('Segredo')..locked = true;
      final l = ed.insert(BlockType.pagelink)!;
      expect(ed.setPageLink(l.id, other.id), true);
      expect(l.title, 'Outra');
      expect(ed.setPageLink(l.id, ed.id), false);
      expect(ed.setPageLink(l.id, trashed.id), false);
      expect(ed.setPageLink(l.id, vault.id), false);
      expect(ed.setPageLink(l.id, 'nada'), false);
      ws.setTitle(other.id, 'Renomeada');
      ed.syncPageLink(l.id);
      expect(l.title, 'Renomeada');
      vault.locked = false;
      other.locked = true;
      ed.syncPageLink(l.id);
      expect(l.title, '');
      ws.pages.removeWhere((p) => p.id == other.id);
      l.title = 'lembrado';
      ed.syncPageLink(l.id);
      expect(l.title, 'lembrado');
    });
  });

  group('ícone, capa, etiquetas', () {
    test('só um emoji de verdade e uma capa conhecida', () {
      ed.setIcon('💡');
      ed.setIcon('<script>');
      ed.setIcon('abc');
      expect(ws.page(ed.id)!.icon, '💡');
      ed.setIcon('');
      expect(ws.page(ed.id)!.icon, '');
      ed.setCover('musgo');
      ed.setCover('lixo');
      expect(ws.page(ed.id)!.cover, 'musgo');
    });
    test('etiquetas: cria, não repete, remove', () {
      expect(ed.addTag('Ideias'), true);
      expect(ed.addTag('ideias'), false);
      expect(ed.addTag('   '), false);
      expect(ws.page(ed.id)!.tags, ['ideias']);
      ed.removeTag('ideias');
      ed.removeTag('nada');
      expect(ws.page(ed.id)!.tags, isEmpty);
      expect(ws.tag('ideias'), isNotNull);
    });
  });

  group('arquivos soltos e revelar', () {
    test('apagar o último bloco que usa um arquivo avisa; se outro usa, não', () {
      final told = <String>[];
      ed.fileUsage = (id, unused) => unused ? told.add(id) : null;
      final a = ed.insert(BlockType.file)!..fileId = 'f1';
      final b = ed.insert(BlockType.image)!..fileId = 'f1';
      ed.remove(a.id);
      expect(told, isEmpty);
      ed.remove(b.id);
      expect(told, ['f1']);
    });
    test('trocar a imagem solta a antiga', () {
      final told = <String>[];
      ed.fileUsage = (id, unused) => told.add(id);
      final i = ed.insert(BlockType.image)!..fileId = 'f9';
      ed.setImage(i.id, 'b.png', 'blob:2');
      expect(told, ['f9']);
      expect((i.fileId, i.src), (null, 'blob:2'));
    });
    test('spoiler e segredo abrem e fecham sem gravar', () {
      final s = ed.insert(BlockType.spoiler)!;
      var calls = 0;
      ed.addListener(() => calls++);
      ed.reveal(s.id, true);
      expect(ed.revealed, {s.id});
      ed.reveal(s.id, false);
      expect(ed.revealed, isEmpty);
      expect(calls, 2);
    });
  });

  group('página na lixeira', () {
    test('só leitura: nada muda', () {
      final a = para('fica');
      ws.trash(ed.id);
      expect(ed.readOnly, true);
      ed.setText(a.id, 'mudou');
      ed.setTitle('novo');
      ed.remove(a.id);
      expect(ed.insert(BlockType.paragraph), isNull);
      expect(ed.duplicate(), isNull);
      expect(a.text, 'fica');
      expect(ed.blocks.length, 1);
    });
  });

  group('persistência', () {
    test('fechar o editor grava o corpo e solta da memória', () {
      para('guardado');
      final id = ed.id;
      ed.dispose();
      expect(ws.page(id)!.content, isNull);
      final again = Workspace(db, clock: () => clock += 10);
      expect(blockText(again.contentOf(id)!.single), 'guardado');
      ed = PageEditor(ws, id);
    });
    test('duplicar a página pelo editor', () {
      para('conteúdo');
      final made = ed.duplicate()!;
      expect(ws.page(made.id)!.title, 'Página (cópia)');
      expect(made.images, 0);
    });
    test('uma enxurrada de edições seguidas termina coerente', () {
      final ids = [for (var i = 0; i < 200; i++) para('b$i').id];
      for (var i = 0; i < 400; i++) {
        final id = ids[(i * 7) % ids.length];
        switch (i % 5) {
          case 0:
            ed.moveBy(id, i.isEven ? 1 : -1);
          case 1:
            ed.setText(id, 'x$i');
          case 2:
            ed.duplicateBlock(id);
          case 3:
            ed.turnInto(id, BlockType.quote);
          case 4:
            ed.split(id, 1);
        }
      }
      expect(ed.blocks.length, lessThanOrEqualTo(maxBlocks));
      expect({for (final b in ed.blocks) b.id}.length, ed.blocks.length);
    });
  });
}
