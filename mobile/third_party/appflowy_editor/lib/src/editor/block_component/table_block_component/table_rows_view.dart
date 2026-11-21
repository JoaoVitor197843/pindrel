// Pindrel: the table laid out by rows, and only the rows near the screen exist.
//
// The stock view is a Column per table column; a row is as tall as its tallest cell
// because each cell's height is measured from its rendered paragraph and written
// back into the document (a callback and two listeners per cell), and every cell of
// the table is built whether it is on screen or not. Measured with 4 tables of
// 8 x 40 cells: +133 MB over an empty page, and an app with a text field per cell
// was past 400 MB. This view lays the grid out by rows (rows share a height by
// construction, nothing is written back) and builds only the rows near the screen
// (table_lazy_rows.dart): +50 MB. A built cell is the package's own paragraph, so
// the mouse, the keyboard, the touch selection, undo, copy and paste all work in it
// exactly as outside the table. An earlier version drew the cells as plain text until
// touched (+36 MB): the editor could not find them for a click or a drag, so the mouse
// could not select and a tap needed two tries.

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_lazy_rows.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// The words the table shows (the app passes them translated).
class TableLabels {
  const TableLabels({
    this.row = 'Linha',
    this.header = 'Cabeçalho',
    this.col = 'Coluna',
    this.addRow = '+ linha',
    this.addCol = 'Adicionar coluna',
    this.insertAbove = 'Inserir linha acima',
    this.insertBelow = 'Inserir linha abaixo',
    this.insertLeft = 'Inserir coluna à esquerda',
    this.insertRight = 'Inserir coluna à direita',
    this.moveUp = 'Mover linha para cima',
    this.moveDown = 'Mover linha para baixo',
    this.moveLeft = 'Mover coluna para a esquerda',
    this.moveRight = 'Mover coluna para a direita',
    this.duplicateRow = 'Duplicar linha',
    this.duplicateCol = 'Duplicar coluna',
    this.clearRow = 'Limpar linha',
    this.clearCol = 'Limpar coluna',
    this.removeRow = 'Excluir linha',
    this.removeCol = 'Excluir coluna',
    this.wider = 'Alargar coluna',
    this.narrower = 'Estreitar coluna',
  });
  final String row, header, col, addRow, addCol;
  final String insertAbove, insertBelow, insertLeft, insertRight, moveUp, moveDown, moveLeft, moveRight;
  final String duplicateRow, duplicateCol, clearRow, clearCol, removeRow, removeCol, wider, narrower;
}

/// One line of a row or column menu.
class TableMenuItem {
  const TableMenuItem(this.label, this.icon, this.run, {this.danger = false, this.startsGroup = false});
  final String label;
  final IconData icon;
  final VoidCallback run;
  final bool danger;

  /// A divider is drawn before it.
  final bool startsGroup;
}

/// What can be done to the rows and columns of one table, in one place for the handles of the table and the
/// right-click menu of the page. Each table registers its own, found by its node ([TableOps.of]).
class TableOps {
  TableOps({required this.editorState, required this.tableNode, required this.labels, this.headerRow = false, this.maxRows, this.maxCols, this.maxColWidth = 600});

  static final _registry = Expando<TableOps>('table ops');

  /// The operations of the table drawn for [table] (a `table` node), if it is on screen.
  static TableOps? of(Node table) => _registry[table];

  EditorState editorState;
  TableNode tableNode;
  TableLabels labels;
  bool headerRow;
  int? maxRows, maxCols;
  double maxColWidth;

  void register() => _registry[tableNode.node] = this;

  Node get node => tableNode.node;
  int get rows => tableNode.rowsLen;
  int get cols => tableNode.colsLen;
  bool get editable => editorState.editable;

  bool canGrow({int rows = 0, int cols = 0}) =>
      (maxRows == null || this.rows + rows <= maxRows!) && (maxCols == null || this.cols + cols <= maxCols!);

  bool isHeader(int r) => headerRow && r == 0;

