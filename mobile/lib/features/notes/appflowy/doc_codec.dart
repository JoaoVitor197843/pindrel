// The bridge between the page's flat `List<Block>` (what is stored, synced and
// shared with the web) and the editor's tree `Document`.
//
// Rule: the editor owns what it edits well, every other block rides along
// untouched.
//  * Native nodes (paragraph, heading 1-3, quote, bullet, numbered, checklist,
//    divider, table) are rebuilt from the document at every sync; their text goes
//    through the markers of `inline_marks.dart`. A table is the package's table
//    node: row 0 holds the column labels (the stored model keeps them apart from
//    the rows), the cells carry the column id (`cid`, on row 0) and the width.
//  * Every other block (code, callout, toggle, toggle heading, media, secure...) is an
//    opaque `pindrel_block` node that only carries the block id. The editor
//    never reads inside it, so nothing it does can damage the block, and the
//    existing widgets keep drawing and editing it.

import 'package:appflowy_editor/appflowy_editor.dart';

import '../data/blocks.dart';
import 'inline_marks.dart';

/// Node type of a block the editor does not edit itself.
const opaqueType = 'pindrel_block';

/// Attribute that carries the stored block id (and, on a checklist row, the item id).
const idKey = 'bid';
const itemKey = 'iid';

/// On the header cell of a column: the stored id of that column.
const colIdKey = 'cid';

/// The longest text a cell and a column label may hold (what the old fields allowed).
const maxCellText = 2000;
const maxLabelText = 80;

bool isNative(Block b) => switch (b.type) {
  BlockType.paragraph || BlockType.quote || BlockType.bullet || BlockType.numbered || BlockType.checklist || BlockType.divider || BlockType.table => true,
  BlockType.heading => !b.toggle,
  _ => false,
};

Node _text(String type, Block b, {Map<String, Object?> extra = const {}}) => Node(
  type: type,
  attributes: {'delta': marksToDelta(b.text ?? '').toJson(), idKey: b.id, ...extra},
);

/// The document for a page body. Never empty: the editor needs a node to put the caret in.
Document blocksToDocument(List<Block> blocks) {
  final root = <Node>[];
  // the last list node at each depth, to nest by `indent`
  var stack = <Node>[];
  for (final b in blocks) {
    if (b.type == BlockType.bullet || b.type == BlockType.numbered) {
      final node = _text(b.type == BlockType.bullet ? 'bulleted_list' : 'numbered_list', b);
      final depth = (b.indent ?? 0).clamp(0, maxIndent).clamp(0, stack.length);
      if (depth == 0) {
        root.add(node);
        stack = [node];
      } else {
        stack[depth - 1].insert(node);
        stack = [...stack.take(depth), node];
      }
      continue;
    }
    stack = [];
    switch (b.type) {
      case BlockType.paragraph:
        root.add(_text('paragraph', b));
      case BlockType.quote:
        root.add(_text('quote', b));
      case BlockType.heading when !b.toggle:
        root.add(_text('heading', b, extra: {'level': (b.level ?? 2).clamp(1, 3)}));
      case BlockType.divider:
        root.add(Node(type: 'divider', attributes: {idKey: b.id}));
      case BlockType.table:
        root.add(_table(b));
      case BlockType.checklist:
        final items = b.items ?? const <ChecklistItem>[];
        if (items.isEmpty) {
          root.add(Node(type: 'todo_list', attributes: {'delta': Delta().toJson(), 'checked': false, idKey: b.id, itemKey: newId('i')}));
        }
        for (final i in items) {
          root.add(Node(
            type: 'todo_list',
            attributes: {'delta': marksToDelta(i.text).toJson(), 'checked': i.done, idKey: b.id, itemKey: i.id},
          ));
        }
      default:
        root.add(Node(type: opaqueType, attributes: {idKey: b.id}));
    }
  }
  if (root.isEmpty) root.add(Node(type: 'paragraph', attributes: {'delta': Delta().toJson()}));
  return Document(root: pageNode(children: root));
}

