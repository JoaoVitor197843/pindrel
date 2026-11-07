import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/notes/data/blocks.dart';
import 'package:mobile/features/notes/data/text.dart';

void main() {
  group('fold', () {
    test('tira acentos e maiúsculas', () {
      expect(fold('Reforma do Apartamento — Orçamento'), 'reforma do apartamento — orcamento');
      expect(fold('AÇÃO, coração, ÓTIMO, pingüim, ÑANDÚ'), 'acao, coracao, otimo, pinguim, nandu');
    });
    test('letras compostas e marcas soltas', () {
      expect(fold('Straße œuvre Æsir'), 'strasse oeuvre aesir');
      expect(fold('é'), 'e');
    });
    test('texto estranho passa sem quebrar', () {
      expect(fold(''), '');
      expect(fold('😀 日本語 ' * 3), '😀 日本語 ' * 3);
    });
  });

  group('makeBlock e JSON', () {
    test('todo tipo nasce e volta igual do JSON', () {
      for (final t in BlockType.values) {
        final b = makeBlock(t);
        final back = Block.fromJson(jsonDecode(jsonEncode(b.toJson())));
        expect(back, isNotNull, reason: t.name);
        expect(back!.toJson(), b.toJson(), reason: t.name);
      }
    });
    test('títulos: nível 2 não é guardado, toggle guarda o corpo', () {
      expect(makeBlock(BlockType.heading, level: 2).toJson().containsKey('level'), false);
      expect(makeBlock(BlockType.heading, level: 3).toJson()['level'], 3);
      final t = makeBlock(BlockType.heading, toggle: true).toJson();
      expect(t['toggle'], true);
      expect(t['body'], '');
    });
    test('JSON estragado ou de uma versão nova nunca lança', () {
      expect(Block.fromJson(null), isNull);
      expect(Block.fromJson('x'), isNull);
      expect(Block.fromJson({'id': 1, 'type': 'paragraph'}), isNull);
      expect(Block.fromJson({'id': 'a', 'type': 'holograma'}), isNull);
      final b = Block.fromJson({'id': 'a', 'type': 'bullet', 'text': 5, 'indent': 99, 'extra': true})!;
      expect(b.text, '');
      expect(b.indent, maxIndent);
      final t = Block.fromJson({
        'id': 't',
        'type': 'table',
        'cols': [
          {'id': 'c1', 'label': 'A', 'w': 5},
          {'id': 3},
          'lixo'
        ],
        'rows': [
          {'c1': 'x', 'c2': 'fora'},
          7
        ],
      })!;
      expect(t.cols!.single.w, minColWidth);
      expect(t.rows, [
        {'c1': 'x'}
      ]);
    });
    test('listas enormes são cortadas', () {
      final b = Block.fromJson({
        'id': 'c',
        'type': 'checklist',
        'items': [for (var i = 0; i < 500; i++) {'id': 'i$i', 'text': 't'}]
      })!;
      expect(b.items!.length, maxItems);
    });
    test('copy muda só o id', () {
      final a = makeBlock(BlockType.checklist)..items!.first.text = 'x';
      final c = a.copy(id: 'novo');
      expect(c.id, 'novo');
      c.items!.first.text = 'y';
      expect(a.items!.first.text, 'x');
    });
    test('ids novos nunca se repetem', () {
      expect({for (var i = 0; i < 5000; i++) newId()}.length, 5000);
    });
  });

  group('texto e resumo', () {
    test('blockText por tipo; segredo nunca entra', () {
      expect(blockText(Block('a', BlockType.paragraph, text: 'oi')), 'oi');
      expect(blockText(Block('a', BlockType.toggle, text: 'T', body: 'B')), 'T B');
      expect(blockText(Block('a', BlockType.secure, text: 'senha')), '');
      expect(blockText(Block('a', BlockType.file, name: 'a.zip')), 'a.zip');
    });
    test('excerpt pula spoiler e segredo, junta espaços e corta', () {
      final list = [
        Block('1', BlockType.spoiler, text: 'não'),
        Block('2', BlockType.secure, text: 'não'),
        Block('3', BlockType.divider),
        Block('4', BlockType.paragraph, text: '  muito\n\n   espaço  '),
      ];
      expect(excerptOf(list), 'muito espaço');
      expect(excerptOf([Block('1', BlockType.paragraph, text: 'a' * 500)]).length, 240);
      expect(excerptOf([]), '');
    });
    test('progresso e estatísticas', () {
      final c = makeBlock(BlockType.checklist)..items = [ChecklistItem(id: 'a', done: true), ChecklistItem(id: 'b')];
      expect(checklistProgress([c]), (done: 1, total: 2));
      final s = pageStats([Block('p', BlockType.paragraph, text: List.filled(450, 'a').join(' ')), Block('s', BlockType.secure, text: 'x y z')]);
      expect((s.words, s.minutes), (450, 3));
      expect(pageStats([]).minutes, 0);
      expect(pageStats([Block('p', BlockType.paragraph, text: 'um')]).minutes, 1);
    });
    test('ago', () {
      const now = 10000000000;
      expect(ago(now - 5000, now: now), 'agora há pouco');
      expect(ago(now - 5 * 60000, now: now), 'há 5 min');
      expect(ago(now - 3 * 3600000, now: now), 'há 3 h');
      expect(ago(now - 4 * 86400000, now: now), 'há 4 d');
      expect(ago(now - 40 * 86400000, now: now), 'há 1 mês');
      expect(ago(now - 100 * 86400000, now: now), 'há 3 meses');
      expect(ago(now + 9999, now: now), 'agora há pouco');
    });
  });

  group('moveItem', () {
    test('sobe, desce e recusa o que não move', () {
      final l = ['a', 'b', 'c', 'd'];
      expect(moveItem(l, 0, 3), true);
      expect(l, ['b', 'c', 'a', 'd']);
      expect(moveItem(l, 3, 0), true);
      expect(l, ['d', 'b', 'c', 'a']);
      expect(moveItem(l, 1, 1), false);
      expect(moveItem(l, 1, 2), false);
      expect(moveItem(l, -1, 2), false);
      expect(moveItem(l, 0, 9), false);
      expect(moveItem(l, 9, 0), false);
      expect(moveItem(l, 0, 4), true);
      expect(l, ['b', 'c', 'a', 'd']);
    });
  });

  group('numeração', () {
    Block n(String id, [int indent = 0]) => Block(id, BlockType.numbered, text: '', indent: indent);
    test('conta no nível, reinicia nos filhos e em qualquer outro bloco', () {
      final r = numbering([n('1'), n('2'), n('2a', 1), n('2b', 1), n('3'), n('3a', 1), Block('p', BlockType.paragraph, text: ''), n('x')]);
      expect(r['1'], 1);
      expect(r['2'], 2);
      expect(r['2a'], 1);
      expect(r['2b'], 2);
      expect(r['3'], 3);
      expect(r['3a'], 1);
      expect(r['x'], 1);
    });
    test('um item com marcador no meio não reinicia o nível de cima', () {
      final r = numbering([n('1'), Block('b', BlockType.bullet, text: '', indent: 1), n('2')]);
      expect(r['2'], 2);
    });
    test('começar fundo não quebra', () {
      expect(numbering([n('a', 3)])['a'], 1);
    });
  });

  group('outline, mídia e arquivos', () {
    test('outline lista só títulos e dá nome ao vazio', () {
      final o = outline([Block('h', BlockType.heading, text: ' Olá   mundo ', level: 1), Block('p', BlockType.paragraph, text: 'x'), Block('v', BlockType.heading, text: '')]);
      expect(o.map((e) => (e.text, e.level)), [('Olá mundo', 1), ('Sem título', 2)]);
    });
    test('mídia direta', () {
      expect(isDirectMedia(BlockType.video, 'https://x.com/a/aula.MP4'), true);
      expect(isDirectMedia(BlockType.video, 'https://youtube.com/watch?v=1'), false);
      expect(isDirectMedia(BlockType.audio, 'https://x.com/s.mp3?x=1'), true);
      expect(isDirectMedia(BlockType.audio, 'sem esquema.mp3'), false);
    });
    test('tipo do bloco pelo que o servidor achou', () {
      expect(blockTypeForFile('image/png', 1), BlockType.image);
      expect(blockTypeForFile('video/mp4', 1), BlockType.video);
      expect(blockTypeForFile('application/ogg', 1), BlockType.video);
      expect(blockTypeForFile('audio/mpeg', 1), BlockType.audio);
      expect(blockTypeForFile('application/pdf', 1), BlockType.pdf);
      expect(blockTypeForFile('image/png', 2), BlockType.file);
      expect(blockTypeForFile('text/plain', 1), BlockType.file);
    });
    test('fileIdsOf junta sem repetir', () {
      expect(fileIdsOf([Block('a', BlockType.file, fileId: 'x'), Block('b', BlockType.image, fileId: 'x'), Block('c', BlockType.video, fileId: ''), Block('d', BlockType.pdf, fileId: 'y')]), ['x', 'y']);
    });
  });
}
