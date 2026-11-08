import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/blocks.dart';
import '../../data/dock.dart';
import '../../data/note_page.dart';
import '../../data/page_editor.dart';
import '../../data/workspace.dart';
import '../widgets/block_fields.dart';
import '../widgets/block_row.dart';
import '../widgets/block_views.dart';
import '../widgets/editor_chrome.dart';
import '../widgets/export_menu.dart';
import '../widgets/insert_menu.dart';
import '../widgets/motion.dart';
import '../widgets/side_panels.dart';
import '../widgets/ui.dart';

const _dockMin = 1340.0;

const _labels = <BlockType, String>{
  BlockType.paragraph: 'Parágrafo',
  BlockType.heading: 'Título de seção',
  BlockType.quote: 'Citação',
  BlockType.callout: 'Destaque',
  BlockType.toggle: 'Toggle',
  BlockType.divider: 'Divisor',
  BlockType.checklist: 'Checklist',
  BlockType.code: 'Bloco de código',
  BlockType.spoiler: 'Spoiler',
  BlockType.secure: 'Bloco seguro',
  BlockType.table: 'Tabela',
  BlockType.image: 'Imagem',
  BlockType.bullet: 'Item de lista',
  BlockType.numbered: 'Item numerado',
  BlockType.toc: 'Sumário',
  BlockType.bookmark: 'Link',
  BlockType.pagelink: 'Link para página',
  BlockType.video: 'Vídeo',
  BlockType.audio: 'Áudio',
  BlockType.pdf: 'PDF',
  BlockType.file: 'Arquivo',
};

/// One page: a cover, an icon, the title, and the blocks, with the properties on the left and the panel on the right.
/// Text blocks are plain fields for now (the rich editor comes later).
class EditorPage extends StatefulWidget {
  const EditorPage({super.key, required this.ws, required this.pageId});
  final Workspace ws;
  final String pageId;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  late final PageEditor _ed = PageEditor(widget.ws, widget.pageId);
  final _scroll = ScrollController();
  final _nodes = <String, FocusNode>{};
  final _rowKeys = <String, GlobalKey>{};
  final _draft = TextEditingController();
  final _draftNode = FocusNode();
  // holds the keyboard focus while nothing is being typed, so Esc can leave the zen mode
  final _pageNode = FocusNode(skipTraversal: true);
  String? _wantFocus;
  var _zen = false;
  // the block that has the keyboard (the others fade back in zen mode), and the rows whose entrance already played
  String? _activeId;
  final _entered = <String>{};
  bool? _propsDock, _panelDock;
  // the panels as drawers over the page (narrow windows); they always start closed
  var _propsDrawer = false, _panelDrawer = false;

