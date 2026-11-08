import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/pages/auth_page.dart';
import '../../data/note_page.dart';
import '../../data/palette.dart';
import '../../data/workspace.dart';
import '../widgets/motion.dart';
import '../widgets/notes_sidebar.dart';
import '../widgets/page_card.dart';
import '../widgets/palette_dialog.dart';
import '../widgets/settings_dialog.dart';
import '../widgets/top_bar.dart';
import '../widgets/ui.dart';
import 'editor_page.dart';

const _desktop = 840.0;
const _wide = 1180.0;

/// The notes of the device: views, search, tags and the pages as cards. Wide windows keep the sidebar beside the list,
/// medium ones a rail of icons that opens over it, phones a drawer.
class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.ws,
    this.userName = 'Você',
    this.server = 'neste aparelho',
  });
  final Workspace ws;
  final String userName, server;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _scaffold = GlobalKey<ScaffoldState>();
  final _search = TextEditingController();
  var _railOpen = false;
  // holds the keyboard focus while nothing is being typed, so Ctrl+K works anywhere on the screen
  final _pageNode = FocusNode(skipTraversal: true);
  Workspace get ws => widget.ws;

  @override
  void dispose() {
    _search.dispose();
    _pageNode.dispose();
    super.dispose();
  }

  void _open(String id) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => EditorPage(ws: ws, pageId: id),
    ),
  );

  void _create() {
    final p = ws.newPage();
    _search.clear();
    Toast.show(context, 'Página criada');
    _open(p.id);
  }

  void _account() => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const AuthPage()));

  void _settings([SettingsSection section = SettingsSection.general]) =>
      showDialog<void>(
        context: context,
        builder: (_) => SettingsDialog(
          ws: ws,
          section: section,
          userName: widget.userName,
          server: widget.server,
          onAccount: _account,
          onToast: (m) => Toast.show(context, m),
        ),
      );

  Future<void> _palette() => showPalette(
    context,
    ws,
    (dialog) => PaletteActions(
      newPage: () {
        Navigator.pop(dialog);
        _create();
      },
      openSettings: () {
        Navigator.pop(dialog);
        _settings();
      },
      close: () => Navigator.pop(dialog),
      open: (id) {
        Navigator.pop(dialog);
        _open(id);
      },
    ),
  );

  Future<void> _confirmEmpty() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Esvaziar a lixeira?', style: AppText.serif(20)),
        content: Text(
          '${ws.counts.trash} página(s) serão apagadas para sempre. Isso não pode ser desfeito.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.offline),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Esvaziar'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      ws.emptyTrash();
      Toast.show(context, 'Lixeira esvaziada');
    }
  }

  NotesSidebar _sidebar({
    bool rail = false,
    VoidCallback? onClose,
    VoidCallback? onNavigated,
  }) => NotesSidebar(
    ws: ws,
    onNew: _create,
    rail: rail,
    onClose: onClose,
    onNavigated: onNavigated,
    onRailToggle: () => setState(() => _railOpen = !_railOpen),
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ws,
      builder: (context, _) {
        final width = MediaQuery.sizeOf(context).width;
        final desktop = width >= _desktop;
        final full = width >= _wide;
        final main = Column(
          children: [
            NotesTopBar(
              search: _search,
              onQuery: ws.setQuery,
              compact: !desktop,
              showMenuButton: !desktop,
              userName: widget.userName,
              server: widget.server,
              onMenu: () => _scaffold.currentState?.openDrawer(),
              onPalette: _palette,
              onSettings: _settings,
              onData: () => _settings(SettingsSection.data),
              onAccount: _account,
            ),
            Expanded(
              child: _Main(
                ws: ws,
                search: _search,
                onOpen: _open,
                onCreate: _create,
                onEmpty: _confirmEmpty,
                onToast: (m) => Toast.show(context, m),
              ),
            ),
          ],
        );
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyK, control: true):
                _palette,
            const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
                _palette,
          },
          child: Focus(
            focusNode: _pageNode,
            autofocus: true,
            child: Scaffold(
              key: _scaffold,
              backgroundColor: AppColors.background,
              drawer: desktop
                  ? null
                  : Drawer(
                      width: (width * 0.85).clamp(0, 320),
                      backgroundColor: AppColors.surface,
                      shape: const RoundedRectangleBorder(),
                      child: _sidebar(
                        onClose: () => _scaffold.currentState?.closeDrawer(),
                        onNavigated: () =>
                            _scaffold.currentState?.closeDrawer(),
                      ),
                    ),
              body: !desktop
                  ? SafeArea(child: main)
                  : full
                  ? Row(
                      children: [
                        Container(
                          width: 288,
                          decoration: const BoxDecoration(
                            border: Border(
                              right: BorderSide(color: AppColors.border),
                            ),
                          ),
                          child: _sidebar(),
                        ),
                        Expanded(child: main),
                      ],
                    )
                  : Stack(
                      children: [
                        Row(
                          children: [
                            const SizedBox(width: 72),
                            Expanded(child: main),
                          ],
                        ),
                        if (_railOpen)
                          Positioned.fill(
                            left: 72,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => setState(() => _railOpen = false),
                              child: const ColoredBox(color: Color(0x66000000)),
                            ),
                          ),
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 150),
                          curve: Curves.easeOut,
                          left: 0,
                          top: 0,
                          bottom: 0,
                          width: _railOpen ? 288 : 72,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              border: const Border(
                                right: BorderSide(color: AppColors.border),
                              ),
                              boxShadow: _railOpen
                                  ? const [
                                      BoxShadow(
                                        color: Color(0x80000000),
                                        blurRadius: 24,
                                      ),
                                    ]
                                  : null,
                            ),
                            // laid out at its final width while the rail grows or shrinks, so nothing wraps on the way
                            child: ClipRect(
                              child: OverflowBox(
                                alignment: Alignment.centerLeft,
                                minWidth: _railOpen ? 288 : 72,
                                maxWidth: _railOpen ? 288 : 72,
                                child: _sidebar(
                                  rail: !_railOpen,
                                  onNavigated: () =>
                                      setState(() => _railOpen = false),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _Main extends StatelessWidget {
  const _Main({
    required this.ws,
    required this.search,
    required this.onOpen,
    required this.onCreate,
    required this.onEmpty,
    required this.onToast,
  });
  final Workspace ws;
  final TextEditingController search;
  final void Function(String) onOpen;
  final VoidCallback onCreate, onEmpty;
  final void Function(String) onToast;

  static const _titles = {
    NotesView.all: 'Minhas páginas',
    NotesView.shared: 'Compartilhadas comigo',
    NotesView.vault: 'Cofre',
    NotesView.trash: 'Lixeira',
  };

  Tag? get _filter => ws.tagFilter == null ? null : ws.tag(ws.tagFilter!);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final padH = width >= 768 ? 32.0 : 16.0;
    final list = ws.layout == NotesLayout.list;
    final columns = list
        ? 1
        : (width >= 1700 ? 4 : (width >= 1280 ? 3 : (width >= 768 ? 2 : 1)));
    final filterTag = _filter;
    final heading = ws.view == NotesView.vault
        ? 'Cofre'
        : (filterTag != null ? '#${filterTag.name}' : _titles[ws.view]!);
    final total = ws.view == NotesView.vault
        ? ws.counts.vault
        : ws.visible.length;
    final noun = ws.view == NotesView.vault
        ? (total == 1 ? 'entrada' : 'entradas')
        : (total == 1 ? 'página' : 'páginas');
    final filtering = ws.query.trim().isNotEmpty || ws.tagFilter != null;
    final groups = ws.groups;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(padH, 24, padH, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  runSpacing: 16,
                  spacing: 16,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.end,
                      spacing: 16,
                      runSpacing: 4,
                      children: [
                        Text(
                          heading,
                          style: AppText.serif(
                            width >= 768 ? 36 : 30,
                          ).copyWith(fontWeight: FontWeight.bold),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              '$total $noun',
                              style: AppText.mono(14, letterSpacing: 0),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (ws.view == NotesView.trash && total > 0)
                          OutlineTextButton(
                            label: 'Esvaziar lixeira',
                            onPressed: onEmpty,
                          ),
                        _Segment(
                          children: [
                            _SegButton(
                              icon: Icons.grid_view,
                              tooltip: 'Grade',
                              on: !list,
                              onTap: () => ws.setLayout(NotesLayout.grid),
                            ),
                            _SegButton(
                              icon: Icons.view_headline,
                              tooltip: 'Lista',
                              on: list,
                              onTap: () => ws.setLayout(NotesLayout.list),
                            ),
                          ],
                        ),
                        _Segment(
                          children: [
                            _SegText(
                              label: 'RECENTES',
                              on: ws.sort == NotesSort.recent,
                              onTap: () => ws.setSort(NotesSort.recent),
                            ),
                            _SegText(
                              label: 'A–Z',
                              on: ws.sort == NotesSort.az,
                              onTap: () => ws.setSort(NotesSort.az),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                if (filterTag != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: RingInkWell(
                        borderRadius: BorderRadius.circular(99),
                        onTap: () => ws.toggleTagFilter(filterTag.id),
                        child: Semantics(
                          button: true,
                          label: 'Remover filtro',
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(color: AppColors.fieldBorder),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'tag: ${filterTag.name}',
                                  style: AppText.mono(
                                    12,
                                    letterSpacing: 0,
                                    color: AppColors.text,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(Icons.close, size: 12),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (ws.view == NotesView.vault)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(padH, 32, padH, 0),
            sliver: const SliverToBoxAdapter(
              child: _Empty(
                icon: Icons.lock_outline,
                title: 'Cofre em breve',
                body:
                    'O cofre guarda páginas cifradas no aparelho; a chave nunca sai daqui. Ainda está sendo construído.',
              ),
            ),
          )
        else if (ws.visible.isEmpty)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(padH, 32, padH, 0),
            sliver: SliverToBoxAdapter(child: _emptyFor(filtering)),
          )
        else
          for (final g in groups) ...[
            if (g.label != null)
              SliverPadding(
                padding: EdgeInsets.fromLTRB(padH, 24, padH, 12),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      Text(g.label!.toUpperCase(), style: monoLabel()),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Divider(height: 1, color: AppColors.border),
                      ),
                      const SizedBox(width: 12),
                      Text('${g.pages.length}', style: monoLabel()),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(padH, 24, padH, 0),
                sliver: const SliverToBoxAdapter(child: SizedBox.shrink()),
              ),
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: padH),
              sliver: SliverList.builder(
                itemCount: (g.pages.length / columns).ceil(),
                itemBuilder: (_, row) {
                  final slice = g.pages
                      .skip(row * columns)
                      .take(columns)
                      .toList();
                  final cards = [for (final p in slice) _card(p, list)];
                  return Padding(
                    padding: EdgeInsets.only(bottom: list ? 8 : 16),
                    child: columns == 1
                        ? cards.first
                        : IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (var i = 0; i < columns; i++) ...[
                                  if (i > 0) const SizedBox(width: 16),
                                  Expanded(
                                    child: i < cards.length
                                        ? cards[i]
                                        : const SizedBox.shrink(),
                                  ),
                                ],
                              ],
                            ),
                          ),
                  );
                },
              ),
            ),
          ],
        const SliverToBoxAdapter(child: SizedBox(height: 48)),
      ],
    );
  }

  Widget _card(NotePage page, bool list) => PageCard(
    key: ValueKey(page.id),
    page: page,
    tags: ws.tags,
    list: list,
    query: ws.query,
    onOpen: () => onOpen(page.id),
    onPin: () => ws.togglePin(page.id),
    onTrash: () {
      final toTrash = ws.settings.useTrash && !page.locked;
      ws.trash(page.id);
      onToast(toTrash ? 'Movida para a lixeira' : 'Página excluída');
    },
    onRestore: () => ws.restore(page.id),
  );

  Widget _emptyFor(bool filtering) {
    if (filtering) {
      return _Empty(
        icon: Icons.search,
        title: 'Nada encontrado',
        body:
            'Nenhuma página corresponde a esse filtro. Tente outro termo ou limpe a tag selecionada.',
        cta: 'Limpar filtros',
        onCta: () {
          search.clear();
          ws.clearFilters();
        },
      );
    }
    if (ws.view == NotesView.shared) {
      return const _Empty(
        icon: Icons.person_outline,
        title: 'Nada compartilhado com você',
        body: 'Quando alguém te der acesso a uma página, ela aparece aqui.',
      );
    }
    if (ws.view == NotesView.trash) {
      return _Empty(
        icon: Icons.delete_outline,
        title: 'Lixeira vazia',
        body: ws.settings.useTrash
            ? 'Páginas excluídas ficam aqui por ${ws.settings.retention} dias antes de sumirem de vez.'
            : 'A lixeira está desligada nas configurações: páginas excluídas somem na hora.',
      );
    }
    return _Empty(
      icon: Icons.description_outlined,
      title: 'Nenhuma página ainda',
      body:
          'Comece um documento em branco — títulos, listas e tags entram depois, no seu ritmo.',
      cta: 'Criar primeira página',
      onCta: onCreate,
      ctaIcon: Icons.add,
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(fieldRadius),
      border: Border.all(color: AppColors.border),
    ),
    // at the largest text sizes the buttons shrink instead of running off the screen
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    ),
  );
}

class _SegButton extends StatelessWidget {
  const _SegButton({
    required this.icon,
    required this.tooltip,
    required this.on,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final bool on;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Semantics(
      button: true,
      selected: on,
      label: tooltip,
      child: RingInkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: on ? AppColors.border : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(
            icon,
            size: 16,
            color: on ? AppColors.text : AppColors.textMuted,
          ),
        ),
      ),
    ),
  );
}

class _SegText extends StatelessWidget {
  const _SegText({required this.label, required this.on, required this.onTap});
  final String label;
  final bool on;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: on,
    child: RingInkWell(
      borderRadius: BorderRadius.circular(7),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? AppColors.primaryButton : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: AppText.mono(
            12,
            color: on ? AppColors.onPrimaryButton : AppColors.textMuted,
            letterSpacing: 1.4,
          ),
        ),
      ),
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.icon,
    required this.title,
    required this.body,
    this.cta,
    this.onCta,
    this.ctaIcon,
  });
  final IconData icon;
  final String title, body;
  final String? cta;
  final IconData? ctaIcon;
  final VoidCallback? onCta;

  @override
  Widget build(BuildContext context) => Entrance(
    child: Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(fieldRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 28, color: AppColors.textMuted),
          const SizedBox(height: 8),
          Text(title, style: AppText.serif(24), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 448),
            child: Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textMuted,
                height: 1.5,
              ),
            ),
          ),
          if (cta != null) ...[
            const SizedBox(height: 20),
            CreamButton(label: cta!, icon: ctaIcon, onPressed: onCta!),
          ],
        ],
      ),
    ),
  );
}
