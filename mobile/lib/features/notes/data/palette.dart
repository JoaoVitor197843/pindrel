import 'text.dart';
import 'workspace.dart';

enum PaletteIcon { page, lock, plus, gear, trash, sort }

class PaletteItem {
  const PaletteItem({required this.label, required this.meta, this.icon, this.dotTag, required this.run});
  final String label, meta;
  final PaletteIcon? icon;

  /// Tag id whose colour dot replaces the icon.
  final String? dotTag;
  final void Function() run;
}

class PaletteGroup {
  const PaletteGroup(this.label, this.items);
  final String label;
  final List<PaletteItem> items;
}

class PaletteActions {
  const PaletteActions({required this.newPage, required this.openSettings, required this.close, required this.open});
  final void Function() newPage, openSettings, close;
  final void Function(String id) open;
}

/// What the command palette lists for [query]: pages, actions and tags, in that order, empty groups left out.
List<PaletteGroup> buildPalette(Workspace ws, String query, PaletteActions act) {
  final q = fold(query.trim());
  bool match(String s) => q.isEmpty || fold(s).contains(q);

  final pages = [for (final p in ws.live) if (match(p.locked ? p.title : '${p.title} ${p.excerpt}')) p]..sort((a, b) => b.updated.compareTo(a.updated));
  final pageItems = [
    for (final p in pages.take(6))
      PaletteItem(label: p.title, meta: formatDate(p.updated), icon: p.locked ? PaletteIcon.lock : PaletteIcon.page, run: () => act.open(p.id)),
  ];

  final actions = [
    PaletteItem(label: 'Criar nova página', meta: 'n', icon: PaletteIcon.plus, run: act.newPage),
    PaletteItem(label: 'Abrir configurações', meta: 'conf', icon: PaletteIcon.gear, run: act.openSettings),
    PaletteItem(label: 'Ir para o cofre', meta: 'cofre', icon: PaletteIcon.lock, run: () {
      ws.go(NotesView.vault);
      act.close();
    }),
    PaletteItem(label: 'Ver lixeira', meta: 'lixeira', icon: PaletteIcon.trash, run: () {
      ws.go(NotesView.trash);
      act.close();
    }),
    PaletteItem(label: 'Alternar ordenação', meta: ws.sort == NotesSort.recent ? 'A–Z' : 'recentes', icon: PaletteIcon.sort, run: () {
      ws.setSort(ws.sort == NotesSort.recent ? NotesSort.az : NotesSort.recent);
      act.close();
    }),
  ].where((a) => match(a.label)).toList();

  final tagItems = [
    for (final t in ws.tags)
      if (match(t.name))
        PaletteItem(label: '#${t.name}', meta: '${ws.tagCounts[t.id] ?? 0} págs', dotTag: t.id, run: () {
          ws.go(NotesView.all);
          ws.toggleTagFilter(t.id);
          act.close();
        }),
  ];

  return [
    PaletteGroup('Páginas', pageItems),
    PaletteGroup('Ações', actions),
    PaletteGroup('Tags', tagItems),
  ].where((g) => g.items.isNotEmpty).toList();
}
