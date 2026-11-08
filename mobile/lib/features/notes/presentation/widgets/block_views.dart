import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/blocks.dart';
import '../../data/page_editor.dart';
import 'block_fields.dart';
import 'ui.dart';

/// Turns the text typed in an empty paragraph, such as "# " or "- ", into the block it announces.
bool markdownShortcut(PageEditor ed, Block b, String text) {
  if (b.type != BlockType.paragraph) return false;
  final m = RegExp(r'^(#{1,3}|[-*+]|\d{1,3}[.)]|>) $').firstMatch(text);
  if (m == null) return false;
  final mark = m.group(1)!;
  final done = mark.startsWith('#')
      ? ed.turnInto(b.id, BlockType.heading, level: mark.length)
      : mark == '>'
          ? ed.turnInto(b.id, BlockType.quote)
          : RegExp(r'\d').hasMatch(mark[0])
              ? ed.turnInto(b.id, BlockType.numbered)
              : ed.turnInto(b.id, BlockType.bullet);
  if (done) ed.setText(b.id, '');
  return done;
}

typedef FocusRequest = void Function(String blockId, {bool atStart});

/// Everything a block needs from its page.
class BlockContext {
  const BlockContext({required this.ed, required this.numbers, required this.focusFor, required this.requestFocus, required this.openSlash, required this.openPage, required this.jump});
  final PageEditor ed;
  final Map<String, int> numbers;
  final FocusNode Function(String blockId) focusFor;
  final FocusRequest requestFocus;
  final void Function(String blockId) openSlash;
  final void Function(String pageId) openPage;

  /// Scrolls the page to a block (the table of contents).
  final void Function(String blockId) jump;
}

const _bodySize = 16.5;
TextStyle _body([Color? c, FontWeight? w]) => TextStyle(fontSize: _bodySize, height: 1.68, color: c ?? AppColors.text.withValues(alpha: 0.9), fontWeight: w);

/// The editable content of one block (no handle, no menu).
class BlockBody extends StatelessWidget {
  const BlockBody({super.key, required this.block, required this.cx});
  final Block block;
  final BlockContext cx;

  PageEditor get ed => cx.ed;

  /// Text typed into a text block: "/" opens the menu, a newline splits.
  void _typed(String text) {
    final b = block;
    if (text == '/' && b.type == BlockType.paragraph) {
      ed.setText(b.id, '');
      cx.openSlash(b.id);
      return;
    }
    if (markdownShortcut(ed, b, text)) {
      cx.requestFocus(b.id);
      return;
    }
    final nl = text.indexOf('\n');
    const splits = {BlockType.paragraph, BlockType.heading, BlockType.quote, BlockType.callout, BlockType.bullet, BlockType.numbered};
    if (nl >= 0 && splits.contains(b.type)) {
      final isItem = b.type == BlockType.bullet || b.type == BlockType.numbered;
      if (isItem && text.replaceAll('\n', '').isEmpty) {
        ed.setText(b.id, '');
        if (ed.leaveList(b.id)) cx.requestFocus(b.id);
        return;
      }
      final made = ed.splitText(b.id, text.substring(0, nl), text.substring(nl + 1).replaceAll('\n', ''));
      if (made != null) cx.requestFocus(made.id, atStart: true);
      return;
    }
    ed.setText(b.id, text);
  }

  void _backspaceEmpty() {
    final b = block;
    final isItem = b.type == BlockType.bullet || b.type == BlockType.numbered;
    if (isItem) {
      if (ed.leaveList(b.id)) cx.requestFocus(b.id);
    } else if (const {BlockType.paragraph, BlockType.quote, BlockType.callout}.contains(b.type)) {
      final i = ed.blocks.indexWhere((x) => x.id == b.id);
      ed.remove(b.id);
      if (i > 0) cx.requestFocus(ed.blocks[i - 1].id);
    }
  }

