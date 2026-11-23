// The body of a page, edited by appflowy_editor.
//
// The page's `List<Block>` stays the source of truth (it is what is stored and
// synced). The editor gets a `Document` made from it (`doc_codec.dart`) and
// every edit is turned back into blocks right away, so the rest of the app
// (outline, word count, export, search) never sees the editor's tree.
// Changes made from outside the editor (the insert menu, a block's own menu, an
// opaque block's editing) come back the other way: when the structure of the
// blocks no longer matches what was last synced, the document is replaced.

import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart' show AppText;
import '../data/blocks.dart';
import '../data/page_editor.dart';
import 'context_menu.dart';
import 'doc_codec.dart';
import 'format_bar.dart';
import 'inline_marks.dart' show deltaToMarks;
import '../presentation/widgets/editor_chrome.dart' show Article;
import 'pindrel_block_component.dart';

/// Lets the page ask the body to move the caret or the view to a block.
class PageBodyController {
  _PageBodyState? _state;

  /// The editor's state, for tests that drive it through its own API.
  @visibleForTesting
  EditorState? get editorState => _state?._es;

  /// Brings the blocks up to date with the editor right now (edits are otherwise copied at the end of the turn).
  @visibleForTesting
  void flush() => _state?._sync();

  void focusBlock(String id) => _state?._focus(id);

  /// The shortcut behind "/" and the others, for tests (the IME that would fire them is not there in a widget test).
  @visibleForTesting
  List<CharacterShortcutEvent> get characterShortcuts => _state?._characters ?? const [];
  void scrollTo(String id) => _state?._scrollTo(id);
}

class PageBody extends StatefulWidget {
  const PageBody({
    super.key,
    required this.ed,
    required this.header,
    required this.footer,
    required this.renderOpaque,
    required this.onSlash,
    required this.onInsertAfter,
    required this.controller,
    this.leftGutter = 0,
    this.textScale = 1.0,
    this.zen = false,
  });

  final PageEditor ed;

  /// Drawn above the first block and below the last one, inside the scrolling area.
  final Widget header, footer;

  /// Draws a block the editor does not edit (code, table, media...).
  final OpaqueRender renderOpaque;

  /// "/" typed in an empty paragraph: the page opens its insert menu for that block.
  final void Function(String blockId) onSlash;

  /// "+" in the formatting bar: the page opens its insert menu below that block.
  final void Function(String blockId) onInsertAfter;
  final PageBodyController controller;

  /// Room the page keeps on the left of each block for its controls (opaque blocks draw them there);
  /// the text of the blocks the editor owns is moved in by the same amount, so everything lines up.
  final double leftGutter;

  /// The user's size for the text of the page (1 = normal); the system's own text size is applied on top of it.
  final double textScale;
  final bool zen;

  @override
  State<PageBody> createState() => _PageBodyState();
}

/// A cheap fingerprint of everything the editor shows, to tell an outside change from our own sync.
int _tableHash(Block b) => Object.hash(
  Object.hashAll([for (final c in b.cols ?? const <TableColumn>[]) Object.hash(c.id, c.label, c.w)]),
  Object.hashAll([for (final r in b.rows ?? const <Map<String, String>>[]) Object.hashAll([for (final c in b.cols ?? const <TableColumn>[]) r[c.id]])]),
);

int blocksFingerprint(List<Block> blocks) => Object.hashAll([
  for (final b in blocks)
    Object.hash(
      b.id,
      b.type,
      b.level,
      b.indent,
      b.toggle,
      isNative(b) ? b.text : null,
      isNative(b) ? Object.hashAll([for (final i in b.items ?? const <ChecklistItem>[]) Object.hash(i.id, i.text, i.done)]) : null,
      b.type == BlockType.table ? _tableHash(b) : null,
    ),
]);

class _PageBodyState extends State<PageBody> {
  final _editorFocus = FocusNode(debugLabel: 'page editor');
  late EditorState _es;
  late EditorScrollController _scroll;
  StreamSubscription<EditorTransactionValue>? _sub;
  var _fingerprint = 0;
  var _syncing = false, _scheduled = false, _replacing = false;

  PageEditor get _ed => widget.ed;

