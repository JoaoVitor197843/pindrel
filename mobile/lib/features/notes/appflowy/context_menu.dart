// The menu of the right mouse button in the page's text. Cut, copy, paste and select all everywhere; in a table
// cell also what can be done to its row and its column (insert, move, duplicate, clear, delete), because the
// handles at the edge are far from the text a person is looking at.

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../presentation/widgets/ui.dart' show monoLabel;

Widget pageContextMenu(BuildContext context, Offset position, EditorState es, VoidCallback close) {
  final sel = es.selection;
  final node = sel == null ? null : es.getNodeAtPath(sel.start.path);
  final cell = node?.parent?.type == TableCellBlockKeys.type ? node!.parent : null;
  final table = cell?.parent;
  final ops = table == null ? null : TableOps.of(table);
  final row = cell?.attributes[TableCellBlockKeys.rowPosition], col = cell?.attributes[TableCellBlockKeys.colPosition];
  final hasRange = sel != null && !sel.isCollapsed;

  final sections = <(String?, List<_Item>)>[
    (null, [
      _Item('Recortar', Icons.content_cut, () => cutCommand.execute(es), enabled: hasRange),
      _Item('Copiar', Icons.content_copy, () => copyCommand.execute(es), enabled: hasRange),
      _Item('Colar', Icons.content_paste, () => pasteCommand.execute(es)),
      _Item('Selecionar tudo', Icons.select_all, () => selectAllCommand.execute(es)),
    ]),
    if (ops != null && ops.editable && row is int && col is int) ...[
      ('LINHA', [for (final i in ops.rowItems(row)) _Item(i.label, i.icon, i.run, danger: i.danger)]),
      ('COLUNA', [for (final i in ops.colItems(col)) _Item(i.label, i.icon, i.run, danger: i.danger)]),
    ],
  ];

  final size = MediaQuery.sizeOf(context);
  const width = 250.0;
  final count = sections.fold<int>(0, (n, s) => n + s.$2.length + (s.$1 == null ? 0 : 1));
  final height = count * 36.0 + 16;
  final left = position.dx.clamp(8.0, (size.width - width - 8).clamp(8.0, double.infinity));
  final top = position.dy.clamp(8.0, (size.height - height - 8).clamp(8.0, double.infinity));

  return Positioned(
    left: left,
    top: top,
    width: width,
    child: Material(
      key: const Key('page-context-menu'),
      color: AppColors.surface,
      elevation: 6,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: AppColors.border)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: size.height - 16),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (title, items) in sections) ...[
              if (title != null) Padding(padding: const EdgeInsets.fromLTRB(14, 8, 14, 2), child: Text(title, style: monoLabel(size: 10, spacing: 1.4))),
              for (final i in items) _Row(item: i, close: close),
              if (title == null && sections.length > 1) const Divider(height: 8, color: AppColors.border),
            ],
          ]),
        ),
      ),
    ),
  );
}

class _Item {
  const _Item(this.label, this.icon, this.run, {this.enabled = true, this.danger = false});
  final String label;
  final IconData icon;
  final VoidCallback run;
  final bool enabled, danger;
}

class _Row extends StatelessWidget {
  const _Row({required this.item, required this.close});
  final _Item item;
  final VoidCallback close;

  @override
  Widget build(BuildContext context) {
    final color = !item.enabled ? AppColors.textMuted.withValues(alpha: 0.5) : (item.danger ? AppColors.offlineText : AppColors.text);
    return InkWell(
      onTap: item.enabled
          ? () {
              close();
              item.run();
            }
          : null,
      child: SizedBox(
        height: 36,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(children: [
            Icon(item.icon, size: 16, color: item.danger ? AppColors.offlineText : AppColors.textMuted),
            const SizedBox(width: 10),
            Expanded(child: Text(item.label, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: color))),
          ]),
        ),
      ),
    );
  }
}
