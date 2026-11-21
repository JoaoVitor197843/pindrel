// The formatting bar under the text: the marks the stored format can keep
// (bold, italic, underline, strike, highlight, code, link) plus undo and redo.
// It talks to the editor through its public commands only. The package's own
// toolbars are not used: they bring a white theme, a keyboard-height plugin and
// colours the stored text has nowhere to keep.

import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../data/blocks.dart';
import '../data/links.dart';
import '../data/page_editor.dart';
import '../presentation/widgets/block_row.dart' show blockMenuItems;
import '../presentation/widgets/ui.dart';
import 'inline_marks.dart';

class FormatBar extends StatefulWidget {
  const FormatBar({super.key, required this.editorState, required this.ed, required this.blockAtCaret, required this.onInsertAfter});
  final EditorState editorState;
  final PageEditor ed;

  /// The block that holds the caret, with the blocks already brought up to date (null: none).
  final Block? Function() blockAtCaret;
  final void Function(String blockId) onInsertAfter;

  @override
  State<FormatBar> createState() => _FormatBarState();
}

class _FormatBarState extends State<FormatBar> {
  EditorState get editorState => widget.editorState;

  /// A menu or dialog of the bar is open: the editor lost the focus (and its selection) to it, but the bar has to stay.
  var _busy = false;

  StreamSubscription<EditorTransactionValue>? _tx;

  @override
  void initState() {
    super.initState();
    // A mark taken off the selected text changes the document, not the selection: the buttons must follow it
    _tx = editorState.transactionStream.listen((e) {
      if (e.$1 == TransactionTime.after && mounted) setState(() {});
    });
    editorState.toggledStyleNotifier.addListener(_restyle);
  }

  void _restyle() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tx?.cancel();
    editorState.toggledStyleNotifier.removeListener(_restyle);
    super.dispose();
  }

  static final _marks = <(String, IconData, String)>[
    (AppFlowyRichTextKeys.bold, Icons.format_bold, 'Negrito'),
    (AppFlowyRichTextKeys.italic, Icons.format_italic, 'Itálico'),
    (AppFlowyRichTextKeys.underline, Icons.format_underlined, 'Sublinhado'),
    (AppFlowyRichTextKeys.strikethrough, Icons.format_strikethrough, 'Riscado'),
    (AppFlowyRichTextKeys.code, Icons.code, 'Código'),
  ];

  bool _on(String key) {
    final sel = editorState.selection;
    if (sel == null) return false;
    if (sel.isCollapsed) return editorState.toggledStyle[key] == true;
    // taking a mark off with the bar's button leaves `bold: false` in the delta, which is not a mark that is on
    final v = editorState.getDeltaAttributeValueInSelection<Object>(key);
    return v != null && v != false;
  }

  Future<void> _highlight() async {
    final sel = editorState.selection;
    if (sel == null || sel.isCollapsed) return;
    await editorState.formatDelta(sel, {highlightKey: _on(highlightKey) ? null : highlightColor});
  }

  Future<void> _link(BuildContext context) async {
    final sel = editorState.selection;
    if (sel == null || sel.isCollapsed) return;
    final had = editorState.getDeltaAttributeValueInSelection<String>(AppFlowyRichTextKeys.href);
    setState(() => _busy = true);
    final value = await showDialog<String>(context: context, builder: (_) => _LinkDialog(initial: had ?? '', canRemove: had != null));
    if (mounted) setState(() => _busy = false);
    if (value == null) return;
    if (value.trim().isEmpty) {
      await editorState.formatDelta(sel, {AppFlowyRichTextKeys.href: null});
      return;
    }
    final url = safeUrl(value);
    if (url != null) await editorState.formatDelta(sel, {AppFlowyRichTextKeys.href: url});
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Selection?>(
      valueListenable: editorState.selectionNotifier,
      builder: (context, sel, _) {
        if (sel == null && !_busy) return const SizedBox.shrink();
        Widget b(IconData icon, String tip, bool on, VoidCallback run) => Semantics(
          button: true,
          selected: on,
          label: tip,
          child: Container(
            decoration: BoxDecoration(color: on ? AppColors.accent.withValues(alpha: 0.5) : null, borderRadius: BorderRadius.circular(6)),
            child: GhostIconButton(icon: icon, tooltip: tip, size: 40, iconSize: 18, color: on ? AppColors.text : AppColors.textMuted, onPressed: run),
          ),
        );
        return Container(
          key: const Key('format-bar'),
          decoration: const BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.border))),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (key, icon, tip) in _marks) b(icon, tip, _on(key), () => editorState.toggleAttribute(key)),
                b(Icons.border_color_outlined, 'Destaque', _on(highlightKey), _highlight),
                b(Icons.link, 'Link', _on(AppFlowyRichTextKeys.href), () => _link(context)),
                const SizedBox(width: 12),
                b(Icons.add, 'Inserir bloco abaixo', false, () {
                  final blk = widget.blockAtCaret();
                  if (blk != null) widget.onInsertAfter(blk.id);
                }),
                _BlockMenu(ed: widget.ed, blockAtCaret: widget.blockAtCaret, onBusy: (v) => setState(() => _busy = v)),
                b(Icons.undo, 'Desfazer', false, () => undoCommand.execute(editorState)),
                b(Icons.redo, 'Refazer', false, () => redoCommand.execute(editorState)),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The same menu the other blocks have (move, duplicate, turn into, delete), for the block that holds the caret.
class _BlockMenu extends StatelessWidget {
  const _BlockMenu({required this.ed, required this.blockAtCaret, required this.onBusy});
  final PageEditor ed;
  final Block? Function() blockAtCaret;
  final ValueChanged<bool> onBusy;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<VoidCallback>(
      tooltip: 'Opções do bloco',
      color: AppColors.surface,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 192),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(fieldRadius), side: const BorderSide(color: AppColors.border)),
      onOpened: () => onBusy(true),
      onCanceled: () => onBusy(false),
      onSelected: (run) {
        onBusy(false);
        run();
      },
      itemBuilder: (_) {
        final b = blockAtCaret();
        if (b == null) return const [];
        final i = ed.blocks.indexWhere((x) => x.id == b.id);
        return blockMenuItems(context, ed: ed, block: b, index: i, count: ed.blocks.length);
      },
      child: const SizedBox(width: 40, height: 40, child: Icon(Icons.more_horiz, size: 18, color: AppColors.textMuted)),
    );
  }
}

/// Asks for a link address. It owns its field, so the controller outlives the dialog's closing animation.
class _LinkDialog extends StatefulWidget {
  const _LinkDialog({required this.initial, required this.canRemove});
  final String initial;
  final bool canRemove;

  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Endereço do link'),
      content: TextField(controller: _text, autofocus: true, keyboardType: TextInputType.url, decoration: const InputDecoration(hintText: 'exemplo.com'), onSubmitted: (v) => Navigator.pop(context, v)),
      actions: [
        if (widget.canRemove) TextButton(onPressed: () => Navigator.pop(context, ''), child: const Text('Remover')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        TextButton(onPressed: () => Navigator.pop(context, _text.text), child: const Text('Aplicar')),
      ],
    );
  }
}
