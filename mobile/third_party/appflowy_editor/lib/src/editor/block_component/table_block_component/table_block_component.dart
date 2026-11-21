import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_rows_view.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'table_view.dart';

class TableBlockKeys {
  const TableBlockKeys._();

  static const String type = 'table';

  static const String colDefaultWidth = 'colDefaultWidth';

  static const String rowDefaultHeight = 'rowDefaultHeight';

  static const String colMinimumWidth = 'colMinimumWidth';

  static const String borderWidth = 'borderWidth';

  static const String colsLen = 'colsLen';

  static const String rowsLen = 'rowsLen';

  static const String colsHeight = 'colsHeight';
}

class TableStyle {
  const TableStyle({
    this.colWidth = 160,
    this.rowHeight = 40,
    this.colMinimumWidth = 40,
    this.borderWidth = 2,
    this.addIcon = TableDefaults.addIcon,
    this.handlerIcon = TableDefaults.handlerIcon,
    this.borderColor = TableDefaults.borderColor,
    this.borderHoverColor = TableDefaults.borderHoverColor,
  });
  final double colWidth;
  final double rowHeight;
  final double colMinimumWidth;
  final double borderWidth;
  final Widget addIcon;
  final Widget handlerIcon;
  final Color borderColor;
  final Color borderHoverColor;
}

class TableDefaults {
  const TableDefaults._();

  static double colWidth = 160.0;

  static double rowHeight = 40.0;

  static double colMinimumWidth = 40.0;

  static double borderWidth = 2.0;

  static const Widget addIcon = Icon(Icons.add, size: 20);

  static const Widget handlerIcon = Icon(Icons.drag_indicator);

  static const Color borderColor = Colors.grey;

  static const Color borderHoverColor = Colors.blue;
}

enum TableDirection { row, col }

typedef TableBlockComponentMenuBuilder = Widget Function(
  Node,
  EditorState,
  int,
  TableDirection,
  VoidCallback?,
  VoidCallback?,
);

class TableBlockComponentBuilder extends BlockComponentBuilder {
  TableBlockComponentBuilder({
    super.configuration,
    this.tableStyle = const TableStyle(),
    this.menuBuilder,
    this.byRows = false,
    this.cellStyle = const TextStyle(fontSize: 16, height: 1.5),
    this.labels = const TableLabels(),
    this.headerRow = false,
    this.gutter = 28,
    this.maxRows,
    this.maxCols,
    this.maxColWidth = 600,
    this.controlColor = const Color(0xFF9A968E),
  });

  final TableBlockComponentMenuBuilder? menuBuilder;
  final TableStyle tableStyle;
  final bool headerRow;
  final double gutter;
  final int? maxRows, maxCols;
  final double maxColWidth;
  final Color controlColor;

  /// Pindrel: lay the table out by rows, building only the ones near the screen (see table_rows_view.dart).
  final bool byRows;
  final TextStyle cellStyle;
  final TableLabels labels;

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    TableDefaults.colWidth = tableStyle.colWidth;
    TableDefaults.rowHeight = tableStyle.rowHeight;
    TableDefaults.colMinimumWidth = tableStyle.colMinimumWidth;
    TableDefaults.borderWidth = tableStyle.borderWidth;

