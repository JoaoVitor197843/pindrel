import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/note_page.dart';
import '../../data/text.dart';
import '../../data/workspace.dart';
import 'tag_style.dart';
import 'ui.dart';

/// One page in the grid or the list, laid out like the web's card. The whole card opens the page (a trashed one cannot
/// be opened). Pin and trash are always visible: a phone or tablet has no hover, and a touch screen can sit on a
/// desktop too, so nothing may depend on it.
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
        list ? 18 : 20,
      ).copyWith(fontWeight: FontWeight.w600, height: 1.3),
      AppText.serif(list ? 18 : 20).copyWith(
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

  // The padding is the web's `p-5` (20), except on the right (12): the pin and the trash are 36 px buttons pulled toward the
  // edge like the web's `-mr-2`, and a widget cannot be tapped outside its parent's bounds, so the room is made by the
  // padding and the text blocks give the other 8 back with their own.
  Widget _card(List<InlineSpan> title) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              // a long title goes down a line instead of being cut (the web's `wrap-anywhere`)
              child: Padding(
                padding: const EdgeInsets.only(top: 6, right: 8),
                child: Text.rich(TextSpan(children: title)),
              ),
            ),
            _lock(),
            _pin(),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 2),
              // three lines of room whatever the text, so the cards of a row keep one size (the web's `line-clamp-3 min-h-[3lh]`)
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 14 * 1.625 * 3),
                child: Text(
                  _excerpt,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.625,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 28),
                child: _chips(),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1, thickness: 1, color: AppColors.border),
            ],
          ),
        ),
        // the 36 px footer row is the web's 20 px line with its `-my-2` button
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: SizedBox(
            height: 36,
            child: Row(
              children: [
                // Expanded, not Flexible + Spacer: those split the free space and leave half of it empty at the end
                Expanded(
                  child: Text(
                    formatDate(page.updated),
                    overflow: TextOverflow.ellipsis,
                    style: AppText.mono(12, letterSpacing: 0),
                  ),
                ),
                Text(pageMeta(page), style: AppText.mono(12, letterSpacing: 0)),
                _trash(),
              ],
            ),
          ),
        ),
        if (page.trashed)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8, right: 8),
            child: _restore(),
          ),
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