  Widget _text(String hint, TextStyle style, {bool back = true}) => SyncedField(
        key: ValueKey('f-${block.id}'),
        value: block.text ?? '',
        hint: hint,
        style: style,
        focusNode: cx.focusFor(block.id),
        readOnly: ed.readOnly,
        onChanged: _typed,
        onBackspaceEmpty: back ? _backspaceEmpty : null,
      );

  @override
  Widget build(BuildContext context) {
    final b = block;
    switch (b.type) {
      case BlockType.paragraph:
        return _text('', _body());
      case BlockType.heading:
        final (size, h) = switch (b.level ?? 2) { 1 => (30.0, 1.25), 3 => (20.0, 1.4), _ => (24.0, 1.35) };
        final title = _text('Título', AppText.serif(size).copyWith(fontWeight: FontWeight.w600, height: h));
        return b.toggle ? _ToggleBody(block: b, cx: cx, title: title) : title;
      case BlockType.quote:
        return Container(
          padding: const EdgeInsets.only(left: 16),
          decoration: const BoxDecoration(border: Border(left: BorderSide(color: AppColors.accentBorder, width: 2))),
          child: _text('Citação', AppText.serif(18).copyWith(fontStyle: FontStyle.italic, height: 1.6, color: AppColors.text.withValues(alpha: 0.85))),
        );
      case BlockType.callout:
        final tone = b.tone ?? CalloutTone.info;
        final c = _toneColor(tone);
        return Stack(children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(48, 12, 16, 12),
            decoration: BoxDecoration(color: tone == CalloutTone.info ? AppColors.surface : c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(fieldRadius), border: Border.all(color: tone == CalloutTone.info ? AppColors.border : c.withValues(alpha: 0.5))),
            child: _text('Destaque', const TextStyle(fontSize: 16, height: 1.6, color: AppColors.text)),
          ),
          Positioned(left: 16, top: 12, child: Text(toneLabels[tone]!.$2, style: const TextStyle(fontSize: 18))),
        ]);
      case BlockType.bullet:
      case BlockType.numbered:
        const bullets = ['•', '◦', '▪'];
        final ind = b.indent ?? 0;
        return Padding(
          padding: EdgeInsets.only(left: 28.0 * ind),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 28, child: Padding(padding: const EdgeInsets.only(right: 8), child: Text(b.type == BlockType.bullet ? bullets[ind % 3] : '${cx.numbers[b.id] ?? 1}.', textAlign: TextAlign.right, style: _body(AppColors.textMuted)))),
            Expanded(child: _text('Item da lista', _body())),
          ]),
        );
      case BlockType.toggle:
        return _ToggleBody(block: b, cx: cx, title: _text('Título do toggle', _body(null, FontWeight.w500)));
      case BlockType.divider:
        return const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(color: AppColors.border, height: 1));
      case BlockType.checklist:
        return _Checklist(block: b, cx: cx);
      case BlockType.code:
        return _Code(block: b, cx: cx);
      case BlockType.spoiler:
        return _Spoiler(block: b, cx: cx);
      case BlockType.secure:
        return _SecureBlock(block: b);
      case BlockType.table:
        return _Table(block: b, cx: cx);
      case BlockType.toc:
        return _Toc(cx: cx);
      case BlockType.bookmark:
      case BlockType.video:
      case BlockType.audio:
      case BlockType.pdf:
        return _UrlCard(block: b, cx: cx);
      case BlockType.pagelink:
        return _PageLink(block: b, cx: cx);
      case BlockType.file:
        return _Card(icon: Icons.attach_file, title: (b.name ?? '').isEmpty ? 'Arquivo' : b.name!, subtitle: 'O envio de arquivos chega em breve');
      case BlockType.image:
        return _Card(icon: Icons.image_outlined, title: (b.name ?? '').isEmpty ? 'Imagem' : b.name!, subtitle: 'O envio de imagens chega em breve');
    }
  }
}

Color _toneColor(CalloutTone t) => switch (t) {
      CalloutTone.info => AppColors.tagBlue,
      CalloutTone.success => AppColors.tagTeal,
      CalloutTone.warning => AppColors.tagGold,
      CalloutTone.danger => AppColors.tagRust,
    };

