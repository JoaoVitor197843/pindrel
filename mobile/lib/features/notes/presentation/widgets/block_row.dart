import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/blocks.dart';
import '../../data/page_editor.dart';
import 'motion.dart';
import 'ui.dart';

const _gutter = 68.0;

/// One block with its controls: "+" (insert below) and the handle (drag to reorder, tap for the menu). On wide screens
/// they sit in the left margin and show on hover; on a phone they appear under the block that was touched last.
class BlockRow extends StatefulWidget {
  const BlockRow({
    super.key,
    required this.index,
    required this.count,
    required this.block,
    required this.label,
    required this.ed,
    required this.child,
    required this.onInsertAfter,
    this.animate = true,
    this.dim = false,
    this.onActive,
  });
  final int index, count;
  final Block block;
  final String label;
  final PageEditor ed;
  final Widget child;
  final VoidCallback onInsertAfter;

  /// Plays the entrance (off when the row is drawn again after scrolling back to it).
  final bool animate;

  /// In zen mode the blocks that are not being written fade back.
  final bool dim;
  final void Function(bool active)? onActive;

  static double gutterFor(double width) => width >= 768 ? _gutter : 0;

  @override
  State<BlockRow> createState() => _BlockRowState();
}

class _BlockRowState extends State<BlockRow> {
  var _hover = false;
  var _active = false;
  var _menu = false;

  static const _turns = <(String, BlockType, int?, bool)>[
    ('Texto', BlockType.paragraph, null, false),
    ('Título 1', BlockType.heading, 1, false),
    ('Título 2', BlockType.heading, 2, false),
    ('Título 3', BlockType.heading, 3, false),
    ('Lista com marcadores', BlockType.bullet, null, false),
    ('Lista numerada', BlockType.numbered, null, false),
    ('Citação', BlockType.quote, null, false),
    ('Destaque', BlockType.callout, null, false),
    ('Toggle', BlockType.toggle, null, false),
    ('Título 1 com toggle', BlockType.heading, 1, true),
    ('Título 2 com toggle', BlockType.heading, 2, true),
    ('Título 3 com toggle', BlockType.heading, 3, true),
  ];

  bool _isCurrent(BlockType t, int? level, bool toggle) {
    final b = widget.block;
    if (b.type != t) return false;
    return t != BlockType.heading ||
        ((b.level ?? 2) == (level ?? 2) && b.toggle == toggle);
  }

  List<PopupMenuEntry<VoidCallback>> _items() {
    final b = widget.block;
    final ed = widget.ed;
    final convertible = isTextType(b.type) || b.type == BlockType.toggle;
    final canDuplicate =
        b.type != BlockType.image || (b.fileId ?? '').isNotEmpty;
    PopupMenuItem<VoidCallback> item(
      String label,
      VoidCallback run, {
      bool enabled = true,
      bool danger = false,
    }) => PopupMenuItem(
      value: run,
      enabled: enabled,
      height: 36,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          color: danger ? AppColors.offlineText : null,
        ),
      ),
    );
    PopupMenuEntry<VoidCallback> heading(String t) => PopupMenuItem(
      enabled: false,
      height: 28,
      child: Text(t.toUpperCase(), style: monoLabel(size: 10, spacing: 1.4)),
    );
    return [
      item('Subir', () => ed.moveBy(b.id, -1), enabled: widget.index > 0),
      item(
        'Descer',
        () => ed.moveBy(b.id, 1),
        enabled: widget.index < widget.count - 1,
      ),
      if (canDuplicate) item('Duplicar', () => ed.duplicateBlock(b.id)),
      if (b.type == BlockType.bullet || b.type == BlockType.numbered) ...[
        item('Aninhar', () => ed.indent(b.id, 1)),
        item('Tirar um nível', () => ed.indent(b.id, -1)),
      ],
      if (b.type == BlockType.callout) ...[
        const PopupMenuDivider(),
        heading('Tom do destaque'),
        PopupMenuItem<VoidCallback>(
          enabled: false,
          height: 40,
          child: Row(
            children: [
              for (final t in CalloutTone.values)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Semantics(
                    button: true,
                    selected: (b.tone ?? CalloutTone.info) == t,
                    label: 'Tom ${toneLabels[t]!.$1}',
                    child: RingInkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: () {
                        Navigator.pop(context);
                        ed.setTone(b.id, t);
                      },
                      child: Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: (b.tone ?? CalloutTone.info) == t
                              ? AppColors.border.withValues(alpha: 0.6)
                              : null,
                          border: Border.all(
                            color: (b.tone ?? CalloutTone.info) == t
                                ? AppColors.accentBorder
                                : Colors.transparent,
                          ),
                        ),
                        child: Text(
                          toneLabels[t]!.$2,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
      if (convertible) ...[
        const PopupMenuDivider(),
        heading('Transformar em'),
        for (final (label, type, level, toggle) in _turns)
          if (!_isCurrent(type, level, toggle))
            item(
              label,
              () => ed.turnInto(b.id, type, level: level ?? 2, toggle: toggle),
            ),
      ],
      const PopupMenuDivider(),
      item('Excluir', () => ed.remove(b.id), danger: true),
    ];
  }

  Widget _controls() {
    final label = '${widget.label} ${widget.index + 1}';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GhostIconButton(
          icon: Icons.add,
          tooltip: 'Inserir bloco depois de $label',
          size: 28,
          onPressed: widget.onInsertAfter,
        ),
        ReorderableDragStartListener(
          index: widget.index,
          // the tooltip would also answer a long press, which is how a finger starts dragging: it is shown on hover only
          child: Tooltip(
            message: 'Opções do bloco ${widget.index + 1}',
            triggerMode: TooltipTriggerMode.manual,
            child: PopupMenuButton<VoidCallback>(
              tooltip: '',
              color: AppColors.surface,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 192),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(fieldRadius),
                side: const BorderSide(color: AppColors.border),
              ),
              onOpened: () => setState(() => _menu = true),
              onCanceled: () => setState(() => _menu = false),
              onSelected: (run) {
                setState(() => _menu = false);
                run();
              },
              itemBuilder: (_) => _items(),
              child: Semantics(
                label: 'Arrastar bloco ${widget.index + 1}',
                child: const SizedBox(
                  width: 28,
                  height: 28,
                  child: Center(
                    child: Text(
                      '⠿',
                      style: TextStyle(
                        fontSize: 16,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 768;
    final touch =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final show = _hover || _active || _menu || touch;
    final readOnly = widget.ed.readOnly;
    return Entrance(
      enabled: widget.animate,
      delay: Duration(
        milliseconds: (widget.index < 10 ? widget.index : 10) * 28,
      ),
      child: AnimatedOpacity(
        opacity: widget.dim ? 0.38 : 1,
        duration: const Duration(milliseconds: 250),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onFocusChange: (f) {
              setState(() => _active = f);
              widget.onActive?.call(f);
            },
            child: Semantics(
              container: true,
              label: '${widget.label} ${widget.index + 1} de ${widget.count}',
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => setState(() => _active = true),
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: _gutter,
                            child: readOnly
                                ? null
                                : Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Align(
                                      alignment: Alignment.topRight,
                                      child: AnimatedOpacity(
                                        duration: const Duration(
                                          milliseconds: 120,
                                        ),
                                        opacity: show ? 1 : 0,
                                        child: IgnorePointer(
                                          ignoring: !show,
                                          child: _controls(),
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                          Expanded(child: widget.child),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          widget.child,
                          if (!readOnly && (_active || _menu))
                            Align(
                              alignment: Alignment.centerRight,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: _controls(),
                              ),
                            ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
