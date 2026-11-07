import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/cover_spec.dart';
import '../../data/emoji_data.dart';
import '../../data/links.dart';
import '../../data/note_page.dart';
import '../../data/page_editor.dart';
import 'motion.dart';
import 'tag_style.dart';
import 'ui.dart';

/// The gradient of a cover spec, or null when there is none (the colours are blended into the page background).
LinearGradient? coverGradient(String spec) {
  final s = coverStops(spec);
  if (s == null) return null;
  final a = s.degrees * math.pi / 180;
  final x = math.sin(a), y = -math.cos(a);
  return LinearGradient(
    begin: Alignment(-x, -y),
    end: Alignment(x, y),
    colors: [
      for (final (hex, pct) in s.stops)
        Color.lerp(AppColors.background, Color(0xFF000000 | hex), pct / 100)!,
    ],
  );
}

/// The page's maximum column and its side margins, as on the web (max-w-3xl, px-7 / md:px-20).
class Article extends StatelessWidget {
  const Article({
    super.key,
    required this.child,
    this.zen = false,
    this.leftGutter = 0,
  });
  final Widget child;
  final bool zen;

  /// Extra room on the left for the block controls, taken out of the margin so the text still starts at the same place.
  final double leftGutter;

  static double padFor(double width) => width >= 768 ? 80 : 28;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final pad = padFor(width);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: zen ? 672 : 768),
        child: Padding(
          padding: EdgeInsets.only(
            left: (pad - leftGutter).clamp(0, 200),
            right: pad,
          ),
          child: child,
        ),
      ),
    );
  }
}

class PageCoverBand extends StatelessWidget {
  const PageCoverBand({super.key, required this.ed});
  final PageEditor ed;