class _Card extends StatelessWidget {
  const _Card({required this.icon, required this.title, this.subtitle, this.onTap, this.trailing});
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: Ink(
          decoration: cardBox(color: Colors.transparent),
          child: RingInkWell(
            borderRadius: BorderRadius.circular(fieldRadius),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(children: [
                Icon(icon, color: AppColors.textMuted, size: 18),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                  if (subtitle != null) Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.mono(12, letterSpacing: 0)),
                ])),
                ?trailing,
              ]),
            ),
          ),
        ),
      );
}

class _ToggleBody extends StatefulWidget {
  const _ToggleBody({required this.block, required this.cx, required this.title});
  final Block block;
  final BlockContext cx;
  final Widget title;
  @override
  State<_ToggleBody> createState() => _ToggleBodyState();
}

class _ToggleBodyState extends State<_ToggleBody> {
  var _open = false;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Tooltip(
              message: _open ? 'Fechar' : 'Abrir',
              child: RingInkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () => setState(() => _open = !_open),
                child: SizedBox(width: 28, height: 28, child: AnimatedRotation(turns: _open ? 0.25 : 0, duration: const Duration(milliseconds: 150), child: const Center(child: Text('▸', style: TextStyle(fontSize: 14, color: AppColors.textMuted))))),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(child: widget.title),
        ]),
        if (_open)
          Padding(
            padding: const EdgeInsets.only(left: 36, top: 4),
            child: Container(
              padding: const EdgeInsets.only(left: 16),
              decoration: const BoxDecoration(border: Border(left: BorderSide(color: AppColors.border))),
              child: SyncedField(key: ValueKey('body-${widget.block.id}'), value: widget.block.body ?? '', hint: 'Conteúdo', style: _body(AppColors.text.withValues(alpha: 0.85)).copyWith(fontSize: 16, height: 1.65), readOnly: widget.cx.ed.readOnly, onChanged: (t) => widget.cx.ed.setBody(widget.block.id, t)),
            ),
          ),
      ]);
}

class _Checklist extends StatelessWidget {
  const _Checklist({required this.block, required this.cx});
  final Block block;
  final BlockContext cx;
  @override
  Widget build(BuildContext context) {
    final ed = cx.ed;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final it in block.items!)
        Padding(
          key: ValueKey(it.id),
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Semantics(
                checked: it.done,
                child: RingInkWell(
                  borderRadius: BorderRadius.circular(5),
                  onTap: ed.readOnly ? null : () => ed.toggleItem(block.id, it.id),
                  child: Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: it.done ? AppColors.accent : null, borderRadius: BorderRadius.circular(5), border: Border.all(color: it.done ? AppColors.accentBorder : AppColors.fieldBorder)),
                    child: it.done ? const Text('✓', style: TextStyle(fontSize: 13, height: 1)) : null,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SyncedField(
                value: it.text,
                hint: 'Tarefa',
                style: _body(it.done ? AppColors.textMuted : AppColors.text.withValues(alpha: 0.9)).copyWith(decoration: it.done ? TextDecoration.lineThrough : null),
                readOnly: ed.readOnly,
                onChanged: (t) {
                  if (t.contains('\n')) {
                    ed.setItemText(block.id, it.id, t.replaceAll('\n', ''));
                    ed.addItem(block.id, it.id);
                  } else {
                    ed.setItemText(block.id, it.id, t);
                  }
                },
              ),
            ),
            if (!ed.readOnly) GhostIconButton(icon: Icons.close, tooltip: 'Remover item', size: 28, iconSize: 14, onPressed: () => ed.removeItem(block.id, it.id)),
          ]),
        ),
      if (!ed.readOnly)
        Align(alignment: Alignment.centerLeft, child: RingInkWell(onTap: () => ed.addItem(block.id), borderRadius: BorderRadius.circular(fieldRadius), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6), child: Text('+ Item', style: AppText.mono(12, letterSpacing: 0))))),
    ]);
  }
}

