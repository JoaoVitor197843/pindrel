import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/notes/appflowy/doc_codec.dart';
import 'package:mobile/features/notes/data/blocks.dart';

Map<String, Block> byId(List<Block> bs) => {for (final b in bs) b.id: b};

/// Through the editor and back, the way a page is opened and then saved.
List<Block> trip(List<Block> blocks) => documentToBlocks(blocksToDocument(blocks), byId(blocks));

String shape(List<Block> bs) => bs.map((b) => '${b.type.name}${b.level ?? ''}${b.indent != null ? '@${b.indent}' : ''}:${b.text ?? b.items?.map((i) => '${i.done ? 'x' : '_'}${i.text}').join('/') ?? ''}').join(' | ');

List<Block> sample() => [
  Block('h', BlockType.heading, text: 'Título **forte**', level: 1),
  Block('p', BlockType.paragraph, text: 'texto com *itálico* e `código`'),
  Block('q', BlockType.quote, text: 'citação'),
  Block('b0', BlockType.bullet, text: 'um', indent: 0),
  Block('b1', BlockType.bullet, text: 'filho', indent: 1),
  Block('b2', BlockType.bullet, text: 'neto', indent: 2),
  Block('b3', BlockType.bullet, text: 'outro', indent: 0),
  Block('n0', BlockType.numbered, text: 'primeiro', indent: 0),
  Block('n1', BlockType.numbered, text: 'segundo', indent: 0),
  Block('c', BlockType.checklist, items: [ChecklistItem(id: 'i1', text: 'a', done: true), ChecklistItem(id: 'i2', text: 'b')]),
  Block('d', BlockType.divider),
  Block('code', BlockType.code, lang: 'go', text: 'fmt.Println()'),
  Block('call', BlockType.callout, text: 'aviso', tone: CalloutTone.warning),
  Block('tog', BlockType.toggle, text: 'título', body: 'corpo'),
  Block('tab', BlockType.table, cols: [TableColumn(id: 'c1', label: 'A')], rows: [{'c1': 'x'}]),
  Block('sec', BlockType.secure, text: 'segredo'),
  Block('toc', BlockType.toc),
];

