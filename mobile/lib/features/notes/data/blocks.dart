// The body of a page: a flat list of blocks, the same shape the web keeps and
// the server will sync as `notes.content`. Plain data with JSON in and out.

import 'dart:math' as math;

enum BlockType {
  paragraph,
  heading,
  quote,
  callout,
  toggle,
  divider,
  checklist,
  code,
  spoiler,
  secure,
  table,
  image,
  bullet,
  numbered,
  toc,
  bookmark,
  pagelink,
  video,
  audio,
  pdf,
  file,
}

BlockType? blockTypeFromName(Object? name) {
  for (final t in BlockType.values) {
    if (t.name == name) return t;
  }
  return null;
}

const maxText = 20000;
const minColWidth = 80;
const maxColWidth = 600;
const maxCols = 12;
const maxRows = 200;
const maxBlocks = 500;
const maxItems = 100;
const maxIndent = 3;

const languages = ['texto', 'python', 'javascript', 'typescript', 'go', 'rust', 'sql', 'bash', 'json', 'html', 'css'];

enum CalloutTone { info, success, warning, danger }

const toneLabels = {
  CalloutTone.info: ('Nota', '💡'),
  CalloutTone.success: ('Sucesso', '✅'),
  CalloutTone.warning: ('Atenção', '⚠️'),
  CalloutTone.danger: ('Perigo', '🚫'),
};

class ChecklistItem {
  ChecklistItem({required this.id, this.text = '', this.done = false});
  final String id;
  String text;
  bool done;

  Map<String, Object?> toJson() => {'id': id, 'text': text, 'done': done};
  static ChecklistItem? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    if (id is! String) return null;
    return ChecklistItem(id: id, text: j['text'] is String ? j['text'] as String : '', done: j['done'] == true);
  }
}

class TableColumn {
  TableColumn({required this.id, required this.label, this.w = 160});
  final String id;
  String label;
  int w;

  Map<String, Object?> toJson() => {'id': id, 'label': label, 'w': w};
  static TableColumn? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String) return null;
    final w = j['w'] is num ? (j['w'] as num).round() : 160;
    return TableColumn(id: j['id'] as String, label: j['label'] is String ? j['label'] as String : '', w: w.clamp(minColWidth, maxColWidth));
  }
}

int _seq = 0;
String newId([String prefix = 'b']) => '$prefix${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${(_seq++).toRadixString(36)}';

/// One block. The fields that apply depend on [type]; the rest stay null.
/// A single class (instead of one per kind) keeps this small and makes turning
/// one text block into another a field change, as the web does.
class Block {
  Block(
    this.id,
    this.type, {
    this.text,
    this.level,
    this.toggle = false,
    this.body,
    this.tone,
    this.indent,
    this.items,
    this.lang,
    this.cols,
    this.rows,
    this.url,
    this.title,
    this.pageId,
    this.fileId,
    this.name,
    this.size,
    this.mime,
    this.fileLevel,
    this.src,
  });

  final String id;
  BlockType type;
  String? text;
  int? level;
  bool toggle;
  String? body;
  CalloutTone? tone;
  int? indent;
  List<ChecklistItem>? items;
  String? lang;
  List<TableColumn>? cols;
  List<Map<String, String>>? rows;
  String? url;
  String? title;
  String? pageId;
  String? fileId;
  String? name;
  int? size;
  String? mime;

  /// 1 plays or shows in the page; 2 and 3 only download (file blocks).
  int? fileLevel;

  /// A picked image of this session only (never stored).
  String? src;

  Block copy({String? id}) => Block.fromJson(toJson(), id: id)!;

