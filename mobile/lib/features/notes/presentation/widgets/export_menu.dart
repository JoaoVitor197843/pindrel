import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/page_editor.dart';
import '../../data/transfer.dart';
import 'ui.dart';

/// "Exportar": copies the page to the clipboard as Markdown, plain text or JSON.
class ExportMenu extends StatelessWidget {
  const ExportMenu({super.key, required this.ed, required this.compact, required this.onDone});
  final PageEditor ed;
  final bool compact;
  final void Function(String message) onDone;

  @override
  Widget build(BuildContext context) => PopupMenuButton<ExportFormat>(
        tooltip: 'Exportar página',
        color: AppColors.surface,
        offset: const Offset(0, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(fieldRadius), side: const BorderSide(color: AppColors.border)),
        onSelected: (f) async {
          final page = ed.page;
          if (page == null) return;
          await Clipboard.setData(ClipboardData(text: exportPage(page, ed.ws.tags, f)));
          onDone('${formatLabels[f]} copiado');
        },
        itemBuilder: (_) => [for (final f in ExportFormat.values) PopupMenuItem(value: f, child: Text('Copiar como ${formatLabels[f]}', style: const TextStyle(fontSize: 14)))],
        child: Container(
          height: 40,
          padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(fieldRadius), border: Border.all(color: compact ? Colors.transparent : AppColors.border)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.file_download_outlined, size: 16, color: AppColors.textMuted),
            if (!compact) ...[const SizedBox(width: 8), const Text('Exportar', style: TextStyle(fontSize: 14, color: AppColors.textMuted))],
          ]),
        ),
      );
}
