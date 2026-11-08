import 'package:flutter/widgets.dart' show ChangeNotifier;
import 'package:characters/characters.dart';

import 'blocks.dart';
import 'cover_spec.dart';
import 'note_page.dart';
import 'notes_db.dart';
import 'text.dart';

enum NotesView { all, shared, vault, trash }

enum NotesSort { recent, az }

enum NotesLayout { grid, list }

class PageGroup {
  const PageGroup(this.key, this.label, this.pages);
  final String key;

  /// null: no visible heading (a single flat list).
  final String? label;
  final List<NotePage> pages;
}

/// The state of the notes screen: pages, tags, filters and what each view
/// shows. Everything is saved to [NotesDb] as it changes.
class Workspace extends ChangeNotifier {
  Workspace(this._db, {int Function()? clock}) : _now = clock ?? (() => DateTime.now().millisecondsSinceEpoch) {
    pages = _db.pages();
    tags = _db.tags();
    settings = _db.settings();
    _purgeExpired();
  }

  final NotesDb _db;
  final int Function() _now;
  int _seq = 0;

  late List<NotePage> pages;
  late List<Tag> tags;
  late Settings settings;
  NotesView view = NotesView.all;
  NotesSort sort = NotesSort.recent;
  NotesLayout layout = NotesLayout.grid;
  String query = '';
  String? tagFilter;

  /// Told which files only the pages deleted for good used, so the server can
  /// drop them at once.
  void Function(List<String> ids) filesGone = (_) {};

  List<NotePage> get live => [for (final p in pages) if (!p.trashed) p];
  List<NotePage> get mine => live;

  ({int all, int shared, int vault, int trash}) get counts => (
        all: live.length,
        shared: 0,
        vault: live.where((p) => p.locked).length,
        trash: pages.length - live.length,
      );

  Map<String, int> get tagCounts => {for (final t in tags) t.id: live.where((p) => p.tags.contains(t.id)).length};

  /// What the current view shows, after search, tag filter and sort.
  List<NotePage> get visible {
    // nothing is shared on the device yet, and the vault lists its own entries
    if (view == NotesView.vault || view == NotesView.shared) return [];
    final q = fold(query.trim());
    final base = view == NotesView.trash ? pages.where((p) => p.trashed) : live.where((p) => !p.locked);
    final list = [
      for (final p in base)
        if ((tagFilter == null || p.tags.contains(tagFilter)) && (q.isEmpty || fold(p.title).contains(q) || fold(p.excerpt).contains(q))) p
    ];
    list.sort((a, b) => sort == NotesSort.az ? fold(a.title).compareTo(fold(b.title)) : b.updated.compareTo(a.updated));
    return list;
  }

  /// [visible] split into sections: pinned first, then by date (or one list
  /// when sorted A–Z). Search results and the trash stay a flat list.
  List<PageGroup> get groups {
    final list = visible;
    if (view == NotesView.trash || query.trim().isNotEmpty) return [PageGroup('all', null, list)];
    final out = <PageGroup>[];
    final pinned = [for (final p in list) if (p.pinned) p];
    var rest = [for (final p in list) if (!p.pinned) p];
    if (pinned.isNotEmpty) out.add(PageGroup('pinned', 'Fixadas', pinned));
    if (sort == NotesSort.az) {
      if (rest.isNotEmpty) out.add(PageGroup('rest', pinned.isNotEmpty ? 'Outras' : null, rest));
      return out;
    }
    final n = DateTime.fromMillisecondsSinceEpoch(_now());
    final startOfDay = DateTime(n.year, n.month, n.day);
    int back(int days) => DateTime(startOfDay.year, startOfDay.month, startOfDay.day - days).millisecondsSinceEpoch;
    final buckets = <(String, String, int)>[
      ('today', 'Hoje', startOfDay.millisecondsSinceEpoch),
      ('week', 'Esta semana', back(6)),
      ('month', 'Últimos 30 dias', back(29)),
      ('older', 'Mais antigas', -(1 << 62)),
    ];
    for (final (key, label, from) in buckets) {
      final here = [for (final p in rest) if (p.updated >= from) p];
      rest = [for (final p in rest) if (p.updated < from) p];
      if (here.isNotEmpty) out.add(PageGroup(key, label, here));
    }
    return out;
  }