  Map<String, Object?> toJson() {
    final m = <String, Object?>{'id': id, 'type': type.name};
    void put(String k, Object? v) {
      if (v != null) m[k] = v;
    }

    switch (type) {
      case BlockType.heading:
        put('text', text ?? '');
        if (level != null && level != 2) put('level', level);
        if (toggle) {
          m['toggle'] = true;
          put('body', body ?? '');
        }
      case BlockType.paragraph || BlockType.quote || BlockType.spoiler || BlockType.secure:
        put('text', text ?? '');
      case BlockType.callout:
        put('text', text ?? '');
        if (tone != null && tone != CalloutTone.info) put('tone', tone!.name);
      case BlockType.bullet || BlockType.numbered:
        put('text', text ?? '');
        put('indent', indent ?? 0);
      case BlockType.toggle:
        put('text', text ?? '');
        put('body', body ?? '');
      case BlockType.divider || BlockType.toc:
        break;
      case BlockType.checklist:
        m['items'] = [for (final i in items ?? const <ChecklistItem>[]) i.toJson()];
      case BlockType.code:
        put('lang', lang ?? 'texto');
        put('text', text ?? '');
      case BlockType.table:
        m['cols'] = [for (final c in cols ?? const <TableColumn>[]) c.toJson()];
        m['rows'] = rows ?? const <Map<String, String>>[];
      case BlockType.bookmark || BlockType.video || BlockType.audio || BlockType.pdf:
        put('url', url ?? '');
        put('title', title ?? '');
        if (fileId != null && fileId!.isNotEmpty) m['fileId'] = fileId;
      case BlockType.pagelink:
        put('pageId', pageId ?? '');
        put('title', title ?? '');
      case BlockType.file:
        m['fileId'] = fileId ?? '';
        m['name'] = name ?? '';
        m['size'] = size ?? 0;
        m['mime'] = mime ?? '';
        m['level'] = fileLevel ?? 3;
      case BlockType.image:
        put('name', name);
        if (fileId != null && fileId!.isNotEmpty) m['fileId'] = fileId;
    }
    return m;
  }

  /// Reads one block; null when it is not a block at all. Unknown fields are
  /// ignored and bad values fall back, so a damaged or newer file never throws.
  static Block? fromJson(Object? j, {String? id}) {
    if (j is! Map) return null;
    final type = blockTypeFromName(j['type']);
    final rawId = j['id'];
    if (type == null || rawId is! String) return null;
    String s(String k) => j[k] is String ? j[k] as String : '';
    String? sn(String k) => j[k] is String ? j[k] as String : null;
    final b = Block(id ?? rawId, type);
    switch (type) {
      case BlockType.heading:
        b.text = s('text');
        final l = j['level'];
        b.level = l is int && l >= 1 && l <= 3 ? l : null;
        if (j['toggle'] == true) {
          b.toggle = true;
          b.body = s('body');
        }
      case BlockType.paragraph || BlockType.quote || BlockType.spoiler || BlockType.secure:
        b.text = s('text');
      case BlockType.callout:
        b.text = s('text');
        b.tone = CalloutTone.values.where((t) => t.name == j['tone']).firstOrNull;
      case BlockType.bullet || BlockType.numbered:
        b.text = s('text');
        final i = j['indent'];
        b.indent = i is int ? i.clamp(0, maxIndent) : 0;
      case BlockType.toggle:
        b.text = s('text');
        b.body = s('body');
      case BlockType.divider || BlockType.toc:
        break;
      case BlockType.checklist:
        final raw = j['items'];
        b.items = [
          if (raw is List)
            for (final i in raw.take(maxItems))
              ?ChecklistItem.fromJson(i),
        ];
      case BlockType.code:
        b.lang = s('lang').isEmpty ? 'texto' : s('lang');
        b.text = s('text');
      case BlockType.table:
        final rawCols = j['cols'];
        b.cols = [
          if (rawCols is List)
            for (final c in rawCols.take(maxCols))
              ?TableColumn.fromJson(c),
        ];
        final rawRows = j['rows'];
        b.rows = [
          if (rawRows is List)
            for (final r in rawRows.take(maxRows))
              if (r is Map) {for (final c in b.cols!) c.id: r[c.id] is String ? r[c.id] as String : ''},
        ];
      case BlockType.bookmark || BlockType.video || BlockType.audio || BlockType.pdf:
        b.url = s('url');
        b.title = s('title');
        b.fileId = sn('fileId');
      case BlockType.pagelink:
        b.pageId = s('pageId');
        b.title = s('title');
      case BlockType.file:
        b.fileId = s('fileId');
        b.name = s('name');
        b.size = j['size'] is num ? (j['size'] as num).toInt() : 0;
        b.mime = s('mime');
        final l = j['level'];
        b.fileLevel = l is int && l >= 1 && l <= 3 ? l : 3;
      case BlockType.image:
        b.name = sn('name');
        b.fileId = sn('fileId');
    }
    return b;
  }
}