class _Code extends StatelessWidget {
  const _Code({required this.block, required this.cx});
  final Block block;
  final BlockContext cx;
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(fieldRadius),
        child: Container(
          decoration: BoxDecoration(color: AppColors.background.withValues(alpha: 0.6), border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(fieldRadius)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
              child: Align(
                alignment: Alignment.centerLeft,
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: languages.contains(block.lang) ? block.lang : 'texto',
                  isDense: true,
                  underline: const SizedBox.shrink(),
                  dropdownColor: AppColors.surface,
                  iconSize: 18,
                  style: AppText.mono(11, letterSpacing: 0.9),
                  items: [for (final l in languages) DropdownMenuItem(value: l, child: Text(l.toUpperCase()))],
                  onChanged: cx.ed.readOnly ? null : (l) => cx.ed.setLang(block.id, l ?? 'texto'),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: SyncedField(
                value: block.text ?? '',
                hint: 'Código',
                codeLang: languages.contains(block.lang) ? block.lang : 'texto',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13.5, height: 1.7, color: AppColors.text),
                readOnly: cx.ed.readOnly,
                onChanged: (t) => cx.ed.setText(block.id, t),
              ),
            ),
          ]),
        ),
      );
}

class _Spoiler extends StatelessWidget {
  const _Spoiler({required this.block, required this.cx});
  final Block block;
  final BlockContext cx;
  @override
  Widget build(BuildContext context) {
    final open = cx.ed.revealed.contains(block.id);
    if (!open) {
      return Semantics(
        button: true,
        label: 'Revelar spoiler',
        child: RingInkWell(
          borderRadius: BorderRadius.circular(fieldRadius),
          onTap: () => cx.ed.reveal(block.id, true),
          child: DashedBorder(
            color: AppColors.fieldBorder,
            child: StripedBox(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                child: Row(children: [
                  Flexible(child: Text('Clique para revelar', maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.mono(12, letterSpacing: 0.7))),
                  const SizedBox(width: 12),
                  Text('SPOILER', style: AppText.mono(10.5, letterSpacing: 0.8)),
                ]),
              ),
            ),
          ),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('SPOILER', style: AppText.mono(10, letterSpacing: 1)),
        const SizedBox(width: 8),
        RingInkWell(onTap: () => cx.ed.reveal(block.id, false), child: Text('ocultar', style: AppText.mono(10, letterSpacing: 1).copyWith(decoration: TextDecoration.underline))),
      ]),
      SyncedField(value: block.text ?? '', hint: 'Spoiler', style: _body(), readOnly: cx.ed.readOnly, onChanged: (t) => cx.ed.setText(block.id, t)),
    ]);
  }
}

/// A secret is kept but never drawn: it opens with the vault password, which this device cannot ask for yet.
class _SecureBlock extends StatelessWidget {
  const _SecureBlock({required this.block});
  final Block block;
  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(padding: EdgeInsets.only(top: 4, right: 12), child: Icon(Icons.lock_outline, size: 16, color: AppColors.textMuted)),
        Expanded(child: Align(alignment: Alignment.centerLeft, child: Semantics(label: 'Ver bloco seguro', button: true, child: OutlineTextButton(label: 'Ver', height: 40, onPressed: () => showDialog<void>(
              context: context,
              builder: (c) => AlertDialog(
                backgroundColor: AppColors.surface,
                title: Text('Bloco seguro', style: AppText.serif(20)),
                content: const Text('O cofre ainda não está pronto neste aparelho. O texto fica guardado e nunca é mostrado sem a senha mestra.'),
                actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Entendi'))],
              ),
            ))))),
      ]);
}

