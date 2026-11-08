import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/palette.dart';
import '../../data/workspace.dart';
import 'tag_style.dart';
import 'ui.dart';

/// The quick search: pages, actions and tags in one list, driven by the keyboard too (arrows, Enter, Esc).
Future<void> showPalette(BuildContext context, Workspace ws, PaletteActions Function(BuildContext dialog) actions) => showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (c) => _Palette(ws: ws, actions: actions(c)),
    );

class _Palette extends StatefulWidget {
  const _Palette({required this.ws, required this.actions});
  final Workspace ws;
  final PaletteActions actions;
  @override
  State<_Palette> createState() => _PaletteState();
}

class _PaletteState extends State<_Palette> {
  final _query = TextEditingController();
  // the arrows and Enter must be read before the text field turns them into cursor moves
  late final FocusNode _node = FocusNode(onKeyEvent: _key);
  var _index = 0;

  @override
  void dispose() {
    _query.dispose();
    _node.dispose();
    super.dispose();
  }

  List<PaletteGroup> get _groups => buildPalette(widget.ws, _query.text, widget.actions);

  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final flat = _groups.expand((g) => g.items).toList();
    if (flat.isEmpty) return KeyEventResult.ignored;
    final cur = _index.clamp(0, flat.length - 1);
    if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() => _index = (cur + 1) % flat.length);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() => _index = (cur - 1 + flat.length) % flat.length);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.enter) {
      flat[cur].run();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    final flat = groups.expand((g) => g.items).toList();
    final cur = flat.isEmpty ? 0 : _index.clamp(0, flat.length - 1);
    var n = 0;
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, MediaQuery.sizeOf(context).height * 0.12, 16, 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 576, maxHeight: MediaQuery.sizeOf(context).height * 0.7),
          child: Material(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(fieldRadius), side: const BorderSide(color: AppColors.border)),
            clipBehavior: Clip.antiAlias,
            child: Semantics(
              label: 'Busca rápida',
              scopesRoute: true,
              explicitChildNodes: true,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
                  child: Row(children: [
                    const Icon(Icons.search, size: 16, color: AppColors.textMuted),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Focus(
                        canRequestFocus: false,
                        child: TextField(
                          controller: _query,
                          focusNode: _node,
                          autofocus: true,
                          maxLength: 200,
                          style: const TextStyle(fontSize: 14),
                          onChanged: (_) => setState(() => _index = 0),
                          decoration: const InputDecoration(
                            counterText: '',
                            filled: false,
                            hintText: 'Buscar páginas, tags ou ações…',
                            hintStyle: TextStyle(fontSize: 14, color: AppColors.textMuted),
                            contentPadding: EdgeInsets.symmetric(vertical: 16),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                          ),
                        ),
                      ),
                    ),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(4)), child: Text('esc', style: AppText.mono(10, letterSpacing: 0))),
                  ]),
                ),
                Flexible(
                  child: flat.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 32),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            const Text('Nada encontrado', style: TextStyle(fontSize: 14)),
                            Text('tente outro termo', style: AppText.mono(12, letterSpacing: 0)),
                          ]),
                        )
                      : ListView(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          children: [
                            for (final g in groups) ...[
                              Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4), child: Text(g.label.toUpperCase(), style: monoLabel(size: 10))),
                              for (final item in g.items) _row(item, n++ == cur, ws: widget.ws),
                            ],
                          ],
                        ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
                  child: Row(children: [
                    Text('↑↓ navegar   ↵ abrir   esc fechar', style: AppText.mono(11, letterSpacing: 0)),
                    const Spacer(),
                    Text('${flat.length} ${flat.length == 1 ? 'resultado' : 'resultados'}', style: AppText.mono(11, letterSpacing: 0)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(PaletteItem item, bool on, {required Workspace ws}) {
    final tag = item.dotTag == null ? null : ws.tag(item.dotTag!);
    return RingInkWell(
      onTap: item.run,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 16, 10),
        decoration: BoxDecoration(color: on ? AppColors.border.withValues(alpha: 0.5) : null, border: Border(left: BorderSide(width: 2, color: on ? AppColors.accentBorder : Colors.transparent))),
        child: Row(children: [
          if (tag != null)
            Container(width: 10, height: 10, decoration: BoxDecoration(color: tagColor(tag.color), shape: BoxShape.circle))
          else if (item.icon != null)
            Icon(_icon(item.icon!), size: 16, color: AppColors.textMuted),
          const SizedBox(width: 12),
          Expanded(child: Text(item.label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14))),
          Text(item.meta, style: AppText.mono(12, letterSpacing: 0)),
        ]),
      ),
    );
  }

  IconData _icon(PaletteIcon i) => switch (i) {
        PaletteIcon.page => Icons.description_outlined,
        PaletteIcon.lock => Icons.lock_outline,
        PaletteIcon.plus => Icons.add,
        PaletteIcon.gear => Icons.settings_outlined,
        PaletteIcon.trash => Icons.delete_outline,
        PaletteIcon.sort => Icons.sort,
      };
}