Block makeBlock(BlockType type, {int? level, bool toggle = false}) {
  final id = newId();
  switch (type) {
    case BlockType.heading:
      return Block(id, type, text: '', level: level != null && level != 2 ? level : null, toggle: toggle, body: toggle ? '' : null);
    case BlockType.bullet || BlockType.numbered:
      return Block(id, type, text: '', indent: 0);
    case BlockType.toc || BlockType.divider:
      return Block(id, type);
    case BlockType.bookmark || BlockType.video || BlockType.audio || BlockType.pdf:
      return Block(id, type, url: '', title: '');
    case BlockType.pagelink:
      return Block(id, type, pageId: '', title: '');
    case BlockType.file:
      return Block(id, type, fileId: '', name: '', size: 0, mime: '', fileLevel: 3);
    case BlockType.paragraph || BlockType.quote || BlockType.callout || BlockType.spoiler || BlockType.secure:
      return Block(id, type, text: '');
    case BlockType.toggle:
      return Block(id, type, text: '', body: '');
    case BlockType.checklist:
      return Block(id, type, items: [ChecklistItem(id: newId('i'))]);
    case BlockType.code:
      return Block(id, type, lang: 'texto', text: '');
    case BlockType.table:
      final cols = [for (var n = 0; n < 3; n++) TableColumn(id: newId('c'), label: 'Coluna ${n + 1}')];
      return Block(id, type, cols: cols, rows: [for (var n = 0; n < 3; n++) {for (final c in cols) c.id: ''}]);
    case BlockType.image:
      return Block(id, type);
  }
}

/// Plain text of a block, for the card excerpt and for search.
/// Secure blocks never contribute.
String blockText(Block b) {
  switch (b.type) {
    case BlockType.heading:
      return b.toggle ? '${b.text ?? ''} ${b.body ?? ''}'.trim() : b.text ?? '';
    case BlockType.paragraph || BlockType.quote || BlockType.callout || BlockType.code || BlockType.spoiler || BlockType.bullet || BlockType.numbered:
      return b.text ?? '';
    case BlockType.bookmark || BlockType.video || BlockType.audio || BlockType.pdf || BlockType.pagelink:
      return b.title ?? '';
    case BlockType.file:
      return b.name ?? '';
    case BlockType.toggle:
      return '${b.text ?? ''} ${b.body ?? ''}'.trim();
    case BlockType.checklist:
      return (b.items ?? const []).map((i) => i.text).join(' ');
    case BlockType.table:
      return (b.rows ?? const []).expand((r) => (b.cols ?? const []).map((c) => r[c.id] ?? '')).join(' ');
    default:
      return '';
  }
}

final _spaces = RegExp(r'\s+');

/// The text a page card shows under the title: the first block that has some,
/// never a spoiler or a secret.
String excerptOf(List<Block> blocks, {int max = 240}) {
  for (final b in blocks) {
    if (b.type == BlockType.spoiler || b.type == BlockType.secure) continue;
    final t = blockText(b).replaceAll(_spaces, ' ').trim();
    if (t.isNotEmpty) return t.length > max ? t.substring(0, max) : t;
  }
  return '';
}

({int done, int total}) checklistProgress(List<Block> blocks) {
  var done = 0, total = 0;
  for (final b in blocks) {
    if (b.type != BlockType.checklist) continue;
    total += b.items!.length;
    done += b.items!.where((i) => i.done).length;
  }
  return (done: done, total: total);
}

/// A short "há 2 h" for the page header.
String ago(int ms, {int? now}) {
  final s = math.max(0, (((now ?? DateTime.now().millisecondsSinceEpoch) - ms) / 1000).round());
  if (s < 60) return 'agora há pouco';
  final m = (s / 60).round();
  if (m < 60) return 'há $m min';
  final h = (m / 60).round();
  if (h < 24) return 'há $h h';
  final d = (h / 24).round();
  final months = (d / 30).round();
  return d < 30 ? 'há $d d' : 'há $months ${months == 1 ? 'mês' : 'meses'}';
}