class _Table extends StatelessWidget {
  const _Table({required this.block, required this.cx});
  final Block block;
  final BlockContext cx;
  @override
  Widget build(BuildContext context) {
    final ed = cx.ed;
    final cols = block.cols!;
    Widget handle(String tip, List<PopupMenuEntry<VoidCallback>> items) => PopupMenuButton<VoidCallback>(
          tooltip: tip,
          color: AppColors.surface,
          padding: EdgeInsets.zero,
          onSelected: (run) => run(),
          itemBuilder: (_) => items,
          child: const SizedBox(width: 22, height: 28, child: Center(child: Text('⠿', style: TextStyle(fontSize: 14, color: AppColors.textMuted)))),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(children: [
          Row(children: [
            const SizedBox(width: 22),
            for (final c in cols)
              Container(
                key: ValueKey('h-${c.id}'),
                width: c.w.toDouble(),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
                child: Row(children: [
                  if (!ed.readOnly)
                    handle('Coluna ${c.label}', [
                      PopupMenuItem(value: () => ed.moveCol(block.id, cols.indexOf(c), cols.indexOf(c) - 1), child: const Text('Mover para a esquerda')),
                      PopupMenuItem(value: () => ed.moveCol(block.id, cols.indexOf(c), cols.indexOf(c) + 2), child: const Text('Mover para a direita')),
                      PopupMenuItem(value: () => ed.resizeCol(block.id, c.id, c.w + 40), child: const Text('Alargar')),
                      PopupMenuItem(value: () => ed.resizeCol(block.id, c.id, c.w - 40), child: const Text('Estreitar')),
                    ]),
                  Expanded(child: SyncedField(value: c.label, hint: 'Coluna', maxLength: 80, readOnly: ed.readOnly, multiline: false, style: AppText.mono(12, color: AppColors.textMuted, letterSpacing: 1.2), onChanged: (t) => ed.setLabel(block.id, c.id, t))),
                  if (!ed.readOnly) GhostIconButton(icon: Icons.close, tooltip: 'Remover coluna ${c.label}', size: 24, iconSize: 12, onPressed: () => ed.removeCol(block.id, c.id)),
                ]),
              ),
          ]),
          for (var r = 0; r < block.rows!.length; r++)
            Row(children: [
              SizedBox(
                width: 22,
                child: ed.readOnly
                    ? null
                    : handle('Linha ${r + 1}', [
                        PopupMenuItem(value: () => ed.moveRow(block.id, r, r - 1), child: const Text('Subir')),
                        PopupMenuItem(value: () => ed.moveRow(block.id, r, r + 2), child: const Text('Descer')),
                        PopupMenuItem(value: () => ed.removeRow(block.id, r), child: const Text('Remover linha')),
                      ]),
              ),
              for (final c in cols)
                Container(
                  key: ValueKey('c-$r-${c.id}'),
                  width: c.w.toDouble(),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
                  child: SyncedField(value: block.rows![r][c.id] ?? '', maxLength: 2000, readOnly: ed.readOnly, style: const TextStyle(fontSize: 16, height: 1.5), onChanged: (t) => ed.setCell(block.id, r, c.id, t)),
                ),
            ]),
        ]),
      ),
      if (!ed.readOnly)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(spacing: 8, children: [
            RingInkWell(onTap: () => ed.addRow(block.id), child: Padding(padding: const EdgeInsets.all(6), child: Text('+ linha', style: AppText.mono(12, letterSpacing: 0)))),
            RingInkWell(onTap: () => ed.addCol(block.id), child: Padding(padding: const EdgeInsets.all(6), child: Text('+ coluna', style: AppText.mono(12, letterSpacing: 0)))),
          ]),
        ),
    ]);
  }
}

class _Toc extends StatelessWidget {
  const _Toc({required this.cx});
  final BlockContext cx;
  @override
  Widget build(BuildContext context) {
    final items = outline(cx.ed.blocks);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: cardBox(color: Colors.transparent),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('SUMÁRIO', style: monoLabel(size: 10, spacing: 1.4)),
        const SizedBox(height: 6),
        if (items.isEmpty) const Text('Os títulos de seção aparecem aqui.', style: TextStyle(fontSize: 14, color: AppColors.textMuted)),
        for (final h in items)
          RingInkWell(
            onTap: () => cx.jump(h.id),
            child: Padding(padding: EdgeInsets.only(left: 14.0 * (h.level - 1), top: 4, bottom: 4), child: Text(h.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: AppColors.text.withValues(alpha: 0.85)))),
          ),
      ]),
    );
  }
}