    return TableBlockComponentWidget(
      key: node.key,
      tableNode: TableNode(node: node),
      node: node,
      configuration: configuration,
      menuBuilder: menuBuilder,
      tableStyle: tableStyle,
      byRows: byRows,
      cellStyle: cellStyle,
      labels: labels,
      headerRow: headerRow,
      gutter: gutter,
      maxRows: maxRows,
      maxCols: maxCols,
      maxColWidth: maxColWidth,
      controlColor: controlColor,
      showActions: showActions(node),
      actionBuilder: (context, state) => actionBuilder(
        blockComponentContext,
        state,
      ),
      actionTrailingBuilder: (context, state) => actionTrailingBuilder(
        blockComponentContext,
        state,
      ),
    );
  }

  @override
  BlockComponentValidate get validate => (node) {
        // check the node is valid
        if (node.attributes.isEmpty) {
          AppFlowyEditorLog.editor
              .debug('TableBlockComponentBuilder: node is empty');

          return false;
        }

        // check the node has rowPosition and colPosition
        if (!node.attributes.containsKey(TableBlockKeys.colsLen) ||
            !node.attributes.containsKey(TableBlockKeys.rowsLen)) {
          AppFlowyEditorLog.editor.debug(
            'TableBlockComponentBuilder: node has no colsLen or rowsLen',
          );

          return false;
        }

        final colsLen = node.attributes[TableBlockKeys.colsLen];
        final rowsLen = node.attributes[TableBlockKeys.rowsLen];

        // check its children
        final children = node.children;
        if (children.isEmpty) {
          AppFlowyEditorLog.editor
              .debug('TableBlockComponentBuilder: children is empty');

          return false;
        }

        if (children.length != colsLen * rowsLen) {
          AppFlowyEditorLog.editor.debug(
            'TableBlockComponentBuilder: children length(${children.length}) is not equal to colsLen * rowsLen($colsLen * $rowsLen)',
          );

          return false;
        }

        // every position (col, row) holds exactly one cell (one pass, not a search per position)
        if (colsLen is! int || rowsLen is! int) return false;
        final seen = <int>{};
        for (final n in children) {
          final c = n.attributes[TableCellBlockKeys.colPosition];
          final r = n.attributes[TableCellBlockKeys.rowPosition];
          if (c is! int || r is! int || c < 0 || c >= colsLen || r < 0 || r >= rowsLen || !seen.add(c * rowsLen + r)) {
            AppFlowyEditorLog.editor.debug(
              'TableBlockComponentBuilder: a cell is missing, repeated or out of the table',
            );

            return false;
          }
        }

        return true;
      };
}