/// Moves `list[from]` so it lands in the gap [at] (0 = before the first item,
/// length = after the last), the way a drop indicator between two rows reads.
/// False when nothing moves.
bool moveItem<T>(List<T> list, int from, int at) {
  if (from < 0 || from >= list.length || at < 0 || at > list.length) return false;
  final to = at > from ? at - 1 : at;
  if (to == from) return false;
  list.insert(to, list.removeAt(from));
  return true;
}

const urlTypes = {BlockType.bookmark, BlockType.video, BlockType.audio, BlockType.pdf};
bool isUrlBlock(Block b) => urlTypes.contains(b.type);

final _videoExt = RegExp(r'\.(mp4|m4v|webm|ogv|mov)$', caseSensitive: false);
final _audioExt = RegExp(r'\.(mp3|m4a|aac|wav|ogg|oga|opus|flac)$', caseSensitive: false);

/// Whether an address points straight at a playable file (not a page that
/// shows a player, like YouTube).
bool isDirectMedia(BlockType kind, String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) return false;
  return (kind == BlockType.video ? _videoExt : _audioExt).hasMatch(uri.path);
}

/// The block that shows a file of this type: media where it can be shown, a
/// file card for everything else.
BlockType blockTypeForFile(String mime, int level) {
  if (level != 1) return BlockType.file;
  if (mime.startsWith('image/')) return BlockType.image;
  if (mime.startsWith('video/') || mime == 'application/ogg') return BlockType.video;
  if (mime.startsWith('audio/')) return BlockType.audio;
  if (mime == 'application/pdf') return BlockType.pdf;
  return BlockType.file;
}

/// Ids of the files kept on the server that these blocks use.
List<String> fileIdsOf(Iterable<Block> blocks) => {
      for (final b in blocks)
        if (b.fileId != null && b.fileId!.isNotEmpty) b.fileId!,
    }.toList();

const textTypes = {BlockType.paragraph, BlockType.heading, BlockType.quote, BlockType.callout, BlockType.bullet, BlockType.numbered};
bool isTextType(BlockType t) => textTypes.contains(t);

int wordCount(String text) => RegExp(r'\S+').allMatches(text).length;

class PageStats {
  const PageStats(this.words, this.chars, this.minutes);
  final int words, chars, minutes;
}

/// What the page says in words. Secure blocks never count.
PageStats pageStats(List<Block> blocks) {
  var words = 0, chars = 0;
  for (final b in blocks) {
    final t = blockText(b);
    words += wordCount(t);
    chars += t.length;
  }
  return PageStats(words, chars, words == 0 ? 0 : math.max(1, (words / 200).ceil()));
}

class OutlineItem {
  const OutlineItem(this.id, this.text, this.level);
  final String id, text;
  final int level;
}

/// The section titles of the page, in order, with their sizes.
List<OutlineItem> outline(List<Block> blocks) => [
      for (final b in blocks)
        if (b.type == BlockType.heading)
          OutlineItem(b.id, (b.text ?? '').replaceAll(_spaces, ' ').trim().isEmpty ? 'Sem título' : (b.text ?? '').replaceAll(_spaces, ' ').trim(), b.level ?? 2),
    ];

/// The number each item of a numbered list shows. Items count up at their own
/// level; a deeper level starts again under every new parent, and any block
/// that is not part of the list ends it.
Map<String, int> numbering(List<Block> blocks) {
  final out = <String, int>{};
  var counters = <int>[];
  for (final b in blocks) {
    if (b.type == BlockType.numbered) {
      final d = (b.indent ?? 0).clamp(0, maxIndent);
      counters = counters.take(d + 1).toList();
      while (counters.length <= d) {
        counters.add(0);
      }
      counters[d]++;
      out[b.id] = counters[d];
    } else if (b.type == BlockType.bullet) {
      counters = counters.take((b.indent ?? 0).clamp(0, maxIndent)).toList();
    } else {
      counters = [];
    }
  }
  return out;
}
