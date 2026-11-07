// What leaves the app: one page as Markdown, plain text or JSON (the same shapes the web writes).

import 'dart:convert';

import 'blocks.dart';
import 'note_page.dart';

enum ExportFormat { md, txt, json }

const formatLabels = {ExportFormat.md: 'Markdown', ExportFormat.txt: 'Texto simples', ExportFormat.json: 'JSON'};

final _spaces = RegExp(r'\s+');
String _oneLine(String s) => s.replaceAll(_spaces, ' ').trim();

List<Block> _blocksOf(NotePage p) => p.content ?? (p.excerpt.isEmpty ? [] : [Block('x', BlockType.paragraph, text: p.excerpt)]);

List<String> _tagNames(NotePage p, List<Tag> tags) => [for (final id in p.tags) tags.where((t) => t.id == id).firstOrNull?.name ?? id];

const _alert = {CalloutTone.info: 'NOTE', CalloutTone.success: 'TIP', CalloutTone.warning: 'WARNING', CalloutTone.danger: 'CAUTION'};

/// A code fence longer than any run of backticks inside the code, so the code can never close it early.
String _fence(String text) {
  var longest = 0;
  for (final m in RegExp('`+').allMatches(text)) {
    if (m.group(0)!.length > longest) longest = m.group(0)!.length;
  }
  return '`' * (longest + 1 < 3 ? 3 : longest + 1);
}

String _cell(String s) => _oneLine(s).replaceAll('|', r'\|');

String _quote(String text) => text.split('\n').map((l) => '> $l'.trimRight()).join('\n');

String _mdBlock(Block b, bool includeSecure, Map<String, int> numbers, List<OutlineItem> titles) {
  switch (b.type) {
    case BlockType.heading:
      final level = b.level ?? 2;
      return b.toggle
          ? '<details><summary><h$level>${_oneLine(b.text ?? '')}</h$level></summary>\n\n${b.body ?? ''}\n\n</details>'
          : '${'#' * level} ${_oneLine(b.text ?? '')}';
    case BlockType.paragraph:
      return b.text ?? '';
    case BlockType.quote:
      return _quote(b.text ?? '');
    case BlockType.callout:
      return '> [!${_alert[b.tone ?? CalloutTone.info]}]\n${_quote(b.text ?? '')}';
    case BlockType.toggle:
      return '<details><summary>${_oneLine(b.text ?? '')}</summary>\n\n${b.body ?? ''}\n\n</details>';
    case BlockType.divider:
      return '---';
    case BlockType.checklist:
      return [for (final i in b.items!) '- [${i.done ? 'x' : ' '}] ${_oneLine(i.text)}'].join('\n');
    case BlockType.code:
      final f = _fence(b.text ?? '');
      return '$f${b.lang == 'texto' ? '' : b.lang}\n${b.text ?? ''}\n$f';
    case BlockType.spoiler:
      return '<details><summary>spoiler</summary>\n\n${b.text ?? ''}\n\n</details>';
    case BlockType.secure:
      return includeSecure ? b.text ?? '' : '> [bloco seguro omitido]';
    case BlockType.table:
      final head = '| ${[for (final c in b.cols!) _cell(c.label)].join(' | ')} |';
      final rule = '| ${[for (final _ in b.cols!) '---'].join(' | ')} |';
      final rows = [for (final r in b.rows!) '| ${[for (final c in b.cols!) _cell(r[c.id] ?? '')].join(' | ')} |'];
      return [head, rule, ...rows].join('\n');
    case BlockType.image:
      return (b.name ?? '').isNotEmpty ? '![${_oneLine(b.name!)}](${Uri.encodeFull(b.name!)})' : '';
    case BlockType.bullet:
      return '${'  ' * (b.indent ?? 0)}- ${_oneLine(b.text ?? '')}';
    case BlockType.numbered:
      return '${'   ' * (b.indent ?? 0)}${numbers[b.id] ?? 1}. ${_oneLine(b.text ?? '')}';
    case BlockType.toc:
      return [for (final t in titles) '${'  ' * (t.level - 1)}- ${_oneLine(t.text)}'].join('\n');
    case BlockType.bookmark || BlockType.video || BlockType.audio || BlockType.pdf:
      if ((b.url ?? '').isEmpty && (b.fileId ?? '').isNotEmpty) return '📎 ${_oneLine(b.title ?? '').isEmpty ? 'arquivo' : _oneLine(b.title!)}';
      return (b.url ?? '').isEmpty ? '' : '[${_oneLine(b.title ?? '').isEmpty ? b.url : _oneLine(b.title!)}](${b.url})';
    case BlockType.pagelink:
      return (b.pageId ?? '').isNotEmpty && (b.title ?? '').isNotEmpty ? '[${_oneLine(b.title!)}](/notes/${b.pageId})' : '';
    case BlockType.file:
      return (b.fileId ?? '').isNotEmpty ? '📎 ${_oneLine(b.name ?? '').isEmpty ? 'arquivo' : _oneLine(b.name!)}' : '';
  }
}

