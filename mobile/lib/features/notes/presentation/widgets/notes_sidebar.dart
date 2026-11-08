import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/note_page.dart';
import '../../data/workspace.dart';
import 'tag_style.dart';
import 'ui.dart';

/// The views, the tags and the sync line. `full` shows names and counts; `rail` (medium screens) only icons.
class NotesSidebar extends StatefulWidget {
  const NotesSidebar({
    super.key,
    required this.ws,
    required this.onNew,
    this.rail = false,
    this.onClose,
    this.onNavigated,
    this.onRailToggle,
  });

  final Workspace ws;
  final VoidCallback onNew;
  final bool rail;

  /// Shown as an X in the header (the drawer).
  final VoidCallback? onClose;

  /// Called after a choice, so a drawer can close itself.
  final VoidCallback? onNavigated;

  /// Tapping the logo of the rail opens or closes it.
  final VoidCallback? onRailToggle;

  @override
  State<NotesSidebar> createState() => _NotesSidebarState();
}

class _NotesSidebarState extends State<NotesSidebar> {
  var _adding = false;
  final _draft = TextEditingController();
  var _color = TagColor.accent;

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Workspace get ws => widget.ws;

  void _view(NotesView v) {
    ws.go(v);
    widget.onNavigated?.call();
  }

  void _submitTag() {
    ws.addTag(_draft.text, _color);
    _draft.clear();
    setState(() {
      _adding = false;
      _color = TagColor.accent;
    });
  }

  static const _items = <(NotesView, String, IconData)>[
    (NotesView.all, 'Todas as páginas', Icons.description_outlined),
    (NotesView.vault, 'Cofre', Icons.lock_outline),
    (NotesView.trash, 'Lixeira', Icons.delete_outline),
  ];

  int _count(NotesView v) {
    final c = ws.counts;
    return switch (v) {
      NotesView.all => c.all,
      NotesView.shared => c.shared,
      NotesView.vault => c.vault,
      NotesView.trash => c.trash,
    };
  }