Node _cell(String text, int col, int row, int width, {String? colId}) => Node(
  type: TableCellBlockKeys.type,
  attributes: {
    TableCellBlockKeys.colPosition: col,
    TableCellBlockKeys.rowPosition: row,
    TableCellBlockKeys.width: width.toDouble(),
    ?(colId == null ? null : colIdKey): colId,
  },
  children: [Node(type: 'paragraph', attributes: {'delta': marksToDelta(text).toJson()})],
);

/// The package's table for a stored one: row 0 is the labels, the rows follow. Cells are stored column by column,
/// the order the package itself builds them in.
Node _table(Block b) {
  final cols = (b.cols == null || b.cols!.isEmpty) ? [TableColumn(id: newId('c'), label: '')] : b.cols!;
  final rows = b.rows ?? const <Map<String, String>>[];
  final cells = <Node>[];
  for (var c = 0; c < cols.length; c++) {
    final col = cols[c];
    cells.add(_cell(col.label, c, 0, col.w, colId: col.id));
    for (var r = 0; r < rows.length; r++) {
      cells.add(_cell(rows[r][col.id] ?? '', c, r + 1, col.w));
    }
  }
  return Node(
    type: TableBlockKeys.type,
    attributes: {TableBlockKeys.colsLen: cols.length, TableBlockKeys.rowsLen: rows.length + 1, TableBlockKeys.colDefaultWidth: TableDefaults.colWidth, TableBlockKeys.rowDefaultHeight: TableDefaults.rowHeight, TableBlockKeys.colMinimumWidth: TableDefaults.colMinimumWidth, idKey: b.id},
    children: cells,
  );
}

String _clip(String t, int max) => t.length > max ? t.substring(0, max) : t;

/// The stored table for a package table. Whatever the editor did to it (rows and columns added, removed,
/// duplicated, moved) is read from the cells' own positions; a column the package made has no id yet and gets one.
Block _tableBlock(Node n, String id, {required bool stamp}) {
  var nCols = 0, nRows = 0;
  final grid = <(int, int), Node>{};
  for (final cell in n.children) {
    final c = cell.attributes[TableCellBlockKeys.colPosition], r = cell.attributes[TableCellBlockKeys.rowPosition];
    if (c is! int || r is! int || c < 0 || r < 0) continue;
    grid.putIfAbsent((c, r), () => cell);
    if (c + 1 > nCols) nCols = c + 1;
    if (r + 1 > nRows) nRows = r + 1;
  }
  String text(Node? cell, int max) {
    final p = cell?.children.firstOrNull;
    return p == null ? '' : _clip(_marks(p), max);
  }

  nCols = nCols.clamp(1, maxCols);
  nRows = nRows.clamp(1, maxRows + 1);
  final cols = <TableColumn>[];
  final seen = <String>{};
  for (var c = 0; c < nCols; c++) {
    final head = grid[(c, 0)];
    final given = head?.attributes[colIdKey];
    var cid = given is String && given.isNotEmpty && seen.add(given) ? given : null;
    if (cid == null) {
      cid = newId('c');
      seen.add(cid);
      if (stamp) head?.updateAttributes({colIdKey: cid});
    }
    final w = head?.attributes[TableCellBlockKeys.width];
    cols.add(TableColumn(id: cid, label: text(head, maxLabelText), w: (w is num ? w.round() : 160).clamp(minColWidth, maxColWidth)));
  }
  final rows = [
    for (var r = 1; r < nRows; r++) {for (var c = 0; c < nCols; c++) cols[c].id: text(grid[(c, r)], maxCellText)},
  ];
  return Block(id, BlockType.table, cols: cols, rows: rows);
}

Delta _delta(Node n) {
  final raw = n.attributes['delta'];
  return raw is List ? Delta.fromJson(raw) : Delta();
}