  @override
  void initState() {
    super.initState();
    widget.controller._state = this;
    AppFlowyEditorLocalizations.load(const Locale('pt', 'BR'));
    _open();
    _ed.addListener(_onPage);
  }

  @override
  void didUpdateWidget(PageBody old) {
    super.didUpdateWidget(old);
    widget.controller._state = this;
    if (old.ed != widget.ed) {
      old.ed.removeListener(_onPage);
      widget.ed.addListener(_onPage);
      _close();
      _open();
    }
  }

  void _open() {
    _es = EditorState(document: blocksToDocument(_ed.blocks));
    _scroll = EditorScrollController(editorState: _es);
    _fingerprint = blocksFingerprint(_ed.blocks);
    _sub = _es.transactionStream.listen((e) {
      if (e.$1 == TransactionTime.after && !_replacing && e.$2.operations.isNotEmpty) {
        // before the sync (microtasks run in order): what the sync would cut when it stores is cut here, where it is typed
        scheduleMicrotask(() {
          if (mounted) _clipToLimits(e.$2);
        });
        _markDirty();
      }
    });
  }

  /// The longest text a node may hold: the same limits `documentToBlocks` cuts at when it stores the page, so what is
  /// on the screen is what is kept (a paste of 3000 characters in a cell used to show 3000 and come back as 2000).
  int _limitOf(Node n) {
    final cell = n.parent;
    if (cell?.type != TableCellBlockKeys.type) return maxText;
    return cell!.attributes[TableCellBlockKeys.rowPosition] == 0 ? maxLabelText : maxCellText;
  }

  /// Cuts the end of every text the transaction touched that is over its limit.
  void _clipToLimits(Transaction t) {
    final seen = <Node>{};
    void visit(Node? n) {
      if (n == null || !seen.add(n)) return;
      if (n.delta != null) _clipNode(n);
      for (final c in n.children.toList()) {
        visit(c);
      }
    }

    for (final op in t.operations) {
      if (op is InsertOperation) {
        for (var i = 0; i < op.nodes.length; i++) {
          visit(_es.getNodeAtPath([...op.path.sublist(0, op.path.length - 1), op.path.last + i]));
        }
      } else {
        visit(_es.getNodeAtPath(op.path));
      }
    }
  }

  void _clipNode(Node n) {
    final d = n.delta!;
    final max = _limitOf(n);
    if (d.length <= max && deltaToMarks(d).length <= max) return;
    final plain = d.toPlainText();
    // the markers (`**`, `[](..)`) count in the stored text, so cut the characters until the stored form fits
    var keep = plain.length < max ? plain.length : max;
    while (keep > 0) {
      final cut = d.compose(Delta()..retain(keep)..delete(plain.length - keep));
      final over = deltaToMarks(cut).length - max;
      if (over <= 0) break;
      keep = keep > over ? keep - over : 0;
    }
    // never leave half of a surrogate pair (an emoji)
    if (keep > 0 && keep < plain.length && (plain.codeUnitAt(keep - 1) & 0xFC00) == 0xD800) keep--;
    if (keep >= plain.length) return;
    final tr = _es.transaction..deleteText(n, keep, plain.length - keep);
    final sel = _es.selection;
    if (sel != null && sel.isCollapsed && listEquals(sel.start.path, n.path) && sel.start.offset > keep) {
      tr.afterSelection = Selection.collapsed(Position(path: n.path, offset: keep));
    }
    _es.apply(tr);
  }

  void _close() {
    _sub?.cancel();
    _scroll.dispose();
    _es.dispose();
  }

  @override
  void dispose() {
    _editorFocus.dispose();
    widget.controller._state = null;
    _ed.removeListener(_onPage);
    _close();
    super.dispose();
  }