class _UrlCard extends StatelessWidget {
  const _UrlCard({required this.block, required this.cx});
  final Block block;
  final BlockContext cx;

  static const _icons = {BlockType.bookmark: Icons.link, BlockType.video: Icons.movie_outlined, BlockType.audio: Icons.audiotrack_outlined, BlockType.pdf: Icons.picture_as_pdf_outlined};
  static const _names = {BlockType.bookmark: 'Link', BlockType.video: 'Vídeo', BlockType.audio: 'Áudio', BlockType.pdf: 'PDF'};

  Future<void> _edit(BuildContext context) async {
    final url = TextEditingController(text: block.url);
    final title = TextEditingController(text: block.title);
    String? error;
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(_names[block.type]!, style: AppText.serif(20)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: url, autofocus: true, keyboardType: TextInputType.url, decoration: InputDecoration(hintText: 'Endereço (https://…)', errorText: error)),
            const SizedBox(height: 10),
            TextField(controller: title, decoration: const InputDecoration(hintText: 'Título (opcional)')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                if (cx.ed.setUrl(block.id, url.text, title.text)) {
                  Navigator.pop(c);
                } else {
                  set(() => error = block.type == BlockType.bookmark ? 'Endereço inválido' : 'Use um endereço http ou https');
                }
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final has = (block.url ?? '').isNotEmpty;
    if (!has && block.type == BlockType.bookmark) {
      return _Card(icon: Icons.link, title: 'Link sem endereço', subtitle: cx.ed.readOnly ? null : 'toque para definir', onTap: cx.ed.readOnly ? null : () => _edit(context));
    }
    final title = (block.title ?? '').isNotEmpty ? block.title! : (has ? Uri.tryParse(block.url!)?.host ?? block.url! : '${_names[block.type]} — toque para definir o endereço');
    return _Card(
      icon: _icons[block.type]!,
      title: title,
      subtitle: has ? block.url : null,
      onTap: cx.ed.readOnly ? null : () => _edit(context),
      trailing: has && !cx.ed.readOnly ? const Padding(padding: EdgeInsets.only(left: 8), child: Text('Editar', style: TextStyle(fontSize: 14, color: AppColors.textMuted))) : null,
    );
  }
}

class _PageLink extends StatelessWidget {
  const _PageLink({required this.block, required this.cx});
  final Block block;
  final BlockContext cx;

  Future<void> _pick(BuildContext context) async {
    final ed = cx.ed;
    final choices = [for (final p in ed.ws.live) if (p.id != ed.id && !p.locked) p];
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (c) => choices.isEmpty
          ? const Padding(padding: EdgeInsets.all(32), child: Text('Não há outras páginas.'))
          : ListView.builder(itemCount: choices.length, itemBuilder: (_, i) => ListTile(title: Text('${choices[i].icon} ${choices[i].title}'.trim()), onTap: () => Navigator.pop(c, choices[i].id))),
    );
    if (picked != null) ed.setPageLink(block.id, picked);
  }

  @override
  Widget build(BuildContext context) {
    final ed = cx.ed;
    final target = ed.ws.page(block.pageId ?? '');
    final usable = target != null && !target.trashed && !target.locked;
    final title = usable
        ? '${target.icon.isEmpty ? '' : '${target.icon} '}${target.title}'
        : (target?.locked ?? false)
            ? 'Página do cofre'
            : (target?.trashed ?? false)
                ? 'Página na lixeira'
                : (block.pageId ?? '').isEmpty
                    ? 'Escolha uma página'
                    : 'Página não encontrada';
    return _Card(
      icon: Icons.description_outlined,
      title: title,
      subtitle: usable ? 'Abrir página' : null,
      onTap: usable ? () => cx.openPage(block.pageId!) : (ed.readOnly ? null : () => _pick(context)),
      trailing: usable && !ed.readOnly ? GhostIconButton(icon: Icons.swap_horiz, tooltip: 'Trocar de página', size: 32, iconSize: 18, onPressed: () => _pick(context)) : null,
    );
  }
}
