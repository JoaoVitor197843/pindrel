// The editor's component for an opaque block (code, callout, table, media...).
// It draws whatever [render] returns for the stored block id and takes no part
// in text editing: for the editor it is a single selectable box, like a divider.

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

import 'doc_codec.dart';

typedef OpaqueRender = Widget Function(BuildContext context, String blockId);

class PindrelBlockBuilder extends BlockComponentBuilder {
  PindrelBlockBuilder({required this.editorState, required this.render, super.configuration});

  final EditorState editorState;
  final OpaqueRender render;

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return PindrelBlockWidget(key: node.key, node: node, configuration: configuration, editorState: editorState, render: render);
  }

  // an opaque block has no children and no text
  @override
  BlockComponentValidate get validate => (node) => node.children.isEmpty;
}

class PindrelBlockWidget extends BlockComponentStatefulWidget {
  const PindrelBlockWidget({super.key, required super.node, super.configuration = const BlockComponentConfiguration(), required this.editorState, required this.render});

  final EditorState editorState;
  final OpaqueRender render;

  @override
  State<PindrelBlockWidget> createState() => _PindrelBlockWidgetState();
}

class _PindrelBlockWidgetState extends State<PindrelBlockWidget> with SelectableMixin, BlockComponentConfigurable {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  final _box = GlobalKey();

  RenderBox? get _renderBox => context.findRenderObject() as RenderBox?;

  @override
  Widget build(BuildContext context) {
    final id = node.attributes[idKey];
    final editorState = widget.editorState;
    return Padding(
      padding: margin,
      child: BlockSelectionContainer(
        node: node,
        delegate: this,
        listenable: editorState.selectionNotifier,
        remoteSelection: editorState.remoteSelections,
        blockColor: editorState.editorStyle.selectionColor,
        cursorColor: editorState.editorStyle.cursorColor,
        selectionColor: editorState.editorStyle.selectionColor,
        supportTypes: const [BlockSelectionType.block],
        child: Padding(key: _box, padding: padding, child: id is String ? widget.render(context, id) : const SizedBox.shrink()),
      ),
    );
  }

  @override
  Position start() => Position(path: widget.node.path);

  @override
  Position end() => Position(path: widget.node.path, offset: 1);

  @override
  Position getPositionInOffset(Offset start) => end();

  @override
  bool get shouldCursorBlink => false;

  @override
  CursorStyle get cursorStyle => CursorStyle.cover;

  @override
  Rect getBlockRect({bool shiftWithBaseOffset = false}) => getRectsInSelection(Selection.invalid()).first;

  @override
  Rect? getCursorRectInPosition(Position position, {bool shiftWithBaseOffset = false}) {
    if (_renderBox == null) return null;
    return getRectsInSelection(Selection.collapsed(position), shiftWithBaseOffset: shiftWithBaseOffset).firstOrNull;
  }

  @override
  List<Rect> getRectsInSelection(Selection selection, {bool shiftWithBaseOffset = false}) {
    if (_renderBox == null) return [];
    final parentBox = context.findRenderObject();
    final box = _box.currentContext?.findRenderObject();
    if (parentBox is RenderBox && box is RenderBox) {
      return [(shiftWithBaseOffset ? box.localToGlobal(Offset.zero, ancestor: parentBox) : Offset.zero) & box.size];
    }
    return [Offset.zero & _renderBox!.size];
  }

  @override
  Selection getSelectionInRange(Offset start, Offset end) => Selection.single(path: widget.node.path, startOffset: 0, endOffset: 1);

  @override
  Offset localToGlobal(Offset offset, {bool shiftWithBaseOffset = false}) => _renderBox!.localToGlobal(offset);

  @override
  TextDirection textDirection() => TextDirection.ltr;
}