  Tag? tag(String id) => tags.where((t) => t.id == id).firstOrNull;

  NotePage? page(String id) => pages.where((p) => p.id == id).firstOrNull;

  void go(NotesView v) {
    view = v;
    tagFilter = null;
    notifyListeners();
  }

  void setQuery(String q) {
    query = q;
    notifyListeners();
  }

  void setSort(NotesSort s) {
    sort = s;
    notifyListeners();
  }

  void setLayout(NotesLayout l) {
    layout = l;
    notifyListeners();
  }

  void toggleTagFilter(String id) {
    tagFilter = tagFilter == id ? null : id;
    if (view == NotesView.vault) view = NotesView.all;
    notifyListeners();
  }

  void clearFilters() {
    query = '';
    tagFilter = null;
    notifyListeners();
  }

  String _newPageId() => 'n${_now().toRadixString(36)}${(_seq++).toRadixString(36)}';

  /// Adds an empty page at the top of "all pages" and returns it.
  NotePage newPage([String title = 'Sem título']) {
    final now = _now();
    final t = title.trim().length > maxTitle ? title.trim().substring(0, maxTitle) : title.trim();
    final p = NotePage(id: _newPageId(), title: t.isEmpty ? 'Sem título' : t, tags: tagFilter == null ? [] : [tagFilter!], updated: now, created: now, content: []);
    pages.insert(0, p);
    view = NotesView.all;
    query = '';
    sort = NotesSort.recent;
    _db.savePage(p, content: true);
    notifyListeners();
    return p;
  }

  /// The body of a page; one that was never opened starts as a single
  /// paragraph with its excerpt. Read from the database the first time.
  List<Block>? contentOf(String id) {
    final p = page(id);
    if (p == null) return null;
    p.content ??= _db.content(id) ?? (p.excerpt.isEmpty ? [] : [Block('${p.id}-b0', BlockType.paragraph, text: p.excerpt)]);
    return p.content;
  }

  /// A page that is no longer open lets its body go (it stays in the database).
  void release(String id) {
    final p = page(id);
    if (p == null || p.content == null) return;
    _db.savePage(p, content: true);
    p.content = null;
  }

  /// After an edit: the card shows the new excerpt, block count and time, and
  /// the body is saved.
  void touch(String id) {
    final p = page(id);
    if (p == null) return;
    p.updated = _now();
    if (p.content != null) {
      p.blocks = p.content!.length;
      p.excerpt = excerptOf(p.content!);
    }
    _db.savePage(p, content: p.content != null);
    notifyListeners();
  }

  void setTitle(String id, String title) {
    final p = page(id);
    if (p == null) return;
    p.title = title.length > maxTitle ? title.substring(0, maxTitle) : title;
    p.updated = _now();
    _db.savePage(p);
    notifyListeners();
  }

  void setIcon(String id, String icon) => _meta(id, (p) => p.icon = icon.characters.take(1).toString());

  void setCover(String id, String cover) => _meta(id, (p) => p.cover = isCover(cover) ? cover : p.cover);

  void _meta(String id, void Function(NotePage) change) {
    final p = page(id);
    if (p == null) return;
    change(p);
    _db.savePage(p);
    notifyListeners();
  }

  /// Other pages that share tags with this one, the ones sharing the most first.
  List<NotePage> related(String id, {int limit = 5}) {
    final p = page(id);
    if (p == null || p.tags.isEmpty) return [];
    int overlap(NotePage x) => x.tags.where(p.tags.contains).length;
    final list = [for (final x in live) if (x.id != id && !x.locked && overlap(x) > 0) x];
    list.sort((a, b) => overlap(b) != overlap(a) ? overlap(b) - overlap(a) : b.updated - a.updated);
    return list.take(limit).toList();
  }