bool _isItem(Block b) => b.type == BlockType.bullet || b.type == BlockType.numbered;

/// Blocks, one under the other: list items stay together, everything else is set apart by a blank line.
String _join(List<Block> blocks, String Function(Block, Map<String, int>, List<OutlineItem>) render) {
  final numbers = numbering(blocks);
  final titles = outline(blocks);
  final out = StringBuffer();
  Block? prev;
  for (final b in blocks) {
    final text = render(b, numbers, titles);
    if (text.isEmpty) continue;
    if (prev != null) out.write(_isItem(prev) && _isItem(b) ? '\n' : '\n\n');
    out.write(text);
    prev = b;
  }
  return out.toString();
}

String pageToMarkdown(NotePage p, List<Tag> tags, {bool includeSecure = false}) {
  final names = _tagNames(p, tags);
  final body = _join(_blocksOf(p), (b, n, t) => _mdBlock(b, includeSecure, n, t));
  final title = _oneLine(p.title).isEmpty ? 'Sem título' : _oneLine(p.title);
  return '# $title\n\n${names.isEmpty ? '' : 'tags: ${names.join(', ')}\n\n'}$body${body.isEmpty ? '' : '\n'}';
}

String _txtBlock(Block b, bool includeSecure, Map<String, int> numbers, List<OutlineItem> titles) {
  switch (b.type) {
    case BlockType.heading:
      final t = (b.text ?? '').toUpperCase();
      return b.toggle ? [t, b.body ?? ''].where((x) => x.isNotEmpty).join('\n') : t;
    case BlockType.quote:
      return _quote(b.text ?? '');
    case BlockType.callout:
      return '${toneLabels[b.tone ?? CalloutTone.info]!.$1}: ${b.text ?? ''}';
    case BlockType.toggle:
      return [b.text ?? '', b.body ?? ''].where((x) => x.isNotEmpty).join('\n');
    case BlockType.divider:
      return '----------';
    case BlockType.checklist:
      return [for (final i in b.items!) '[${i.done ? 'x' : ' '}] ${_oneLine(i.text)}'].join('\n');
    case BlockType.secure:
      return includeSecure ? b.text ?? '' : '[bloco seguro omitido]';
    case BlockType.table:
      return [for (final r in b.rows!) [for (final c in b.cols!) r[c.id] ?? ''].join('\t')].join('\n');
    case BlockType.bullet:
      return '${'  ' * (b.indent ?? 0)}• ${_oneLine(b.text ?? '')}';
    case BlockType.numbered:
      return '${'   ' * (b.indent ?? 0)}${numbers[b.id] ?? 1}. ${_oneLine(b.text ?? '')}';
    case BlockType.toc:
      return [for (final t in titles) '${'  ' * (t.level - 1)}${_oneLine(t.text)}'].join('\n');
    case BlockType.code || BlockType.paragraph || BlockType.spoiler:
      return b.text ?? '';
    default:
      return blockText(b);
  }
}

String pageToText(NotePage p, List<Tag> tags, {bool includeSecure = false}) {
  final title = _oneLine(p.title).isEmpty ? 'Sem título' : _oneLine(p.title);
  final body = _join(_blocksOf(p), (b, n, t) => _txtBlock(b, includeSecure, n, t));
  return '${title.toUpperCase()}\n\n$body${body.isEmpty ? '' : '\n'}';
}

String pageToJson(NotePage p, List<Tag> tags, {bool includeSecure = false}) {
  final blocks = [
    for (final b in _blocksOf(p))
      if (b.type == BlockType.secure && !includeSecure) {'id': b.id, 'type': 'secure', 'omitted': true} else b.toJson(),
  ];
  return const JsonEncoder.withIndent('  ').convert({
    'app': 'pindrel',
    'title': p.title,
    'tags': _tagNames(p, tags),
    'created': DateTime.fromMillisecondsSinceEpoch(p.created, isUtc: true).toIso8601String(),
    'updated': DateTime.fromMillisecondsSinceEpoch(p.updated, isUtc: true).toIso8601String(),
    'blocks': blocks,
  });
}

String exportPage(NotePage p, List<Tag> tags, ExportFormat f, {bool includeSecure = false}) => switch (f) {
      ExportFormat.md => pageToMarkdown(p, tags, includeSecure: includeSecure),
      ExportFormat.txt => pageToText(p, tags, includeSecure: includeSecure),
      ExportFormat.json => pageToJson(p, tags, includeSecure: includeSecure),
    };

/// A safe file name for a page: no slashes, no dots at the start, no control characters, never empty.
String fileNameFor(String title, String ext) {
  final base = _oneLine(title).replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-').replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
  final cut = base.length > 60 ? base.substring(0, 60) : base;
  return '${cut.isEmpty ? 'pagina' : cut}.$ext';
}

/// Pages that can leave the app in clear: the vault, and the trash, never do.
List<NotePage> exportable(List<NotePage> pages) => [for (final p in pages) if (!p.trashed && !p.locked) p];
