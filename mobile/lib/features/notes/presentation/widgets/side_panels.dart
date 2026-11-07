import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/blocks.dart';
import '../../data/page_editor.dart';
import '../../data/workspace.dart';
import 'editor_chrome.dart';
import 'tag_style.dart';
import 'ui.dart';

/// The properties on the left: tags and the page's basic facts.
class PageProps extends StatelessWidget {
  const PageProps({super.key, required this.ed});
  final PageEditor ed;

  Widget _label(String t) => Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(t.toUpperCase(), style: monoLabel(size: 10.5, spacing: 1.6)));

  @override
  Widget build(BuildContext context) {
    final p = ed.page!;
    final n = ed.blocks.length;
    final pr = ed.progress;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label('Tags'),
      TagBar(ed: ed),
      const SizedBox(height: 16),
      _label('Dono'),
      const Text('Você', style: TextStyle(fontSize: 14)),
      const SizedBox(height: 16),
      _label('Criada'),
      Text(formatDate(p.created), style: const TextStyle(fontSize: 14)),
      const SizedBox(height: 16),
      _label('Conteúdo'),
      Text('$n ${n == 1 ? 'bloco' : 'blocos'}${pr.total > 0 ? ' · ${pr.done} de ${pr.total} feitas' : ''}', style: const TextStyle(fontSize: 14)),
      const SizedBox(height: 16),
      _label('Editada'),
      Text(ago(p.updated), style: const TextStyle(fontSize: 14)),
    ]);
  }
}

/// The panel on the right: the outline, the details, related pages and the page's actions; each part folds.
class SidePanel extends StatefulWidget {
  const SidePanel({super.key, required this.ed, required this.onJump, required this.onOpen, required this.onDuplicate});
  final PageEditor ed;
  final void Function(String blockId) onJump;
  final void Function(String pageId) onOpen;
  final VoidCallback onDuplicate;
  @override
  State<SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends State<SidePanel> {
  final _folded = <String>{};

  Widget _section(String id, String title, Widget body) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        RingInkWell(
          onTap: () => setState(() => _folded.contains(id) ? _folded.remove(id) : _folded.add(id)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              Expanded(child: Text(title.toUpperCase(), style: monoLabel(size: 10.5, spacing: 1.6))),
              AnimatedRotation(turns: _folded.contains(id) ? 0 : 0.25, duration: const Duration(milliseconds: 150), child: const Text('›', style: TextStyle(fontSize: 14, color: AppColors.textMuted))),
            ]),
          ),
        ),
        if (!_folded.contains(id)) Padding(padding: const EdgeInsets.only(top: 8), child: body),
        const SizedBox(height: 28),
      ]);

  @override
  Widget build(BuildContext context) {
    final ed = widget.ed;
    final p = ed.page!;
    final items = ed.outlineItems;
    final stats = ed.stats;
    final pr = ed.progress;
    final related = ed.related;
    Widget fact(String k, String v) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(k, style: AppText.mono(12, letterSpacing: 0)), Text(v, style: const TextStyle(fontSize: 14))]);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _section(
        'outline',
        'Nesta página',
        items.isEmpty
            ? const Text('Os títulos de seção aparecem aqui.', style: TextStyle(fontSize: 14, color: AppColors.textMuted))
            : Container(
                decoration: const BoxDecoration(border: Border(left: BorderSide(color: AppColors.border))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final it in items)
                    RingInkWell(
                      onTap: () => widget.onJump(it.id),
                      child: Padding(padding: EdgeInsets.fromLTRB(12 + (it.level - 1) * 14.0, 6, 0, 6), child: Text(it.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, color: AppColors.textMuted))),
                    ),
                ]),
              ),
      ),
      _section(
        'details',
        'Detalhes',
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 24, runSpacing: 12, children: [
            SizedBox(width: 90, child: fact('palavras', '${stats.words}')),
            SizedBox(width: 90, child: fact('leitura', stats.minutes > 0 ? '${stats.minutes} min' : '—')),
            SizedBox(width: 90, child: fact('blocos', '${ed.blocks.length}')),
            SizedBox(width: 90, child: fact('caracteres', '${stats.chars}')),
            SizedBox(width: 90, child: fact('criada', formatDate(p.created))),
            SizedBox(width: 90, child: fact('editada', ago(p.updated))),
          ]),
          if (pr.total > 0) ...[
            const SizedBox(height: 16),
            Row(children: [Text('checklists', style: AppText.mono(12, letterSpacing: 0)), const Spacer(), Text('${pr.done} de ${pr.total}', style: AppText.mono(12, letterSpacing: 0))]),
            const SizedBox(height: 6),
            ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(value: pr.done / pr.total, minHeight: 6, backgroundColor: AppColors.border, color: AppColors.accentBorder)),
          ],
        ]),
      ),
      _section(
        'related',
        'Relacionadas',
        related.isEmpty
            ? Text(p.tags.isNotEmpty ? 'Nenhuma outra página com as mesmas tags.' : 'Adicione tags para ver páginas parecidas.', style: const TextStyle(fontSize: 14, color: AppColors.textMuted))
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final o in related)
                  RingInkWell(
                    borderRadius: BorderRadius.circular(fieldRadius),
                    onTap: () => widget.onOpen(o.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(o.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.serif(15).copyWith(fontWeight: FontWeight.w600)),
                        Wrap(spacing: 8, children: [
                          for (final id in o.tags.where(p.tags.contains))
                            if (ed.ws.tag(id) case final t?) Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 6, height: 6, decoration: BoxDecoration(color: tagColor(t.color), shape: BoxShape.circle)), const SizedBox(width: 4), Text(t.name, style: AppText.mono(11, letterSpacing: 0))]),
                        ]),
                      ]),
                    ),
                  ),
              ]),
      ),
      _section(
        'actions',
        'Ações',
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!ed.readOnly) ...[
            OutlineTextButton(label: p.pinned ? 'Desafixar página' : 'Fixar página', icon: Icons.push_pin_outlined, onPressed: ed.togglePin),
            const SizedBox(height: 8),
            OutlineTextButton(label: 'Duplicar página', icon: Icons.content_copy, onPressed: widget.onDuplicate),
          ],
        ]),
      ),
    ]);
  }
}