  void _apply(void Function(Transaction t) build) {
    final t = editorState.transaction;
    build(t);
    if (t.operations.isNotEmpty) editorState.apply(t);
  }

  void resize(int col, double w) => _apply((t) => tableNode.setColWidth(col, w.clamp(tableNode.config.colMinimumWidth, maxColWidth), transaction: t));

  static const _own = {TableCellBlockKeys.rowPosition, TableCellBlockKeys.colPosition, TableCellBlockKeys.width, TableCellBlockKeys.height};

  /// Swaps what two cells hold (text and whatever the app keeps on them, like a column id), never where they are:
  /// the package needs the cells in their order, so a move is a swap of contents.
  void _swapCells(Transaction t, Node a, Node b) {
    final pa = a.children.first, pb = b.children.first;
    t.updateNode(pa, {'delta': pb.attributes['delta'] ?? Delta().toJson()});
    t.updateNode(pb, {'delta': pa.attributes['delta'] ?? Delta().toJson()});
    final ka = {for (final e in a.attributes.entries) if (!_own.contains(e.key)) e.key: e.value};
    final kb = {for (final e in b.attributes.entries) if (!_own.contains(e.key)) e.key: e.value};
    final keys = {...ka.keys, ...kb.keys};
    t.updateNode(a, {for (final k in keys) k: kb[k]});
    t.updateNode(b, {for (final k in keys) k: ka[k]});
  }

  void moveRow(int r, int to) {
    if (to < (headerRow ? 1 : 0) || to >= rows) return;
    _apply((t) {
      for (var c = 0; c < cols; c++) {
        _swapCells(t, tableNode.getCell(c, r), tableNode.getCell(c, to));
      }
    });
  }

  void moveCol(int c, int to) {
    if (to < 0 || to >= cols) return;
    final wc = tableNode.getColWidth(c), wt = tableNode.getColWidth(to);
    _apply((t) {
      for (var r = 0; r < rows; r++) {
        _swapCells(t, tableNode.getCell(c, r), tableNode.getCell(to, r));
      }
      tableNode.setColWidth(c, wt, transaction: t, force: true);
      tableNode.setColWidth(to, wc, transaction: t, force: true);
    });
  }

  void insertRow(int at) => TableActions.add(node, at, editorState, TableDirection.row);
  void insertCol(int at) => TableActions.add(node, at, editorState, TableDirection.col);

  List<TableMenuItem> rowItems(int r) {
    final header = isHeader(r);
    final grow = canGrow(rows: 1);
    final shrink = rows > (headerRow ? 2 : 1);
    final first = headerRow ? 1 : 0;
    final l = labels;
    return [
      if (!header && grow) TableMenuItem(l.insertAbove, Icons.keyboard_arrow_up, () => insertRow(r)),
      if (grow) TableMenuItem(l.insertBelow, Icons.keyboard_arrow_down, () => insertRow(r + 1)),
      if (!header && r > first) TableMenuItem(l.moveUp, Icons.arrow_upward, () => moveRow(r, r - 1), startsGroup: true),
      if (!header && r < rows - 1) TableMenuItem(l.moveDown, Icons.arrow_downward, () => moveRow(r, r + 1)),
      if (!header && grow) TableMenuItem(l.duplicateRow, Icons.content_copy, () => TableActions.duplicate(node, r, editorState, TableDirection.row), startsGroup: true),
      TableMenuItem(l.clearRow, Icons.backspace_outlined, () => TableActions.clear(node, r, editorState, TableDirection.row), startsGroup: header || !grow),
      if (!header && shrink) TableMenuItem(l.removeRow, Icons.delete_outline, () => TableActions.delete(node, r, editorState, TableDirection.row), danger: true, startsGroup: true),
    ];
  }

