import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/notes/data/blocks.dart';
import 'package:mobile/features/notes/data/note_page.dart';
import 'package:mobile/features/notes/data/notes_db.dart';
import 'package:mobile/features/notes/data/workspace.dart';

const day = 86400000;

void main() {
  late NotesDb db;
  late int now;
  Workspace make() => Workspace(db, clock: () => now);

  setUp(() {
    db = NotesDb.inMemory();
    now = DateTime(2026, 11, 7, 12).millisecondsSinceEpoch;
  });
  tearDown(() => db.dispose());

  NotePage add(Workspace w, String title, {int? ageDays, List<String> tags = const [], bool pin = false, String body = ''}) {
    final p = w.newPage(title);
    p.tags = [...tags];
    p.pinned = pin;
    if (body.isNotEmpty) p.content = [Block('b', BlockType.paragraph, text: body)];
    w.touch(p.id);
    if (ageDays != null) {
      p.updated = now - ageDays * day;
      db.savePage(p);
    }
    return p;
  }

  group('páginas', () {
    test('começa vazio; nova página vai ao topo e limpa filtros', () {
      final w = make();
      expect(w.pages, isEmpty);
      add(w, 'Primeira');
      w.setQuery('xis');
      w.setSort(NotesSort.az);
      w.go(NotesView.trash);
      final p = w.newPage('  Segunda  ');
      expect(p.title, 'Segunda');
      expect(w.pages.first.id, p.id);
      expect((w.view, w.query, w.sort), (NotesView.all, '', NotesSort.recent));
    });
    test('título vazio, enorme ou só espaços', () {
      final w = make();
      expect(w.newPage('   ').title, 'Sem título');
      expect(w.newPage('x' * 500).title.length, maxTitle);
      w.setTitle(w.pages.first.id, 'y' * 500);
      expect(w.pages.first.title.length, maxTitle);
    });
    test('nova página recebe a etiqueta que está filtrada', () {
      final w = make();
      final t = w.addTag('Ideias')!;
      w.toggleTagFilter(t.id);
      expect(w.newPage().tags, [t.id]);
    });
    test('ids nunca se repetem, mesmo no mesmo milissegundo', () {
      final w = make();
      expect({for (var i = 0; i < 300; i++) w.newPage().id}.length, 300);
    });
    test('o corpo só é lido ao abrir e solto ao fechar', () {
      final w = make();
      final p = add(w, 'A', body: 'texto salvo');
      w.release(p.id);
      expect(p.content, isNull);
      expect(blockText(w.contentOf(p.id)!.first), 'texto salvo');
      // a page never given a body starts from its excerpt
      final q = NotePage(id: 'q', updated: now, created: now, excerpt: 'resumo');
      w.pages.add(q);
      expect(blockText(w.contentOf('q')!.single), 'resumo');
      expect(w.contentOf('nada'), isNull);
    });
    test('touch atualiza resumo, contagem e hora', () {
      final w = make();
      final p = w.newPage('A');
      p.content!.add(Block('b1', BlockType.paragraph, text: 'oi'));
      now += 5000;
      w.touch(p.id);
      expect((p.excerpt, p.blocks, p.updated), ('oi', 1, now));
    });
    test('duplicar copia o corpo com ids novos, sem fixar e sem imagem da sessão', () {
      final w = make();
      final p = add(w, 'Original', tags: ['a'], pin: true);
      p.content = [Block('x', BlockType.paragraph, text: 'oi'), Block('i', BlockType.image, name: 'f.png', src: 'blob:1')];
      final r = w.duplicate(p.id)!;
      expect(r.images, 1);
      expect(r.page.title, 'Original (cópia)');
      expect(r.page.pinned, false);
      expect(r.page.tags, ['a']);
      expect(r.page.content!.map((b) => b.id), isNot(contains('x')));
      expect(r.page.content!.last.src, isNull);
      expect(p.content!.last.src, 'blob:1');
      expect(w.duplicate('nada'), isNull);
    });
    test('ícone fica em uma letra só, capa só conhecida', () {
      final w = make();
      final p = w.newPage();
      w.setIcon(p.id, '👨‍👩‍👧 resto');
      expect(p.icon, '👨‍👩‍👧');
      w.setCover(p.id, 'musgo');
      w.setCover(p.id, 'inexistente');
      expect(p.cover, 'musgo');
      w.setCover(p.id, '');
      expect(p.cover, '');
    });
  });

  group('visões, busca e ordem', () {
    test('busca ignora acento e caixa, no título e no resumo', () {
      final w = make();
      add(w, 'Reforma do apartamento', body: 'Orçamento total');
      add(w, 'Outra');
      w.setQuery('ORCAMENTO');
      expect(w.visible.map((p) => p.title), ['Reforma do apartamento']);
      w.setQuery('  ');
      expect(w.visible.length, 2);
      w.setQuery('%_*[(');
      expect(w.visible, isEmpty);
    });
    test('ordem recente e A–Z com acento', () {
      final w = make();
      add(w, 'Ônibus', ageDays: 1);
      add(w, 'abacaxi', ageDays: 3);
      add(w, 'Zebra', ageDays: 0);
      expect(w.visible.map((p) => p.title), ['Zebra', 'Ônibus', 'abacaxi']);
      w.setSort(NotesSort.az);
      expect(w.visible.map((p) => p.title), ['abacaxi', 'Ônibus', 'Zebra']);
    });
    test('filtro de etiqueta e contagens', () {
      final w = make();
      final a = w.addTag('a')!, b = w.addTag('b')!;
      add(w, '1', tags: [a.id]);
      add(w, '2', tags: [a.id, b.id]);
      add(w, '3');
      expect(w.tagCounts, {a.id: 2, b.id: 1});
      w.toggleTagFilter(b.id);
      expect(w.visible.map((p) => p.title), ['2']);
      w.toggleTagFilter(b.id);
      expect(w.tagFilter, isNull);
      w.go(NotesView.vault);
      w.toggleTagFilter(a.id);
      expect(w.view, NotesView.all);
      w.clearFilters();
      expect(w.visible.length, 3);
    });
    test('grupos: fixadas, hoje, semana, mês e antigas', () {
      final w = make();
      add(w, 'fixa', ageDays: 50, pin: true);
      add(w, 'hoje', ageDays: 0);
      add(w, 'semana', ageDays: 3);
      add(w, 'mes', ageDays: 20);
      add(w, 'velha', ageDays: 90);
      expect(w.groups.map((g) => '${g.label}: ${g.pages.map((p) => p.title).join(',')}'), [
        'Fixadas: fixa',
        'Hoje: hoje',
        'Esta semana: semana',
        'Últimos 30 dias: mes',
        'Mais antigas: velha',
      ]);
      w.setSort(NotesSort.az);
      expect(w.groups.map((g) => g.label), ['Fixadas', 'Outras']);
      w.setQuery('h');
      expect(w.groups.single.label, isNull);
    });
    test('o limite de "hoje" é a meia-noite e o de "semana" são 6 dias antes', () {
      final w = make();
      final midnight = DateTime(2026, 11, 7).millisecondsSinceEpoch;
      final a = add(w, 'logo depois', ageDays: 0)..updated = midnight;
      final b = add(w, 'um ms antes', ageDays: 0)..updated = midnight - 1;
      final c = add(w, 'seis dias', ageDays: 0)..updated = DateTime(2026, 11, 1).millisecondsSinceEpoch;
      final d = add(w, 'sete dias', ageDays: 0)..updated = DateTime(2026, 11, 1).millisecondsSinceEpoch - 1;
      final byKey = {for (final g in w.groups) g.key: g.pages};
      expect(byKey['today'], [a]);
      expect(byKey['week'], containsAll([b, c]));
      expect(byKey['month'], [d]);
    });
    test('relacionadas pelas etiquetas em comum', () {
      final w = make();
      final a = w.addTag('a')!, b = w.addTag('b')!;
      final x = add(w, 'x', tags: [a.id, b.id], ageDays: 5);
      add(w, 'só a', tags: [a.id], ageDays: 1);
      add(w, 'a e b', tags: [a.id, b.id], ageDays: 9);
      add(w, 'nenhuma');
      expect(w.related(x.id).map((p) => p.title), ['a e b', 'só a']);
      expect(w.related(x.id, limit: 1).length, 1);
      expect(w.related('nada'), isEmpty);
    });
  });

  group('lixeira', () {
    test('ir para a lixeira, restaurar e esvaziar', () {
      final w = make();
      final p = add(w, 'A');
      w.trash(p.id);
      expect((w.counts.all, w.counts.trash), (0, 1));
      w.go(NotesView.trash);
      expect(w.visible, [p]);
      w.restore(p.id);
      expect(w.counts.all, 1);
      w.trash(p.id);
      w.emptyTrash();
      expect(w.pages, isEmpty);
      expect(db.pages(), isEmpty);
    });
    test('lixeira desligada apaga na hora', () {
      final w = make();
      w.saveSettings(const Settings(useTrash: false));
      final p = add(w, 'A');
      w.trash(p.id);
      expect(w.pages, isEmpty);
    });
    test('página do cofre nunca espera na lixeira', () {
      final w = make();
      final p = add(w, 'segredo')..locked = true;
      w.trash(p.id);
      expect(w.pages, isEmpty);
    });
    test('páginas velhas na lixeira somem ao abrir; as recentes ficam', () {
      var w = make();
      final old = add(w, 'velha');
      final fresh = add(w, 'recente');
      w.trash(old.id);
      w.trash(fresh.id);
      old.updated = now - 31 * day;
      db.savePage(old);
      w = make();
      expect(w.pages.map((p) => p.title), ['recente']);
      w.saveSettings(const Settings(retention: 7));
      expect(w.settings.retention, 7);
    });
    test('apagar de vez avisa só os arquivos que mais nenhuma página usa', () {
      final w = make();
      final gone = <String>[];
      w.filesGone = gone.addAll;
      final a = add(w, 'A');
      a.content = [Block('1', BlockType.file, fileId: 'f1'), Block('2', BlockType.file, fileId: 'f2')];
      w.touch(a.id);
      final b = add(w, 'B');
      b.content = [Block('3', BlockType.file, fileId: 'f2')];
      w.touch(b.id);
      w.deleteForever(a.id);
      expect(gone, ['f1']);
      gone.clear();
      w.trash(b.id);
      w.emptyTrash();
      expect(gone, ['f2']);
    });
    test('apagar o que não existe ou esvaziar uma lixeira vazia não faz nada', () {
      final w = make();
      var calls = 0;
      w.filesGone = (_) => calls++;
      w.addListener(() => calls++);
      w.deleteForever('nada');
      w.emptyTrash();
      w.trash('nada');
      w.restore('nada');
      expect(calls, 0);
    });
  });

  group('etiquetas e ajustes', () {
    test('nome limpo, único sem importar acento, cor válida', () {
      final w = make();
      final t = w.addTag('  Minha   ideia  ', TagColor.rust)!;
      expect((t.id, t.name, t.color), ('minha-ideia', 'minha-ideia', TagColor.rust));
      expect(w.addTag('MINHA-IDEIA'), same(t));
      expect(w.addTag('Operações')!.id, 'operacoes');
      expect(w.addTag('   '), isNull);
      expect(w.addTag('x' * 80)!.name.length, maxTagName);
    });
    test('ajustes limitam a retenção', () {
      final w = make();
      w.saveSettings(const Settings(retention: 1000));
      expect(w.settings.retention, 90);
      w.saveSettings(const Settings(retention: 0));
      expect(w.settings.retention, 7);
    });
  });

  group('persistência', () {
    test('tudo volta igual ao abrir de novo', () {
      var w = make();
      final t = w.addTag('Ideias', TagColor.gold)!;
      final p = w.newPage('Minha página');
      p.content!.addAll([Block('b1', BlockType.paragraph, text: 'olá'), makeBlock(BlockType.table)]);
      p.tags = [t.id];
      w.touch(p.id);
      w.setIcon(p.id, '💡');
      w.setCover(p.id, 'oceano');
      w.togglePin(p.id);
      w.saveSettings(const Settings(useTrash: false, retention: 14));
      w.setLayout(NotesLayout.list);
      w = make();
      final r = w.pages.single;
      expect('${r.title}|${r.tags}|${r.icon}|${r.cover}|${r.pinned}|${r.blocks}|${r.excerpt}', 'Minha página|[${t.id}]|💡|oceano|true|2|olá');
      expect(r.content, isNull);
      expect(w.contentOf(r.id)!.map((b) => b.type), [BlockType.paragraph, BlockType.table]);
      expect(w.tags.single.color, TagColor.gold);
      expect((w.settings.useTrash, w.settings.retention), (false, 14));
    });
    test('corpo estragado no disco não derruba: a página abre vazia', () {
      final w = make();
      final p = add(w, 'A');
      db.savePage(p);
      expect(db.content('nada'), isNull);
    });
    test('liberar a página grava o corpo antes de soltar', () {
      var w = make();
      final p = w.newPage('A');
      p.content!.add(Block('b', BlockType.paragraph, text: 'mudou'));
      w.release(p.id);
      w = make();
      expect(blockText(w.contentOf(w.pages.single.id)!.single), 'mudou');
    });
    test('mil páginas: lista rápida e sem os corpos na memória', () {
      final w = make();
      final sw = Stopwatch()..start();
      for (var i = 0; i < 1000; i++) {
        final p = w.newPage('Página $i');
        p.content!.add(Block('b$i', BlockType.paragraph, text: 'conteúdo ' * 100));
        w.touch(p.id);
        w.release(p.id);
      }
      final again = make();
      expect(again.pages.length, 1000);
      expect(again.pages.every((p) => p.content == null), true);
      expect(again.groups.expand((g) => g.pages).length, 1000);
      expect(sw.elapsed.inSeconds, lessThan(20));
    });
    test('arquivo no disco: grava, fecha e reabre', () {
      final dir = Directory.systemTemp.createTempSync('notes_db');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/notes.db';
      final d1 = NotesDb.open(path);
      final w1 = Workspace(d1, clock: () => now)..newPage('No disco');
      expect(w1.pages.length, 1);
      d1.dispose();
      final d2 = NotesDb.open(path);
      expect(Workspace(d2, clock: () => now).pages.single.title, 'No disco');
      d2.dispose();
    });
  });
}