  @override
  Widget build(BuildContext context) {
    final rail = widget.rail;
    final tagCounts = ws.tagCounts;
    return Container(
      color: AppColors.surface,
      padding: EdgeInsets.symmetric(horizontal: rail ? 8 : 16, vertical: 20),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: rail
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Row(
                mainAxisAlignment: rail
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.spaceBetween,
                children: [
                  if (rail)
                    RingInkWell(
                      onTap: widget.onRailToggle,
                      borderRadius: BorderRadius.circular(fieldRadius),
                      child: Semantics(
                        label: 'Pindrel',
                        child: Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            borderRadius: BorderRadius.circular(fieldRadius),
                          ),
                          child: Text(
                            'P',
                            style: AppText.serif(
                              20,
                            ).copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // the name shrinks before it would push the badge out at the largest text sizes
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Pindrel',
                                style: AppText.serif(
                                  30,
                                ).copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text(
                                'SELF-HOSTED',
                                maxLines: 1,
                                overflow: TextOverflow.clip,
                                style: monoLabel(size: 10, spacing: 1.8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (widget.onClose != null)
                    GhostIconButton(
                      icon: Icons.close,
                      tooltip: 'Fechar menu',
                      iconSize: 18,
                      onPressed: widget.onClose,
                    ),
                ],
              ),
            ),
            if (rail)
              Tooltip(
                message: 'Nova página',
                child: Material(
                  color: AppColors.primaryButton,
                  borderRadius: BorderRadius.circular(fieldRadius),
                  child: RingInkWell(
                    key: const Key('new-page'),
                    borderRadius: BorderRadius.circular(fieldRadius),
                    onTap: () {
                      widget.onNew();
                      widget.onNavigated?.call();
                    },
                    child: const SizedBox(
                      width: 44,
                      height: 44,
                      child: Icon(Icons.add, size: 18, color: AppColors.onPrimaryButton),
                    ),
                  ),
                ),
              )
            else
              CreamButton(
                buttonKey: const Key('new-page'),
                label: 'Nova página',
                icon: Icons.add,
                expand: true,
                onPressed: () {
                  widget.onNew();
                  widget.onNavigated?.call();
                },
              ),
            const SizedBox(height: 20),
            for (final (view, label, icon) in _items)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _Entry(
                  key: ValueKey('view-${view.name}'),
                  rail: rail,
                  selected: ws.view == view,
                  label: label,
                  leading: Icon(
                    icon,
                    size: 18,
                    color: ws.view == view
                        ? AppColors.accentText
                        : AppColors.text,
                  ),
                  count: _count(view),
                  onTap: () => _view(view),
                ),
              ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Divider(height: 1, color: AppColors.border),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: rail
                    ? CrossAxisAlignment.center
                    : CrossAxisAlignment.stretch,
                children: [
                  if (!rail) ...[
                    Padding(
                      padding: const EdgeInsets.only(left: 12, bottom: 8),
                      child: Row(
                        children: [
                          Text('TAGS ', style: monoLabel()),
                          Text('${ws.tags.length}', style: monoLabel()),
                          const Spacer(),
                          GhostIconButton(
                            icon: Icons.add,
                            tooltip: 'Nova tag',
                            size: 28,
                            color: AppColors.accentText,
                            onPressed: () => setState(() => _adding = !_adding),
                          ),
                        ],
                      ),
                    ),
                    if (_adding)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              height: 36,
                              child: TextField(
                                controller: _draft,
                                autofocus: true,
                                maxLength: maxTagName,
                                style: const TextStyle(fontSize: 14),
                                decoration: InputDecoration(
                                  isDense: true,
                                  counterText: '',
                                  hintText: 'nome da tag',
                                  fillColor: AppColors.background,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                      fieldRadius,
                                    ),
                                    borderSide: const BorderSide(
                                      color: AppColors.fieldBorder,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                      fieldRadius,
                                    ),
                                    borderSide: const BorderSide(
                                      color: AppColors.accentBorder,
                                    ),
                                  ),
                                ),
                                onSubmitted: (_) => _submitTag(),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final c in TagColor.values)
                                  Semantics(
                                    button: true,
                                    selected: _color == c,
                                    label: 'Cor ${tagColorNames[c]}',
                                    child: GestureDetector(
                                      onTap: () => setState(() => _color = c),
                                      child: Container(
                                        width: 24,
                                        height: 24,
                                        decoration: BoxDecoration(
                                          color: tagColor(c),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: _color == c
                                                ? AppColors.text
                                                : Colors.transparent,
                                            width: 2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                RingInkWell(
                                  onTap: _submitTag,
                                  borderRadius: BorderRadius.circular(
                                    fieldRadius,
                                  ),
                                  child: Container(
                                    height: 32,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: AppColors.accent,
                                      borderRadius: BorderRadius.circular(
                                        fieldRadius,
                                      ),
                                    ),
                                    child: const Text(
                                      'Criar',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OutlineTextButton(
                                  label: 'Cancelar',
                                  height: 32,
                                  compact: true,
                                  onPressed: () =>
                                      setState(() => _adding = false),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                  Expanded(
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: ws.tags.length,
                      itemBuilder: (c, i) {
                        final t = ws.tags[i];
                        final on = ws.tagFilter == t.id;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: _Entry(
                            key: ValueKey('tag-${t.id}'),
                            rail: rail,
                            tall: false,
                            selected: on,
                            selectedFill: AppColors.border.withValues(
                              alpha: 0.6,
                            ),
                            selectedText: AppColors.text,
                            label: t.name,
                            leading: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: tagColor(t.color),
                                shape: BoxShape.circle,
                              ),
                            ),
                            count: tagCounts[t.id] ?? 0,
                            onTap: () {
                              ws.toggleTagFilter(t.id);
                              widget.onNavigated?.call();
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.only(top: 16),
              padding: EdgeInsets.fromLTRB(rail ? 0 : 12, 16, 0, 0),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Semantics(
                liveRegion: true,
                label: 'local · no aparelho',
                child: Row(
                  mainAxisAlignment: rail
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.start,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.accentBorder,
                        shape: BoxShape.circle,
                      ),
                    ),
                    if (!rail) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'local · no aparelho',
                          overflow: TextOverflow.ellipsis,
                          style: AppText.mono(12),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({
    super.key,
    required this.rail,
    required this.selected,
    required this.label,
    required this.leading,
    required this.count,
    required this.onTap,
    this.tall = true,
    this.selectedFill,
    this.selectedText,
  });
  final bool rail, selected, tall;
  final String label;
  final Widget leading;
  final int count;
  final VoidCallback onTap;
  final Color? selectedFill, selectedText;

  @override
  Widget build(BuildContext context) {
    final fill = selected
        ? (selectedFill ?? AppColors.accent.withValues(alpha: 0.45))
        : Colors.transparent;
    final text = selected
        ? (selectedText ?? AppColors.accentText)
        : AppColors.text;
    final h = tall ? 44.0 : 40.0;
    return Tooltip(
      message: rail ? label : '',
      child: Semantics(
        button: true,
        selected: selected,
        label: rail ? label : null,
        child: Material(
          color: Colors.transparent,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(fieldRadius),
            ),
            child: RingInkWell(
              borderRadius: BorderRadius.circular(fieldRadius),
              onTap: onTap,
              child: SizedBox(
                height: h,
                width: rail ? 44 : null,
                child: rail
                    ? Center(child: leading)
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            leading,
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                label,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 15, color: text),
                              ),
                            ),
                            Text(
                              '$count',
                              style: AppText.mono(
                                12,
                                color: selected && tall
                                    ? AppColors.accentText
                                    : AppColors.textMuted,
                                letterSpacing: 0,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