  List<TableMenuItem> colItems(int c) {
    final grow = canGrow(cols: 1);
    final l = labels;
    return [
      if (grow) TableMenuItem(l.insertLeft, Icons.keyboard_arrow_left, () => insertCol(c)),
      if (grow) TableMenuItem(l.insertRight, Icons.keyboard_arrow_right, () => insertCol(c + 1)),
      if (c > 0) TableMenuItem(l.moveLeft, Icons.arrow_back, () => moveCol(c, c - 1), startsGroup: true),
      if (c < cols - 1) TableMenuItem(l.moveRight, Icons.arrow_forward, () => moveCol(c, c + 1)),
      TableMenuItem(l.wider, Icons.unfold_more_double, () => resize(c, tableNode.getColWidth(c) + 40), startsGroup: true),
      TableMenuItem(l.narrower, Icons.unfold_less_double, () => resize(c, tableNode.getColWidth(c) - 40)),
      if (grow) TableMenuItem(l.duplicateCol, Icons.content_copy, () => TableActions.duplicate(node, c, editorState, TableDirection.col), startsGroup: true),
      TableMenuItem(l.clearCol, Icons.backspace_outlined, () => TableActions.clear(node, c, editorState, TableDirection.col), startsGroup: !grow),
      if (cols > 1) TableMenuItem(l.removeCol, Icons.delete_outline, () => TableActions.delete(node, c, editorState, TableDirection.col), danger: true, startsGroup: true),
    ];
  }
}

class RowsTableView extends StatefulWidget {
  const RowsTableView({
    super.key,
    required this.editorState,
    required this.tableNode,
    required this.tableStyle,
    required this.cellStyle,
    this.labels = const TableLabels(),
    this.headerRow = false,
    this.gutter = 28,
    this.maxRows,
    this.maxCols,
    this.maxColWidth = 600,
    this.cellPadding = 8,
    this.controlColor = const Color(0xFF9A968E),
  });

  final EditorState editorState;
  final TableNode tableNode;
  final TableStyle tableStyle;

  /// The style of a cell's text, to guess the height of a row before it is built.
  final TextStyle cellStyle;
  final TableLabels labels;

  /// Row 0 is a header: it cannot be removed, moved or have a row put above it.
  final bool headerRow;

  /// Width of the column of row handles, left of the cells.
  final double gutter;

  /// Limits of the stored model (rows count the header); the controls stop offering to grow past them.
  final int? maxRows, maxCols;
  final double maxColWidth;
  final double cellPadding;
  final Color controlColor;

  @override
  State<RowsTableView> createState() => _RowsTableViewState();
}

/// Rebuilds only itself when the mouse comes and goes (a row is not rebuilt for it).
class _Hover extends StatefulWidget {
  const _Hover({required this.builder});
  final Widget Function(BuildContext context, bool hover) builder;

  @override
  State<_Hover> createState() => _HoverState();
}

class _HoverState extends State<_Hover> {
  var _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() => _hover = false),
    child: widget.builder(context, _hover),
  );
}

class _RowsTableViewState extends State<RowsTableView> {
  // widths while a column is being dragged; the document gets one edit when the finger lifts
  final _live = <int, double>{};
  late final TableOps _ops = TableOps(
    editorState: widget.editorState,
    tableNode: widget.tableNode,
    labels: widget.labels,
    headerRow: widget.headerRow,
    maxRows: widget.maxRows,
    maxCols: widget.maxCols,
    maxColWidth: widget.maxColWidth,
  );

  TableNode get _t => widget.tableNode;
  EditorState get _es => widget.editorState;
  TableLabels get _l => widget.labels;

  double _w(int c) => _live[c] ?? _t.getColWidth(c);

  // ---- the menus on the handles

