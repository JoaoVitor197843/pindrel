// Fills a notes.db with a believable person's notes, for trying the real app by hand or by script. Not part of the
// suite: it does nothing without SEED_DB.
//   SEED_DB=/tmp/x/notes.db SEED=normal|heavy fvm flutter test tool/seed_notes_test.dart
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/notes/data/blocks.dart';
import 'package:mobile/features/notes/data/note_page.dart';
import 'package:mobile/features/notes/data/notes_db.dart';
import 'package:mobile/features/notes/data/workspace.dart';

const _topics = ['Reunião', 'Receita', 'Projeto', 'Ideias', 'Estudo', 'Viagem', 'Compras', 'Finanças', 'Saúde', 'Leitura', 'Treino', 'Casa', 'Trabalho', 'Carro', 'Presentes'];
const _words = ['planejamento', 'orçamento', 'prazo', 'revisão', 'contrato', 'cliente', 'tarefa', 'lista', 'meta', 'resumo', 'conversa', 'decisão', 'pendência', 'rascunho', 'versão', 'ajuste', 'entrega', 'relatório', 'agenda', 'ponto'];

void main() {
  final path = Platform.environment['SEED_DB'];
  if (path == null) return;
  test('seed', () {
    final heavy = Platform.environment['SEED'] == 'heavy';
    final rnd = Random(7);
    final db = NotesDb.open(path);
    final ws = Workspace(db);
    final tags = ['pessoal', 'trabalho', 'casa', 'estudo', 'ideias', 'finanças', 'saúde', 'viagem'];
    for (var i = 0; i < (heavy ? 8 : 5); i++) {
      ws.addTag(tags[i], TagColor.values[i % TagColor.values.length]);
    }
    String sentence(int n) => [for (var i = 0; i < n; i++) _words[rnd.nextInt(_words.length)]].join(' ');
    final now = DateTime.now().millisecondsSinceEpoch;
    final count = heavy ? 3000 : 28;
    for (var i = 0; i < count; i++) {
      final id = 'p$i';
      final topic = _topics[rnd.nextInt(_topics.length)];
      final blocks = <Block>[];
      var n = 0;
      String bid() => 'b${i}_${n++}';
      final size = heavy ? (i % 50 == 0 ? 280 : 6 + rnd.nextInt(40)) : 4 + rnd.nextInt(14);
      blocks.add(Block(bid(), BlockType.heading, text: '$topic: ${sentence(2)}', level: 2));
      while (blocks.length < size) {
        switch (rnd.nextInt(12)) {
          case 0:
            blocks.add(Block(bid(), BlockType.heading, text: sentence(3), level: 3));
          case 1 || 2 || 3 || 4:
            blocks.add(Block(bid(), BlockType.paragraph, text: '${sentence(8 + rnd.nextInt(18))}. **${sentence(2)}** e ${sentence(5)}.'));
          case 5:
            for (var k = 0; k < 3 + rnd.nextInt(3); k++) {
              blocks.add(Block(bid(), BlockType.bullet, text: sentence(4), indent: k == 1 ? 1 : 0));
            }
          case 6:
            blocks.add(Block(bid(), BlockType.checklist, items: [for (var k = 0; k < 3 + rnd.nextInt(4); k++) ChecklistItem(id: 'i${i}_${n}_$k', text: sentence(3), done: rnd.nextBool())]));
          case 7:
            blocks.add(Block(bid(), BlockType.quote, text: sentence(10)));
          case 8:
            blocks.add(Block(bid(), BlockType.callout, text: sentence(9), tone: CalloutTone.values[rnd.nextInt(CalloutTone.values.length)]));
          case 9:
            final cols = [for (var c = 0; c < 3 + rnd.nextInt(3); c++) TableColumn(id: 'c${i}_${n}_$c', label: _words[rnd.nextInt(_words.length)])];
            blocks.add(Block(bid(), BlockType.table, cols: cols, rows: [for (var r = 0; r < 4 + rnd.nextInt(heavy && i % 7 == 0 ? 60 : 8); r++) {for (final c in cols) c.id: sentence(1 + rnd.nextInt(3))}]));
          case 10:
            blocks.add(Block(bid(), BlockType.code, lang: 'python', text: 'def f(x):\n    return x * ${rnd.nextInt(9)}'));
          default:
            blocks.add(Block(bid(), BlockType.divider));
        }
      }
      final age = heavy ? rnd.nextInt(500) : rnd.nextInt(60);
      final p = NotePage(
        id: id,
        title: '$topic — ${sentence(2)}',
        excerpt: excerptOf(blocks),
        tags: [if (rnd.nextInt(3) > 0) tags[rnd.nextInt(heavy ? 8 : 5)]],
        updated: now - age * 86400000 - rnd.nextInt(80000000),
        created: now - (age + 20) * 86400000,
        blocks: blocks.length,
        content: blocks,
        pinned: i % (heavy ? 150 : 9) == 0,
        trashed: heavy && i % 40 == 7,
        icon: i % 5 == 0 ? '📝' : '',
      );
      db.savePage(p, content: true);
    }
    ws.dispose();
    expect(File(path).existsSync(), true);
  });
}
