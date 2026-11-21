import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/blocks.dart';
import '../../data/text.dart';
import 'ui.dart';

class InsertChoice {
  const InsertChoice(this.type, {this.level, this.toggle = false});
  final BlockType type;
  final int? level;
  final bool toggle;
}

class _Item {
  const _Item(this.label, this.glyph, this.choice, [this.also = '']);
  final String label, glyph, also;
  final InsertChoice choice;
}

const _groups = <(String, List<_Item>)>[
  (
    'Texto',
    [
      _Item('Texto', 'T', InsertChoice(BlockType.paragraph)),
      _Item('Título 1', 'H1', InsertChoice(BlockType.heading, level: 1)),
      _Item('Título 2', 'H2', InsertChoice(BlockType.heading, level: 2)),
      _Item('Título 3', 'H3', InsertChoice(BlockType.heading, level: 3)),
      _Item('Citação', '“', InsertChoice(BlockType.quote)),
      _Item(
        'Destaque',
        '!',
        InsertChoice(BlockType.callout),
        'aviso nota callout',
      ),
    ],
  ),
  (
    'Listas e toggles',
    [
      _Item('Lista com marcadores', '•', InsertChoice(BlockType.bullet)),
      _Item('Lista numerada', '1.', InsertChoice(BlockType.numbered)),
      _Item(
        'Checklist',
        '✓',
        InsertChoice(BlockType.checklist),
        'tarefas lista de tarefas todo',
      ),
      _Item('Toggle', '▸', InsertChoice(BlockType.toggle)),
      _Item(
        'Título 1 com toggle',
        '▸1',
        InsertChoice(BlockType.heading, level: 1, toggle: true),
      ),
      _Item(
        'Título 2 com toggle',
        '▸2',
        InsertChoice(BlockType.heading, level: 2, toggle: true),
      ),
      _Item(
        'Título 3 com toggle',
        '▸3',
        InsertChoice(BlockType.heading, level: 3, toggle: true),
      ),
    ],
  ),
  (
    'Mídia e links',
    [
      _Item('Imagem', '▣', InsertChoice(BlockType.image), 'foto figura'),
      _Item('Vídeo', '▶', InsertChoice(BlockType.video)),
      _Item('Áudio', '♪', InsertChoice(BlockType.audio)),
      _Item('Arquivo', '📎', InsertChoice(BlockType.file)),
      _Item('PDF', 'PDF', InsertChoice(BlockType.pdf)),
      _Item('Link', '↗', InsertChoice(BlockType.bookmark)),
      _Item('Link para página', '📄', InsertChoice(BlockType.pagelink)),
    ],
  ),
  (
    'Dados e código',
    [
      _Item(
        'Tabela',
        '▦',
        InsertChoice(BlockType.table),
        'grade planilha linhas colunas',
      ),
      _Item(
        'Código',
        '</>',
        InsertChoice(BlockType.code),
        'programacao codigo code',
      ),
    ],
  ),
  (
    'Estrutura e sigilo',
    [
      _Item('Sumário', '☰', InsertChoice(BlockType.toc), 'indice'),
      _Item('Divisor', '—', InsertChoice(BlockType.divider), 'linha separador'),
      _Item('Spoiler', '◐', InsertChoice(BlockType.spoiler)),
      _Item('Bloco seguro', '🔒', InsertChoice(BlockType.secure)),
    ],
  ),
];

/// Items whose name or synonyms contain every word of [query] (accents and case ignored).
List<(String, List<_Item>)> _filtered(String query) {
  final words = fold(query).split(' ').where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return _groups;
  bool hit(_Item it) {
    final hay = fold('${it.label} ${it.also}');
    return words.every(hay.contains);
  }

  return [
    for (final (title, items) in _groups)
      if (items.any(hit)) (title, items.where(hit).toList()),
  ];
}

/// The list of blocks that can be added, in a sheet that scrolls (the web opens the same list under the block).
/// A search box on top narrows it as you type; Enter takes the first match.
Future<InsertChoice?> showInsertMenu(
  BuildContext context, {
  List<BlockType> disabled = const [],
}) => showModalBottomSheet<InsertChoice>(
  context: context,
  isScrollControlled: true,
  backgroundColor: AppColors.surface,
  showDragHandle: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(fieldRadius)),
  ),
  constraints: const BoxConstraints(maxWidth: 560),
  builder: (c) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.7,
    maxChildSize: 0.95,
    builder: (c, scroll) => Semantics(
      label: 'Inserir bloco',
      scopesRoute: true,
      explicitChildNodes: true,
      child: _InsertList(scroll: scroll, disabled: disabled),
    ),
  ),
);

class _InsertList extends StatefulWidget {
  const _InsertList({required this.scroll, required this.disabled});
  final ScrollController scroll;
  final List<BlockType> disabled;

  @override
  State<_InsertList> createState() => _InsertListState();
}

class _InsertListState extends State<_InsertList> {
  String _q = '';

  // The keyboard of a phone would cover half the sheet the moment it opened: only a desktop starts typing.
  static bool get _desktop => switch (defaultTargetPlatform) {
    TargetPlatform.linux ||
    TargetPlatform.windows ||
    TargetPlatform.macOS => true,
    _ => false,
  };

  void _first() {
    for (final (_, items) in _filtered(_q)) {
      for (final it in items) {
        if (!widget.disabled.contains(it.choice.type)) {
          Navigator.pop(context, it.choice);
          return;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = _filtered(_q);
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
          child: TextField(
            key: const Key('insert-filter'),
            autofocus: _desktop,
            maxLength: 40,
            textInputAction: TextInputAction.done,
            style: const TextStyle(fontSize: 14),
            onChanged: (v) => setState(() => _q = v),
            onSubmitted: (_) => _first(),
            decoration: InputDecoration(
              isDense: true,
              counterText: '',
              hintText: 'Digite para filtrar: tabela, título, lista…',
              hintStyle: const TextStyle(
                fontSize: 14,
                color: AppColors.textMuted,
              ),
              prefixIcon: const Icon(
                Icons.filter_list,
                size: 16,
                color: AppColors.textMuted,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(fieldRadius),
                borderSide: const BorderSide(color: AppColors.fieldBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(fieldRadius),
                borderSide: const BorderSide(color: AppColors.accentBorder),
              ),
            ),
          ),
        ),
        if (groups.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 24, 8, 8),
            child: Text(
              'Nenhum bloco com esse nome. Tente "texto", "lista" ou "tabela".',
              style: TextStyle(fontSize: 14, color: AppColors.textMuted),
            ),
          ),
        for (final (title, items) in groups) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
            child: Text(
              title.toUpperCase(),
              style: monoLabel(size: 10, spacing: 1.4),
            ),
          ),
          for (final it in items)
            RingInkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: widget.disabled.contains(it.choice.type)
                  ? null
                  : () => Navigator.pop(context, it.choice),
              child: Opacity(
                opacity: widget.disabled.contains(it.choice.type) ? 0.4 : 1,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(
                          it.glyph,
                          style: AppText.mono(
                            12,
                            color: AppColors.textMuted,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(it.label, style: const TextStyle(fontSize: 14)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}