  Widget _menu(String tip, List<TableMenuItem> items, Widget child) {
    if (items.isEmpty || !_es.editable) return child;
    return PopupMenuButton<int>(
      tooltip: tip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 220),
      onSelected: (i) => items[i].run(),
      itemBuilder: (_) => [
        for (var i = 0; i < items.length; i++) ...[
          if (items[i].startsGroup && i > 0) const PopupMenuDivider(height: 8),
          PopupMenuItem(
            value: i,
            height: 38,
            child: Row(children: [
              Icon(items[i].icon, size: 16, color: items[i].danger ? const Color(0xFFCD7064) : widget.controlColor),
              const SizedBox(width: 10),
              Flexible(child: Text(items[i].label, style: TextStyle(fontSize: 14, color: items[i].danger ? const Color(0xFFCD7064) : null))),
            ]),
          ),
        ],
      ],
      child: child,
    );
  }

  Widget _grip(String tip, List<TableMenuItem> items, {double size = 24}) => _menu(
    tip,
    items,
    SizedBox(width: size, height: size, child: Center(child: Icon(Icons.drag_indicator, size: 16, color: widget.controlColor))),
  );

  Widget _plus(String tip, VoidCallback run) => Tooltip(
    message: tip,
    child: InkResponse(
      radius: 12,
      onTap: run,
      child: SizedBox(width: 20, height: 24, child: Center(child: Icon(Icons.add, size: 16, color: widget.controlColor))),
    ),
  );

  /// The handle of a row: always there to open its menu; the mouse also shows a "+" to insert a row right below.
  Widget _rowHandle(int r) {
    final header = widget.headerRow && r == 0;
    final grow = _ops.canGrow(rows: 1);
    final name = header ? _l.header : '${_l.row} ${widget.headerRow ? r : r + 1}';
    if (!_es.editable) return SizedBox(width: widget.gutter);
    return _Hover(
      builder: (context, hover) => SizedBox(
        width: widget.gutter,
        height: 28,
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          if (hover && grow && widget.gutter >= 44) _plus(_l.insertBelow, () => _ops.insertRow(r + 1)),
          _grip(name, _ops.rowItems(r)),
        ]),
      ),
    );
  }

  Widget _colHandle(int c, {required bool hover}) {
    final grow = _ops.canGrow(cols: 1);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (hover && grow) _plus(_l.insertRight, () => _ops.insertCol(c + 1)),
      _grip('${_l.col} ${c + 1}', _ops.colItems(c)),
    ]);
  }

  // ---- layout

  /// The cheap cell for rows built while the page moves: the same text, plain, in the same box, with as few render
  /// objects as it takes (no handles, no keys, no gesture detector: a row that lives a tenth of a second). A tap on
  /// it is not served: the page is moving, and the real paragraph is there before a finger can come back.
  Widget _lightCell(int r, int c) {
    final cell = _t.getCell(c, r);
    final bg = ((cell.attributes[TableCellBlockKeys.colBackgroundColor] ?? cell.attributes[TableCellBlockKeys.rowBackgroundColor]) as String?)?.tryToColor();
    final pad = widget.cellPadding;
    final cfg = _es.editorStyle.textStyleConfiguration;
    Widget child = Padding(
      padding: EdgeInsets.fromLTRB(pad, 4, pad, 4),
      // the same line height rules as the paragraph of the editor, so the swap to the real one moves nothing
      child: Text.rich(
        _span(cell.children.first, widget.cellStyle),
        textHeightBehavior: TextHeightBehavior(
          applyHeightToFirstAscent: cfg.applyHeightToFirstAscent,
          applyHeightToLastDescent: cfg.applyHeightToLastDescent,
          leadingDistribution: cfg.leadingDistribution,
        ),
        textScaler: TextScaler.linear(_es.editorStyle.textScaleFactor),
      ),
    );
    if (bg != null) child = ColoredBox(color: bg, child: child);
    return SizedBox(width: _w(c), child: child);
  }

  /// An empty row of the height the row is expected to have, with faint bars where the text will be: what is drawn
  /// while the page goes too fast for anyone to read it (one render object, nothing to lay out).
  Widget _skeleton(int r, double height, BorderSide line) {
    final widths = [for (var c = 0; c < _t.colsLen; c++) _w(c)];
    return SizedBox(
      height: height,
      child: CustomPaint(painter: _SkeletonPainter(widths, widget.gutter, widget.cellPadding, widget.controlColor.withValues(alpha: 0.18), line.color)),
    );
  }

  final _est = <int, double>{};

  /// What a row never built is guessed to measure: one line is the least a row is, and every extra line a cell's text
  /// is expected to wrap into adds a line of the cell's style. A guess from the length of the text, not a layout.
  double _estimate(int r) => _est[r] ??= () {
    final scale = _es.editorStyle.textScaleFactor;
    final fontSize = (widget.cellStyle.fontSize ?? 15) * scale;
    final lineHeight = fontSize * (widget.cellStyle.height ?? 1.5);
    var lines = 1;
    for (var c = 0; c < _t.colsLen; c++) {
      final text = _t.getCell(c, r).children.firstOrNull?.delta?.toPlainText() ?? '';
      if (text.isEmpty) continue;
      final perLine = ((_w(c) - 2 * widget.cellPadding) / (fontSize * 0.56)).clamp(3, 400);
      var n = 0;
      for (final part in text.split('\n')) {
        n += (part.length / perLine).ceil().clamp(1, 1000);
      }
      if (n > lines) lines = n;
    }
    return 28 * scale.clamp(1.0, 3.0) + (lines - 1) * lineHeight;
  }();

  /// The row the selection is in, so that row is never torn down while the page scrolls past it.
  Set<int> _keep() {
    final s = _es.selection;
    if (s == null) return const {};
    final base = _t.node.path;
    final out = <int>{};
    for (final p in [s.start.path, s.end.path]) {
      if (p.length <= base.length) continue;
      var same = true;
      for (var i = 0; i < base.length; i++) {
        if (p[i] != base[i]) same = false;
      }
      if (!same) continue;
      final cell = _t.node.children.elementAtOrNull(p[base.length]);
      final r = cell?.attributes[TableCellBlockKeys.rowPosition];
      if (r is int) out.add(r);
    }
    return out;
  }

  Widget _cell(BuildContext context, int r, int c) {
    final cell = _t.getCell(c, r);
    final header = widget.headerRow && r == 0;
    final bg = ((cell.attributes[TableCellBlockKeys.colBackgroundColor] ?? cell.attributes[TableCellBlockKeys.rowBackgroundColor]) as String?)?.tryToColor();
    final text = _es.renderer.build(context, cell.children.first);
    final pad = widget.cellPadding;
    return SizedBox(
      key: cell.key,
      width: _w(c),
      child: Container(
        color: bg,
        padding: EdgeInsets.only(left: pad, right: header ? 0 : pad),
        child: header && _es.editable
            ? _Hover(
                builder: (context, hover) => Stack(children: [
                  Row(children: [
                    Expanded(child: text),
                    _colHandle(c, hover: hover),
                  ]),
                  // the edge of the column: drag to resize
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    width: 6,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeColumn,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        dragStartBehavior: DragStartBehavior.down,
                        onHorizontalDragUpdate: (d) => setState(() => _live[c] = (_w(c) + d.delta.dx).clamp(_t.config.colMinimumWidth, widget.maxColWidth)),
                        onHorizontalDragEnd: (_) => _endResize(c),
                        onHorizontalDragCancel: () => setState(() => _live.remove(c)),
                      ),
                    ),
                  ),
                ]),
              )
            : text,
      ),
    );
  }

  void _endResize(int c) {
    final w = _live.remove(c);
    setState(() {});
    if (w != null) _ops.resize(c, w);
  }

  Widget _row(BuildContext context, int r, RowDetail detail, double height) {
    final light = detail == RowDetail.light;
    final line = BorderSide(color: widget.tableStyle.borderColor.withValues(alpha: 0.6));
    final header = widget.headerRow && r == 0;
    if (detail == RowDetail.skeleton && !header) return _skeleton(r, height, line);
    if (light && !header) {
      // Out of the accessibility tree: such a row lives a tenth of a second, and building and moving the nodes of the
      // rows that come and go was most of the cost of a frame (8 of 13 ms on the timeline of the real page).
      return ExcludeSemantics(child: DecoratedBox(
        decoration: BoxDecoration(border: Border(bottom: line)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // as tall as the handle of a real row, which is what sets the least height of a row
          SizedBox(width: widget.gutter, height: 28),
          for (var c = 0; c < _t.colsLen; c++) _lightCell(r, c),
          const SizedBox(width: 32),
        ]),
      ));
    }
    return DecoratedBox(
      decoration: BoxDecoration(border: Border(bottom: line)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _rowHandle(r),
        Table(
          columnWidths: {for (var c = 0; c < _t.colsLen; c++) c: FixedColumnWidth(_w(c))},
          children: [
            TableRow(children: [for (var c = 0; c < _t.colsLen; c++) _cell(context, r, c)]),
          ],
        ),
        if (header && _es.editable && _ops.canGrow(cols: 1))
          IconButton(
            tooltip: _l.addCol,
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            padding: EdgeInsets.zero,
            color: widget.controlColor,
            icon: const Icon(Icons.add),
            onPressed: () => _ops.insertCol(_t.colsLen),
          )
        else
          const SizedBox(width: 32),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    _est.clear();
    _ops
      ..editorState = _es
      ..tableNode = _t
      ..labels = _l
      ..headerRow = widget.headerRow
      ..maxRows = widget.maxRows
      ..maxCols = widget.maxCols
      ..maxColWidth = widget.maxColWidth
      ..register();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LazyRows(
          // another text size is another height for every row: what was measured is forgotten
          key: ValueKey(_es.editorStyle.textScaleFactor),
          estimateFor: _estimate,
          count: _t.rowsLen,
          keep: _keep(),
          rowBuilder: _row,
        ),
        if (_es.editable && _ops.canGrow(rows: 1))
          Padding(
            padding: EdgeInsets.only(left: widget.gutter, top: 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () => _ops.insertRow(_t.rowsLen),
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: Text(_l.addRow, style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: widget.controlColor))),
            ),
          ),
      ],
    );
  }
}