  // Edits made in one turn of the event loop are turned into blocks once.
  void _markDirty() {
    if (_scheduled) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      if (mounted) _sync();
    });
  }

  void _sync() {
    final byId = {for (final b in _ed.blocks) b.id: b};
    final next = documentToBlocks(_es.document, byId, stamp: true);
    _syncing = true;
    try {
      _ed.replaceBlocks(next);
    } finally {
      _syncing = false;
    }
    _fingerprint = blocksFingerprint(_ed.blocks);
  }

  void _onPage() {
    if (_syncing) return;
    final f = blocksFingerprint(_ed.blocks);
    if (f != _fingerprint) _replace();
  }

  var _busy = false, _again = false;

  /// The blocks changed under the editor: put the new ones in its document (the view stays where it is).
  /// One at a time: a second change that arrives while the document is being rebuilt waits and is applied after it.
  Future<void> _replace() async {
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    try {
      do {
        _again = false;
        if (!mounted) return;
        _fingerprint = blocksFingerprint(_ed.blocks);
        final fresh = blocksToDocument(_ed.blocks).root.children.toList();
        for (final n in fresh) {
          n.unlink();
        }
        final old = _es.document.root.children.toList();
        _replacing = true;
        try {
          // two steps: deleting and inserting in one transaction put the new nodes in the wrong order
          if (old.isNotEmpty) await _es.apply(_es.transaction..deleteNodes(old), isRemote: true, withUpdateSelection: false, skipEditableCheck: true);
          await _es.apply(_es.transaction..insertNodes([0], fresh, deepCopy: false), isRemote: true, withUpdateSelection: false, skipEditableCheck: true);
        } finally {
          _replacing = false;
        }
      } while (_again);
    } finally {
      _busy = false;
    }
  }

  /// The block that holds the caret, after bringing the blocks up to date with the editor.
  Block? _blockAtCaret() {
    final sel = _es.selection;
    if (sel == null) return null;
    _sync();
    var node = _es.getNodeAtPath(sel.start.path);
    // a caret in a table cell belongs to the table
    while (node != null && node.attributes[idKey] is! String) {
      node = node.parent;
    }
    final id = node?.attributes[idKey];
    return id is String ? _ed.blocks.where((b) => b.id == id).firstOrNull : null;
  }

  int? _indexOf(String id) {
    final i = _es.document.root.children.toList().indexWhere((n) => n.attributes[idKey] == id);
    return i < 0 ? null : i;
  }

  void _focus(String id) {
    // the page may have just changed the blocks: wait for the document to catch up
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final i = _indexOf(id);
      if (i == null) return;
      final n = _es.getNodeAtPath([i]);
      if (n?.delta == null) return;
      _es.selection = Selection.collapsed(Position(path: [i]));
      // The editor takes the keyboard focus too, not only the text input. Without it typing worked but Ctrl+B, Ctrl+I
      // and the other shortcuts did nothing until the first click in the text (found on the real app after
      // "Começar com: Texto"): a selection set by code is not a tap, so the editor does not ask for the focus itself.
      _editorFocus.requestFocus();
    });
    WidgetsBinding.instance.scheduleFrame(); // a post-frame callback waits for a frame, and there may be none coming
  }

  void _scrollTo(String id) {
    final i = _indexOf(id);
    if (i == null || _scroll.shrinkWrap) return;
    // +1 for the header that sits at the top of the list
    _scroll.itemScrollController.scrollTo(index: i + 1, duration: const Duration(milliseconds: 250));
  }

  TextStyle get _headerText => AppText.mono(12, color: AppColors.textMuted, letterSpacing: 0.9).copyWith(height: 1.8);

  TextStyle get _cellText => const TextStyle(fontSize: 15, height: 1.5, color: AppColors.text);

  TextStyle get _text => TextStyle(fontSize: 16.5, height: 1.68, color: AppColors.text.withValues(alpha: 0.9));

  /// The blocks the editor does not edit (code, callouts...) are scaled the way its paragraphs are.
  Widget _renderOpaque(BuildContext context, String id) {
    final q = MediaQuery.of(context);
    return MediaQuery(data: q.copyWith(textScaler: TextScaler.linear(widget.textScale * q.textScaler.scale(1.0))), child: widget.renderOpaque(context, id));
  }

  Map<String, BlockComponentBuilder> _builders() {
    final pad = EdgeInsets.fromLTRB(widget.leftGutter, 6, 0, 6);
    // a paragraph inside a table cell: no gutter, no hint, a smaller step
    bool inCell(Node n) => n.parent?.type == TableCellBlockKeys.type;
    bool inHeader(Node n) => inCell(n) && n.parent!.attributes[TableCellBlockKeys.rowPosition] == 0;
    BlockComponentConfiguration cfg(String hint) => BlockComponentConfiguration(
      padding: (n) => inCell(n) ? const EdgeInsets.symmetric(vertical: 4) : pad,
      textStyle: (n, {textSpan}) => inHeader(n) ? _headerText : inCell(n) ? _cellText : _text,
      placeholderText: (n) => inCell(n) ? '' : hint,
      placeholderTextStyle: (_, {textSpan}) => _text.copyWith(color: AppColors.textMuted.withValues(alpha: 0.6)),
    );
    return {
      PageBlockKeys.type: PageBlockComponentBuilder(),
      ParagraphBlockKeys.type: ParagraphBlockComponentBuilder(configuration: cfg('Digite “/” para inserir um bloco')),
      HeadingBlockKeys.type: HeadingBlockComponentBuilder(
        configuration: cfg('Título'),
        textStyleBuilder: (level) => TextStyle(fontFamily: 'serif', fontWeight: FontWeight.bold, height: 1.3, color: AppColors.text, fontSize: switch (level) { 1 => 30.0, 2 => 24.0, _ => 19.0 }),
      ),
      QuoteBlockKeys.type: QuoteBlockComponentBuilder(configuration: cfg('Citação')),
      BulletedListBlockKeys.type: BulletedListBlockComponentBuilder(configuration: cfg('Item')),
      NumberedListBlockKeys.type: NumberedListBlockComponentBuilder(configuration: cfg('Item')),
      TodoListBlockKeys.type: TodoListBlockComponentBuilder(configuration: cfg('Tarefa')),
      DividerBlockKeys.type: DividerBlockComponentBuilder(lineColor: AppColors.border, configuration: BlockComponentConfiguration(padding: (_) => EdgeInsets.fromLTRB(widget.leftGutter, 8, 0, 8))),
      TableBlockKeys.type: TableBlockComponentBuilder(
        byRows: true,
        // the row handles hang in the gutter the other blocks leave on the left; on a phone they take their own 28 px
        configuration: BlockComponentConfiguration(padding: (_) => EdgeInsets.only(left: (widget.leftGutter - 28).clamp(0, 400)), margin: (_) => const EdgeInsets.symmetric(vertical: 6)),
        tableStyle: const TableStyle(borderColor: AppColors.border),
        cellStyle: _cellText,
        headerRow: true,
        maxCols: maxCols,
        maxRows: maxRows + 1,
        maxColWidth: maxColWidth.toDouble(),
        controlColor: AppColors.textMuted,
      ),
      opaqueType: PindrelBlockBuilder(editorState: _es, render: _renderOpaque, configuration: const BlockComponentConfiguration(padding: _noPad, margin: _noPad)),
    };
  }

  static EdgeInsets _noPad(Node _) => const EdgeInsets.symmetric(vertical: 6);

  /// "/" in an empty paragraph opens the page's own insert menu (the package's has other blocks and English labels).
  late final _slash = CharacterShortcutEvent(
    key: 'pindrel slash',
    character: '/',
    handler: (es) async {
      final sel = es.selection;
      if (sel == null || !sel.isCollapsed) return false;
      final node = es.getNodeAtPath(sel.start.path);
      if (node == null || node.type != ParagraphBlockKeys.type || node.parent?.type != PageBlockKeys.type || (node.delta?.isEmpty ?? true) == false) return false;
      _sync();
      final id = node.attributes[idKey];
      if (id is! String) return false;
      widget.onSlash(id);
      return true;
    },
  );

  /// "> " at the start of a paragraph makes a quote (the package only knows the typographic quotes).
  static final _greaterToQuote = CharacterShortcutEvent(
    key: 'pindrel greater to quote',
    character: ' ',
    handler: (es) async => formatMarkdownSymbol(
      es,
      (node) => node.type != QuoteBlockKeys.type,
      (_, text, _) => text == '>',
      (_, node, delta) => [
        quoteNode(attributes: {QuoteBlockKeys.delta: delta.compose(Delta()..delete(1)).toJson()}),
        ...node.children,
      ],
    ),
  );

  // The shortcuts that turn a paragraph into another block must not fire inside a table cell: a cell holds one
  // paragraph and its text, nothing else. The inline ones (bold, italic, code...) and the line breaks stay.
  static final _blockShortcuts = {
    formatAsteriskToBulletedList,
    formatMinusToBulletedList,
    formatNumberToNumberedList,
    formatDoubleQuoteToQuote,
    formatSignToHeading,
    formatEmptyBracketsToUncheckedBox,
    formatHyphenEmptyBracketsToUncheckedBox,
    formatFilledBracketsToCheckedBox,
    formatHyphenFilledBracketsToCheckedBox,
    convertMinusesToDivider,
    convertStarsToDivider,
    convertUnderscoreToDivider,
    _greaterToQuote,
  };

  static CharacterShortcutEvent _notInCell(CharacterShortcutEvent e) => CharacterShortcutEvent(
    key: e.key,
    character: e.character,
    handler: (es) async {
      final sel = es.selection;
      final node = sel == null ? null : es.getNodeAtPath(sel.start.path);
      if (node?.parent?.type == TableCellBlockKeys.type) return false;
      return e.handler(es);
    },
  );

  List<CharacterShortcutEvent> get _characters => [
    for (final e in standardCharacterShortcutEvents)
      if (e != slashCommand) _blockShortcuts.contains(e) ? _notInCell(e) : e,
    _notInCell(_greaterToQuote),
    _slash,
  ];

  // Tab/Shift+Tab on lists only (a Tab in a paragraph would nest it inside the previous one); the table's own
  // keys (Tab to the next cell, arrows, Enter) stay
  List<CommandShortcutEvent> get _commands => standardCommandShortcutEvents;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    // the blocks sit in a column as wide as the page's article; the header and footer use the full width
    final pad = Article.padFor(width);
    final side = ((width - (widget.zen ? 672 : 768)) / 2).clamp(0.0, 4000.0) + pad;
    final touch = defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;
    final style = EditorStyle(
      padding: EdgeInsets.only(left: (side - widget.leftGutter).clamp(0.0, 4000.0) + 0, right: side),
      // the editor's paragraphs ignore the system's text size, so it is folded in here
      textScaleFactor: widget.textScale * MediaQuery.textScalerOf(context).scale(1.0),
      cursorColor: AppColors.accentBorder,
      dragHandleColor: AppColors.accentBorder,
      selectionColor: AppColors.accent.withValues(alpha: 0.45),
      textStyleConfiguration: TextStyleConfiguration(
        text: _text,
        bold: const TextStyle(fontWeight: FontWeight.w700),
        italic: const TextStyle(fontStyle: FontStyle.italic),
        underline: const TextStyle(decoration: TextDecoration.underline),
        strikethrough: const TextStyle(decoration: TextDecoration.lineThrough),
        href: const TextStyle(color: AppColors.accentText, decoration: TextDecoration.underline),
        code: TextStyle(fontFamily: 'monospace', fontSize: 14.5, color: AppColors.text, backgroundColor: AppColors.border.withValues(alpha: 0.7)),
      ),
      textSpanDecorator: touch ? mobileTextSpanDecoratorForAttribute : defaultTextSpanDecoratorForAttribute,
      mobileDragHandleBallSize: touch ? const Size(8, 8) : Size.zero,
      mobileDragHandleWidth: touch ? 2.0 : 0.0,
      enableHapticFeedbackOnAndroid: touch,
    );
    return Column(
      children: [
        Expanded(
          child: AppFlowyEditor(
            key: ObjectKey(_es),
            focusNode: _editorFocus,
            contextMenuBuilder: pageContextMenu,
            editorState: _es,
            editorScrollController: _scroll,
            editable: !_ed.readOnly,
            editorStyle: style,
            blockComponentBuilders: _builders(),
            characterShortcutEvents: _characters,
            commandShortcutEvents: _commands,
            header: widget.header,
            footer: widget.footer,
            showMagnifier: touch,
          ),
        ),
        if (!_ed.readOnly) FormatBar(editorState: _es, ed: _ed, blockAtCaret: _blockAtCaret, onInsertAfter: widget.onInsertAfter),
      ],
    );
  }
}