String _marks(Node n) {
  final t = deltaToMarks(_delta(n));
  return t.length > maxText ? t.substring(0, maxText) : t;
}

String? _bid(Node n) {
  final v = n.attributes[idKey];
  return v is String && v.isNotEmpty ? v : null;
}

/// The blocks for a document. [keep] holds the blocks the page has right now, by id:
/// opaque nodes are looked up there (and dropped if the block is gone).
/// Ids the editor copied onto a second node (Enter copies attributes) are given to the first one only.
/// With [stamp] a node that had no id (or a repeated one) gets the new id written on it, so the next
/// sync names the same block the same way.
List<Block> documentToBlocks(Document doc, Map<String, Block> keep, {bool stamp = false}) {
  final out = <Block>[];
  final seen = <String>{};
  String idFor(Node n) {
    final b = _bid(n);
    if (b != null && seen.add(b)) return b;
    final fresh = newId();
    seen.add(fresh);
    if (stamp) n.updateAttributes({idKey: fresh});
    return fresh;
  }

  Block? open; // the checklist being filled
  void walk(Node n, int depth) {
    final type = n.type;
    switch (type) {
      case 'paragraph':
        open = null;
        out.add(Block(idFor(n), BlockType.paragraph, text: _marks(n)));
      case 'quote':
        open = null;
        out.add(Block(idFor(n), BlockType.quote, text: _marks(n)));
      case 'heading':
        open = null;
        final l = (n.attributes['level'] is int ? n.attributes['level'] as int : 2).clamp(1, 3);
        out.add(Block(idFor(n), BlockType.heading, text: _marks(n), level: l == 2 ? null : l));
      case 'bulleted_list' || 'numbered_list':
        open = null;
        out.add(Block(idFor(n), type == 'bulleted_list' ? BlockType.bullet : BlockType.numbered, text: _marks(n), indent: depth.clamp(0, maxIndent)));
      case 'todo_list':
        // Enter copies the attributes, so a repeated item id gets a fresh one and the row stays in the same list
        final wanted = n.attributes[itemKey];
        final used = open?.items?.any((i) => i.id == wanted) ?? false;
        final item = ChecklistItem(
          id: wanted is String && wanted.isNotEmpty && !used ? wanted : newId('i'),
          text: _marks(n),
          done: n.attributes['checked'] == true,
        );
        if (stamp && item.id != wanted) n.updateAttributes({itemKey: item.id});
        final cur = open;
        if (cur != null && cur.items!.length < maxItems) {
          cur.items!.add(item);
        } else {
          open = Block(idFor(n), BlockType.checklist, items: [item]);
          out.add(open!);
        }
      case 'divider':
        open = null;
        out.add(Block(idFor(n), BlockType.divider));
      case TableBlockKeys.type:
        open = null;
        out.add(_tableBlock(n, idFor(n), stamp: stamp));
      case opaqueType:
        open = null;
        final id = _bid(n);
        final b = id == null ? null : keep[id];
        if (b != null && seen.add(id!)) out.add(b);
      default:
        // a node this bridge does not know (a feature switched on later): keep its text rather than lose it
        open = null;
        if (n.attributes['delta'] is List) out.add(Block(idFor(n), BlockType.paragraph, text: _marks(n)));
    }
    // the cells of a table are read by the table, never as blocks of their own
    if (n.type == TableBlockKeys.type) return;
    final nested = n.type == 'bulleted_list' || n.type == 'numbered_list';
    for (final c in n.children) {
      walk(c, nested ? depth + 1 : 0);
    }
  }

  for (final n in doc.root.children) {
    walk(n, 0);
  }
  // the caret's empty paragraph in a page that had no blocks is not a block
  if (keep.isEmpty && out.length == 1 && out.first.type == BlockType.paragraph && (out.first.text ?? '').isEmpty) {
    return [];
  }
  return out.take(maxBlocks).toList();
}
