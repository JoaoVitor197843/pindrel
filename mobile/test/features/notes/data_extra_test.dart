import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/notes/data/blocks.dart';
import 'package:mobile/features/notes/data/cover_spec.dart';
import 'package:mobile/features/notes/data/emoji_data.dart';
import 'package:mobile/features/notes/data/highlight.dart';
import 'package:mobile/features/notes/data/links.dart';
import 'package:mobile/features/notes/data/note_page.dart';
import 'package:mobile/features/notes/data/notes_db.dart';
import 'package:mobile/features/notes/data/palette.dart';
import 'package:mobile/features/notes/data/transfer.dart';
import 'package:mobile/features/notes/data/workspace.dart';

void main() {
  group('capas', () {
    test('as especificações conhecidas viram cores; as desconhecidas não', () {
      for (final spec in ['solid:verde', 'mono:ouro', 'duo:rosa:azul:dr', 'mix:aurora', 'musgo', 'noite']) {
        expect(coverStops(spec), isNotNull, reason: spec);
        expect(isCover(spec), true, reason: spec);
      }
      for (final spec in ['', 'solid:nada', 'solid:verde:x', 'duo:rosa:azul', 'duo:rosa:azul:zz', 'mix:nada', 'url(x)', 'a' * 100, 'javascript:1']) {
        if (spec.isEmpty) {
          expect(isCover(spec), true);
        } else {
          expect(coverStops(spec), isNull, reason: spec);
        }
      }
    });
    test('duo respeita a direção; mix tem uma cor por parada', () {
      expect(coverStops('duo:rosa:azul:d')!.degrees, 180);
      expect(coverStops('duo:rosa:azul:dl')!.degrees, 240);
      expect(coverStops('mix:arco-iris')!.stops.length, 7);
      expect(coverStops('mono:verde')!.stops.map((s) => s.$2), [88, 32]);
    });
    test('os construtores de especificação e a descrição voltam ao mesmo lugar', () {
      expect(describeCover(duoSpec('rosa', 'azul', 'r')).dir, 'r');
      expect(describeCover(soloSpec('verde')).kind, 'solid');
      expect(describeCover(monoSpec('verde')).kind, 'mono');
      expect(describeCover(mixSpec('mar')).a, 'mar');
      expect(describeCover('musgo').kind, 'preset');
      expect(describeCover('lixo').kind, 'none');
      expect(describeCover('').kind, 'none');
    });
    test('a página só aceita capas válidas', () {
      final ws = Workspace(NotesDb.inMemory());
      final p = ws.newPage();
      ws.setCover(p.id, 'duo:rosa:azul:dr');
      expect(p.cover, 'duo:rosa:azul:dr');
      ws.setCover(p.id, 'lixo');
      expect(p.cover, 'duo:rosa:azul:dr');
      ws.setCover(p.id, '');
      expect(p.cover, '');
    });
  });

  group('destaque de código', () {
    String join(List<Token> t) => t.map((x) => x.text).join();
    test('os pedaços sempre refazem o texto original', () {
      for (final lang in [...languages, 'inexistente']) {
        for (final code in ['', 'def f(x):\n  return "oi" # nota\n', "const a = 'x\n/* aberto", r'"\"', '1.5e3 + abc123 `multi\nlinha`', '😀 日本語', 'x' * 30000]) {
          expect(join(highlight(code, lang)), code, reason: lang);
        }
      }
    });
    test('reconhece comentário, texto, número e palavra-chave', () {
      final t = highlight('if x == 10: # fim', 'python');
      expect(t.map((x) => x.kind), [TokenKind.keyword, TokenKind.text, TokenKind.number, TokenKind.text, TokenKind.comment]);
      expect(highlight('SELECT 1', 'sql').first.kind, TokenKind.keyword);
      expect(highlight('select', 'python').first.kind, TokenKind.text);
      expect(highlight('"abc"', 'texto').single.kind, TokenKind.text);
    });
    test('texto enorme não trava: só o começo é colorido', () {
      final sw = Stopwatch()..start();
      final t = highlight('def x\n' * 20000, 'python');
      expect(sw.elapsed.inSeconds, lessThan(5));
      expect(t.last.kind, TokenKind.text);
    });
  });

  group('exportar', () {
    late Workspace ws;
    late NotePage p;
    setUp(() {
      ws = Workspace(NotesDb.inMemory());
      final t = ws.addTag('ideias')!;
      p = ws.newPage('Minha página');
      p.tags = [t.id];
      p.content = [
        Block('1', BlockType.heading, text: 'Título', level: 1),
        Block('2', BlockType.paragraph, text: 'texto'),
        Block('3', BlockType.numbered, text: 'um', indent: 0),
        Block('4', BlockType.numbered, text: 'dois', indent: 0),
        Block('5', BlockType.bullet, text: 'ponto', indent: 1),
        Block('6', BlockType.callout, text: 'cuidado', tone: CalloutTone.warning),
        Block('7', BlockType.code, lang: 'python', text: 'print("```")'),
        Block('8', BlockType.secure, text: 'segredo'),
        Block('9', BlockType.divider),
        Block('10', BlockType.checklist, items: [ChecklistItem(id: 'a', text: 'feito', done: true), ChecklistItem(id: 'b', text: 'falta')]),
        Block('11', BlockType.table, cols: [TableColumn(id: 'c', label: 'A|B')], rows: [
          {'c': 'x|y'}
        ]),
        Block('12', BlockType.bookmark, url: 'https://a.com', title: 'Site'),
      ];
    });
    test('markdown: títulos, listas, alertas, cerca de código e segredo omitido', () {
      final md = pageToMarkdown(p, ws.tags);
      expect(md, startsWith('# Minha página\n\ntags: ideias\n\n'));
      expect(md, contains('# Título'));
      expect(md, contains('1. um\n2. dois\n  - ponto'));
      expect(md, contains('> [!WARNING]\n> cuidado'));
      expect(md, contains('````python\nprint("```")\n````'));
      expect(md, contains('> [bloco seguro omitido]'));
      expect(md, isNot(contains('segredo')));
      expect(md, contains('- [x] feito\n- [ ] falta'));
      expect(md, contains(r'| A\|B |'));
      expect(md, contains('[Site](https://a.com)'));
      expect(pageToMarkdown(p, ws.tags, includeSecure: true), contains('segredo'));
    });
    test('texto simples e JSON', () {
      expect(pageToText(p, ws.tags), startsWith('MINHA PÁGINA'));
      expect(pageToText(p, ws.tags), isNot(contains('segredo')));
      final j = jsonDecode(pageToJson(p, ws.tags)) as Map<String, dynamic>;
      expect(j['app'], 'pindrel');
      expect(j['tags'], ['ideias']);
      expect((j['blocks'] as List)[7], {'id': '8', 'type': 'secure', 'omitted': true});
      expect(exportPage(p, ws.tags, ExportFormat.json), pageToJson(p, ws.tags));
    });
    test('página nunca aberta exporta só o resumo; página vazia não quebra', () {
      final q = NotePage(id: 'q', updated: 0, created: 0, excerpt: 'só o resumo');
      expect(pageToMarkdown(q, []), contains('só o resumo'));
      final e = NotePage(id: 'e', title: '   ', updated: 0, created: 0);
      expect(pageToMarkdown(e, []), '# Sem título\n\n');
    });
    test('nome de arquivo seguro', () {
      expect(fileNameFor('Reforma: orçamento/2026!', 'md'), 'Reforma-or-amento-2026.md');
      expect(fileNameFor('../../etc/passwd', 'md'), 'etc-passwd.md');
      expect(fileNameFor('   ', 'json'), 'pagina.json');
      expect(fileNameFor('a' * 200, 'md').length, 63);
    });
    test('o que sai em claro não inclui cofre nem lixeira', () {
      final v = ws.newPage('cofre')..locked = true;
      final l = ws.newPage('lixo')..trashed = true;
      final out = exportable(ws.pages);
      expect(out, isNot(contains(v)));
      expect(out, isNot(contains(l)));
      expect(out, contains(p));
    });
  });

  group('busca rápida', () {
    late Workspace ws;
    final log = <String>[];
    PaletteActions acts() => PaletteActions(newPage: () => log.add('nova'), openSettings: () => log.add('conf'), close: () => log.add('fecha'), open: (id) => log.add('abre $id'));
    setUp(() {
      log.clear();
      ws = Workspace(NotesDb.inMemory());
    });
    test('páginas, ações e tags, nessa ordem, sem grupos vazios', () {
      ws.newPage('Pão caseiro');
      ws.addTag('pao');
      final g = buildPalette(ws, 'pao', acts());
      expect(g.map((x) => x.label), ['Páginas', 'Tags']);
      expect(buildPalette(ws, '', acts()).map((x) => x.label), ['Páginas', 'Ações', 'Tags']);
      expect(buildPalette(ws, 'zzz', acts()), isEmpty);
    });
    test('só seis páginas, as mais recentes primeiro; a do cofre só pelo título', () {
      for (var i = 0; i < 10; i++) {
        ws.newPage('Página $i');
      }
      final v = ws.newPage('Segredo')..locked = true;
      v.excerpt = 'palavra-secreta';
      expect(buildPalette(ws, 'página', acts()).first.items.length, 6);
      expect(buildPalette(ws, 'palavra-secreta', acts()), isEmpty);
      expect(buildPalette(ws, 'segredo', acts()).first.items.single.icon, PaletteIcon.lock);
    });
    test('cada item faz o que diz', () {
      final p = ws.newPage('Alvo');
      final g = buildPalette(ws, '', acts());
      g.first.items.firstWhere((i) => i.label == 'Alvo').run();
      expect(log.last, 'abre ${p.id}');
      final actions = g.firstWhere((x) => x.label == 'Ações').items;
      actions.firstWhere((i) => i.label == 'Criar nova página').run();
      actions.firstWhere((i) => i.label == 'Abrir configurações').run();
      expect(log, ['abre ${p.id}', 'nova', 'conf']);
      actions.firstWhere((i) => i.label == 'Ver lixeira').run();
      expect(ws.view, NotesView.trash);
      actions.firstWhere((i) => i.label == 'Alternar ordenação').run();
      expect(ws.sort, NotesSort.az);
      ws.addTag('x');
      buildPalette(ws, 'x', acts()).firstWhere((x) => x.label == 'Tags').items.first.run();
      expect((ws.view, ws.tagFilter), (NotesView.all, 'x'));
    });
  });

  group('ícones', () {
    test('as oito listas existem e não têm itens vazios', () {
      expect(emojiGroups.length, 8);
      for (final g in emojiGroups) {
        expect(g.list, isNotEmpty);
        expect(g.list.every((e) => e.isNotEmpty), true, reason: g.key);
      }
    });
    test('firstEmoji acha o primeiro emoji no meio do texto', () {
      expect(firstEmoji('ola 🎉 mundo', isEmoji), '🎉');
      expect(firstEmoji('sem emoji', isEmoji), isNull);
      expect(firstEmoji('', isEmoji), isNull);
    });
  });

  group('visão compartilhadas', () {
    test('está sempre vazia no aparelho e não quebra os contadores', () {
      final ws = Workspace(NotesDb.inMemory());
      ws.newPage('A');
      ws.go(NotesView.shared);
      expect(ws.visible, isEmpty);
      expect(ws.groups, isEmpty);
      expect(ws.counts.shared, 0);
    });
  });
}