void main() {
  group('blocks to document', () {
    test('the editor edits text, lists, checklists, dividers and tables; everything else is opaque', () {
      final doc = blocksToDocument(sample());
      expect(doc.root.children.map((n) => n.type).toList(), [
        'heading', 'paragraph', 'quote',
        'bulleted_list', 'bulleted_list', // b0 (with b1/b2 inside) and b3
        'numbered_list', 'numbered_list',
        'todo_list', 'todo_list', 'divider',
        opaqueType, opaqueType, opaqueType, 'table', opaqueType, opaqueType,
      ]);
    });

    test('indent becomes nesting', () {
      final doc = blocksToDocument(sample());
      final b0 = doc.root.children[3];
      expect(b0.children.length, 1);
      expect(b0.children.first.children.length, 1);
    });

    test('an opaque node carries only the id', () {
      final doc = blocksToDocument(sample());
      final n = doc.root.children.firstWhere((n) => n.type == opaqueType);
      expect(n.attributes.keys.toList(), [idKey]);
      expect(n.attributes[idKey], 'code');
    });

    test('a toggle heading is opaque, a plain heading is not', () {
      final doc = blocksToDocument([Block('t', BlockType.heading, text: 'x', toggle: true, body: 'y'), Block('h', BlockType.heading, text: 'z', level: 3)]);
      expect(doc.root.children.map((n) => n.type).toList(), [opaqueType, 'heading']);
      expect(doc.root.children[1].attributes['level'], 3);
    });

    test('no blocks still gives a node for the caret', () {
      final doc = blocksToDocument(const []);
      expect(doc.root.children.length, 1);
      expect(doc.root.children.first.type, 'paragraph');
    });

    test('an indent deeper than its parent is clamped, never lost', () {
      final bs = [Block('a', BlockType.bullet, text: 'a', indent: 3), Block('b', BlockType.bullet, text: 'b', indent: 3)];
      expect(trip(bs).map((b) => b.text), ['a', 'b']);
    });
  });

  group('the trip is lossless', () {
    test('a whole page comes back identical', () {
      final before = sample();
      final json = before.map((b) => b.toJson()).toList();
      final after = trip(before);
      expect(after.map((b) => b.toJson()).toList(), json);
    });

    test('opaque blocks come back as the very same objects (nothing in the editor can damage them)', () {
      final before = sample();
      final after = trip(before);
      for (final id in ['code', 'call', 'tog', 'sec', 'toc']) {
        expect(identical(after.firstWhere((b) => b.id == id), before.firstWhere((b) => b.id == id)), isTrue, reason: id);
      }
    });

    test('rich text survives', () {
      final after = trip([Block('p', BlockType.paragraph, text: '**a** *b* __c__ ~~d~~ ==e== `f` [g](https://x.org)')]);
      expect(after.single.text, '**a** *b* __c__ ~~d~~ ==e== `f` [g](https://x.org)');
    });
  });

  group('tables', () {
    Block table() => Block(
      't',
      BlockType.table,
      cols: [TableColumn(id: 'a', label: 'Nome', w: 200), TableColumn(id: 'b', label: '**Idade**', w: 120)],
      rows: [
        {'a': 'Ana', 'b': '30'},
        {'a': 'Bia *B*', 'b': ''},
      ],
    );

    test('the stored table is the package table: row 0 holds the labels, cells carry id and width', () {
      final doc = blocksToDocument([table()]);
      final n = doc.root.children.single;
      expect(n.type, 'table');
      expect(n.attributes[idKey], 't');
      expect((n.attributes['colsLen'], n.attributes['rowsLen']), (2, 3));
      expect(n.children.length, 6);
      final head = n.children.where((c) => c.attributes['rowPosition'] == 0).toList();
      expect(head.map((c) => c.attributes[colIdKey]), ['a', 'b']);
      expect(head.map((c) => c.attributes['width']), [200.0, 120.0]);
      expect(head.last.children.single.delta!.toPlainText(), 'Idade', reason: 'the marks became a mark, not characters');
    });

    test('the trip is lossless, with marks in cells and labels', () {
      final t = table();
      final after = trip([t]).single;
      expect(after.id, 't');
      expect([for (final c in after.cols!) (c.id, c.label, c.w)], [('a', 'Nome', 200), ('b', '**Idade**', 120)]);
      expect(after.rows, [
        {'a': 'Ana', 'b': '30'},
        {'a': 'Bia *B*', 'b': ''},
      ]);
    });

    test('a table with no columns or no rows still has a header and survives', () {
      expect(trip([Block('t', BlockType.table, cols: [], rows: [])]).single.cols!.length, 1);
      final noRows = trip([Block('t', BlockType.table, cols: [TableColumn(id: 'a', label: 'A')], rows: [])]).single;
      expect((noRows.cols!.length, noRows.rows!.length), (1, 0));
    });

    test('the cells of a table are never read as blocks of their own', () {
      final out = trip([Block('p', BlockType.paragraph, text: 'a'), table(), Block('q', BlockType.paragraph, text: 'b')]);
      expect(out.map((b) => b.type), [BlockType.paragraph, BlockType.table, BlockType.paragraph]);
    });

    test('a column the editor made has no id: it gets one, and the same one at every later sync', () {
      final doc = blocksToDocument([table()]);
      final n = doc.root.children.single;
      // what the package does for "insert a column on the right": new cells without our attributes, positions renumbered
      for (final c in n.children) {
        if (c.attributes['colPosition'] == 1) c.updateAttributes({'colPosition': 2});
      }
      for (var r = 0; r < 3; r++) {
        n.insert(Node(type: 'table/cell', attributes: {'colPosition': 1, 'rowPosition': r}, children: [Node(type: 'paragraph', attributes: {'delta': (Delta()..insert(r == 0 ? 'Nova' : '')).toJson()})]));
      }
      n.updateAttributes({'colsLen': 3});
      final first = documentToBlocks(doc, {}, stamp: true).single;
      expect(first.cols!.map((c) => c.label), ['Nome', 'Nova', '**Idade**']);
      expect(first.cols![0].id, 'a');
      expect(first.cols![2].id, 'b');
      final fresh = first.cols![1].id;
      expect(fresh, isNot(anyOf('a', 'b')));
      expect(documentToBlocks(doc, {}).single.cols![1].id, fresh, reason: 'stamped on the header cell');
    });

    test('a duplicated column gets a new id, the first keeps its own', () {
      final doc = blocksToDocument([table()]);
      final n = doc.root.children.single;
      final copies = [for (final c in n.children.where((c) => c.attributes['colPosition'] == 0)) Node(type: 'table/cell', attributes: {...c.attributes, 'colPosition': 1}, children: [c.children.first.copyWith()])];
      for (final c in n.children) {
        if (c.attributes['colPosition'] == 1) c.updateAttributes({'colPosition': 2});
      }
      n.updateAttributes({'colsLen': 3});
      for (final c in copies) {
        n.insert(c);
      }
      final cols = documentToBlocks(doc, {}).single.cols!;
      expect(cols.map((c) => c.id).toSet().length, 3);
      expect(cols[0].id, 'a');
      expect(cols.map((c) => c.label), ['Nome', 'Nome', '**Idade**']);
    });

    test('limits: columns, rows and the size of a cell are cut to what the model allows', () {
      final big = Block('t', BlockType.table, cols: [for (var i = 0; i < 12; i++) TableColumn(id: 'c$i', label: 'x')], rows: [for (var r = 0; r < 200; r++) {for (var i = 0; i < 12; i++) 'c$i': 'v'}]);
      final doc = blocksToDocument([big]);
      final n = doc.root.children.single;
      // a hundred more columns and rows than the model keeps, and a huge cell
      for (var c = 12; c < 40; c++) {
        for (var r = 0; r < 205; r++) {
          n.insert(Node(type: 'table/cell', attributes: {'colPosition': c, 'rowPosition': r}, children: [Node(type: 'paragraph', attributes: {'delta': (Delta()..insert('z' * 5000)).toJson()})]));
        }
      }
      n.children.first.children.first.updateAttributes({'delta': (Delta()..insert('y' * 5000)).toJson()});
      final out = documentToBlocks(doc, {}).single;
      expect(out.cols!.length, maxCols);
      expect(out.rows!.length, maxRows);
      expect(out.cols!.first.label.length, maxLabelText);
    });

    test('a damaged table (missing cells, bad positions, no paragraph inside) never throws', () {
      final doc = blocksToDocument([table()]);
      final n = doc.root.children.single;
      n.children.last.children.first.unlink();
      n.insert(Node(type: 'table/cell', attributes: {'colPosition': 'x', 'rowPosition': -1}));
      n.insert(Node(type: 'table/cell'));
      n.children[1].unlink();
      final out = documentToBlocks(doc, {});
      expect(out.single.type, BlockType.table);
      expect(out.single.cols, isNotEmpty);
    });

    test('a repeated width or a width outside the range is brought back into it', () {
      final doc = blocksToDocument([table()]);
      for (final c in doc.root.children.single.children.where((c) => c.attributes['rowPosition'] == 0)) {
        c.updateAttributes({'width': 5.0});
      }
      expect(documentToBlocks(doc, {}).single.cols!.map((c) => c.w), [minColWidth, minColWidth]);
    });
  });

  group('what the editor does to the document', () {
    test('Enter copies the id: the second node gets a new one', () {
      final doc = blocksToDocument([Block('p', BlockType.paragraph, text: 'ab')]);
      final first = doc.root.children.first;
      doc.root.insert(Node(type: 'paragraph', attributes: {...first.attributes, 'delta': (Delta()..insert('cd')).toJson()}));
      final out = documentToBlocks(doc, {});
      expect(out.length, 2);
      expect(out[0].id, 'p');
      expect(out[1].id, isNot('p'));
      expect(out.map((b) => b.text), ['ab', 'cd']);
    });

    test('a new line in a checklist stays in the same checklist, with its own item id', () {
      final bs = [Block('c', BlockType.checklist, items: [ChecklistItem(id: 'i1', text: 'a')])];
      final doc = blocksToDocument(bs);
      doc.root.insert(Node(type: 'todo_list', attributes: {...doc.root.children.first.attributes, 'delta': (Delta()..insert('b')).toJson()}));
      final out = documentToBlocks(doc, byId(bs));
      expect(out.length, 1);
      expect(out.single.items!.map((i) => i.text), ['a', 'b']);
      expect(out.single.items!.map((i) => i.id).toSet().length, 2);
    });

    test('a divider between two checklists makes two checklists', () {
      final bs = [
        Block('c1', BlockType.checklist, items: [ChecklistItem(id: 'i1', text: 'a')]),
        Block('d', BlockType.divider),
        Block('c2', BlockType.checklist, items: [ChecklistItem(id: 'i2', text: 'b')]),
      ];
      expect(trip(bs).map((b) => b.type), [BlockType.checklist, BlockType.divider, BlockType.checklist]);
    });

    test('an opaque node whose block is gone is dropped', () {
      final doc = blocksToDocument(sample());
      final out = documentToBlocks(doc, {});
      expect(out.any((b) => b.type == BlockType.code), isFalse);
    });

    test('an opaque node copied twice shows the block once', () {
      final bs = [Block('code', BlockType.code, lang: 'go', text: 'x')];
      final doc = blocksToDocument(bs);
      doc.root.insert(Node(type: opaqueType, attributes: {idKey: 'code'}));
      expect(documentToBlocks(doc, byId(bs)).length, 1);
    });

    test('a heading of level 4 or more is level 3', () {
      final doc = blocksToDocument([Block('h', BlockType.heading, text: 'x')]);
      doc.root.children.first.updateAttributes({'level': 5});
      expect(documentToBlocks(doc, {}).single.level, 3);
    });

    test('a nested paragraph (Tab) is flattened, not lost', () {
      final doc = blocksToDocument([Block('a', BlockType.paragraph, text: 'a')]);
      doc.root.children.first.insert(Node(type: 'paragraph', attributes: {'delta': (Delta()..insert('filho')).toJson()}));
      expect(documentToBlocks(doc, {}).map((b) => b.text), ['a', 'filho']);
    });

    test('a node this bridge does not know keeps its text', () {
      final doc = Document(root: pageNode(children: [Node(type: 'callout', attributes: {'delta': (Delta()..insert('olá')).toJson()})]));
      final out = documentToBlocks(doc, {});
      expect(out.single.type, BlockType.paragraph);
      expect(out.single.text, 'olá');
    });

    test('an emptied list item that became a paragraph is kept (the page had blocks)', () {
      final bs = [Block('b', BlockType.bullet, text: 'x', indent: 0)];
      final doc = blocksToDocument(bs);
      doc.root.children.first.updateAttributes({'delta': Delta().toJson()});
      final converted = Node(type: 'paragraph', attributes: {'delta': Delta().toJson()});
      doc.root.children.first.insertBefore(converted);
      doc.root.children.last.unlink();
      expect(documentToBlocks(doc, byId(bs)).single.type, BlockType.paragraph);
    });

    test('a lone empty paragraph of a page that had no blocks stays no block', () {
      expect(documentToBlocks(blocksToDocument(const []), {}), isEmpty);
    });
  });

  group('careless use', () {
    test('the block limit is kept', () {
      final bs = [for (var i = 0; i < maxBlocks + 50; i++) Block('p$i', BlockType.paragraph, text: 't$i')];
      expect(trip(bs).length, maxBlocks);
    });

    test('a text over the limit is cut, not refused', () {
      final big = 'x' * (maxText + 500);
      expect(trip([Block('p', BlockType.paragraph, text: big)]).single.text!.length, maxText);
    });

    test('a checklist over the item limit spills into another one, losing nothing', () {
      final items = [for (var i = 0; i < maxItems; i++) ChecklistItem(id: 'i$i', text: 't$i')];
      final doc = blocksToDocument([Block('c', BlockType.checklist, items: items)]);
      for (var i = 0; i < 5; i++) {
        doc.root.insert(Node(type: 'todo_list', attributes: {'delta': (Delta()..insert('extra$i')).toJson(), 'checked': false}));
      }
      final out = documentToBlocks(doc, {});
      expect(out.fold<int>(0, (a, b) => a + (b.items?.length ?? 0)), maxItems + 5);
    });

    test('a damaged delta reads as empty text, never throws', () {
      final doc = Document(root: pageNode(children: [Node(type: 'paragraph', attributes: {'delta': 'oops'}), Node(type: 'paragraph')]));
      expect(() => documentToBlocks(doc, {}), returnsNormally);
    });

    test('500 blocks of every kind trip quickly', () {
      final bs = [for (var i = 0; i < 100; i++) ...[Block('p$i', BlockType.paragraph, text: '**a** $i'), Block('b$i', BlockType.bullet, text: 'x', indent: i % 3), Block('t$i', BlockType.table, cols: [TableColumn(id: 'c', label: 'A')], rows: [{'c': '$i'}]), Block('q$i', BlockType.quote, text: 'q'), Block('d$i', BlockType.divider)]];
      final sw = Stopwatch()..start();
      expect(trip(bs).length, 500);
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });
  });
}
