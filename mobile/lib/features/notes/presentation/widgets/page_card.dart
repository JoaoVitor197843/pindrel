import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/note_page.dart';
import '../../data/text.dart';
import '../../data/workspace.dart';
import 'tag_style.dart';
import 'ui.dart';

/// One page in the grid or the list. The whole card opens the page (a trashed one cannot be opened); pin and trash are
/// always visible, there being no hover on a phone.
class PageCard extends StatelessWidget {
  const PageCard({
    super.key,
    required this.page,
    required this.tags,
    this.list = false,
    this.query = '',
    this.onOpen,
    this.onPin,
    this.onTrash,
    this.onRestore,
  });

  final NotePage page;
  final List<Tag> tags;
  final bool list;
  final String query;
  final VoidCallback? onOpen, onPin, onTrash, onRestore;

  String get _title => (page.icon.isEmpty ? '' : '${page.icon} ') + page.title;
  String get _excerpt => page.locked
      ? 'Conteúdo protegido. Desbloqueie o Cofre para visualizar esta página.'
      : (page.excerpt.isEmpty
            ? 'Página vazia. Comece a escrever.'
            : page.excerpt);

  Widget _chips() => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final id in page.tags)
        if (tags.where((t) => t.id == id).firstOrNull case final t?)
          TagPill(name: t.name, color: tagColor(t.color)),
    ],
  );

  Widget _pin() => page.trashed
      ? const SizedBox.shrink()
      : GhostIconButton(
          icon: page.pinned ? Icons.push_pin : Icons.push_pin_outlined,
          tooltip: '${page.pinned ? 'Desafixar' : 'Fixar'} ${page.title}',
          color: page.pinned ? AppColors.accentText : AppColors.textMuted,
          onPressed: onPin,
        );

  Widget _trash() => page.trashed
      ? const SizedBox.shrink()
      : GhostIconButton(
          icon: Icons.delete_outline,
          tooltip: 'Mover ${page.title} para a lixeira',
          onPressed: onTrash,
        );

  Widget _restore() => page.trashed
      ? Semantics(
          label: 'Restaurar ${page.title}',
          button: true,
          child: OutlineTextButton(
            label: 'Restaurar',
            icon: Icons.restore,
            onPressed: onRestore,
          ),
        )
      : const SizedBox.shrink();

  Widget _lock() => page.locked
      ? const SizedBox(
          width: 36,
          height: 36,
          child: Icon(Icons.lock_outline, size: 16, color: AppColors.textMuted),
        )
      : const SizedBox.shrink();

  @override
  Widget build(BuildContext context) {
    final title = highlightSpans(
      _title,
      query,
      AppText.serif(
        list ? 17 : 18,
      ).copyWith(fontWeight: FontWeight.w600, height: 1.3),
      AppText.serif(list ? 17 : 18).copyWith(
        fontWeight: FontWeight.w600,
        height: 1.3,
        backgroundColor: AppColors.accent.withValues(alpha: 0.45),
      ),
    );
    final canOpen = onOpen != null && !page.trashed;
    return HoverBox(
      builder: (context, hover) => Semantics(
        container: true,
        label: _title,
        child: Material(
          color: Colors.transparent,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: cardBox(hover: hover && canOpen),
            child: RingInkWell(
              key: const Key('page-card'),
              borderRadius: BorderRadius.circular(fieldRadius),
              onTap: canOpen ? onOpen : null,
              child: list ? _row(title) : _card(title),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(List<InlineSpan> title) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(children: title),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                _excerpt,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        _lock(),
        _restore(),
        _pin(),
        _trash(),
      ],
    ),
  );

  Widget _card(List<InlineSpan> title) => Padding(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(children: title),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Transform.translate(
              offset: const Offset(8, -6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [_lock(), _pin()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _excerpt,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13,
            height: 1.5,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 24),
          child: _chips(),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.only(top: 4),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  formatDate(page.updated),
                  overflow: TextOverflow.ellipsis,
                  style: AppText.mono(12, letterSpacing: 0),
                ),
              ),
              const Spacer(),
              Text(pageMeta(page), style: AppText.mono(12, letterSpacing: 0)),
              const SizedBox(width: 4),
              _trash(),
            ],
          ),
        ),
        if (page.trashed)
          Padding(padding: const EdgeInsets.only(top: 12), child: _restore()),
      ],
    ),
  );
}

/// Splits [text] around every match of [query] (ignoring case and accents). Only a match that keeps the text the same
/// length once folded can be marked in place; otherwise the text is shown unmarked rather than marked wrong.
List<InlineSpan> highlightSpans(
  String text,
  String query,
  TextStyle base,
  TextStyle mark,
) {
  final q = foldKeepingLength(query.trim());
  if (q.isEmpty) return [TextSpan(text: text, style: base)];
  final f = foldKeepingLength(text);
  if (f.length != text.length) return [TextSpan(text: text, style: base)];
  final out = <InlineSpan>[];
  var at = 0;
  while (true) {
    final i = f.indexOf(q, at);
    if (i < 0) break;
    if (i > at) out.add(TextSpan(text: text.substring(at, i), style: base));
    out.add(TextSpan(text: text.substring(i, i + q.length), style: mark));
    at = i + q.length;
  }
  if (at < text.length) {
    out.add(TextSpan(text: text.substring(at), style: base));
  }
  return out;
}