  @override
  Widget build(BuildContext context) {
    final spec = ed.page!.cover;
    final g = coverGradient(spec);
    if (g == null) return const SizedBox.shrink();
    final wide = MediaQuery.sizeOf(context).width >= 768;
    return Stack(
      children: [
        // keyed on the cover, so changing it fades the new one in
        Entrance(
          key: ValueKey(spec),
          kind: EntranceKind.fade,
          child: Container(
            key: const Key('cover'),
            height: wide ? 208 : 160,
            width: double.infinity,
            decoration: BoxDecoration(gradient: g),
          ),
        ),
        if (!ed.readOnly)
          Positioned.fill(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 768),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, wide ? 80 : 16, 12),
                  child: Align(
                    alignment: Alignment.bottomRight,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      alignment: WrapAlignment.end,
                      children: [
                        _CoverButton(
                          label: 'Trocar capa',
                          onTap: () => showCoverPicker(context, ed),
                        ),
                        _CoverButton(
                          label: 'Remover capa',
                          muted: true,
                          onTap: () => ed.setCover(''),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CoverButton extends StatelessWidget {
  const _CoverButton({
    required this.label,
    required this.onTap,
    this.muted = false,
  });
  final String label;
  final VoidCallback onTap;
  final bool muted;
  @override
  Widget build(BuildContext context) => RingInkWell(
    borderRadius: BorderRadius.circular(fieldRadius),
    onTap: onTap,
    child: Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(fieldRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Center(
        widthFactor: 1,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: muted ? AppColors.textMuted : AppColors.text,
          ),
        ),
      ),
    ),
  );
}

Future<void> showCoverPicker(BuildContext context, PageEditor ed) =>
    showDialog<void>(
      context: context,
      builder: (_) => _CoverPicker(ed: ed),
    );

class _CoverPicker extends StatefulWidget {
  const _CoverPicker({required this.ed});
  final PageEditor ed;
  @override
  State<_CoverPicker> createState() => _CoverPickerState();
}

class _CoverPickerState extends State<_CoverPicker> {
  var _from = 'violeta', _to = 'ferrugem', _dir = 'dr';
  PageEditor get ed => widget.ed;

  Widget _section(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 6, top: 4),
    child: Text(t.toUpperCase(), style: monoLabel(size: 10, spacing: 1.4)),
  );

  Widget _swatch(
    String spec, {
    required String label,
    double size = 28,
    Color? flat,
  }) {
    final on = ed.page!.cover == spec;
    return Semantics(
      button: true,
      selected: on,
      label: label,
      child: RingInkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          ed.setCover(spec);
          setState(() {});
        },
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: coverGradient(spec),
            color: flat,
            border: Border.all(
              color: on ? AppColors.text : Colors.transparent,
              width: 2,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = describeCover(ed.page!.cover);
    final from = now.kind == 'duo' ? now.a! : _from;
    final to = now.kind == 'duo' ? now.b! : _to;
    final dir = now.kind == 'duo' ? now.dir! : _dir;
    void duo(String a, String b, String d) {
      _from = a;
      _to = b;
      _dir = d;
      ed.setCover(duoSpec(a, b, d));
      setState(() {});
    }

    Widget palettes(String label, String chosen, void Function(String) pick) =>
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 36,
              child: Text(label, style: AppText.mono(10, letterSpacing: 0)),
            ),
            for (final c in palette)
              Semantics(
                button: true,
                selected: chosen == c.id,
                label: '$label ${c.label}',
                child: RingInkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => pick(c.id),
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF000000 | c.hex),
                      border: Border.all(
                        color: now.kind == 'duo' && chosen == c.id
                            ? AppColors.text
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );

    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(fieldRadius),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340, maxHeight: 520),
        child: Semantics(
          label: 'Escolher capa',
          scopesRoute: true,
          explicitChildNodes: true,
          child: ListView(
            padding: const EdgeInsets.all(12),
            shrinkWrap: true,
            children: [
              _section('Combinações'),
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 2.2,
                children: [
                  for (final m in mixes)
                    Semantics(
                      button: true,
                      selected: ed.page!.cover == mixSpec(m.key),
                      label: 'Capa ${m.label}',
                      child: RingInkWell(
                        borderRadius: BorderRadius.circular(fieldRadius),
                        onTap: () {
                          ed.setCover(mixSpec(m.key));
                          setState(() {});
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: coverGradient(mixSpec(m.key)),
                            borderRadius: BorderRadius.circular(fieldRadius),
                            border: Border.all(
                              color: ed.page!.cover == mixSpec(m.key)
                                  ? AppColors.text
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              _section('Duas cores'),
              palettes('início', from, (id) => duo(id, to, dir)),
              const SizedBox(height: 8),
              palettes('fim', to, (id) => duo(from, id, dir)),
              const SizedBox(height: 8),
              Row(
                children: [
                  SizedBox(
                    width: 36,
                    child: Text(
                      'rumo',
                      style: AppText.mono(10, letterSpacing: 0),
                    ),
                  ),
                  for (final d in directions)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Semantics(
                        button: true,
                        selected: dir == d.key,
                        excludeSemantics: true,
                        label: d.label,
                        child: RingInkWell(
                          borderRadius: BorderRadius.circular(4),
                          onTap: () => duo(from, to, d.key),
                          child: Container(
                            width: 28,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: dir == d.key
                                  ? AppColors.border.withValues(alpha: 0.6)
                                  : null,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: dir == d.key
                                    ? AppColors.text
                                    : AppColors.border,
                              ),
                            ),
                            child: Text(d.glyph),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              _section('Uma cor, em degradê'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in palette)
                    _swatch(monoSpec(c.id), label: 'Degradê ${c.label}'),
                ],
              ),
              const SizedBox(height: 12),
              _section('Cor lisa'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in palette)
                    _swatch(soloSpec(c.id), label: 'Lisa ${c.label}'),
                ],
              ),
              const SizedBox(height: 12),
              _section('Clássicas'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in classics)
                    _swatch(c.key, label: 'Capa ${c.label}'),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: OutlineTextButton(
                  label: 'Fechar',
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The icon above the title (and the quiet "add icon / add cover" buttons).
class PageIconRow extends StatelessWidget {
  const PageIconRow({super.key, required this.ed});
  final PageEditor ed;

  @override
  Widget build(BuildContext context) {
    final p = ed.page!;
    final editable = !ed.readOnly;
    if (p.icon.isEmpty && !(editable && (p.cover.isEmpty || p.icon.isEmpty))) {
      return const SizedBox.shrink();
    }
    final wide = MediaQuery.sizeOf(context).width >= 768;
    final straddle = p.cover.isNotEmpty && p.icon.isNotEmpty;
    final box = wide ? 96.0 : 80.0;
    final up = wide ? 88.0 : 80.0;
    final row = Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        if (p.icon.isNotEmpty)
          editable
              ? Tooltip(
                  message: 'Trocar ícone da página',
                  child: RingInkWell(
                    borderRadius: BorderRadius.circular(fieldRadius),
                    onTap: () => showIconPicker(context, ed),
                    child: Entrance(
                      key: ValueKey(p.icon),
                      kind: EntranceKind.icon,
                      child: SizedBox(
                        width: box,
                        height: box,
                        child: Center(
                          child: Text(
                            p.icon,
                            style: TextStyle(
                              fontSize: wide ? 64 : 56,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              : Semantics(
                  label: 'Ícone da página',
                  child: SizedBox(
                    width: box,
                    height: box,
                    child: Center(
                      child: Text(
                        p.icon,
                        style: TextStyle(fontSize: wide ? 64 : 56, height: 1),
                      ),
                    ),
                  ),
                ),
        if (editable && p.icon.isEmpty)
          _GhostText(
            label: '☺ Adicionar ícone',
            onTap: () => showIconPicker(context, ed),
          ),
        if (editable && p.cover.isEmpty)
          _GhostText(
            label: '▭ Adicionar capa',
            onTap: () => ed.setCover('musgo'),
          ),
      ],
    );
    if (!straddle) {
      return Padding(
        padding: EdgeInsets.only(top: p.cover.isNotEmpty ? 20 : 0, bottom: 12),
        child: row,
      );
    }
    // with a cover the icon hangs over its lower edge like a badge: it takes only what is left below the edge
    return SizedBox(
      height: box - up + 12,
      child: Stack(
        clipBehavior: Clip.none,
        children: [Positioned(left: 0, top: -up, height: box, child: row)],
      ),
    );
  }
}

class _GhostText extends StatelessWidget {
  const _GhostText({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => RingInkWell(
    borderRadius: BorderRadius.circular(fieldRadius),
    onTap: onTap,
    child: Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Center(
        widthFactor: 1,
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
      ),
    ),
  );
}

Future<void> showIconPicker(BuildContext context, PageEditor ed) =>
    showDialog<void>(
      context: context,
      builder: (_) => _IconPicker(ed: ed),
    );

class _IconPicker extends StatefulWidget {
  const _IconPicker({required this.ed});
  final PageEditor ed;
  @override
  State<_IconPicker> createState() => _IconPickerState();
}

class _IconPickerState extends State<_IconPicker> {
  var _group = emojiGroups.first.key;
  final _typed = TextEditingController();
  static final _recent = <String>[];

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  void _choose(String icon) {
    widget.ed.setIcon(icon);
    if (icon.isNotEmpty) {
      _recent.remove(icon);
      _recent.insert(0, icon);
      if (_recent.length > 8) _recent.removeLast();
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final list = emojiGroups.firstWhere((g) => g.key == _group).list;
    final current = widget.ed.page!.icon;
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(fieldRadius),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340, maxHeight: 520),
        child: Semantics(
          label: 'Escolher ícone',
          scopesRoute: true,
          explicitChildNodes: true,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_recent.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'RECENTES',
                          style: monoLabel(size: 10, spacing: 1.4),
                        ),
                        for (final e in _recent)
                          RingInkWell(
                            onTap: () => _choose(e),
                            child: SizedBox(
                              width: 32,
                              height: 32,
                              child: Center(
                                child: Text(
                                  e,
                                  style: const TextStyle(fontSize: 20),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.only(bottom: 6),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(
                    children: [
                      for (final g in emojiGroups)
                        Expanded(
                          child: Tooltip(
                            message: g.label,
                            child: RingInkWell(
                              borderRadius: BorderRadius.circular(4),
                              onTap: () => setState(() => _group = g.key),
                              child: Container(
                                height: 32,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: _group == g.key
                                      ? AppColors.border.withValues(alpha: 0.6)
                                      : null,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Opacity(
                                  opacity: _group == g.key ? 1 : 0.6,
                                  child: Text(
                                    g.sign,
                                    style: const TextStyle(fontSize: 18),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: GridView.builder(
                    shrinkWrap: true,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 8,
                          mainAxisExtent: 36,
                        ),
                    itemCount: list.length,
                    itemBuilder: (_, i) => RingInkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: () => _choose(list[i]),
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: current == list[i]
                              ? AppColors.border.withValues(alpha: 0.5)
                              : null,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Semantics(
                          label: 'Ícone ${list[i]}',
                          excludeSemantics: true,
                          child: Text(
                            list[i],
                            style: const TextStyle(fontSize: 20),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 32,
                        child: TextField(
                          controller: _typed,
                          maxLength: 40,
                          style: const TextStyle(fontSize: 14),
                          decoration: InputDecoration(
                            isDense: true,
                            counterText: '',
                            hintText: 'Cole qualquer emoji',
                            fillColor: AppColors.background,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(fieldRadius),
                              borderSide: const BorderSide(
                                color: AppColors.fieldBorder,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(fieldRadius),
                              borderSide: const BorderSide(
                                color: AppColors.accentBorder,
                              ),
                            ),
                          ),
                          onSubmitted: (_) => _use(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    RingInkWell(
                      onTap: _use,
                      borderRadius: BorderRadius.circular(fieldRadius),
                      child: Container(
                        height: 32,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(fieldRadius),
                        ),
                        child: const Text(
                          'Usar',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                if (current.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlineTextButton(
                      label: 'Remover ícone',
                      height: 32,
                      onPressed: () => _choose(''),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _use() {
    final found = firstEmoji(_typed.text, isEmoji);
    if (found != null) {
      _choose(found);
    } else {
      _typed.clear();
    }
  }
}

/// The page's tags as pills, with a dashed "+ tag" that opens a small form (existing tags to pick, or a new name and colour).
class TagBar extends StatefulWidget {
  const TagBar({super.key, required this.ed});
  final PageEditor ed;
  @override
  State<TagBar> createState() => _TagBarState();
}

class _TagBarState extends State<TagBar> {
  var _adding = false;
  final _name = TextEditingController();
  var _color = TagColor.accent;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (_name.text.trim().isNotEmpty) widget.ed.addTag(_name.text, _color);
    _name.clear();
    setState(() {
      _adding = false;
      _color = TagColor.accent;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ed = widget.ed;
    final p = ed.page!;
    final ws = ed.ws;
    final unused = [
      for (final t in ws.tags)
        if (!p.tags.contains(t.id)) t,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final id in p.tags)
              if (ws.tag(id) case final t?)
                TagPill(
                  key: ValueKey('chip-$id'),
                  name: t.name,
                  hash: true,
                  color: tagColor(t.color),
                  onRemove: ed.readOnly ? null : () => ed.removeTag(id),
                ),
            if (!ed.readOnly)
              RingInkWell(
                borderRadius: BorderRadius.circular(99),
                onTap: () => setState(() => _adding = !_adding),
                child: DashedBorder(
                  radius: 99,
                  color: AppColors.fieldBorder,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    child: Text(
                      '+ tag',
                      style: AppText.mono(12, letterSpacing: 0),
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (_adding && !ed.readOnly)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            constraints: const BoxConstraints(maxWidth: 448),
            decoration: cardBox(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (unused.isNotEmpty) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final t in unused)
                        RingInkWell(
                          borderRadius: BorderRadius.circular(99),
                          onTap: () => ed.addTag(t.name, t.color),
                          child: TagPill(
                            name: t.name,
                            color: tagColor(t.color),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _name,
                    autofocus: true,
                    maxLength: maxTagName,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      isDense: true,
                      counterText: '',
                      hintText: 'nova tag',
                      fillColor: AppColors.background,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(fieldRadius),
                        borderSide: const BorderSide(
                          color: AppColors.fieldBorder,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(fieldRadius),
                        borderSide: const BorderSide(
                          color: AppColors.accentBorder,
                        ),
                      ),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final c in TagColor.values)
                      Semantics(
                        button: true,
                        selected: _color == c,
                        label: 'Cor ${tagColorNames[c]}',
                        child: GestureDetector(
                          onTap: () => setState(() => _color = c),
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: tagColor(c),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _color == c
                                    ? AppColors.text
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: RingInkWell(
                    onTap: _submit,
                    borderRadius: BorderRadius.circular(fieldRadius),
                    child: Container(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(fieldRadius),
                      ),
                      child: const Center(
                        widthFactor: 1,
                        child: Text('Criar', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

enum DockKind { rail, edge }

/// The arrow that opens or closes a side panel. `rail`: round, in the strip of a panel (or beside a drawer), in the middle
/// of its height. `edge`: a tab stuck to the edge of the screen. It points toward the edge to close and toward the page
/// to open.
class DockToggle extends StatelessWidget {
  const DockToggle({
    super.key,
    required this.left,
    required this.open,
    required this.label,
    required this.onTap,
    this.kind = DockKind.rail,
  });
  final bool left, open;
  final String label;
  final VoidCallback onTap;
  final DockKind kind;

  @override
  Widget build(BuildContext context) {
    final icon = left == open ? Icons.chevron_left : Icons.chevron_right;
    final edge = kind == DockKind.edge;
    final radius = edge
        ? BorderRadius.horizontal(
            left: left ? Radius.zero : const Radius.circular(16),
            right: left ? const Radius.circular(16) : Radius.zero,
          )
        : BorderRadius.circular(99);
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        expanded: open,
        label: label,
        child: FocusRing(
          radius: edge ? 16 : 22,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Container(
              width: edge ? 32 : 44,
              height: edge ? 64 : 44,
              decoration: BoxDecoration(
                color: edge
                    ? AppColors.surface.withValues(alpha: 0.9)
                    : AppColors.surface,
                borderRadius: radius,
                border: edge
                    ? Border(
                        top: const BorderSide(color: AppColors.border),
                        bottom: const BorderSide(color: AppColors.border),
                        left: left
                            ? BorderSide.none
                            : const BorderSide(color: AppColors.border),
                        right: left
                            ? const BorderSide(color: AppColors.border)
                            : BorderSide.none,
                      )
                    : Border.all(color: AppColors.border),
                boxShadow: edge
                    ? null
                    : const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 2,
                          offset: Offset(0, 1),
                        ),
                      ],
              ),
              child: Icon(
                icon,
                size: edge ? 20 : 22,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