  /// A copy of the page: same body and tags, not pinned. Images picked in this
  /// session are left out (their temporary links belong to the original);
  /// returns the copy and how many images stayed behind.
  ({NotePage page, int images})? duplicate(String id) {
    final src = page(id);
    if (src == null) return null;
    var images = 0;
    final body = <Block>[];
    for (final b in contentOf(id) ?? const <Block>[]) {
      // `src` is not part of the saved form, so the copy never has it; the name goes too
      final c = b.copy(id: newId());
      if (b.type == BlockType.image && b.src != null) {
        images++;
        c.name = null;
      }
      body.add(c);
    }
    final now = _now();
    final t = '${src.title} (cópia)';
    final copy = NotePage(
      id: _newPageId(),
      title: t.length > maxTitle ? t.substring(0, maxTitle) : t,
      excerpt: src.excerpt,
      tags: [...src.tags],
      updated: now,
      created: now,
      blocks: body.length,
      content: body,
      locked: src.locked,
      icon: src.icon,
      cover: src.cover,
    );
    pages.insert(0, copy);
    _db.savePage(copy, content: true);
    notifyListeners();
    return (page: copy, images: images);
  }

  void togglePin(String id) => _meta(id, (p) => p.pinned = !p.pinned);

  /// Moves a page to the trash, or deletes it for good when the trash is turned
  /// off in the settings (vault pages never wait in the trash either).
  void trash(String id) {
    final p = page(id);
    if (p == null) return;
    if (!settings.useTrash || p.locked) {
      deleteForever(id);
      return;
    }
    p.trashed = true;
    // the day it went to the trash decides when it is purged
    p.updated = _now();
    _db.savePage(p);
    notifyListeners();
  }

  void restore(String id) => _meta(id, (p) {
        p.trashed = false;
        p.updated = _now();
      });

  void emptyTrash() => _drop([for (final p in pages) if (p.trashed) p]);

  void deleteForever(String id) => _drop([for (final p in pages) if (p.id == id) p]);

  void _drop(List<NotePage> gone) {
    if (gone.isEmpty) return;
    // the bodies of the doomed pages are read once, to find their files
    final ids = <String>{};
    for (final p in gone) {
      final body = p.content ?? _db.content(p.id) ?? const <Block>[];
      ids.addAll(fileIdsOf(body));
    }
    final goneIds = {for (final p in gone) p.id};
    pages = [for (final p in pages) if (!goneIds.contains(p.id)) p];
    _db.deletePages(goneIds);
    if (ids.isNotEmpty) {
      final kept = <String>{};
      for (final (_, body) in _db.bodies()) {
        kept.addAll(fileIdsOf(body));
      }
      final alone = [for (final id in ids) if (!kept.contains(id)) id];
      if (alone.isNotEmpty) filesGone(alone);
    }
    notifyListeners();
  }

  /// Pages that sat in the trash for longer than the retention are deleted for good.
  void _purgeExpired() {
    final limit = _now() - settings.retention * 86400000;
    final old = [for (final p in pages) if (p.trashed && p.updated < limit) p];
    if (old.isNotEmpty) _drop(old);
  }

  /// Returns the new tag, or the existing one when the name is taken; null for an empty name.
  Tag? addTag(String name, [TagColor color = TagColor.accent]) {
    var clean = name.trim().replaceAll(RegExp(r'\s+'), '-');
    if (clean.length > maxTagName) clean = clean.substring(0, maxTagName);
    if (clean.isEmpty) return null;
    final id = fold(clean);
    final existing = tag(id);
    if (existing != null) return existing;
    final t = Tag(id, clean.toLowerCase(), color);
    tags.add(t);
    _db.saveTag(t, tags.length - 1);
    notifyListeners();
    return t;
  }

  void saveSettings(Settings next) {
    settings = next.copy();
    _db.saveSettings(settings);
    _purgeExpired();
    notifyListeners();
  }
}

String formatDate(int ms) {
  const months = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} ${d.year}';
}

/// The small right-hand note of a card: where it lives, or its size.
String pageMeta(NotePage p) => p.locked ? 'cofre' : '${p.blocks} ${p.blocks == 1 ? 'bloco' : 'blocos'}';