  @override
  void dispose() {
    _ed.dispose();
    _scroll.dispose();
    _draft.dispose();
    _draftNode.dispose();
    _pageNode.dispose();
    for (final n in _nodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  void _setZen(bool on) {
    setState(() => _zen = on);
    if (on) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _pageNode.requestFocus();
        }
      });
    }
  }

  FocusNode _focusFor(String id) => _nodes.putIfAbsent(id, FocusNode.new);

  void _requestFocus(String id, {bool atStart = false}) {
    _wantFocus = id;
    setState(() {});
  }

  void _applyFocus() {
    final id = _wantFocus;
    if (id == null) return;
    _wantFocus = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusFor(id).requestFocus();
    });
  }

  void _toast(String text) => Toast.show(context, text);

  void _jump(String id) {
    final ctx = _rowKeys[id]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      // far away and not built: land near it, then settle once it is drawn
      final i = _ed.blocks.indexWhere((b) => b.id == id);
      if (i >= 0 && _scroll.hasClients) {
        _scroll
            .animateTo(
              (i * 64.0).clamp(0, _scroll.position.maxScrollExtent),
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
            )
            .then((_) {
              final c = _rowKeys[id]?.currentContext;
              if (mounted && c != null && c.mounted) {
                Scrollable.ensureVisible(c);
              }
            });
      }
    }
    if (_panelDrawer) setState(() => _panelDrawer = false);
  }

  Future<void> _insertMenu({String? after, bool replaceEmpty = false}) async {
    final c = await showInsertMenu(context);
    if (c == null || !mounted) return;
    final b = _ed.insert(
      c.type,
      afterId: after,
      level: c.level,
      toggle: c.toggle,
    );
    if (b == null) {
      _toast('Esta página chegou ao limite de $maxBlocks blocos');
      return;
    }
    if (replaceEmpty && after != null) {
      final empty = _ed.blocks.where((x) => x.id == after).firstOrNull;
      if (empty != null &&
          empty.type == BlockType.paragraph &&
          (empty.text ?? '').isEmpty) {
        _ed.remove(after);
      }
    }
    if (isTextType(b.type) ||
        b.type == BlockType.toggle ||
        b.type == BlockType.code) {
      _requestFocus(b.id);
    }
  }

  void _openPage(String id) => Navigator.of(context).pushReplacement(
    MaterialPageRoute<void>(
      builder: (_) => EditorPage(ws: widget.ws, pageId: id),
    ),
  );

  void _duplicate() {
    final made = _ed.duplicate();
    if (made == null) return;
    _toast(
      made.images > 0
          ? 'Página duplicada (as imagens não foram copiadas)'
          : 'Página duplicada',
    );
    _openPage(made.id);
  }

  Future<void> _delete() async {
    final page = _ed.page;
    if (page == null) return;
    final permanent =
        page.trashed || page.locked || !widget.ws.settings.useTrash;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          permanent ? 'Excluir esta página?' : 'Mover para a lixeira?',
          style: AppText.serif(20),
        ),
        content: Text(
          permanent
              ? '“${page.title}” será apagada para sempre. Isso não pode ser desfeito.'
              : '“${page.title}” vai para a lixeira e pode ser restaurada por ${widget.ws.settings.retention} dias.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.offline),
            onPressed: () => Navigator.pop(c, true),
            child: Text(
              permanent ? 'Excluir definitivamente' : 'Mover para a lixeira',
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (permanent) {
      widget.ws.deleteForever(widget.pageId);
    } else {
      widget.ws.trash(widget.pageId);
    }
    final message = permanent ? 'Página excluída' : 'Movida para a lixeira';
    final nav = Navigator.of(context);
    final overlay = nav.overlay;
    nav.pop();
    // the page is gone: the toast goes on the navigator's own overlay
    Toast.showOn(overlay, message);
  }

  /// The panels as drawers (windows too narrow to dock them), and the tabs on the edges that open them. Laid out over the
  /// whole screen, header included: the tabs are centred on the window, as the web's `fixed` ones are.
  List<Widget> _drawers(double width, bool docked, bool roomForArrows) {
    if (_zen || docked || _ed.page == null) return const [];
    final w = width * 0.8 < 352 ? width * 0.8 : 352.0;
    Widget drawer({
      required bool left,
      required String title,
      required Widget body,
      required VoidCallback close,
    }) {
      final panel = Material(
        color: AppColors.surface,
        child: Container(
          width: w,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            border: Border(
              left: left
                  ? BorderSide.none
                  : const BorderSide(color: AppColors.border),
              right: left
                  ? const BorderSide(color: AppColors.border)
                  : BorderSide.none,
            ),
          ),
          child: SafeArea(
            child: ListView(
              children: [
                Text(title, style: AppText.serif(20)),
                const SizedBox(height: 20),
                body,
              ],
            ),
          ),
        ),
      );
      final arrow = SizedBox(
        width: 56,
        child: Center(
          child: DockToggle(
            left: left,
            open: true,
            label: left ? 'Fechar propriedades' : 'Fechar painel',
            onTap: close,
          ),
        ),
      );
      return Positioned(
        left: left ? 0 : null,
        right: left ? null : 0,
        top: 0,
        bottom: 0,
        child: Row(
          children: [
            if (!left) arrow,
            Entrance(
              kind: left
                  ? EntranceKind.slideFromLeft
                  : EntranceKind.slideFromRight,
              child: panel,
            ),
            if (left) arrow,
          ],
        ),
      );
    }

    Widget scrim(String label, VoidCallback close) => Positioned.fill(
      child: Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: close,
          child: ColoredBox(color: AppColors.background.withValues(alpha: 0.7)),
        ),
      ),
    );

    return [
      if (roomForArrows && !_propsDrawer && !_panelDrawer) ...[
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: Center(
            child: DockToggle(
              left: true,
              open: false,
              kind: DockKind.edge,
              label: 'Abrir propriedades',
              onTap: () => setState(() => _propsDrawer = true),
            ),
          ),
        ),
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          child: Center(
            child: DockToggle(
              left: false,
              open: false,
              kind: DockKind.edge,
              label: 'Abrir painel',
              onTap: () => setState(() => _panelDrawer = true),
            ),
          ),
        ),
      ],
      if (_propsDrawer) ...[
        scrim(
          'Fechar propriedades (fundo)',
          () => setState(() => _propsDrawer = false),
        ),
        drawer(
          left: true,
          title: 'Propriedades',
          body: PageProps(ed: _ed),
          close: () => setState(() => _propsDrawer = false),
        ),
      ],
      if (_panelDrawer) ...[
        scrim(
          'Fechar painel (fundo)',
          () => setState(() => _panelDrawer = false),
        ),
        drawer(
          left: false,
          title: 'Painel',
          body: SidePanel(
            ed: _ed,
            onJump: _jump,
            onOpen: _openPage,
            onDuplicate: _duplicate,
          ),
          close: () => setState(() => _panelDrawer = false),
        ),
      ],
    ];
  }

  Widget _panelBox(String title, Widget child) => Container(
    width: 240,
    margin: const EdgeInsets.symmetric(vertical: 16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surface.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(fieldRadius),
      border: Border.all(color: AppColors.border),
    ),
    child: ListView(
      children: [
        Text(title, style: AppText.serif(20)),
        const SizedBox(height: 20),
        child,
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_ed, widget.ws]),
      builder: (context, _) {
        final page = _ed.page;
        if (page == null) {
          return Scaffold(
            appBar: AppBar(backgroundColor: AppColors.background),
            body: const Center(child: Text('Esta página não existe mais.')),
          );
        }
        _applyFocus();
        final width = MediaQuery.sizeOf(context).width;
        final docked = width >= _dockMin && !_zen;
        final roomForArrows = width >= 360;
        final compact = width < 480;
        final propsOpen = _propsDock ?? true;
        final panelOpen = _panelDock ?? true;
        final cx = BlockContext(
          ed: _ed,
          numbers: numbering(_ed.blocks),
          focusFor: _focusFor,
          requestFocus: _requestFocus,
          openSlash: (id) => _insertMenu(after: id, replaceEmpty: true),
          openPage: _openPage,
          jump: _jump,
        );
        final gutter = BlockRow.gutterFor(width);
        final place = page.trashed ? 'Lixeira' : (page.locked ? 'Cofre' : null);

        Widget block(int i) {
          final b = _ed.blocks[i];
          final key = _rowKeys.putIfAbsent(b.id, GlobalKey.new);
          final animate = !_entered.contains(b.id);
          _entered.add(b.id);
          return Article(
            key: ValueKey(b.id),
            zen: _zen,
            leftGutter: gutter,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: BlockRow(
                key: key,
                index: i,
                count: _ed.blocks.length,
                block: b,
                label: _labels[b.type]!,
                ed: _ed,
                onInsertAfter: () => _insertMenu(after: b.id),
                animate: animate,
                dim: _zen && _activeId != null && _activeId != b.id,
                onActive: (on) {
                  if (on) {
                    if (_activeId != b.id) setState(() => _activeId = b.id);
                  } else if (_activeId == b.id) {
                    setState(() => _activeId = null);
                  }
                },
                child: BlockBody(block: b, cx: cx),
              ),
            ),
          );
        }

        final list = ReorderableListView.builder(
          scrollController: _scroll,
          buildDefaultDragHandles: false,
          padding: const EdgeInsets.only(bottom: 128),
          proxyDecorator: (child, index, animation) => Material(
            color: Colors.transparent,
            child: Opacity(opacity: 0.6, child: child),
          ),
          header: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_zen) PageCoverBand(ed: _ed),
              Article(
                zen: _zen,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: _zen ? 96 : 40),
                    if (_ed.readOnly)
                      Container(
                        margin: const EdgeInsets.only(bottom: 24),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: cardBox(),
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            const Text(
                              'Esta página está na lixeira e não pode ser editada.',
                              style: TextStyle(fontSize: 14),
                            ),
                            OutlineTextButton(
                              label: 'Restaurar',
                              height: 36,
                              onPressed: () => widget.ws.restore(widget.pageId),
                            ),
                          ],
                        ),
                      ),
                    if (!_zen || page.icon.isNotEmpty) PageIconRow(ed: _ed),
                    SyncedField(
                      key: const ValueKey('title'),
                      value: page.title,
                      hint: 'Sem título',
                      style: AppText.serif(
                        width >= 768 ? 41.6 : 36,
                      ).copyWith(fontWeight: FontWeight.bold, height: 1.2),
                      readOnly: _ed.readOnly,
                      maxLength: maxTitle,
                      onChanged: _ed.setTitle,
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ],
          ),
          footer: Article(
            zen: _zen,
            leftGutter: gutter,
            child: Padding(
              padding: EdgeInsets.only(left: gutter > 0 ? gutter : 0, top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!_ed.readOnly)
                    TextField(
                      key: const Key('draft'),
                      controller: _draft,
                      focusNode: _draftNode,
                      maxLength: maxText,
                      maxLines: null,
                      style: const TextStyle(fontSize: 16.5, height: 1.68),
                      decoration: InputDecoration(
                        counterText: '',
                        filled: false,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 6),
                        hintText:
                            'Escreva algo, ou digite “/” para inserir um bloco',
                        hintStyle: TextStyle(
                          fontSize: 16.5,
                          color: AppColors.textMuted.withValues(alpha: 0.7),
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                      onChanged: (v) {
                        if (v == '/') {
                          _draft.clear();
                          _insertMenu();
                        } else if (v.isNotEmpty) {
                          final b = _ed.insert(BlockType.paragraph);
                          _draft.clear();
                          if (b != null) {
                            _ed.setText(b.id, v);
                            _requestFocus(b.id);
                          } else {
                            _toast(
                              'Esta página chegou ao limite de $maxBlocks blocos',
                            );
                          }
                        }
                      },
                    ),
                  if (_ed.blocks.isEmpty && !_ed.readOnly)
                    Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Começar com',
                            style: AppText.mono(12, letterSpacing: 0),
                          ),
                          for (final (label, type) in const [
                            ('Texto', BlockType.paragraph),
                            ('Título', BlockType.heading),
                            ('Checklist', BlockType.checklist),
                            ('Tabela', BlockType.table),
                            ('Código', BlockType.code),
                          ])
                            RingInkWell(
                              borderRadius: BorderRadius.circular(99),
                              onTap: () {
                                final b = _ed.insert(type);
                                if (b != null &&
                                    (isTextType(b.type) ||
                                        b.type == BlockType.code)) {
                                  _requestFocus(b.id);
                                }
                              },
                              child: Container(
                                height: 36,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(99),
                                  border: Border.all(
                                    color: AppColors.fieldBorder,
                                  ),
                                ),
                                child: Center(
                                  widthFactor: 1,
                                  child: Text(
                                    label,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          itemCount: _ed.blocks.length,
          onReorderItem: (from, to) => _ed.move(from, to > from ? to + 1 : to),
          itemBuilder: (_, i) => block(i),
        );

        final propsPanel = _panelBox('Propriedades', PageProps(ed: _ed));
        final sidePanel = _panelBox(
          'Painel',
          SidePanel(
            ed: _ed,
            onJump: _jump,
            onOpen: _openPage,
            onDuplicate: _duplicate,
          ),
        );

        final header = _zen
            ? null
            : Container(
                padding: EdgeInsets.symmetric(
                  horizontal: width >= 768 ? 32 : (width >= 400 ? 16 : 8),
                  vertical: 12,
                ),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.border)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          RingInkWell(
                            borderRadius: BorderRadius.circular(fieldRadius),
                            onTap: () => Navigator.of(context).maybePop(),
                            child: Semantics(
                              button: true,
                              label: 'Voltar ao dashboard',
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 10,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      '←',
                                      style: TextStyle(
                                        color: AppColors.accentText,
                                        fontSize: 15,
                                      ),
                                    ),
                                    if (width >= 400) ...[
                                      const SizedBox(width: 8),
                                      const Flexible(
                                        child: Text(
                                          'Dashboard',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: AppColors.accentText,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (width >= 768)
                            Expanded(
                              child: Row(
                                children: [
                                  if (place != null) ...[
                                    const Text(
                                      ' / ',
                                      style: TextStyle(
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                    Flexible(
                                      child: Text(
                                        place,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: AppColors.textMuted,
                                        ),
                                      ),
                                    ),
                                  ],
                                  const Text(
                                    ' / ',
                                    style: TextStyle(
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                  Flexible(
                                    child: Text(
                                      '${page.icon} ${page.title.isEmpty ? 'Sem título' : page.title}'
                                          .trim(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  if (width >= 1000)
                                    Flexible(
                                      child: Text(
                                        'editada ${ago(page.updated)}',
                                        key: const Key('crumb-edited'),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppText.mono(
                                          12,
                                          letterSpacing: 0,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (compact) ...[
                      ExportMenu(ed: _ed, compact: true, onDone: _toast),
                      PopupMenuButton<VoidCallback>(
                        tooltip: 'Mais opções da página',
                        color: AppColors.surface,
                        icon: const Icon(
                          Icons.more_horiz,
                          color: AppColors.textMuted,
                        ),
                        onSelected: (run) => run(),
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: () => _setZen(true),
                            child: const Text('Modo zen'),
                          ),
                          PopupMenuItem(
                            value: () => setState(() => _propsDrawer = true),
                            child: const Text('Propriedades'),
                          ),
                          PopupMenuItem(
                            value: () => setState(() => _panelDrawer = true),
                            child: const Text('Painel'),
                          ),
                          PopupMenuItem(
                            value: _delete,
                            child: Text(
                              page.trashed
                                  ? 'Excluir definitivamente'
                                  : 'Excluir página',
                              style: const TextStyle(
                                color: AppColors.offlineText,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      _HeaderButton(
                        icon: Icons.fullscreen,
                        label: 'Zen',
                        tooltip: 'Modo zen',
                        showLabel: width >= 1100,
                        onTap: () => _setZen(true),
                      ),
                      if (!roomForArrows) ...[
                        _HeaderButton(
                          icon: Icons.description_outlined,
                          label: '',
                          tooltip: 'Propriedades da página',
                          showLabel: false,
                          onTap: () => setState(() => _propsDrawer = true),
                        ),
                        _HeaderButton(
                          icon: Icons.view_sidebar_outlined,
                          label: '',
                          tooltip: 'Painel da página',
                          showLabel: false,
                          onTap: () => setState(() => _panelDrawer = true),
                        ),
                      ],
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: ExportMenu(
                          ed: _ed,
                          compact: width < 1100,
                          onDone: _toast,
                        ),
                      ),
                      _HeaderButton(
                        icon: Icons.delete_outline,
                        label: 'Excluir',
                        tooltip: page.trashed
                            ? 'Excluir página definitivamente'
                            : 'Excluir página',
                        showLabel: width >= 1100,
                        danger: true,
                        onTap: _delete,
                      ),
                    ],
                    const SizedBox(width: 8),
                    Semantics(
                      liveRegion: true,
                      child: Row(
                        children: [
                          if (width >= 1000)
                            Text(
                              _ed.saving
                                  ? 'salvando…'
                                  : 'salvo automaticamente',
                              style: AppText.mono(12, letterSpacing: 0),
                            ),
                          const SizedBox(width: 8),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _ed.saving
                                  ? AppColors.tagGold
                                  : AppColors.accentBorder,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );

        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                _zen ? _setZen(false) : null,
          },
          child: Focus(
            focusNode: _pageNode,
            autofocus: true,
            child: Scaffold(
              backgroundColor: AppColors.background,
              body: Stack(
                children: [
                  SafeArea(
                    child: Column(
                      children: [
                        ?header,
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, box) {
                              final scale = dockScale(width);
                              // a dock keeps its own size and grows as a whole (the web's `zoom`): laid out unscaled, drawn scaled
                              Widget dock({
                                required bool left,
                                required Widget child,
                              }) {
                                final inner = dockRailWidth + dockPanelWidth;
                                return SizedBox(
                                  width: inner * scale,
                                  height: box.maxHeight,
                                  child: OverflowBox(
                                    alignment: left
                                        ? Alignment.topLeft
                                        : Alignment.topRight,
                                    minWidth: inner,
                                    maxWidth: inner,
                                    minHeight: box.maxHeight / scale,
                                    maxHeight: box.maxHeight / scale,
                                    child: Transform.scale(
                                      scale: scale,
                                      alignment: left
                                          ? Alignment.topLeft
                                          : Alignment.topRight,
                                      child: SizedBox(
                                        width: inner,
                                        height: box.maxHeight / scale,
                                        child: child,
                                      ),
                                    ),
                                  ),
                                );
                              }

                              return Stack(
                                children: [
                                  Positioned.fill(
                                    child: Entrance(
                                      kind: EntranceKind.fade,
                                      child: list,
                                    ),
                                  ),
                                  if (!_zen && docked) ...[
                                    Positioned(
                                      left: 0,
                                      top: 0,
                                      bottom: 0,
                                      child: dock(
                                        left: true,
                                        child: Row(
                                          // the strip hugs the edge of the window even when the panel is closed and the row is shorter than the dock
                                          mainAxisAlignment:
                                              MainAxisAlignment.start,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            SizedBox(
                                              width: dockRailWidth,
                                              child: Center(
                                                child: DockToggle(
                                                  left: true,
                                                  open: propsOpen,
                                                  label: propsOpen
                                                      ? 'Fechar propriedades'
                                                      : 'Abrir propriedades',
                                                  onTap: () => setState(
                                                    () =>
                                                        _propsDock = !propsOpen,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            if (propsOpen)
                                              Entrance(
                                                key: const ValueKey('props-in'),
                                                kind:
                                                    EntranceKind.slideFromLeft,
                                                child: propsPanel,
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      right: 0,
                                      top: 0,
                                      bottom: 0,
                                      child: dock(
                                        left: false,
                                        child: Row(
                                          // the strip hugs the edge of the window even when the panel is closed and the row is shorter than the dock
                                          mainAxisAlignment:
                                              MainAxisAlignment.end,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            if (panelOpen)
                                              Entrance(
                                                key: const ValueKey('panel-in'),
                                                kind:
                                                    EntranceKind.slideFromRight,
                                                child: sidePanel,
                                              ),
                                            SizedBox(
                                              width: dockRailWidth,
                                              child: Center(
                                                child: DockToggle(
                                                  left: false,
                                                  open: panelOpen,
                                                  label: panelOpen
                                                      ? 'Fechar painel'
                                                      : 'Abrir painel',
                                                  onTap: () => setState(
                                                    () =>
                                                        _panelDock = !panelOpen,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (_zen)
                                    Positioned(
                                      top: 16,
                                      right: 16,
                                      child: _ZenPill(
                                        words: _ed.stats.words,
                                        saving: _ed.saving,
                                        onExit: () => _setZen(false),
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  ..._drawers(width, docked, roomForArrows),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.showLabel,
    required this.onTap,
    this.danger = false,
  });
  final IconData icon;
  final String label, tooltip;
  final bool showLabel, danger;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.offlineText : AppColors.textMuted;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          label: tooltip,
          child: RingInkWell(
            borderRadius: BorderRadius.circular(fieldRadius),
            onTap: onTap,
            child: Container(
              height: 40,
              padding: EdgeInsets.symmetric(horizontal: showLabel ? 12 : 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(fieldRadius),
                border: Border.all(
                  color: showLabel
                      ? (danger
                            ? AppColors.offline.withValues(alpha: 0.5)
                            : AppColors.border)
                      : Colors.transparent,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: color),
                  if (showLabel) ...[
                    const SizedBox(width: 8),
                    Text(label, style: TextStyle(fontSize: 14, color: color)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The words and the save light in zen mode, with the way out: faint until the pointer comes near (as on the web).
class _ZenPill extends StatefulWidget {
  const _ZenPill({
    required this.words,
    required this.saving,
    required this.onExit,
  });
  final int words;
  final bool saving;
  final VoidCallback onExit;
  @override
  State<_ZenPill> createState() => _ZenPillState();
}

class _ZenPillState extends State<_ZenPill> {
  var _near = false;

  @override
  Widget build(BuildContext context) => Entrance(
    kind: EntranceKind.fade,
    child: MouseRegion(
      onEnter: (_) => setState(() => _near = true),
      onExit: (_) => setState(() => _near = false),
      child: AnimatedOpacity(
        opacity: _near ? 1 : 0.6,
        duration: const Duration(milliseconds: 200),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                liveRegion: true,
                child: Text(
                  '${widget.words} ${widget.words == 1 ? 'palavra' : 'palavras'}',
                  key: const Key('zen-words'),
                  style: AppText.mono(12, letterSpacing: 0),
                ),
              ),
              const SizedBox(width: 12),
              Semantics(
                label: widget.saving ? 'salvando…' : 'salvo automaticamente',
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: widget.saving
                        ? AppColors.tagGold
                        : AppColors.accentBorder,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              RingInkWell(
                borderRadius: BorderRadius.circular(99),
                onTap: widget.onExit,
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: AppColors.fieldBorder),
                  ),
                  child: Center(
                    widthFactor: 1,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Sair do zen',
                          style: TextStyle(fontSize: 12, color: AppColors.text),
                        ),
                        const SizedBox(width: 6),
                        Text('Esc', style: AppText.mono(12, letterSpacing: 0)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
