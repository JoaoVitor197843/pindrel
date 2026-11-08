import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/blocks.dart';
import 'ui.dart';

class InsertChoice {
  const InsertChoice(this.type, {this.level, this.toggle = false});
  final BlockType type;
  final int? level;
  final bool toggle;
}

class _Item {
  const _Item(this.label, this.glyph, this.choice);
  final String label, glyph;
  final InsertChoice choice;
}

const _groups = <(String, List<_Item>)>[
  ('Texto', [
    _Item('Texto', 'T', InsertChoice(BlockType.paragraph)),
    _Item('Título 1', 'H1', InsertChoice(BlockType.heading, level: 1)),
    _Item('Título 2', 'H2', InsertChoice(BlockType.heading, level: 2)),
    _Item('Título 3', 'H3', InsertChoice(BlockType.heading, level: 3)),
    _Item('Citação', '“', InsertChoice(BlockType.quote)),
    _Item('Destaque', '!', InsertChoice(BlockType.callout)),
  ]),
  ('Listas e toggles', [
    _Item('Lista com marcadores', '•', InsertChoice(BlockType.bullet)),
    _Item('Lista numerada', '1.', InsertChoice(BlockType.numbered)),
    _Item('Checklist', '✓', InsertChoice(BlockType.checklist)),
    _Item('Toggle', '▸', InsertChoice(BlockType.toggle)),
    _Item('Título 1 com toggle', '▸1', InsertChoice(BlockType.heading, level: 1, toggle: true)),
    _Item('Título 2 com toggle', '▸2', InsertChoice(BlockType.heading, level: 2, toggle: true)),
    _Item('Título 3 com toggle', '▸3', InsertChoice(BlockType.heading, level: 3, toggle: true)),
  ]),
  ('Mídia e links', [
    _Item('Imagem', '▣', InsertChoice(BlockType.image)),
    _Item('Vídeo', '▶', InsertChoice(BlockType.video)),
    _Item('Áudio', '♪', InsertChoice(BlockType.audio)),
    _Item('Arquivo', '📎', InsertChoice(BlockType.file)),
    _Item('PDF', 'PDF', InsertChoice(BlockType.pdf)),
    _Item('Link', '↗', InsertChoice(BlockType.bookmark)),
    _Item('Link para página', '📄', InsertChoice(BlockType.pagelink)),
  ]),
  ('Dados e código', [
    _Item('Tabela', '▦', InsertChoice(BlockType.table)),
    _Item('Código', '</>', InsertChoice(BlockType.code)),
  ]),
  ('Estrutura e sigilo', [
    _Item('Sumário', '☰', InsertChoice(BlockType.toc)),
    _Item('Divisor', '—', InsertChoice(BlockType.divider)),
    _Item('Spoiler', '◐', InsertChoice(BlockType.spoiler)),
    _Item('Bloco seguro', '🔒', InsertChoice(BlockType.secure)),
  ]),
];

/// The list of blocks that can be added, in a sheet that scrolls (the web opens the same list under the block).
Future<InsertChoice?> showInsertMenu(BuildContext context, {List<BlockType> disabled = const []}) => showModalBottomSheet<InsertChoice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(fieldRadius))),
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (c, scroll) => Semantics(
          label: 'Inserir bloco',
          scopesRoute: true,
              explicitChildNodes: true,
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            children: [
              for (final (title, items) in _groups) ...[
                Padding(padding: const EdgeInsets.fromLTRB(8, 14, 8, 6), child: Text(title.toUpperCase(), style: monoLabel(size: 10, spacing: 1.4))),
                for (final it in items)
                  RingInkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: disabled.contains(it.choice.type) ? null : () => Navigator.pop(c, it.choice),
                    child: Opacity(
                      opacity: disabled.contains(it.choice.type) ? 0.4 : 1,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        child: Row(children: [
                          Container(width: 32, height: 32, alignment: Alignment.center, decoration: BoxDecoration(borderRadius: BorderRadius.circular(7), border: Border.all(color: AppColors.border)), child: Text(it.glyph, style: AppText.mono(12, color: AppColors.textMuted, letterSpacing: 0))),
                          const SizedBox(width: 12),
                          Text(it.label, style: const TextStyle(fontSize: 14)),
                        ]),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