/// The text of a paragraph as a span, with the marks the editor keeps.
TextSpan _span(Node paragraph, TextStyle base) {
  final delta = paragraph.delta;
  if (delta == null) return TextSpan(text: '', style: base);
  final spans = <InlineSpan>[];
  for (final op in delta) {
    if (op is! TextInsert) continue;
    final a = op.attributes ?? const <String, dynamic>{};
    var style = base;
    if (a[AppFlowyRichTextKeys.bold] == true) style = style.copyWith(fontWeight: FontWeight.bold);
    if (a[AppFlowyRichTextKeys.italic] == true) style = style.copyWith(fontStyle: FontStyle.italic);
    final lines = <TextDecoration>[
      if (a[AppFlowyRichTextKeys.underline] == true || a[AppFlowyRichTextKeys.href] != null) TextDecoration.underline,
      if (a[AppFlowyRichTextKeys.strikethrough] == true) TextDecoration.lineThrough,
    ];
    if (lines.isNotEmpty) style = style.copyWith(decoration: TextDecoration.combine(lines));
    if (a[AppFlowyRichTextKeys.code] == true) style = style.copyWith(fontFamily: 'monospace', backgroundColor: const Color(0x22FFFFFF));
    final bg = a[AppFlowyRichTextKeys.backgroundColor];
    if (bg is String) {
      final c = bg.tryToColor();
      if (c != null) style = style.copyWith(backgroundColor: c);
    }
    spans.add(TextSpan(text: op.text, style: style));
  }
  return TextSpan(style: base, children: spans);
}

class _SkeletonPainter extends CustomPainter {
  const _SkeletonPainter(this.widths, this.gutter, this.padding, this.bar, this.line);
  final List<double> widths;
  final double gutter, padding;
  final Color bar, line;

  @override
  void paint(Canvas canvas, Size size) {
    var x = gutter;
    final p = Paint()..color = bar;
    for (final w in widths) {
      final inner = w - 2 * padding;
      if (inner > 8) canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x + padding, 10, inner * 0.62, 8), const Radius.circular(3)), p);
      x += w;
    }
    canvas.drawLine(Offset(0, size.height - 0.5), Offset(size.width, size.height - 0.5), Paint()..color = line.withValues(alpha: 0.6));
  }

  @override
  bool shouldRepaint(_SkeletonPainter old) => false;
}