class TableBlockComponentWidget extends BlockComponentStatefulWidget {
  const TableBlockComponentWidget({
    super.key,
    required this.tableNode,
    required super.node,
    this.tableStyle = const TableStyle(),
    this.menuBuilder,
    this.byRows = false,
    this.cellStyle = const TextStyle(fontSize: 16, height: 1.5),
    this.labels = const TableLabels(),
    this.headerRow = false,
    this.gutter = 28,
    this.maxRows,
    this.maxCols,
    this.maxColWidth = 600,
    this.controlColor = const Color(0xFF9A968E),
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  final TableNode tableNode;

  final TableBlockComponentMenuBuilder? menuBuilder;
  final TableStyle tableStyle;
  final bool byRows;
  final TextStyle cellStyle;
  final TableLabels labels;
  final bool headerRow;
  final double gutter;
  final int? maxRows, maxCols;
  final double maxColWidth;
  final Color controlColor;

  @override
  State<TableBlockComponentWidget> createState() =>
      _TableBlockComponentWidgetState();
}

class _TableBlockComponentWidgetState extends State<TableBlockComponentWidget>
    with SelectableMixin, BlockComponentConfigurable {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  late final editorState = Provider.of<EditorState>(context, listen: false);
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget child = Scrollbar(
      controller: _scrollController,
      // a table wider than the page is cut at its edge: the bar says so (it only shows when there is more to see)
      thumbVisibility: widget.byRows,
      child: SingleChildScrollView(
        padding: widget.byRows ? EdgeInsets.zero : const EdgeInsets.only(top: 10, left: 10, bottom: 4),
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        child: widget.byRows
            ? RowsTableView(
                tableNode: widget.tableNode,
                editorState: editorState,
                tableStyle: widget.tableStyle,
                cellStyle: widget.cellStyle,
                labels: widget.labels,
                headerRow: widget.headerRow,
                gutter: widget.gutter,
                maxRows: widget.maxRows,
                maxCols: widget.maxCols,
                maxColWidth: widget.maxColWidth,
                controlColor: widget.controlColor,
              )
            : TableView(
                tableNode: widget.tableNode,
                editorState: editorState,
                menuBuilder: widget.menuBuilder,
                tableStyle: widget.tableStyle,
              ),
      ),
    );

    // by rows the table is as wide as the page's column, not as its cells: the block must not be centered
    if (widget.byRows) child = SizedBox(width: double.infinity, child: child);
    child = Padding(
      key: tableKey,
      padding: padding,
      child: child,
    );

    child = BlockSelectionContainer(
      node: node,
      delegate: this,
      listenable: editorState.selectionNotifier,
      remoteSelection: editorState.remoteSelections,
      blockColor: editorState.editorStyle.selectionColor,
      supportTypes: const [
        BlockSelectionType.block,
      ],
      child: child,
    );

    if (widget.showActions && widget.actionBuilder != null) {
      child = BlockComponentActionWrapper(
        node: node,
        actionBuilder: widget.actionBuilder!,
        actionTrailingBuilder: widget.actionTrailingBuilder,
        child: child,
      );
    }

    child = Padding(
      padding: margin,
      child: child,
    );

    return child;
  }

  final tableKey = GlobalKey();

  RenderBox get _renderBox => context.findRenderObject() as RenderBox;

  @override
  Position start() => Position(path: widget.node.path);

  @override
  Position end() => Position(path: widget.node.path, offset: 1);

  @override
  Position getPositionInOffset(Offset start) => end();

  @override
  List<Rect> getRectsInSelection(
    Selection selection, {
    bool shiftWithBaseOffset = false,
  }) {
    final parentBox = context.findRenderObject();
    final tableBox = tableKey.currentContext?.findRenderObject();
    if (parentBox is RenderBox && tableBox is RenderBox) {
      return [
        (shiftWithBaseOffset
                ? tableBox.localToGlobal(Offset.zero, ancestor: parentBox)
                : Offset.zero) &
            tableBox.size,
      ];
    }

    return [Offset.zero & _renderBox.size];
  }

  @override
  Selection getSelectionInRange(Offset start, Offset end) => Selection.single(
        path: widget.node.path,
        startOffset: 0,
        endOffset: 1,
      );

  @override
  bool get shouldCursorBlink => false;

  @override
  CursorStyle get cursorStyle => CursorStyle.cover;

  @override
  Offset localToGlobal(
    Offset offset, {
    bool shiftWithBaseOffset = false,
  }) =>
      _renderBox.localToGlobal(offset);

  @override
  Rect getBlockRect({
    bool shiftWithBaseOffset = false,
  }) {
    return getRectsInSelection(Selection.invalid()).first;
  }

  @override
  Rect? getCursorRectInPosition(
    Position position, {
    bool shiftWithBaseOffset = false,
  }) {
    final size = _renderBox.size;

    return Rect.fromLTWH(-size.width / 2.0, 0, size.width, size.height);
  }
}

SelectionMenuItem tableMenuItem = SelectionMenuItem(
  getName: () => AppFlowyEditorL10n.current.table,
  icon: (editorState, isSelected, style) => SelectionMenuIconWidget(
    icon: Icons.table_view,
    isSelected: isSelected,
    style: style,
  ),
  keywords: ['table'],
  handler: (editorState, _, __) async {
    final selection = editorState.selection;
    if (selection == null || !selection.isCollapsed) {
      return;
    }

    final currentNode = editorState.getNodeAtPath(selection.end.path);
    if (currentNode == null) {
      return;
    }

    final tableNode = TableNode.fromList([
      ['', ''],
      ['', ''],
    ]);

    final transaction = editorState.transaction;
    final delta = currentNode.delta;
    if (delta != null && delta.isEmpty) {
      transaction
        ..insertNode(selection.end.path, tableNode.node)
        ..deleteNode(currentNode);
      transaction.afterSelection = Selection.collapsed(
        Position(
          path: selection.end.path + [0, 0],
        ),
      );
    } else {
      transaction.insertNode(selection.end.path.next, tableNode.node);
      transaction.afterSelection = Selection.collapsed(
        Position(
          path: selection.end.path.next + [0, 0],
        ),
      );
    }

    await editorState.apply(transaction);
  },
);
